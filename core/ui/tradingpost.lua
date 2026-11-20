local ListingsTab = require("core/ui/tabs/listingstab")
local ManageTab = require("core/ui/tabs/managetab")
local OffersTab = require("core/ui/tabs/offerstab")
local TradesTab = require("core/ui/tabs/tradestab")
local Sync = require("core/data/sync")

local TradingPostUI = {
    activeTab = nil,
    activeTabObject = nil,
    activeTabValue = "",
    activeWindow = nil,
    tabs = nil,
}

local TAB_DEFS = {
    { text = "Listings", value = "listings", class = ListingsTab, tooltip = "Every player's listings, make offers here." },
    { text = "Manage",   value = "manage",   class = ManageTab,   tooltip = "Manage your listings or add new ones." },
    { text = "Offers",   value = "offers",   class = OffersTab,   tooltip = "Offers you've made on other players' listings." },
    { text = "Trades",   value = "trades",   class = TradesTab,   tooltip = "Accepted offers waiting to be traded in game." },
}

local TAB_CLASSES = {}
for _, def in ipairs(TAB_DEFS) do
    TAB_CLASSES[def.value] = def.class
end

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
            width = pageWidth,
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

local function onWindowClosed()
    local tabObject = TradingPostUI.activeTabObject

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
        width = 1500,
        height = 650,
        scrollable = false,
        destroyOnClose = true,
        onClose = function(win)
            onWindowClosed()
            if onClose ~= nil then onClose(win) end
        end,
    })

    TradingPostUI.activeWindow = window

    local tabList = {}
    for i, def in ipairs(TAB_DEFS) do
        tabList[i] = { text = def.text, value = def.value, tooltip = def.tooltip, scrollable = false }
    end

    local content = window.content
    local tabs = window:AddTabs(tabList, { height = content.height - 40, onChange = buildTab })

    TradingPostUI.tabs = tabs

    local activeTabIndex = tabs:GetActiveIndex()
    buildTabFor(tabs:GetPage(activeTabIndex), TAB_DEFS[activeTabIndex].value)

    -- Fetch offers now and every 3 minutes while the window is open (core/data/sync.lua)
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