local Json = require("core/util/json")
local Settings = require("core/data/settings")

--[[
    Every call to the Dart backend lives here. Handlers call these never HTTPRequest directly.

    Base URL is "urls.api" in plugin.json. Needs the httpAccess permission.
    Every request except register sends the X-Secret-Key header.

    All functions take onDone(ok, data, statusCode):
        ok = true  - data is the decoded JSON response
        ok = false - data is a message the UI can show as is
]]

local Api = {}

local SECRET_KEY_HEADER = "X-Secret-Key"
local CANT_REACH = "Can't reach the Trading Post server, try again later."


local activeRequests = {}

local function urlEncode(text)
    return (tostring(text):gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- Turns a finished HTTPRequest into onDone(ok, data, statusCode).
local function handleResponse(req, onDone)
    activeRequests[req] = nil

    if req.cancelled then return end

    if req.timedOut or (req.failed and (req.responseCode or 0) == 0) then
        onDone(false, CANT_REACH, 0)
        return
    end

    local code = req.responseCode or 0
    local body = nil

    if req.data ~= nil and req.data ~= "" then
        body = Json.decode(req.data)
    end

    if code >= 200 and code < 300 then
        onDone(true, body or {}, code)
        return
    end

    -- API errors are always { "error": "message" }
    local message = type(body) == "table" and body.error or nil

    onDone(false, message or formatStr("Trading Post server error ({}).", code), code)
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

    if not Plugin.HasPermission(PluginPermissions.httpAccess) then
        onDone(false, "Enable the HTTP permission for POF Trading Post in the plugin settings.", 0)
        return
    end

    if Plugin.urls == nil or Plugin.urls.api == nil then
        onDone(false, "Trading Post server address missing from plugin.json.", 0)
        return
    end

    local key = Settings.get("secretKey")

    if not options.noKey and (key == nil or key == "") then
        onDone(false, "No secret key yet. Check the Trading Post settings page.", 401)
        return
    end

    local ok, problem = pcall(function()
        local req = HTTPRequest.new(Plugin.urls.api, path)

        req:AddHeader("Content-Type", "application/json")

        if not options.noKey then
            req:AddHeader(SECRET_KEY_HEADER, key)
        end

        activeRequests[req] = true

        local function onComplete(finished)
            local handled, err = pcall(handleResponse, finished, onDone)

            if not handled then
                activeRequests[finished] = nil
                print("POF Trading Post: response handler failed for " .. path .. ": " .. tostring(err))
            end
        end

        if method == "POST" then
            req:Post(Json.encode(body or {}), onComplete)
        else
            req:Get(onComplete)
        end
    end)

    if not ok then
        print("POF Trading Post: request to " .. path .. " failed: " .. tostring(problem))
        onDone(false, CANT_REACH, 0)
    end
end

local function get(path, onDone)
    request("GET", path, nil, onDone)
end

local function post(path, body, onDone)
    request("POST", path, body, onDone)
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

-- Cancels everything in flight (plugin shutdown).
function Api.shutdown()
    for req in pairs(activeRequests) do
        pcall(function() req:Cancel() end)
    end

    activeRequests = {}
end

return Api