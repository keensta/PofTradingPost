local Json = require("core/util/json")
local Settings = require("core/data/settings")

--[[
    Every call to the Dart backend lives here. Handlers call these never HTTPRequest directly.

    Base URL is "urls.api" in plugin.json. Needs the httpAccess permission.
    Every request except register sends the X-Secret-Key header.

    All functions take onDone(ok, data, statusCode):
        ok = true  - data is the decoded JSON response
        ok = false - data is a message the UI can show as is

    Requests are queued and sent ONE AT A TIME:
    - Calling Api.x() only adds a job to the queue, nothing is sent straight away.
    - The next job only starts once the current one has finished (or timed out).
    - A GET for a path that's already waiting in the queue doesn't send twice, the
      callbacks are added to the waiting job instead.
    - onDone is always called later (never synchronously), even for errors like
      missing permission, so callers behave the same either way.

    Call Api.init() on plugin start and Api.shutdown() on plugin shutdown.
]]

local Api = {}

local SECRET_KEY_HEADER = "X-Secret-Key"
local CANT_REACH = "Can't reach the Trading Post server, try again later."
local SUBSCRIBER_ID = "pofTradingPost_apiQueue"

-- Event.Logic runs 50 times a second. Give up on a request after 30 seconds.
local LOGIC_PER_SECOND = 50
local TIMEOUT_TICKS = 30 * LOGIC_PER_SECOND

local queue = {}     -- jobs waiting to be sent, oldest first
local current = nil  -- the job in flight, or nil
local ticks = 0
local running = false

local function urlEncode(text)
    return (tostring(text):gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- Calls every callback waiting on this job exactly once.
local function finishJob(job, ok, data, code)
    if job.done then return end

    job.done = true

    if current == job then current = nil end

    for _, onDone in ipairs(job.callbacks) do
        local handled, err = pcall(onDone, ok, data, code)

        if not handled then
            print("POF Trading Post: handler for " .. job.path .. " failed: " .. tostring(err))
        end
    end
end

-- Turns a finished HTTPRequest into onDone(ok, data, statusCode).
local function handleResponse(job, req)
    if job.done then return end -- timed out or shut down already

    if req.cancelled then
        finishJob(job, false, CANT_REACH, 0)
        return
    end

    if req.timedOut or (req.failed and (req.responseCode or 0) == 0) then
        finishJob(job, false, CANT_REACH, 0)
        return
    end

    local code = req.responseCode or 0
    local body = nil

    if req.data ~= nil and req.data ~= "" then
        local decoded, result = pcall(Json.decode, req.data)

        if decoded then
            body = result
        elseif code >= 200 and code < 300 then
            -- 2xx but not JSON, e.g. a proxy / challenge page
            print("POF Trading Post: bad JSON from " .. job.path)
            finishJob(job, false, "Trading Post server sent a bad response, try again later.", code)
            return
        end
    end

    if code >= 200 and code < 300 then
        finishJob(job, true, body or {}, code)
        return
    end

    -- API errors are always { "error": "message" }
    local message = type(body) == "table" and body.error or nil

    finishJob(job, false, message or formatStr("Trading Post server error ({}).", code), code)
end

-- Sends one job. Checks happen here, at send time, so a key saved after queueing is used.
local function send(job)
    if not Plugin.HasPermission(PluginPermissions.httpAccess) then
        finishJob(job, false, "Enable the HTTP permission for POF Trading Post in the plugin settings.", 0)
        return
    end

    if Plugin.urls == nil or Plugin.urls.api == nil then
        finishJob(job, false, "Trading Post server address missing from plugin.json.", 0)
        return
    end

    local key = Settings.get("secretKey")

    if not job.options.noKey and (key == nil or key == "") then
        finishJob(job, false, "No secret key yet. Check the Trading Post settings page.", 401)
        return
    end

    current = job
    job.startedAt = ticks

    local ok, problem = pcall(function()
        local req = HTTPRequest.new(Plugin.urls.api, job.path)

        job.req = req

        req:AddHeader("Content-Type", "application/json")

        if not job.options.noKey then
            req:AddHeader(SECRET_KEY_HEADER, key)
        end

        local function onComplete(finished)
            local handled, err = pcall(handleResponse, job, finished)

            if not handled then
                print("POF Trading Post: response handler failed for " .. job.path .. ": " .. tostring(err))
                finishJob(job, false, CANT_REACH, 0)
            end
        end

        if job.method == "POST" then
            req:Post(Json.encode(job.body or {}), onComplete)
        else
            req:Get(onComplete)
        end
    end)

    if not ok then
        print("POF Trading Post: request to " .. job.path .. " failed: " .. tostring(problem))
        finishJob(job, false, CANT_REACH, 0)
    end
end

-- Runs every Logic tick: watch the current request, or start the next one.
local function pump()
    ticks = ticks + 1

    if current ~= nil then
        if ticks - current.startedAt > TIMEOUT_TICKS then
            local job = current

            print("POF Trading Post: " .. job.path .. " took too long, skipping it")
            finishJob(job, false, CANT_REACH, 0) -- marks done first so the cancel callback is ignored
            pcall(function() job.req:Cancel() end)
        end

        return
    end

    local job = table.remove(queue, 1)

    if job ~= nil then send(job) end
end

--[[
    method  - "GET" or "POST" (the client's HTTPRequest has no PUT / DELETE)
    path    - e.g. "/listings/mine"
    body    - table to send as JSON (POST only), or nil
    options - { noKey = true } for /auth/register
]]
local function request(method, path, body, onDone, options)
    onDone = onDone or function() end
    options = options or {}

    -- Same GET already waiting? Share it instead of sending twice.
    if method == "GET" then
        for _, waiting in ipairs(queue) do
            if waiting.method == "GET" and waiting.path == path then
                waiting.callbacks[#waiting.callbacks + 1] = onDone
                return
            end
        end
    end

    queue[#queue + 1] = {
        method = method,
        path = path,
        body = body,
        options = options,
        callbacks = { onDone },
        done = false,
    }
end

local function get(path, onDone)
    request("GET", path, nil, onDone)
end

local function post(path, body, onDone)
    request("POST", path, body, onDone)
end

-- Queue control ----------------------------------------------------------------------

function Api.init()
    if running then return end

    running = true
    queue = {}
    current = nil
    ticks = 0

    Event.Logic.Subscribe(SUBSCRIBER_ID, pump)
end

-- How many requests are waiting or in flight (handy for debugging).
function Api.pending()
    return #queue + (current ~= nil and 1 or 0)
end

-- Auth -------------------------------------------------------------------------------

-- First start with no saved key. 409 = tracking ID already registered.
function Api.register(trackingId, displayName, onDone)
    request("POST", "/auth/register", { trackingId = trackingId, displayName = displayName }, onDone, { noKey = true })
end

-- Every start-up: checks the key and keeps the display name current. 401 = bad key.
function Api.session(displayName, onDone)
    post("/auth/session", { displayName = displayName }, onDone)
end

-- New key, the old one stops working straight away. Response { secretKey }.
function Api.rotateKey(onDone)
    post("/auth/rotate_key", {}, onDone)
end

-- Listings ---------------------------------------------------------------------------

-- Response { variants = { { variant, count }, ... } }
function Api.getVariants(onDone)
    get("/listings/variants", onDone)
end

-- Response { listings, page, hasMore }
function Api.getListings(variant, page, onDone)
    get(formatStr("/listings?variant={}&page={}", urlEncode(variant), page or 1), onDone)
end

-- Response { listings }
function Api.getMyListings(onDone)
    get("/listings/mine", onDone)
end

-- Response { listing }
function Api.createListing(animal, onDone)
    post("/listings", { animal = animal:toApiData() }, onDone)
end

-- Response { listing, voidedCount }
function Api.updateListing(listingID, animal, onDone)
    post("/listings/" .. listingID .. "/update", { animal = animal:toApiData() }, onDone)
end

-- Response { ok }
function Api.cancelListing(listingID, onDone)
    post("/listings/" .. listingID .. "/cancel", {}, onDone)
end

-- Offers -----------------------------------------------------------------------------

-- Response { offers, listings }
function Api.getOffers(onDone)
    get("/offers", onDone)
end

-- Response { offer }
function Api.makeOffer(listingID, amount, onDone)
    post("/listings/" .. listingID .. "/offers", { amount = amount }, onDone)
end

-- Response { offer, listing }
function Api.acceptOffer(offerID, onDone)
    post("/offers/" .. offerID .. "/accept", {}, onDone)
end

-- Response { offer }
function Api.rejectOffer(offerID, onDone)
    post("/offers/" .. offerID .. "/reject", {}, onDone)
end

-- Response { offer, listing }
function Api.reverseOffer(offerID, onDone)
    post("/offers/" .. offerID .. "/reverse", {}, onDone)
end

-- Response { ok }
function Api.withdrawOffer(offerID, onDone)
    post("/offers/" .. offerID .. "/withdraw", {}, onDone)
end

-- Response { offer, listingClosed }
function Api.completeTrade(offerID, onDone)
    post("/offers/" .. offerID .. "/complete", {}, onDone)
end

-- Response { name }. Only works for accepted offers you're part of.
function Api.getTradeName(offerID, onDone)
    get("/offers/" .. offerID .. "/trade_name", onDone)
end

-- Drops everything waiting and cancels the request in flight (plugin shutdown).
-- No callbacks are called, the UI is going away anyway.
function Api.shutdown()
    Event.Logic.Unsubscribe(SUBSCRIBER_ID)
    running = false

    for _, job in ipairs(queue) do job.done = true end
    queue = {}

    if current ~= nil then
        local job = current

        job.done = true
        current = nil
        pcall(function() job.req:Cancel() end)
    end
end

return Api