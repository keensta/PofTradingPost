local PofEvent = require("core/util/pofevent")
local OffersHandler = require("core/handlers/offershandler")
local OffersTable = require("core/ui/components/offerstable")

local TradesTab = {}
TradesTab.__index = TradesTab

local MESSAGE_HEIGHT = 32
local GAP = 6
local MESSAGE_COLOUR = 0xC9BEA4FF
local SUBSCRIBER_ID = "pofTradingPost_tradesTab"

local TEXT_DEFAULT = "Do the trade in game, then press Complete Trade."
local TEXT_EMPTY = "No trades right now. Accepted offers will show up here."

local function getTradeIds()
    local ids = {}
    local count = 0

    for _, offer in ipairs(OffersHandler:getTrades()) do
        ids[offer.id] = true
        count = count + 1
    end

    return ids, count
end

function TradesTab.new(pageLayer, options)
    options = options or {}

    local self = setmetatable({}, TradesTab)
    self.pageLayer = pageLayer

    self.width = options.width
    self.height = options.height
    self.dialogParent = options.dialogParent

    self.knownTrades, self.tradeCount = getTradeIds()

    self:buildMessage()
    self:buildTable()

    -- OffersTable redraws itself, we only watch for trades appearing / the list emptying
    PofEvent.OffersUpdated.Subscribe(SUBSCRIBER_ID, function()
        self:onOffersUpdated()
    end)

    return self
end

function TradesTab:setMessage(text)
    if self.messageText ~= nil then
        self.messageText.content = text or ""
    end
end

function TradesTab:defaultMessage()
    return self.tradeCount > 0 and TEXT_DEFAULT or TEXT_EMPTY
end

function TradesTab:onOffersUpdated()
    local current, count = getTradeIds()
    local newCount = 0

    for offerID in pairs(current) do
        if not self.knownTrades[offerID] then
            newCount = newCount + 1
        end
    end

    local wasEmpty = self.tradeCount == 0

    self.knownTrades = current
    self.tradeCount = count

    if newCount > 0 then
        local noun = newCount == 1 and "trade" or "trades"
        self:setMessage(newCount .. " new " .. noun .. " came in. " .. TEXT_DEFAULT)
    elseif wasEmpty ~= (count == 0) then
        self:setMessage(self:defaultMessage())
    end
end

function TradesTab:buildMessage()
    self.messageText = prettyui.Text.new(self.pageLayer, {
        text = self:defaultMessage(),
        x = 5,
        y = 4,
        width = self.width - 10,
        height = MESSAGE_HEIGHT - 8,
        colour = MESSAGE_COLOUR,
    })
end

function TradesTab:buildTable()
    local tableY = MESSAGE_HEIGHT + GAP

    self.offersTable = OffersTable.new(self.pageLayer, {
        mode = "trades",
        x = 0,
        y = tableY,
        width = self.width,
        height = self.height - tableY,
        dialogParent = self.dialogParent,
        onMessage = function(text)
            self:setMessage(text)
        end,
    })
end

function TradesTab:destroy()
    PofEvent.OffersUpdated.Unsubscribe(SUBSCRIBER_ID)

    if self.offersTable ~= nil then
        self.offersTable:destroy()
        self.offersTable = nil
    end
end

return TradesTab