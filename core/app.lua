local AuthHandler = require("core/handlers/authhandler")
local ListingsHandler = require("core/handlers/listingshandler")
local OffersHandler = require("core/handlers/offershandler")
local ContentUI = require("core/ui/contentui")
local SettingsUI = require("core/ui/settingsui")
local TradingPostUI = require("core/ui/tradingpost")
local PlayerData = require("core/data/player")
local Sync = require("core/data/sync")
local Api = require("core/data/api")

local App = {}

function App.start()
    ExecuteConsoleCommand("ppr PofTradingPost")
    ExecuteConsoleCommand("ppe PofTradingPost trackingAccess")
    ExecuteConsoleCommand("ppe PofTradingPost httpAccess")

    --print("POF Trading Post Loading...")

    AuthHandler:init()
    PlayerData.init()

    ListingsHandler:init()
    OffersHandler:init()
    Sync.init()
    ContentUI.init()
    SettingsUI.init()
end

function App.shutdown()
    ContentUI.shutdown()
    SettingsUI.shutdown()
    TradingPostUI.close()
    Sync.shutdown()
    Api.shutdown()
    OffersHandler:shutdown()
    ListingsHandler:shutdown()
    AuthHandler:shutdown()
    PlayerData.shutdown()
end

return App
