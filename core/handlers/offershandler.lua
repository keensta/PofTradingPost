local PofEvent = require("core/util/pofevent")
local ListingsHandler = require("core/handlers/listingshandler")
local Offer = require("core/models/offer")
local Api = require("core/data/api")

--[[
    Offershandler handles every Offer the API has sent. UI calls the methods here, fire PofEvent.OffersUpdated whenever something changes.

    OffersUpdated payload:
        offers - every offer we know about
        type   - "loaded", "created", "accepted", "rejected", "reversed", "withdrawn", "removed", "traded",
                 "nameLoaded", "busy"
        offer  - the offer that changed (single offer changes only)

    Rules (the server enforces all of these, we just mirror them for the UI):
    - Offers are made at the listing price no lower offers (yet to be implemented at a later date).
    - Accepting takes the amount off the listing quantity. Pending offers asking for more than what's left can't be accepted.
    - Accepting can be reversed, the amount goes back on the listing.
    - Accepted offers are "trades". They leave the Offers tab and show on the Trades tab until either side
      presses Complete Trade (To be decided if needs both confirmations or only seller). Once a sold out listing has no trades left the server closes it.
    - Nobody sees the other player's name until an offer is accepted. Then we ask the API for it.
    - Listing species/variant/age/traits changes void every current offer, price drops lower pending offers.
      The server does this, we re-fetch offers when a listing is updated.
    - Cancelled listings take their offers with them.

    Offers are fetched by refresh when the Trading Post opens and every 10 minutes while it's open (core/data/sync.lua).
    All methods that talk to the API take an optional onDone(ok, problem).
]]

local OffersHandler = {
    offers = {},
    busy = {},
    nameRequests = {},
    nameFailed = {},
    refreshing = false,
    ready = false,
}

local SUBSCRIBER_ID = "pofTradingPost_offersHandler"

local function fire(eventType, offer)
    PofEvent.OffersUpdated.Fire({ offers = OffersHandler.offers, type = eventType, offer = offer })
end

local function finish(onDone, ok, problem)
    if onDone ~= nil then onDone(ok, problem) end
end

function OffersHandler:init()
    self.offers = {}
    self.busy = {}
    self.nameRequests = {}
    self.nameFailed = {}

    PofEvent.ListingsUpdated.Subscribe(SUBSCRIBER_ID, function(event)
        self:onListingsUpdated(event)
    end)

    self.ready = true
end

-- GET /offers replaces our offers with the servers, keeping names we already fetched for trades.
function OffersHandler:refresh(onDone)
    if self.refreshing then return finish(onDone, false, "Already refreshing.") end

    self.refreshing = true

    Api.getOffers(function(ok, data)
        self.refreshing = false

        if not ok then return finish(onDone, false, data) end

        -- Listings first so offers can look them up when the event fires
        ListingsHandler:storeListings(data.listings)
        self:storeOffers(data.offers)

        finish(onDone, true)
    end)
end

-- Same offer objects are reused (updated in place) so trade names we already have survive a refresh.
function OffersHandler:storeOffers(offers)
    local existing = {}

    for _, offer in ipairs(self.offers) do
        existing[offer.id] = offer
    end

    local stored = {}

    for _, data in ipairs(offers or {}) do
        local offer = existing[data.id]

        if offer ~= nil then
            offer:applyData(data)
        else
            offer = Offer.fromData(data)
        end

        stored[#stored + 1] = offer
    end

    self.offers = stored

    fire("loaded")

    for _, offer in ipairs(self:getTrades()) do
        self:requestTradeName(offer)
    end
end

function OffersHandler:onListingsUpdated(event)
    if event.type == "cancelled" or event.type == "removed" then
        self:removeOffersForListing(event.listingID)
    elseif event.type == "updated" then
        -- Server may have voided or repriced offers on it
        self:refresh()
    end
end

function OffersHandler:getOfferById(offerID)
    for _, offer in ipairs(self.offers) do
        if offer.id == offerID then return offer end
    end

    return nil
end

function OffersHandler:getOffersForListing(listingID)
    local out = {}

    for _, offer in ipairs(self.offers) do
        if offer.listingId == listingID then out[#out + 1] = offer end
    end

    return out
end

function OffersHandler:getPendingCount(listingID)
    local count = 0

    for _, offer in ipairs(self.offers) do
        if offer.listingId == listingID and offer:isPending() then count = count + 1 end
    end

    return count
end

function OffersHandler:getSentOffers()
    local out = {}

    for _, offer in ipairs(self.offers) do
        if offer.isMine and not offer:isAccepted() and not offer:isCompleted() then
            out[#out + 1] = offer
        end
    end

    return out
end

function OffersHandler:isPlayerSeller(offer)
    return ListingsHandler:isPlayerListing(ListingsHandler:getListingById(offer.listingId))
end

function OffersHandler:isPlayerBuyer(offer)
    return offer.isMine
end

function OffersHandler:getTrades()
    local out = {}

    for _, offer in ipairs(self.offers) do
        if offer:isAccepted() and (self:isPlayerBuyer(offer) or self:isPlayerSeller(offer)) then
            out[#out + 1] = offer
        end
    end

    return out
end

-- The Trades tab only shows when this is true.
function OffersHandler:hasTrades()
    return #self:getTrades() > 0
end

--[[
    Asks the API for the other players name on an accepted offer buyers name if we're selling,
    sellers name if we're buying. Fires OffersUpdated "nameLoaded" when it arrives.
    We may later have it so names are shown once a listing has a offer etc but for now only when we are at the trade stage
]]
function OffersHandler:requestTradeName(offer)
    if offer == nil or not offer:isAccepted() then return end
    if self.nameRequests[offer.id] then return end

    local isSeller = self:isPlayerSeller(offer)

    if isSeller and offer.buyerName ~= nil then return end
    if not isSeller and offer.sellerName ~= nil then return end

    self.nameRequests[offer.id] = true
    self.nameFailed[offer.id] = nil

    Api.getTradeName(offer.id, function(ok, data)
        self.nameRequests[offer.id] = nil

        -- Reversed or completed while we were waiting, don't show it
        if not offer:isAccepted() then return end

        if not ok or data.name == nil then
            self.nameFailed[offer.id] = true
        elseif isSeller then
            offer.buyerName = data.name
        else
            offer.sellerName = data.name
        end

        fire("nameLoaded", offer)
    end)
end

function OffersHandler:getTradeName(offer)
    local name = self:isPlayerSeller(offer) and offer.buyerName or offer.sellerName

    if name ~= nil then return name end
    if self.nameFailed[offer.id] then return "Unavailable" end

    return "Loading..."
end

function OffersHandler:getPlayerOfferFor(listingID)
    for _, offer in ipairs(self.offers) do
        if offer.listingId == listingID and offer.isMine and offer:isPending() then
            return offer
        end
    end

    return nil
end

function OffersHandler:canAccept(offer)
    if offer == nil or not offer:isPending() or self.busy[offer.id] then return false end

    local listing = ListingsHandler:getListingById(offer.listingId)

    if listing == nil or not listing:isActive() then return false end

    return offer.amount <= listing:getQuantity()
end

function OffersHandler:isBusy(offerID)
    return self.busy[offerID] == true
end

-- Text for the Status column. Covers the "can't accept" cases so the player knows why.
function OffersHandler:getStatusText(offer)
    if self.busy[offer.id] then return "Working..." end

    if offer:isPending() then
        local listing = ListingsHandler:getListingById(offer.listingId)

        if listing == nil then return "Listing gone" end
        if not listing:isActive() then return "Sold out" end
        if offer.amount > listing:getQuantity() then return "Exceeds stock" end

        return "Pending"
    end

    if offer.status == Offer.Status.ACCEPTED then return "Accepted" end
    if offer.status == Offer.Status.REJECTED then return "Rejected" end
    if offer.status == Offer.Status.VOIDED then return "Voided" end
    if offer.status == Offer.Status.COMPLETED then return "Traded" end

    return offer.status
end

--[[
    Runs an API action on one offer - marks it busy (buttons disable), calls apiCall(offerID, callback),
    then onSuccess(data) if it worked. Stops double clicks sending the same request twice.
]]
local function runOfferAction(self, offerID, apiCall, onSuccess, onDone)
    local offer = self:getOfferById(offerID)

    if offer == nil then return finish(onDone, false, "Offer no longer exists.") end
    if self.busy[offerID] then return finish(onDone, false, "Already working on that offer.") end

    self.busy[offerID] = true
    fire("busy", offer)

    apiCall(offerID, function(ok, data)
        self.busy[offerID] = nil

        if not ok then
            fire("busy", offer)
            return finish(onDone, false, data)
        end

        onSuccess(offer, data)
        finish(onDone, true)
    end)
end

function OffersHandler:newOffer(listing, amount, onDone)
    amount = math.tointeger(amount)

    if listing == nil then return finish(onDone, false, "This listing no longer exists.") end
    if not listing:isActive() then return finish(onDone, false, "This listing has sold out.") end
    if ListingsHandler:isPlayerListing(listing) then return finish(onDone, false, "You can't offer on your own listing.") end
    if self:getPlayerOfferFor(listing.id) ~= nil then
        return finish(onDone, false, "You already have a pending offer on this listing.")
    end

    if amount == nil or amount < 1 then return finish(onDone, false, "Quantity must be at least 1.") end
    if amount > listing:getQuantity() then
        return finish(onDone, false, formatStr("Only {} available.", listing:getQuantity()))
    end

    Api.makeOffer(listing.id, amount, function(ok, data)
        if not ok then return finish(onDone, false, data) end

        local offer = Offer.fromData(data.offer)

        table.insert(self.offers, offer)

        fire("created", offer)
        finish(onDone, true)
    end)
end

function OffersHandler:acceptOffer(offerID, onDone)
    runOfferAction(self, offerID, Api.acceptOffer, function(offer, data)
        offer:applyData(data.offer)

        fire("accepted", offer)
        ListingsHandler:applyListingChange(data.listing)

        self:requestTradeName(offer)
    end, onDone)
end

function OffersHandler:rejectOffer(offerID, onDone)
    runOfferAction(self, offerID, Api.rejectOffer, function(offer, data)
        offer:applyData(data.offer)
        fire("rejected", offer)
    end, onDone)
end

-- Puts an accepted offer back to pending and returns its amount to the listing (re-opening it if it had completed).
function OffersHandler:reverseAcceptance(offerID, onDone)
    runOfferAction(self, offerID, Api.reverseOffer, function(offer, data)
        offer:applyData(data.offer)
        self.nameFailed[offer.id] = nil

        fire("reversed", offer)
        ListingsHandler:applyListingChange(data.listing)
    end, onDone)
end

--[[
    Either side marks an accepted offer as traded in game. It drops off the Trades tab.
    If that was the last trade on a sold out listing, the server closes the listing and we drop it.

    Still undecided if we should have it so only seller can complete or if need both to confirm
]]
function OffersHandler:completeTrade(offerID, onDone)
    runOfferAction(self, offerID, Api.completeTrade, function(offer, data)
        self:removeOffer(offer.id)
        fire("traded", offer)

        if data.listingClosed then
            ListingsHandler:removeClosedListing(offer.listingId)
        end
    end, onDone)
end

function OffersHandler:withdrawOffer(offerID, onDone)
    runOfferAction(self, offerID, Api.withdrawOffer, function(offer)
        self:removeOffer(offer.id)
        fire("withdrawn", offer)
    end, onDone)
end

function OffersHandler:removeOffer(offerID)
    for i, offer in ipairs(self.offers) do
        if offer.id == offerID then
            table.remove(self.offers, i)
            return
        end
    end
end

function OffersHandler:removeOffersForListing(listingID)
    local kept = {}

    for _, offer in ipairs(self.offers) do
        if offer.listingId ~= listingID then kept[#kept + 1] = offer end
    end

    if #kept == #self.offers then return end

    self.offers = kept

    fire("removed")
end

function OffersHandler:shutdown()
    PofEvent.ListingsUpdated.Unsubscribe(SUBSCRIBER_ID)
end

return OffersHandler
