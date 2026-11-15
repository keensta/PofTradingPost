local Animal = require("core/models/animal")

local Listing = {}
Listing.__index = Listing

--[[
    active    - Visible on the Listings tab, can receive offers.
    completed - Quantity hit 0 from accepted offers. Hidden from Listings/Manage tabs but kept while it still
                has trades to complete so they can still be reversed (which reopens the listing).
                Removed once the last trade is completed.

    No player IDs or seller name on listings. The server works out whos asking from their secret key
    and sends isMine = true on the players own listings.
]]

Listing.Status = {
    ACTIVE = "active",
    COMPLETED = "completed",
}

function Listing.new(data)
    assert(data.animal, "Listing.new: animal is required")

    local self = setmetatable({}, Listing)

    self.id = data.id

    if getmetatable(data.animal) == Animal then
        self.animal = data.animal
    else
        self.animal = Animal.fromData(data.animal)
    end

    self.isMine = data.isMine == true
    self.status = data.status or Listing.Status.ACTIVE

    return self
end

function Listing:toData()
    return {
        id = self.id,
        animal = self.animal:toData(),
        isMine = self.isMine,
        status = self.status,
    }
end

function Listing.fromData(data)
    return Listing.new(data)
end

function Listing:applyData(data)
    self.animal = Animal.fromData(data.animal)
    self.isMine = data.isMine == true
    self.status = data.status or self.status
end

function Listing:isActive()
    return self.status == Listing.Status.ACTIVE
end

function Listing:getQuantity()
    return self.animal.quantity
end

function Listing:getPrice()
    return self.animal.price
end

function Listing:toRow()
    local row = self.animal:toRow()

    row.id = self.id
    row.listing = self
    return row
end

return Listing
