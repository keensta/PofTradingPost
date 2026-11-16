local PofEvent = require("core/util/pofevent")
local OffersHandler = require("core/handlers/offershandler")
local ListingsHandler = require("core/handlers/listingshandler")
local AuthHandler = require("core/handlers/authhandler")
local ListingDialog = require("core/ui/dialogs/listingdialog")
local OffersTable = require("core/ui/components/offerstable")

local ManageTab = {}
ManageTab.__index = ManageTab

local TOOLBAR_HEIGHT = 32
local GAP = 6
local SUBSCRIBER_ID = "pofTradingPost_manageTab"
local MESSAGE_COLOUR = 0xC9BEA4FF

-- Offers popup layout
local OFFERS_DIALOG_WIDTH = 760
local OFFERS_DIALOG_HEIGHT = 460
local OFFERS_TABLE_HEIGHT = 330

function ManageTab.new(pageLayer, options)
    options = options or {}

    local self = setmetatable({}, ManageTab)
    self.pageLayer = pageLayer

    self.width = options.width
    self.height = options.height
    self.dialogParent = options.dialogParent

    self.listings = {}
    self.listingDialog = nil
    self.offersDialog = nil
    self.offersTable = nil
    self.confirm = nil

    self:buildToolbar()
    self:buildGrid()
    self:showListings()
    self:loadListings()

    PofEvent.ListingsUpdated.Subscribe(SUBSCRIBER_ID, function(event)
        self:showListings(true)

        -- Listing sold out, cancelled or closed while its offers popup was open
        local listing = self.offersListingId and ListingsHandler:getListingById(self.offersListingId)

        if self.offersListingId ~= nil and (listing == nil or not listing:isActive()) then
            self:closeOffersDialog()
        end
    end)

    -- Pending offer counts live in the grid
    PofEvent.OffersUpdated.Subscribe(SUBSCRIBER_ID, function()
        self:refreshGrid(true)
    end)

    -- Connected after the tab opened (first start / server came back)
    PofEvent.AuthChanged.Subscribe(SUBSCRIBER_ID, function(change)
        if change.ready then
            self:loadListings()
        else
            self:setMessage(change.text)
        end
    end)

    return self
end

function ManageTab:setListings(listings, keepScroll)
    self.listings = listings or {}

    self:refreshGrid(keepScroll)
end

-- Shows what ListingsHandler has, no request.
function ManageTab:showListings(keepScroll)
    self:setListings(ListingsHandler:getPlayerListings(), keepScroll)
end

--GET /listings/mine. The ListingsUpdated event redraws the grid when it arrives.
function ManageTab:loadListings()
    if not AuthHandler:isReady() then
        self:setMessage(AuthHandler:getStatusText())
        return
    end

    self:setMessage("Loading your listings...")

    ListingsHandler:loadMyListings(function(ok, problem)
        self:setMessage(ok and "" or problem)
    end)
end

function ManageTab:refreshGrid(keepScroll)
    local rows = {}

    for i, listing in ipairs(self.listings) do
        local row = listing:toRow()
        row.offerCount = OffersHandler:getPendingCount(listing.id)
        rows[i] = row
    end

    self.grid:SetRows(rows, keepScroll == true)
end

function ManageTab:setMessage(text)
    if self.messageText ~= nil then
        self.messageText.content = text or ""
    end
end

function ManageTab:buildToolbar()
    prettyui.SimpleButton.new(self.pageLayer, "Create Listing", function()
        self:openListingDialog()
    end, { x = 5, y = 5, width = 140, height = TOOLBAR_HEIGHT - 8 })

    self.messageText = prettyui.Text.new(self.pageLayer, {
        text = AuthHandler:isReady() and "" or AuthHandler:getStatusText(),
        x = 160,
        y = 4,
        width = self.width - 170,
        height = TOOLBAR_HEIGHT - 8,
        colour = MESSAGE_COLOUR,
    })
end

local function actionButton(cell, text, x, width, cellHeight, onClick)
    return prettyui.SimpleButton.new(cell, text, onClick, {
        x = x, y = 6, width = width, height = cellHeight - 14
    })
end

function ManageTab:buildGrid()
    local gridY = TOOLBAR_HEIGHT + GAP

    self.grid = prettyui.Table.new(self.pageLayer, {
        x = 0,
        y = gridY,
        width = self.width,
        height = self.height - gridY,
        stretch = true,
        emptyText = "You have no active listings. Use Create Listing to add one.",
        columns = {
            { key = "type", label = "Type", width = 200 },
            { key = "quantity", label = "Quantity", width = 70 },
            { key = "price", label = "Price (each)", width = 90 },
            { key = "age", label = "Age", width = 90 },
            { key = "trait1", label = "Trait 1", width = 140 },
            { key = "trait2", label = "Trait 2", width = 140 },
            { key = "trait3", label = "Trait 3", width = 140 },
            { key = "offerCount", label = "Offers", width = 60 },
            {
                label = "Actions",
                width = 250,
                stretch = false,
                render = function(cell, row, cellWidth, cellHeight)
                    local buttonWidth = math.floor((cellWidth - GAP * 4) / 3)

                    actionButton(cell, "Edit", GAP, buttonWidth, cellHeight, function()
                        self:openListingDialog(row.listing)
                    end)

                    actionButton(cell, "Offers", GAP * 2 + buttonWidth, buttonWidth, cellHeight, function()
                        self:openOffersDialog(row.listing)
                    end)

                    actionButton(cell, "Cancel", GAP * 3 + buttonWidth * 2, buttonWidth, cellHeight, function()
                        self:confirmCancel(row.listing)
                    end)
                end
            }
        }
    })
end

--[[
    Create (listing = nil) or edit a listing.
    Editing species/variant/age/traits on a listing with current offers asks first, since those offers get voided.
]]
function ManageTab:openListingDialog(listing)
    self:closeListingDialog()

    self.listingDialog = ListingDialog.new(self.dialogParent, {
        listing = listing,
        onSubmit = function(animal, done)
            if listing == nil then
                ListingsHandler:newListing(animal, done)
                return
            end

            if not listing.animal:detailsMatch(animal) and self:countCurrentOffers(listing.id) > 0 then
                self:confirmEdit(listing, animal, done) -- form stays open behind the confirm
                return
            end

            ListingsHandler:updateListing(listing.id, animal, done)
        end,
    })
end

function ManageTab:countCurrentOffers(listingID)
    local count = 0

    for _, offer in ipairs(OffersHandler:getOffersForListing(listingID)) do
        if offer:isCurrent() then count = count + 1 end
    end

    return count
end

function ManageTab:confirmEdit(listing, animal, done)
    self:openConfirm({
        title = "VOID OFFERS?",
        body = formatStr("Changing the species, variant, age or traits will void {} current offer(s). Continue?",
            self:countCurrentOffers(listing.id)),
        confirmLabel = "SAVE",
        confirmVariant = "negative",
        onConfirm = function()
            ListingsHandler:updateListing(listing.id, animal, done)
        end,
        onCancel = function()
            done(false, "")
        end,
    })
end

function ManageTab:confirmCancel(listing)
    self:openConfirm({
        title = "CANCEL LISTING",
        body = formatStr("Cancel your {} listing? Any offers on it will be removed.", listing.animal.variant),
        cancelLabel = "KEEP",
        confirmLabel = "CANCEL LISTING",
        confirmVariant = "negative",
        onConfirm = function()
            self:setMessage("Cancelling listing...")

            ListingsHandler:cancelListing(listing.id, function(ok, problem)
                self:setMessage(ok and "Listing cancelled." or problem)
            end)
        end,
    })
end

function ManageTab:openOffersDialog(listing)
    self:closeOffersDialog()

    self.offersListingId = listing.id

    self.offersDialog = prettyui.Dialog.new(self.dialogParent, {
        title = "Offers - " .. listing.animal.variant,
        width = OFFERS_DIALOG_WIDTH,
        height = OFFERS_DIALOG_HEIGHT,
        content = function(window)
            local status = window:AddText({ text = "", colour = MESSAGE_COLOUR })

            self.offersTable = OffersTable.new(window.content, {
                mode = "listing",
                listingId = listing.id,
                x = 10,
                y = 40,
                width = OFFERS_DIALOG_WIDTH - 40,
                height = OFFERS_TABLE_HEIGHT,
                dialogParent = self.dialogParent,
                onMessage = function(text)
                    status.content = text
                end,
            })
        end,
        
        onDismiss = function()
            if self.offersTable ~= nil then
                self.offersTable:destroy()
                self.offersTable = nil
            end

            self.offersDialog = nil
            self.offersListingId = nil
        end,
        actions = {
            {
                label = "Close",
                variant = "neutral",
                onClick = function()
                    self:closeOffersDialog()
                end
            },
        },
    })
end

function ManageTab:closeOffersDialog()
    if self.offersTable ~= nil then
        self.offersTable:destroy()
        self.offersTable = nil
    end

    if self.offersDialog ~= nil and not self.offersDialog.closed then
        pcall(function() self.offersDialog:Destroy() end)
    end

    self.offersDialog = nil
    self.offersListingId = nil
end

function ManageTab:closeListingDialog()
    if self.listingDialog ~= nil then
        self.listingDialog:destroy()
    end

    self.listingDialog = nil
end

function ManageTab:openConfirm(options)
    self:closeConfirm()

    self.confirm = prettyui.Confirm.new(self.dialogParent, options)
end

function ManageTab:closeConfirm()
    if self.confirm ~= nil and not self.confirm.closed then
        pcall(function() self.confirm:Destroy() end)
    end

    self.confirm = nil
end

function ManageTab:destroy()
    PofEvent.ListingsUpdated.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.OffersUpdated.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.AuthChanged.Unsubscribe(SUBSCRIBER_ID)

    self:closeConfirm()
    self:closeListingDialog()
    self:closeOffersDialog()
end

return ManageTab
