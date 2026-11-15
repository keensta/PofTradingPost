local Offer = {}
Offer.__index = Offer

--[[
    pending  - Waiting on the seller.
    accepted - Seller accepted, amount has been taken off the listing quantity. Can be reversed back to pending.
    rejected - Seller rejected.
    voided   - Listing species/variant/age/traits changed after the offer was made.
    completed - Accepted and the trade has been done in game. Off every tab from here.

    No player IDs on offers. The server sends:
    isMine     - true if the local player made this offer (they're the buyer).
                 They're the seller if the offer's listing has isMine = true.

    Names are never sent with offers. Once an offer is accepted the client asks the API for the other
    players name (OffersHandler:requestTradeName) and fills in one of these for the Trades tab:
    buyerName  - when the local player is the seller.
    sellerName - when the local player is the buyer.
]]

Offer.Status = {
    PENDING = "pending",
    ACCEPTED = "accepted",
    REJECTED = "rejected",
    VOIDED = "voided",
    COMPLETED = "completed",
}

function Offer.new(data)
    local self = setmetatable({}, Offer)

    self.id = data.id
    self.listingId = data.listingId
    self.isMine = data.isMine == true
    self.buyerName = data.buyerName
    self.sellerName = data.sellerName
    self.amount = data.amount or 0
    self.price = data.price or 0
    self.status = data.status or Offer.Status.PENDING

    return self
end

function Offer:toData()
    return {
        id = self.id,
        listingId = self.listingId,
        isMine = self.isMine,
        buyerName = self.buyerName,
        sellerName = self.sellerName,
        amount = self.amount,
        price = self.price,
        status = self.status,
    }
end

function Offer.fromData(data)
    return Offer.new(data)
end

--[[
    Updates this offer in place from newer API data. Names are only kept while it's accepted
    anything else and they're hidden again.
]]
function Offer:applyData(data)
    self.listingId = data.listingId or self.listingId
    self.isMine = data.isMine == true
    self.amount = data.amount or self.amount
    self.price = data.price or self.price
    self.status = data.status or self.status

    if self.status ~= Offer.Status.ACCEPTED then
        self.buyerName = nil
        self.sellerName = nil
    end
end

function Offer:isPending()
    return self.status == Offer.Status.PENDING
end

function Offer:isAccepted()
    return self.status == Offer.Status.ACCEPTED
end

function Offer:isCompleted()
    return self.status == Offer.Status.COMPLETED
end

function Offer:isCurrent()
    return self:isPending() or self:isAccepted()
end

function Offer:getTotal()
    return self.price * self.amount
end

function Offer:toRow()
    return {
        id = self.id,
        listingId = self.listingId,
        buyerName = self.buyerName,
        sellerName = self.sellerName,
        amount = self.amount,
        price = self.price,
        status = self.status,
        offer = self,
    }
end

return Offer
