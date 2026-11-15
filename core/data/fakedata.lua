--[[
    TEMP: Test data until the Dart backend exists. Delete this file (and the FakeData lines in App) once
    ListingsHandler/OffersHandler load from the API.

    On start we load a pile of listings from fake players so the Listings tab has something to show.
    Once PlayerData knows who you are we also add a few listings owned by you (with offers from fake buyers)
    and a few offers you've "sent", so the Manage and Offers tabs can be tested.
]]

local PofEvent = require("core/util/pofevent")
local ListingsHandler = require("core/handlers/listingshandler")
local OffersHandler = require("core/handlers/offershandler")
local Animal = require("core/models/animal")
local AnimalSpecies = require("core/models/animalspecies")
local AnimalTraits = require("core/models/animaltraits")
local Listing = require("core/models/listing")
local Offer = require("core/models/offer")
local Uuid = require("core/util/uuid")
local Api = require("core/data/api")

local FakeData = {}

local SUBSCRIBER_ID = "pofTradingPost_fakeData"
local FAKE_LISTING_COUNT = 10000
local PLAYER_LISTING_COUNT = 6
local PLAYER_SENT_OFFER_COUNT = 5

-- Fake players, used as buyer names on your listings and seller names once your offers get accepted
local playerNames = {
    "Alice", "Bob", "Charlie", "Diana", "Eve",
    "Frank", "Grace", "Heidi", "Ivan", "Judy",
}

local function randomFrom(list)
    return list[math.random(#list)]
end

-- One random Animal: random species, a variant of that species, a real age,
-- 1-20 of them, and a random trait in each slot.
local function randomAnimal()
    local species = randomFrom(AnimalSpecies.getSpeciesNames())
    local variant = randomFrom(AnimalSpecies.getVariants(species))
    local animal = Animal.new({
        quantity = math.random(1, 20),
        species = species,
        variant = variant,
        age = randomFrom(Animal.getAges()),
        price = math.random(1, 5000) * 500, -- 500 to 2.5m, so all the k/m formats show up
        traits = {},
    })

    for slot = 1, 3 do
        animal:setTrait(slot, randomFrom(AnimalTraits.getDropdownOptions(slot)))
    end

    return animal
end

local function randomListing(isMine)
    return Listing.new({
        id = Uuid.generate(),
        animal = randomAnimal(),
        isMine = isMine,
    })
end

local function populateFakeListings(count)
    local listings = {}

    for i = 1, count do
        listings[i] = randomListing(false)
    end

    ListingsHandler:loadListings(listings)

    print("FakeData: populated " .. count .. " fake listings")
end

-- Listings owned by the player, each with a handful of offers from fake buyers.
-- Some offers ask for more than the listing has so the "Exceeds stock" state shows up.
local function populatePlayerData()
    local listings = {}
    local offers = {}

    for _, listing in ipairs(ListingsHandler:getAllListings()) do
        listings[#listings + 1] = listing
    end

    for _ = 1, PLAYER_LISTING_COUNT do
        local listing = randomListing(true)
        listings[#listings + 1] = listing

        for _ = 1, math.random(0, 4) do
            local offer = Offer.new({
                id = Uuid.generate(),
                listingId = listing.id,
                isMine = false,
                amount = math.random(1, listing:getQuantity() + 3),
                price = listing:getPrice(),
            })

            offers[#offers + 1] = offer
            Api.setFakeTradeName(offer.id, randomFrom(playerNames)) -- The buyer, revealed when you accept
        end
    end

    -- Offers the player has sent on other people's listings
    for i = 1, PLAYER_SENT_OFFER_COUNT do
        local listing = listings[i]

        local offer = Offer.new({
            id = Uuid.generate(),
            listingId = listing.id,
            isMine = true,
            amount = math.random(1, listing:getQuantity()),
            price = listing:getPrice(),
        })

        -- First one has "already been accepted" by the seller so the buyer side of the Trades tab has something
        if i == 1 then
            offer.status = Offer.Status.ACCEPTED
        end

        offers[#offers + 1] = offer
        Api.setFakeTradeName(offer.id, randomFrom(playerNames)) -- The seller, revealed once accepted
    end

    ListingsHandler:loadListings(listings)
    OffersHandler:loadOffers(offers)

    print("FakeData: added " .. PLAYER_LISTING_COUNT .. " player listings and " .. #offers .. " offers")
end

function FakeData.init()
    populateFakeListings(FAKE_LISTING_COUNT)

    PofEvent.PlayerReady.Subscribe(SUBSCRIBER_ID, function()
        PofEvent.PlayerReady.Unsubscribe(SUBSCRIBER_ID)
        populatePlayerData()
    end)
end

function FakeData.shutdown()
    PofEvent.PlayerReady.Unsubscribe(SUBSCRIBER_ID)
end

return FakeData
