local OffersTable = require("core/ui/components/offerstable")

local TradesTab = {}
TradesTab.__index = TradesTab

local MESSAGE_HEIGHT = 32
local GAP = 8
local MESSAGE_COLOUR = 0xC9BEA4FF

function TradesTab.new(pageLayer, options)
    options = options or {}

    local self = setmetatable({}, TradesTab)
    self.pageLayer = pageLayer

    self.width = options.width
    self.height = options.height
    self.dialogParent = options.dialogParent

    self:buildMessage()
    self:buildTable()

    return self
end

function TradesTab:setMessage(text)
    if self.messageText ~= nil then
        self.messageText.content = text or ""
    end
end

function TradesTab:buildMessage()
    self.messageText = prettyui.Text.new(self.pageLayer, {
        text = "Do the trade in game, then press Complete Trade.",
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
    if self.offersTable ~= nil then
        self.offersTable:destroy()
        self.offersTable = nil
    end
end

return TradesTab
