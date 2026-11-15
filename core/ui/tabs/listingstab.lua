local PofEvent = require("core/util/pofevent")
local OffersHandler = require("core/handlers/offershandler")
local ListingsHandler = require("core/handlers/listingshandler")
local AuthHandler = require("core/handlers/authhandler")
local OfferDialog = require("core/ui/dialogs/offerdialog")

--[[
    Everyone's active listings, one animal type (variant) at a time.

    Sidebar comes from GET /listings/variants (types that have listings, with counts).
    Picking one loads GET /listings?variant=X, 200 at a time, Load More gets the next 200.
    Players make offers from here. Your own listings show as "Yours" and listings you've
    already got a pending offer on show as "Offered".
]]

local ListingsTab = {}
ListingsTab.__index = ListingsTab

local SIDEBAR_WIDTH = 210
local GAP = 6
local FOOTER_HEIGHT = 66 -- Load More button + status line under the sidebar
local MESSAGE_COLOUR = 0xC9BEA4FF
local SUBSCRIBER_ID = "pofTradingPost_listingsTab"

function ListingsTab.new(pageLayer, options)
    options = options or {}

    local self = setmetatable({}, ListingsTab)
    self.pageLayer = pageLayer

    self.width = options.width
    self.height = options.height
    self.dialogParent = options.dialogParent

    self.selectedType = nil
    self.sidebarList = nil
    self.typeByID = {}
    self.building = false
    self.offerDialog = nil

    self:buildGrid()
    self:buildFooter()
    self:loadVariants()

    PofEvent.ListingsUpdated.Subscribe(SUBSCRIBER_ID, function(event)
        if event.type == "variants" then
            self:buildSidebar()
        end

        self:refreshGrid(true)
        self:updateFooter()
    end)

    -- Offer button state ("Offer" / "Offered") depends on offers too
    PofEvent.OffersUpdated.Subscribe(SUBSCRIBER_ID, function()
        self:refreshGrid(true)
    end)

    -- Connected after the tab opened (first start / server came back)
    PofEvent.AuthChanged.Subscribe(SUBSCRIBER_ID, function(change)
        if change.ready then
            self:loadVariants()
        else
            self:setMessage(change.text)
        end
    end)

    return self
end

function ListingsTab:setMessage(text)
    if self.messageText ~= nil then
        self.messageText.content = text or ""
    end
end

-- GET /listings/variants, the event then rebuilds the sidebar and loads the selected variant.
function ListingsTab:loadVariants()
    if not AuthHandler:isReady() then
        self:setMessage(AuthHandler:getStatusText())
        return
    end

    self:setMessage("Loading...")

    ListingsHandler:loadVariants(function(ok, problem)
        if not ok then self:setMessage(problem) end
    end)
end

-- GET /listings?variant=X (first page).
function ListingsTab:loadSelected()
    if self.selectedType == nil then
        self:setMessage("No listings yet.")
        return
    end

    self:setMessage("Loading " .. self.selectedType .. "...")

    ListingsHandler:loadVariant(self.selectedType, function(ok, problem)
        self:setMessage(ok and "" or problem)
    end)
end

function ListingsTab:openOfferDialog(listing)
    if self.offerDialog ~= nil and self.offerDialog:isOpen() then
        self.offerDialog:destroy()
    end

    self.offerDialog = OfferDialog.new(self.dialogParent, { listing = listing })
end

local function offerButtonState(listing)
    if ListingsHandler:isPlayerListing(listing) then
        return "Yours", true, "This is your listing."
    end

    if OffersHandler:getPlayerOfferFor(listing.id) ~= nil then
        return "Offered", true, "You already have a pending offer on this listing."
    end

    return "Offer", false, nil
end

function ListingsTab:buildGrid()
    local rightX = SIDEBAR_WIDTH + GAP

    self.grid = prettyui.Table.new(self.pageLayer, {
        x = rightX,
        y = 0,
        width = self.width - rightX,
        height = self.height,
        rowHeight = 60,
        stretch = true,
        emptyText = "No listings available.",
        columns = {
            { key = "type", label = "Type", width = 200 },
            { key = "quantity", label = "Quantity", width = 70 },
            { key = "price", label = "Price (each)", width = 90 },
            { key = "age", label = "Age", width = 90 },
            { key = "trait1", label = "Trait 1", width = 160 },
            { key = "trait2", label = "Trait 2", width = 160 },
            { key = "trait3", label = "Trait 3", width = 160 },
            {
                label = "Offer",
                width = 90,
                stretch = false,
                render = function(cell, row, cellWidth, cellHeight)
                    local text, disabled, tooltip = offerButtonState(row.listing)

                    return prettyui.SimpleButton.new(cell, text, function()
                        self:openOfferDialog(row.listing)
                    end, {
                        x = 6, y = 10, width = cellWidth - 12, height = cellHeight - 20,
                        disabled = disabled,
                        tooltip = tooltip,
                    })
                end
            }
        }
    })
end

-- Load More button + status line under the sidebar
function ListingsTab:buildFooter()
    local footerY = self.height - FOOTER_HEIGHT

    self.loadMoreButton = prettyui.SimpleButton.new(self.pageLayer, "Load More", function()
        if self.selectedType == nil then return end

        self:setMessage("Loading more...")

        ListingsHandler:loadMore(self.selectedType, function(ok, problem)
            self:setMessage(ok and "" or problem)
        end)
    end, {
        x = 0, y = footerY + 4, width = SIDEBAR_WIDTH, height = 26,
        disabled = true,
        tooltip = "Load the next 200 listings of this type.",
    })

    self.messageText = prettyui.Text.new(self.pageLayer, {
        text = "",
        x = 0,
        y = footerY + 34,
        width = SIDEBAR_WIDTH,
        height = 28,
        colour = MESSAGE_COLOUR,
    })
end

function ListingsTab:updateFooter()
    if self.loadMoreButton == nil then return end

    local canLoadMore = self.selectedType ~= nil and ListingsHandler:hasMore(self.selectedType)
        and not ListingsHandler:isLoading(self.selectedType)

    self.loadMoreButton:SetDisabled(not canLoadMore)
end

function ListingsTab:refreshGrid(keepScroll)
    self.grid:SetRows(self:filteredListings(), keepScroll == true)
end

function ListingsTab:filteredListings()
    local out = {}
    if self.selectedType == nil then return out end

    for _, listing in ipairs(ListingsHandler:getVariantListings(self.selectedType)) do
        out[#out + 1] = listing:toRow()
    end

    return out
end

function ListingsTab:buildSidebar()
    if self.sidebarList ~= nil then
        pcall(function() self.sidebarList:Destroy() end)
    end
    self.sidebarList = nil

    local variants = ListingsHandler:getVariants()
    local seen = {}

    for _, entry in ipairs(variants) do seen[entry.variant] = true end

    local previousType = self.selectedType

    if self.selectedType == nil or not seen[self.selectedType] then
        self.selectedType = variants[1] and variants[1].variant or nil
    end

    self.typeByID = {}

    local entries = {}

    for i, entry in ipairs(variants) do
        self.typeByID[i] = entry.variant
        entries[i] = {
            label = formatStr("{} ({})", entry.variant, entry.count),
            id = i,
            selected = (entry.variant == self.selectedType),
        }
    end

    if #entries > 0 then
        self.building = true

        self.sidebarList = prettyui.List.new(self.pageLayer, {
            x = 0,
            y = 0,
            width = SIDEBAR_WIDTH,
            height = self.height - FOOTER_HEIGHT,
            entries = entries,
            maxSelected = 1,
            onChange = function(_, entryID, selected)
                if self.building then return end

                if not selected then return end

                local typeName = self.typeByID[entryID]
                if typeName == nil or typeName == self.selectedType then return end

                self.selectedType = typeName
                self:refreshGrid()
                self:updateFooter()
                self:loadSelected()
            end,
        })

        self.building = false
    end

    -- Always reload the selected type when the sidebar is rebuilt (tab opened / reconnected)
    if self.selectedType ~= nil or previousType ~= nil then
        self:loadSelected()
    else
        self:setMessage("No listings yet.")
    end
end

function ListingsTab:destroy()
    PofEvent.ListingsUpdated.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.OffersUpdated.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.AuthChanged.Unsubscribe(SUBSCRIBER_ID)

    if self.offerDialog ~= nil then
        self.offerDialog:destroy()
        self.offerDialog = nil
    end
end

return ListingsTab
