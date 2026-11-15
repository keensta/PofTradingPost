local OffersTable = require("core/ui/components/offerstable")

local OffersTab = {}
OffersTab.__index = OffersTab

local MESSAGE_HEIGHT = 32
local GAP = 8
local MESSAGE_COLOUR = 0xC9BEA4FF

function OffersTab.new(pageLayer, options)
    options = options or {}

    local self = setmetatable({}, OffersTab)
    self.pageLayer = pageLayer

    self.width = options.width
    self.height = options.height
    self.dialogParent = options.dialogParent

    self.offersTable = nil

    self:buildMessage()
    self:buildTable()

    return self
end

function OffersTab:setMessage(text)
    if self.messageText ~= nil then
        self.messageText.content = text or ""
    end
end

function OffersTab:buildMessage()
    self.messageText = prettyui.Text.new(self.pageLayer, {
        text = "Offers you've made. Once a seller accepts one it moves to the Trades tab.",
        x = 5,
        y = 4,
        width = self.width - 10,
        height = MESSAGE_HEIGHT - 8,
        colour = MESSAGE_COLOUR,
    })
end

function OffersTab:buildTable()
    local tableY = MESSAGE_HEIGHT + GAP

    self.offersTable = OffersTable.new(self.pageLayer, {
        mode = "sent",
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

function OffersTab:destroy()
    if self.offersTable ~= nil then
        self.offersTable:destroy()
        self.offersTable = nil
    end
end

return OffersTab
