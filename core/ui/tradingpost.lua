local ListingsTab = require("core/ui/tabs/listingstab")
local ManageTab = require("core/ui/tabs/managetab")
local OffersTab = require("core/ui/tabs/offerstab")
local TradesTab = require("core/ui/tabs/tradestab")
local OffersHandler = require("core/handlers/offershandler")
local PofEvent = require("core/util/pofevent")
local Sync = require("core/data/sync")

local TradingPostUI = {
    activeTab = nil,       
    activeTabObject = nil, -- ListingsTab / ManageTab / OffersTab instance, destroy() unsubscribes its events
    activeTabValue = "",
    activeWindow = nil,
    tabs = nil,
    tradesVisible = nil,
}

local TAB_LISTINGS = "listings"
local TAB_MANAGE = "manage"
local TAB_OFFERS = "offers"
local TAB_TRADES = "trades"

-- Trades must stay the last tab, hiding the last tab's button leaves no gap in the tab bar
local TRADES_INDEX = 4
local SUBSCRIBER_ID = "pofTradingPost_tradingPostUI"

local TAB_RIGHT_INSET = 16

local TAB_CLASSES = {
    [TAB_LISTINGS] = ListingsTab,
    [TAB_MANAGE] = ManageTab,
    [TAB_OFFERS] = OffersTab,
    [TAB_TRADES] = TradesTab,
}

local function isLoaded(component)
    return component ~= nil and ui.Interfaces:GetInterface(component.interfaceID) ~= nil
end

local function destroyOldTab()
    local tabObject = TradingPostUI.activeTabObject
    local activeTab = TradingPostUI.activeTab

    -- Tab first so it unsubscribes and closes its dialogs before its components go
    if tabObject ~= nil and tabObject.destroy ~= nil then
        pcall(function() tabObject:destroy() end)
    end

    if activeTab ~= nil and isLoaded(activeTab) then
        pcall(function() activeTab:Destroy() end)
    end

    TradingPostUI.activeTab = nil
    TradingPostUI.activeTabObject = nil
end

--[[
    Only the visible tab's components exist at any given time, so we have to rebuild the tab when switching.
    This is due to a component limitation so to avoid taking up IDS we get rid of the shit we don't need.

    Please JAGEX just give us either more component IDS or more catagoryIDS so less likely to clash with other plugins!!!
]]
local function buildTabFor(page, value)
    destroyOldTab()

    local root = ui.Layer.new(page.content)
    root:SetPos(0, 0)
    root:SetSize(0, 0, 1.0, 1.0)
    root.clickthrough = true

    local pageWidth = root.width or page.content.width
    local pageHeight = root.height or page.content.height

    local TabClass = TAB_CLASSES[value]

    if TabClass ~= nil then
        TradingPostUI.activeTabObject = TabClass.new(root, {
            width = pageWidth - TAB_RIGHT_INSET,
            height = pageHeight,
            dialogParent = TradingPostUI.parent
        })
    end

    TradingPostUI.activeTab = root
    TradingPostUI.activeTabValue = value
end

local function buildTab(_, _, value, page)
    buildTabFor(page, value)
end

--[[
    Trades tab only shows while there are accepted offers to trade.
    prettyui Tabs has no hide yet, so we disable it (which also moves off it if it's open) and hide its button.
]]
local function setTradesTabVisible(visible)
    local tabs = TradingPostUI.tabs

    if tabs == nil or TradingPostUI.tradesVisible == visible then return end

    TradingPostUI.tradesVisible = visible

    local tab = tabs:GetTab(TRADES_INDEX)

    if tab == nil then return end

    tabs:SetDisabled(TRADES_INDEX, not visible)

    if tab.visual ~= nil then tab.visual.hidden = not visible end
    if tab.hit ~= nil then tab.hit.hidden = not visible end
end

local function refreshTradesTab()
    setTradesTabVisible(OffersHandler:hasTrades())
end

local function subscribeEvents()
    PofEvent.OffersUpdated.Subscribe(SUBSCRIBER_ID, refreshTradesTab)
    PofEvent.ListingsUpdated.Subscribe(SUBSCRIBER_ID, refreshTradesTab)
    PofEvent.PlayerReady.Subscribe(SUBSCRIBER_ID, refreshTradesTab)
end

local function unsubscribeEvents()
    PofEvent.OffersUpdated.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.ListingsUpdated.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.PlayerReady.Unsubscribe(SUBSCRIBER_ID)
end

local function onWindowClosed()
    local tabObject = TradingPostUI.activeTabObject

    unsubscribeEvents()
    Sync.stop()

    if tabObject ~= nil and tabObject.destroy ~= nil then
        pcall(function() tabObject:destroy() end)
    end

    TradingPostUI.activeTab = nil
    TradingPostUI.activeTabObject = nil
    TradingPostUI.activeTabValue = ""
    TradingPostUI.activeWindow = nil
    TradingPostUI.parent = nil
    TradingPostUI.tabs = nil
    TradingPostUI.tradesVisible = nil
end

function TradingPostUI.createWindow(parent, onClose)
    TradingPostUI.parent = parent

    local window = prettyui.Window.new(parent, {
        title = "Trading Post",
        categoryID = "auto",
        x = -400,
        y = -350,
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = 1300,
        height = 650,
        scrollable = false,
        destroyOnClose = true,
        onClose = function(win)
            onWindowClosed()
            if onClose ~= nil then onClose(win) end
        end,
    })

    TradingPostUI.activeWindow = window

    local content = window.content
    local tabs = window:AddTabs({
        { text = "Listings", value = TAB_LISTINGS, tooltip = "Every player's listings, make offers here.", scrollable = false },
        { text = "Manage", value = TAB_MANAGE, tooltip = "Manage your listings or add new ones.", scrollable = false },
        { text = "Offers", value = TAB_OFFERS, tooltip = "Offers you've made on other players' listings.", scrollable = false },
        { text = "Trades", value = TAB_TRADES, tooltip = "Accepted offers waiting to be traded in game.", scrollable = false }
    }, { height = content.height - 40, onChange = buildTab })

    TradingPostUI.tabs = tabs

    local activeTabIndex = tabs:GetActiveIndex()
    local tabValues = { TAB_LISTINGS, TAB_MANAGE, TAB_OFFERS, TAB_TRADES }

    buildTabFor(tabs:GetPage(activeTabIndex), tabValues[activeTabIndex])

    refreshTradesTab()
    subscribeEvents()

    -- Fetch offers now and every 10 minutes while the window is open (core/data/sync.lua)
    Sync.start()

    return window
end

function TradingPostUI.isOpen()
    return TradingPostUI.activeWindow ~= nil
end

function TradingPostUI.open()
    if TradingPostUI.isOpen() then return TradingPostUI.activeWindow end

    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

    if parent == nil then
        print("POF Trading Post: plugin build layer not available, can't open window")

        return nil
    end

    return TradingPostUI.createWindow(parent)
end

function TradingPostUI.close()
    local window = TradingPostUI.activeWindow

    if window == nil then return end

    -- Tab cleanup first (closes its dialogs) while everything still exists
    destroyOldTab()

    pcall(function() window:Destroy() end)
    onWindowClosed()
end

function TradingPostUI.toggle()
    if TradingPostUI.isOpen() then
        TradingPostUI.close()
    else
        TradingPostUI.open()
    end
end

return TradingPostUI
