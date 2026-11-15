local Animal = require("core/models/animal")
local AnimalSpecies = require("core/models/animalspecies")
local AnimalTraits = require("core/models/animaltraits")

--[[
    Create / Edit listing popup. Same form for both, edit mode just pre-fills it from the listing.

]]

local ListingDialog = {}
ListingDialog.__index = ListingDialog

local DIALOG_WIDTH = 460
local DIALOG_HEIGHT = 470
local EDIT_DIALOG_HEIGHT = 510
local LABEL_WIDTH = 110
local FIELD_WIDTH = 290
local ROW_HEIGHT = 30
local NO_TRAIT = "(None)"
local ERROR_COLOUR = 0xE05050FF
local HINT_COLOUR = 0xC9BEA4FF
local MAX_QUANTITY = 99999

local function addFormRow(window, label, addControl)
    window:AddText({ text = label, width = LABEL_WIDTH, height = ROW_HEIGHT })

    return addControl({ inline = true, width = FIELD_WIDTH, height = ROW_HEIGHT })
end

local function traitEntries(slotIndex)
    local entries = { { label = NO_TRAIT, id = 0 } }

    for i, traitName in ipairs(AnimalTraits.getDropdownOptions(slotIndex)) do
        entries[#entries + 1] = { label = traitName, id = i }
    end

    return entries
end

local function variantEntries(species)
    local entries = {}

    for i, variantName in ipairs(AnimalSpecies.getVariants(species)) do
        entries[i] = { label = variantName, id = i, order = i }
    end

    return entries
end

local function indexOf(list, value)
    for i, item in ipairs(list) do
        if item == value then return i end
    end

    return nil
end

-- Starting values for the form, from the listing when editing or defaults when creating.
local function initialValues(listing)
    local speciesNames = AnimalSpecies.getSpeciesNames()
    local ages = Animal.getAges()

    if listing == nil then
        return {
            species = 1,
            speciesName = speciesNames[1],
            variant = 1,
            age = indexOf(ages, "Adult") or 1,
            traits = { 0, 0, 0 },
            quantity = "1",
            price = "",
        }
    end

    local animal = listing.animal
    local species = indexOf(speciesNames, animal.species) or 1
    local traits = {}

    for slot = 1, 3 do
        traits[slot] = indexOf(AnimalTraits.getDropdownOptions(slot), animal.traits[slot]) or 0
    end

    return {
        species = species,
        speciesName = speciesNames[species],
        variant = indexOf(AnimalSpecies.getVariants(speciesNames[species]), animal.variant) or 1,
        age = indexOf(ages, animal.age) or 1,
        traits = traits,
        quantity = tostring(animal.quantity),
        price = tostring(animal.price),
    }
end

function ListingDialog.new(parent, options)
    options = options or {}

    local self = setmetatable({}, ListingDialog)

    self.listing = options.listing
    self.onSubmit = options.onSubmit
    self.fields = {}
    self.closed = false
    self.saving = false

    self:build(parent)

    return self
end

function ListingDialog:build(parent)
    local isEdit = self.listing ~= nil
    local fields = self.fields
    local speciesNames = AnimalSpecies.getSpeciesNames()
    local ages = Animal.getAges()
    local values = initialValues(self.listing)

    self.dialog = prettyui.Dialog.new(parent, {
        title = isEdit and "Edit Listing" or "Create Listing",
        width = DIALOG_WIDTH,
        height = isEdit and EDIT_DIALOG_HEIGHT or DIALOG_HEIGHT,
        hideCloseButton = true,
        content = function(window)
            fields.species = addFormRow(window, "Species", function(opts)
                opts.entries = speciesNames
                opts.selected = values.species
                opts.onChange = function(_, _, label)
                    if fields.variant ~= nil then
                        fields.variant:SetEntries(variantEntries(label), 1)
                    end
                end
                return window:AddComboBox(opts)
            end)

            fields.variant = addFormRow(window, "Variant", function(opts)
                opts.entries = variantEntries(values.speciesName)
                opts.selected = values.variant
                return window:AddComboBox(opts)
            end)

            fields.age = addFormRow(window, "Age", function(opts)
                opts.entries = ages
                opts.selected = values.age
                return window:AddComboBox(opts)
            end)

            fields.traits = {}

            for slot = 1, 3 do
                fields.traits[slot] = addFormRow(window, "Trait " .. slot, function(opts)
                    opts.entries = traitEntries(slot)
                    opts.selected = values.traits[slot]
                    return window:AddComboBox(opts)
                end)
            end

            fields.quantity = addFormRow(window, "Quantity", function(opts)
                opts.text = values.quantity
                opts.filterMode = ui.InputFieldFilterMode.NUMERIC
                opts.maxLength = 5
                return window:AddTextField(opts)
            end)

            fields.price = addFormRow(window, "Price (each)", function(opts)
                opts.text = values.price
                opts.placeholder = "e.g. 250000, 250k, 1.5m"
                opts.maxLength = 13
                return window:AddTextField(opts)
            end)

            if isEdit then
                window:AddText({
                    text = "Changing species, variant, age or traits voids all current offers.",
                    colour = HINT_COLOUR,
                })
            end

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
                label = isEdit and "SAVE" or "CREATE",
                variant = "positive",
                -- Always returns false (keeps the popup open), we close it ourselves once the API says ok.
                onClick = function()
                    if self.saving then return false end

                    local animal, problem = self:readForm()

                    if animal == nil then
                        self:setError(problem)
                        return false
                    end

                    if self.onSubmit == nil then return true end

                    self.saving = true
                    self:setError("Saving...")

                    self.onSubmit(animal, function(ok, reason)
                        self.saving = false

                        if not self:isOpen() then return end

                        if ok then
                            self:destroy()
                        else
                            self:setError(reason)
                        end
                    end)

                    return false
                end,
            },
        },
    })
end

function ListingDialog:setError(text)
    if self.fields.error ~= nil then
        self.fields.error.content = text or ""
    end
end

function ListingDialog:readForm()
    local fields = self.fields

    local species = fields.species:GetSelectedLabel()
    local variant = fields.variant:GetSelectedLabel()
    local age = fields.age:GetSelectedLabel()

    if species == nil then return nil, "Pick a species." end
    if variant == nil then return nil, "Pick a variant." end
    if age == nil then return nil, "Pick an age." end

    local quantity = math.tointeger(tonumber(fields.quantity:GetText()))

    if quantity == nil or quantity < 1 then return nil, "Quantity must be at least 1." end
    if quantity > MAX_QUANTITY then return nil, "Quantity is too high." end

    local price = Animal.parsePrice(fields.price:GetText())

    if price == nil then return nil, "Enter a valid price, e.g. 250000, 250k or 1.5m." end

    local animal = Animal.new({
        quantity = quantity,
        species = species,
        variant = variant,
        age = age,
        price = price,
        traits = {},
    })

    for slot = 1, 3 do
        local traitName = fields.traits[slot]:GetSelectedLabel()

        if traitName ~= nil and traitName ~= NO_TRAIT then
            if not animal:setTrait(slot, traitName) then
                return nil, traitName .. " can't go in trait slot " .. slot .. "."
            end
        end
    end

    return animal
end

function ListingDialog:isOpen()
    return self.dialog ~= nil and not self.dialog.closed
end

function ListingDialog:destroy()
    if self:isOpen() then
        pcall(function() self.dialog:Destroy() end)
    end

    self.dialog = nil
    self.closed = true
end

return ListingDialog
