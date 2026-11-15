local PofEvent = require("core/util/pofevent")
local Listing = require("core/models/listing")
local Api = require("core/data/api")

--[[
    
    Listhing Handler handles All Listings that been sent by the API. UI calls the methods here we fire
    PofEvent.ListingsUpdated whenever something changes.

    Listings are kept once per ID in byId and updated in place whichever request they came from
    (a variant page, /listings/mine, the listings attached to /offers, or an accept/reverse response).

    ListingsUpdated payload:
        type      - "variants" - sidebar variant list loaded
                    "variantLoaded"- a page of one variant loaded
                    "mineLoaded" - the players listings loaded
                    "created", "updated", "cancelled"
                    "changed"       quantity/status changed by an offer being accepted or reversed
                    "removed"       sold out and its last trade completed
                    "stored"        listings attached to /offers stored
        listing   - the listing that changed (single listing changes only)
        listingID
        variant   - "variantLoaded" only
        voidedCount - "updated" only, how many offers the server voided

    All methods that talk to the API take an optional onDone(ok, problem).
]]

local ListingsHandler = {
    byId = {},
    variants = {},
    variantPages = {},
    myListingIds = {},
    ready = false,
    ticks = 0,
    variantsLoadedAt = nil,
}

local FRESH_TICKS = 100

local function fire(eventType, listing, extra)
    local payload = extra or {}

    payload.type = eventType
    payload.listing = listing
    payload.listingID = payload.listingID or (listing and listing.id)

    PofEvent.ListingsUpdated.Fire(payload)
end

local function finish(onDone, ok, problem)
    if onDone ~= nil then onDone(ok, problem) end
end

local function removeId(ids, listingID)
    for i, id in ipairs(ids) do
        if id == listingID then
            table.remove(ids, i)
            return
        end
    end
end

function ListingsHandler:init()
    self.byId = {}
    self.variants = {}
    self.variantPages = {}
    self.myListingIds = {}
    self.ready = true
    self.ticks = 0
    self.variantsLoadedAt = nil
end

-- Adds or updates one listing from API data. Returns the Listing.
function ListingsHandler:storeListing(data)
    local listing = self.byId[data.id]

    if listing == nil then
        listing = Listing.fromData(data)
        self.byId[listing.id] = listing
    else
        listing:applyData(data)
    end

    return listing
end

-- Stores the listings attached to GET /offers, so offers on sold out listings still have details.
function ListingsHandler:storeListings(listings)
    for _, data in ipairs(listings or {}) do
        self:storeListing(data)
    end

    fire("stored")
end

function ListingsHandler:forgetListing(listingID)
    self.byId[listingID] = nil
    removeId(self.myListingIds, listingID)

    for _, page in pairs(self.variantPages) do
        removeId(page.ids, listingID)
    end
end

function ListingsHandler:getListingById(listingID)
    return self.byId[listingID]
end

function ListingsHandler:isPlayerListing(listing)
    return listing ~= nil and listing.isMine
end

function ListingsHandler:getVariants()
    return self.variants
end

function ListingsHandler:loadVariants(onDone)
    if self.variantsLoadedAt ~= nil and self.ticks - self.variantsLoadedAt < FRESH_TICKS then
        fire("variants")
        return finish(onDone, true)
    end


    Api.getVariants(function(ok, data)
        if not ok then return finish(onDone, false, data) end

        self.variants = data.variants or {}

        fire("variants")
        finish(onDone, true)
    end)
end

-- Active listings of one variant we have loaded so far, in the order the server sent them.
function ListingsHandler:getVariantListings(variant)
    local out = {}
    local page = self.variantPages[variant]

    if page == nil then return out end

    for _, id in ipairs(page.ids) do
        local listing = self.byId[id]

        if listing ~= nil and listing:isActive() then out[#out + 1] = listing end
    end

    return out
end

function ListingsHandler:hasMore(variant)
    local page = self.variantPages[variant]

    return page ~= nil and page.hasMore
end

function ListingsHandler:isLoading(variant)
    local page = self.variantPages[variant]

    return page ~= nil and page.loading
end

local function loadVariantPage(self, variant, pageNumber, onDone)
    local page = self.variantPages[variant]

    if page == nil then
        page = { ids = {}, page = 0, hasMore = false, loading = false }
        self.variantPages[variant] = page
    end

    if page.loading then return finish(onDone, false, "Already loading.") end

    page.loading = true

    Api.getListings(variant, pageNumber, function(ok, data)
        page.loading = false

        if not ok then return finish(onDone, false, data) end

        if pageNumber == 1 then page.ids = {} end

        for _, listingData in ipairs(data.listings or {}) do
            local listing = self:storeListing(listingData)
            page.ids[#page.ids + 1] = listing.id
        end

        page.page = pageNumber
        page.hasMore = data.hasMore == true

        if pageNumber == 1 then page.loadedAt = self.ticks end

        fire("variantLoaded", nil, { variant = variant })
        finish(onDone, true)
    end)
end

function ListingsHandler:loadVariant(variant, onDone, force)
    local page = self.variantPages[variant]

    if not force and page ~= nil and page.loadedAt ~= nil and not page.loading
        and self.ticks - page.loadedAt < FRESH_TICKS then
        fire("variantLoaded", nil, { variant = variant })
        return finish(onDone, true)
    end

    loadVariantPage(self, variant, 1, onDone)
end

function ListingsHandler:loadMore(variant, onDone)
    local page = self.variantPages[variant]

    if page == nil or not page.hasMore then return finish(onDone, false, "Nothing more to load.") end

    loadVariantPage(self, variant, page.page + 1, onDone)
end

-- The player's active listings this is what the Manage tab shows.
function ListingsHandler:getPlayerListings()
    local out = {}

    for _, id in ipairs(self.myListingIds) do
        local listing = self.byId[id]

        if listing ~= nil and listing:isActive() then out[#out + 1] = listing end
    end

    return out
end

function ListingsHandler:loadMyListings(onDone)
    Api.getMyListings(function(ok, data)
        if not ok then return finish(onDone, false, data) end

        self.myListingIds = {}

        for _, listingData in ipairs(data.listings or {}) do
            local listing = self:storeListing(listingData)
            self.myListingIds[#self.myListingIds + 1] = listing.id
        end

        fire("mineLoaded")
        finish(onDone, true)
    end)
end

-- Creates a new listing owned by the local player.
function ListingsHandler:newListing(animal, onDone)
    Api.createListing(animal, function(ok, data)
        if not ok then return finish(onDone, false, data) end

        local listing = self:storeListing(data.listing)

        table.insert(self.myListingIds, 1, listing.id)

        -- Show it straight away if that variant's page is loaded
        local page = self.variantPages[listing.animal.variant]
        if page ~= nil then table.insert(page.ids, 1, listing.id) end

        fire("created", listing)
        finish(onDone, true)
    end)
end

--[[
    Replaces a listings animal (price, quantity, traits, age, etc).
    The server voids offers if species/variant/age/traits changed and lowers pending offers on a price drop,
    OffersHandler refetches offers when it sees "updated".
]]
function ListingsHandler:updateListing(listingID, animal, onDone)
    Api.updateListing(listingID, animal, function(ok, data)
        if not ok then return finish(onDone, false, data) end

        local oldVariant = self.byId[listingID] and self.byId[listingID].animal.variant
        local listing = self:storeListing(data.listing)

        if oldVariant ~= nil and oldVariant ~= listing.animal.variant and self.variantPages[oldVariant] then
            removeId(self.variantPages[oldVariant].ids, listing.id)
        end

        fire("updated", listing, { voidedCount = data.voidedCount or 0 })
        finish(onDone, true)
    end)
end

function ListingsHandler:cancelListing(listingID, onDone)
    Api.cancelListing(listingID, function(ok, data)
        if not ok then return finish(onDone, false, data) end

        local listing = self.byId[listingID]

        self:forgetListing(listingID)

        fire("cancelled", listing, { listingID = listingID })
        finish(onDone, true)
    end)
end

--[[
    Accept / reverse responses carry the listing's new quantity and status (completed when sold out,
    active again when re-opened). Completed listings drop off the Listings and Manage tabs by themselves.
]]
function ListingsHandler:applyListingChange(data)
    if data == nil then return end

    fire("changed", self:storeListing(data))
end

-- Sold out and the last trade completed, the server closed it.
function ListingsHandler:removeClosedListing(listingID)
    local listing = self.byId[listingID]

    if listing == nil then return end

    self:forgetListing(listingID)

    fire("removed", listing, { listingID = listingID })
end

function ListingsHandler:onTick()
    self.ticks = self.ticks + 1
end

function ListingsHandler:shutdown()

end

return ListingsHandler
