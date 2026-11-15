local AnimalTraits = require("core/models/animaltraits")

local Animal = {}
Animal.__index = Animal

local ages = {
    "Egg",
    "Child",
    "Adolescent",
    "Adult",
    "Elder"
}

local PRICE_UNITS = {
    { 1e9, "b" },
    { 1e6, "m" },
    { 1e3, "k" },
}

local PRICE_SUFFIXES = {
    [""] = 1,
    k = 1e3,
    m = 1e6,
    b = 1e9,
}

--Max cash stack in game, nobody should be listing above this.
local MAX_PRICE = 2147483647

function Animal.getAges()
    return ages
end

-- Copies trait slots so instances never share the same table.
local function copyTraits(traits)
    local copy = {}
    for slot, name in pairs(traits or {}) do
        copy[slot] = name
    end

    return copy
end

function Animal.new(data)
    local self = setmetatable({}, Animal)

    self.quantity = data.quantity or 1
    self.species = data.species
    self.variant = data.variant
    self.age = data.age
    self.price = data.price
    self.traits = copyTraits(data.traits)

    return self
end

function Animal:toData()
    return {
        quantity = self.quantity,
        species = self.species,
        variant = self.variant,
        age = self.age,
        price = self.price,
        traits = copyTraits(self.traits),
    }
end

function Animal.fromData(data)
    if data.traits == nil and (data.trait1 or data.trait2 or data.trait3) then
        local copy = {}
        for key, value in pairs(data) do copy[key] = value end

        copy.traits = { [1] = data.trait1, [2] = data.trait2, [3] = data.trait3 }
        data = copy
    end

    return Animal.new(data)
end

function Animal:toApiData()
    return {
        species = self.species,
        variant = self.variant,
        age = self.age,
        quantity = self.quantity,
        price = self.price,
        trait1 = self.traits[1],
        trait2 = self.traits[2],
        trait3 = self.traits[3],
    }
end

function Animal:setTrait(slotIndex, traitName)
    if traitName == nil or traitName == "" then
        self.traits[slotIndex] = nil
        return true
    end

    if AnimalTraits.isValid(traitName, slotIndex) then
        self.traits[slotIndex] = traitName
        return true
    else
        print("Error: " .. traitName .. " cannot be placed in slot " .. slotIndex)
        return false
    end
end

function Animal:getQuantity()
    return self.quantity
end

function Animal:getFullName()
    return self.variant .. " " .. self.species
end

function Animal.formatPrice(value)
    if value == nil then return "-" end

    for _, unit in ipairs(PRICE_UNITS) do
        local size, suffix = unit[1], unit[2]

        if value >= size then
            local scaled = math.floor(value / size * 10) / 10
            local text = string.format("%.1f", scaled):gsub("%.0$", "")
            return text .. suffix
        end
    end

    return tostring(math.floor(value))
end

--[[
 Turns player typed prices into whole coins: "250000", "250,000", "250k", "1.5m", "2b".
 Returns nil if the text isn't a valid price.
]]
 function Animal.parsePrice(text)
    if text == nil then return nil end

    local cleaned = string.lower(tostring(text)):gsub("[%s,]", "")
    local number, suffix = cleaned:match("^(%d+%.?%d*)([kmb]?)$")

    if number == nil then return nil end

    local value = math.floor(tonumber(number) * PRICE_SUFFIXES[suffix])

    if value < 1 or value > MAX_PRICE then return nil end

    return value
end

function Animal:getPrice()
    return Animal.formatPrice(self.price)
end

--[[ 
    True if both animals are the same species, variant, age and traits.
    Price and quantity are ignored, changing those doesn't void offers.
]]
function Animal:detailsMatch(other)
    if other == nil then return false end

    if self.species ~= other.species or self.variant ~= other.variant or self.age ~= other.age then
        return false
    end

    for slot = 1, 3 do
        if self.traits[slot] ~= other.traits[slot] then
            return false
        end
    end

    return true
end

function Animal:getAge()
    return self.age
end

function Animal:getTrait(slotIndex)
    return self.traits[slotIndex] or "No trait in this slot"
end


function Animal:toRow()
    return {
        type = self.variant,
        species = self.species,
        variant = self.variant,
        age = self.age,
        quantity = self.quantity,
        price = self:getPrice(),
        trait1 = self.traits[1] or "-",
        trait2 = self.traits[2] or "-",
        trait3 = self.traits[3] or "-",
        animal = self,
    }
end

return Animal