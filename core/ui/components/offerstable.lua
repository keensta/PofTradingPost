local PofEvent = require("core/util/pofevent")
local OffersHandler = require("core/handlers/offershandler")
local ListingsHandler = require("core/handlers/listingshandler")
local Animal = require("core/models/animal")
local Offer = require("core/models/offer")

--[[
    OffersTable is a helper component that expands on prettyui tables to better suit our needs. 
    It adds specific features for offers, which are used across three separate systems. This approach allows 
    us to manage everything in one central location instead of duplicating code in three different places.

    Keeps itself up to date from PofEvent so callers just create it and destroy it.

    OffersTable.new(parent, {
        mode = "sent" | "listing" | "trades",
        listingId = id, - "listing" mode only
        x, y, width, height,
        dialogParent = parent, - where confirm popups go
        onMessage = function(text) - optional, shows handler errors to the player
    })

    listing - seller view of one listings offers Accept / Reject on pending. No buyer names.
    sent - buyer view of offers you've made: Withdraw on pending. No seller names.
    trades - accepted offers either side, with the other player's name (requested from the API on accept):
              Complete Trade, plus Reverse if you're the seller.

    Accepted and completed offers only ever show in trades mode.
]]

local OffersTable = {}
OffersTable.__index = OffersTable

local MODE_SENT = "sent"
local MODE_LISTING = "listing"
local MODE_TRADES = "trades"

local ROW_HEIGHT = 44
local BUTTON_GAP = 6

local STATUS_ORDER = {
    [Offer.Status.PENDING] = 1,
    [Offer.Status.ACCEPTED] = 2,
    [Offer.Status.REJECTED] = 3,
    [Offer.Status.VOIDED] = 4,
    [Offer.Status.COMPLETED] = 5,
}

local instanceCount = 0

function OffersTable.new(parent, options)
    options = options or {}

    local self = setmetatable({}, OffersTable)

    instanceCount = instanceCount + 1

    self.parent = parent
    self.mode = options.mode or MODE_LISTING
    self.listingId = options.listingId
    self.dialogParent = options.dialogParent
    self.onMessage = options.onMessage
    self.subscriberId = "pofTradingPost_offersTable_" .. instanceCount
    self.confirm = nil

    self:buildGrid(options)
    self:refresh()

    PofEvent.OffersUpdated.Subscribe(self.subscriberId, function()
        self:refresh(true)
    end)

    PofEvent.ListingsUpdated.Subscribe(self.subscriberId, function()
        self:refresh(true)
    end)

    return self
end

function OffersTable:isSellerView()
    return self.mode == MODE_LISTING
end

function OffersTable:message(text)
    if self.onMessage ~= nil then self.onMessage(text or "") end
end

function OffersTable:run(action, successText)
    self:message("")

    action(function(ok, problem)
        if self.grid == nil then return end -- table destroyed while we waited

        if not ok then
            self:message(problem)
        else
            self:message(successText)
        end
    end)
end

function OffersTable:openConfirm(options)
    self:closeConfirm()

    self.confirm = prettyui.Confirm.new(self.dialogParent, options)
end

function OffersTable:closeConfirm()
    if self.confirm ~= nil and not self.confirm.closed then
        pcall(function() self.confirm:Destroy() end)
    end

    self.confirm = nil
end

local function cellButton(cell, text, x, width, height, onClick, options)
    options = options or {}

    return prettyui.SimpleButton.new(cell, text, onClick, {
        x = x,
        y = 6,
        width = width,
        height = height - 14,
        disabled = options.disabled,
        tooltip = options.tooltip,
    })
end

-- Disabled while a request for this offer is in flight, stops double clicks.
local function busyOptions(offer, options)
    options = options or {}

    if OffersHandler:isBusy(offer.id) then
        options.disabled = true
        options.tooltip = "Waiting for the server..."
    end

    return options
end

-- Seller actions: Accept + Reject on pending.
function OffersTable:renderSellerActions(cell, row, cellWidth, cellHeight)
    local offer = row.offer

    if offer:isPending() then
        local halfWidth = math.floor((cellWidth - BUTTON_GAP * 3) / 2)
        local canAccept = OffersHandler:canAccept(offer)

        cellButton(cell, "Accept", BUTTON_GAP, halfWidth, cellHeight, function()
            self:run(function(done) OffersHandler:acceptOffer(offer.id, done) end,
                "Offer accepted, it's now on the Trades tab with the buyer's name.")
        end, busyOptions(offer, {
            disabled = not canAccept,
            tooltip = (not canAccept) and "Not enough left on the listing for this offer." or nil,
        }))

        cellButton(cell, "Reject", BUTTON_GAP * 2 + halfWidth, halfWidth, cellHeight, function()
            self:openConfirm({
                title = "REJECT OFFER",
                body = formatStr("Reject the offer for {} x {} ({})?", offer.amount, row.animal, row.total),
                confirmLabel = "REJECT",
                confirmVariant = "negative",
                onConfirm = function()
                    self:run(function(done) OffersHandler:rejectOffer(offer.id, done) end)
                end,
            })
        end, busyOptions(offer))
    end
end

-- Trade actions: Complete Trade for either side, Reverse for the seller.
function OffersTable:renderTradeActions(cell, row, cellWidth, cellHeight)
    local offer = row.offer

    if not offer:isAccepted() then return end

    local isSeller = OffersHandler:isPlayerSeller(offer)
    local completeWidth = cellWidth - BUTTON_GAP * 2

    if isSeller then
        completeWidth = math.floor((cellWidth - BUTTON_GAP * 3) * 0.6)
    end

    cellButton(cell, "Complete Trade", BUTTON_GAP, completeWidth, cellHeight, function()
        self:openConfirm({
            title = "COMPLETE TRADE",
            body = formatStr("Confirm the trade with {} for {} x {} ({}) has been done in game?",
                row.otherName, offer.amount, row.animal, row.total),
            confirmLabel = "COMPLETE",
            onConfirm = function()
                self:run(function(done) OffersHandler:completeTrade(offer.id, done) end)
            end,
        })
    end, busyOptions(offer))

    if isSeller then
        local reverseX = BUTTON_GAP * 2 + completeWidth

        cellButton(cell, "Reverse", reverseX, cellWidth - reverseX - BUTTON_GAP, cellHeight, function()
            self:run(function(done) OffersHandler:reverseAcceptance(offer.id, done) end)
        end, busyOptions(offer, { tooltip = "Undo the acceptance, the offer goes back to pending and the quantity back on the listing." }))
    end
end

function OffersTable:renderBuyerActions(cell, row, cellWidth, cellHeight)
    local offer = row.offer

    if not offer:isPending() then return end

    cellButton(cell, "Withdraw", BUTTON_GAP, cellWidth - BUTTON_GAP * 2, cellHeight, function()
        self:openConfirm({
            title = "WITHDRAW OFFER",
            body = formatStr("Withdraw your offer for {} x {}?", offer.amount, row.animal),
            confirmLabel = "WITHDRAW",
            confirmVariant = "negative",
            onConfirm = function()
                self:run(function(done) OffersHandler:withdrawOffer(offer.id, done) end)
            end,
        })
    end, busyOptions(offer))
end

function OffersTable:buildColumns()
    local columns = {}

    if self.mode == MODE_TRADES then
        return {
            { key = "role", label = "You Are", width = 90 },
            { key = "otherName", label = "Trade With", width = 140 },
            { key = "animal", label = "Animal", width = 220 },
            { key = "age", label = "Age", width = 90 },
            { key = "amount", label = "Quantity", width = 80 },
            { key = "price", label = "Price (each)", width = 100 },
            { key = "total", label = "Total", width = 100 },
            {
                label = "Actions",
                width = 260,
                stretch = false,
                render = function(cell, row, cellWidth, cellHeight)
                    self:renderTradeActions(cell, row, cellWidth, cellHeight)
                end
            },
        }
    end

    -- No name columns here, names only show on the Trades tab once accepted
    if self.mode ~= MODE_LISTING then
        columns[#columns + 1] = { key = "animal", label = "Animal", width = 220 }
        columns[#columns + 1] = { key = "age", label = "Age", width = 90 }
    end

    columns[#columns + 1] = { key = "amount", label = "Quantity", width = 80 }
    columns[#columns + 1] = { key = "price", label = "Price (each)", width = 100 }
    columns[#columns + 1] = { key = "total", label = "Total", width = 100 }
    columns[#columns + 1] = { key = "statusText", label = "Status", width = 110 }

    if self:isSellerView() then
        columns[#columns + 1] = {
            label = "Actions",
            width = 190,
            stretch = false,
            render = function(cell, row, cellWidth, cellHeight)
                self:renderSellerActions(cell, row, cellWidth, cellHeight)
            end
        }
    else
        columns[#columns + 1] = {
            label = "Actions",
            width = 110,
            stretch = false,
            render = function(cell, row, cellWidth, cellHeight)
                self:renderBuyerActions(cell, row, cellWidth, cellHeight)
            end
        }
    end

    return columns
end

function OffersTable:buildGrid(options)
    local emptyText = "No offers yet."

    if self.mode == MODE_SENT then emptyText = "You haven't made any offers." end
    if self.mode == MODE_TRADES then emptyText = "No trades to complete." end

    self.grid = prettyui.Table.new(self.parent, {
        x = options.x or 0,
        y = options.y or 0,
        width = options.width,
        height = options.height,
        rowHeight = ROW_HEIGHT,
        stretch = true,
        emptyText = emptyText,
        columns = self:buildColumns(),
    })
end

function OffersTable:getOffers()
    if self.mode == MODE_SENT then return OffersHandler:getSentOffers() end
    if self.mode == MODE_TRADES then return OffersHandler:getTrades() end

    -- MODE_LISTING: accepted ones are on the Trades tab
    local out = {}

    for _, offer in ipairs(OffersHandler:getOffersForListing(self.listingId)) do
        if not offer:isAccepted() and not offer:isCompleted() then out[#out + 1] = offer end
    end

    return out
end

local function toRow(offer, index)
    local row = offer:toRow()
    local listing = ListingsHandler:getListingById(offer.listingId)

    row.index = index
    row.price = Animal.formatPrice(offer.price)
    row.total = Animal.formatPrice(offer:getTotal())
    row.statusText = OffersHandler:getStatusText(offer)
    row.animal = listing and listing.animal.variant or "-"
    row.age = listing and listing.animal.age or "-"

    -- Trades tab
    row.role = OffersHandler:isPlayerSeller(offer) and "Selling" or "Buying"
    row.otherName = offer:isAccepted() and OffersHandler:getTradeName(offer) or "-"

    return row
end

function OffersTable:buildRows()
    local rows = {}

    for i, offer in ipairs(self:getOffers()) do
        rows[i] = toRow(offer, i)
    end

    table.sort(rows, function(a, b)
        local orderA = STATUS_ORDER[a.status] or 99
        local orderB = STATUS_ORDER[b.status] or 99

        if orderA ~= orderB then return orderA < orderB end

        return a.index < b.index
    end)

    return rows
end

function OffersTable:refresh(keepScroll)
    if self.grid == nil then return end

    self.grid:SetRows(self:buildRows(), keepScroll == true)
end

function OffersTable:getCount()
    return #self:getOffers()
end

function OffersTable:destroy()
    PofEvent.OffersUpdated.Unsubscribe(self.subscriberId)
    PofEvent.ListingsUpdated.Unsubscribe(self.subscriberId)

    self:closeConfirm()

    if self.grid ~= nil then
        pcall(function() self.grid:Destroy() end)
    end

    self.grid = nil
end

return OffersTable
