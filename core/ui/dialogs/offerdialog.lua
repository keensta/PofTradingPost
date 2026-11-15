local Animal = require("core/models/animal")
local OffersHandler = require("core/handlers/offershandler")

--[[
    Make Offer popup shown from the Listings tab.
    Offers are made at the listing price. If the listing has more than 1 we ask how many they want.
]]

local OfferDialog = {}
OfferDialog.__index = OfferDialog

local DIALOG_WIDTH = 420
local DIALOG_HEIGHT = 304
local QUANTITY_DIALOG_HEIGHT = 354
local LABEL_WIDTH = 110
local FIELD_WIDTH = 250
local ROW_HEIGHT = 26
local ERROR_COLOUR = 0xE05050FF
local TOTAL_COLOUR = 0xF2C66DFF

local function addDetailRow(window, label, value)
    window:AddText({ text = label, width = LABEL_WIDTH, height = ROW_HEIGHT })

    return window:AddText({ text = value or "-", inline = true, width = FIELD_WIDTH, height = ROW_HEIGHT })
end

local function traitsText(animal)
    local traits = {}

    for slot = 1, 3 do
        if animal.traits[slot] ~= nil then traits[#traits + 1] = animal.traits[slot] end
    end

    if #traits == 0 then return "None" end

    return table.concat(traits, ", ")
end

function OfferDialog.new(parent, options)
    options = options or {}

    local self = setmetatable({}, OfferDialog)

    self.listing = options.listing
    self.fields = {}

    self:build(parent)

    return self
end

function OfferDialog:build(parent)
    local listing = self.listing
    local animal = listing.animal
    local fields = self.fields
    local askQuantity = listing:getQuantity() > 1

    self.dialog = prettyui.Dialog.new(parent, {
        title = "Make Offer",
        width = DIALOG_WIDTH,
        height = askQuantity and QUANTITY_DIALOG_HEIGHT or DIALOG_HEIGHT,
        hideCloseButton = true,
        content = function(window)
            addDetailRow(window, "Animal", animal.variant)
            addDetailRow(window, "Age", animal.age)
            addDetailRow(window, "Traits", traitsText(animal))
            addDetailRow(window, "Price (each)", animal:getPrice())
            addDetailRow(window, "Available", tostring(listing:getQuantity()))

            if askQuantity then
                window:AddText({ text = "Quantity", width = LABEL_WIDTH, height = 30 })

                fields.quantity = window:AddTextField({
                    inline = true,
                    width = FIELD_WIDTH,
                    height = 30,
                    text = "1",
                    filterMode = ui.InputFieldFilterMode.NUMERIC,
                    maxLength = 5,
                    onChange = function()
                        self:updateTotal()
                    end,
                })
            end

            window:AddText({ text = "Total", width = LABEL_WIDTH, height = ROW_HEIGHT })
            fields.total = window:AddText({
                text = "", inline = true, width = FIELD_WIDTH, height = ROW_HEIGHT, colour = TOTAL_COLOUR
            })

            fields.error = window:AddText({ text = "", colour = ERROR_COLOUR })
        end,

        actions = {
            {
                label = "Cancel",
                variant = "neutral",
                onClick = function()
                    self:destroy()
                end
            },
            {
                label = "MAKE OFFER",
                variant = "positive",
                -- Stays open until the API answers, closes itself on success
                onClick = function()
                    if self.sending then return false end

                    self.sending = true
                    fields.error.content = "Sending offer..."

                    OffersHandler:newOffer(listing, self:getQuantity(), function(ok, problem)
                        self.sending = false

                        if not self:isOpen() then return end

                        if ok then
                            self:destroy()
                        else
                            fields.error.content = problem or ""
                        end
                    end)

                    return false
                end,
            },
        },
    })

    self:updateTotal()
end

-- nil if the quantity box has something silly in it
function OfferDialog:getQuantity()
    if self.fields.quantity == nil then return 1 end

    return math.tointeger(tonumber(self.fields.quantity:GetText()))
end

function OfferDialog:updateTotal()
    local total = self.fields.total

    if total == nil then return end

    local quantity = self:getQuantity()

    if quantity == nil or quantity < 1 then
        total.content = "-"
        return
    end

    total.content = Animal.formatPrice(self.listing:getPrice() * quantity)
end

function OfferDialog:isOpen()
    return self.dialog ~= nil and not self.dialog.closed
end

function OfferDialog:destroy()
    if self:isOpen() then
        pcall(function() self.dialog:Destroy() end)
    end

    self.dialog = nil
end

return OfferDialog
