local PofEvent = require("core/util/pofevent")
local AuthHandler = require("core/handlers/authhandler")
local ListingsHandler = require("core/handlers/listingshandler.lua")
local OffersHandler = require("core/handlers/offershandler")

--[[
    
    Keeps offers up to date while the Trading Post window is open.

    - Window opens (TradingPostUI calls Sync.start) - refresh straight away.
    - Every REFRESH_MINUTES while it's open - refresh again, so buyers see accepted offers appear
      on their Trades tab without reopening the window.

    If we're not connected to the API yet (server was down), each refresh retries the connection instead.

    Uses the ServerLogic tick (every 0.6 seconds) to count time, the client API has no timers.
]]

local Sync = {
    running = false,
    ticks = 0,
}

local REFRESH_MINUTES = 10

local SECONDS_PER_TICK = 0.6
local REFRESH_TICKS = math.floor(REFRESH_MINUTES * 60 / SECONDS_PER_TICK)

local SUBSCRIBER_ID = "pofTradingPost_sync"

function Sync.init()
    Event.ServerLogic.Subscribe(SUBSCRIBER_ID, function()
        ListingsHandler:onTick()
        Sync.onTick()
    end)

    -- Connected while the window was open (e.g. first ever start), fetch now rather than in 10 minutes
    PofEvent.AuthChanged.Subscribe(SUBSCRIBER_ID, function(change)
        if change.ready and Sync.running then
            Sync.refreshNow()
        end
    end)
end

function Sync.onTick()
    if not Sync.running then return end

    Sync.ticks = Sync.ticks + 1

    if Sync.ticks >= REFRESH_TICKS then
        Sync.refreshNow()
    end
end

function Sync.refreshNow()
    Sync.ticks = 0

    if not AuthHandler:isReady() then
        -- Only retry when the server was unreachable. Missing / bad keys need the player to act in Settings.
        if AuthHandler:getStatus() == AuthHandler.Status.OFFLINE then
            AuthHandler:connect()
        end
        return
    end

    OffersHandler:refresh()
end

-- Window opened
function Sync.start()
    Sync.running = true
    Sync.refreshNow()
end

-- Window closed
function Sync.stop()
    Sync.running = false
    Sync.ticks = 0
end

function Sync.shutdown()
    Sync.stop()
    Event.ServerLogic.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.AuthChanged.Unsubscribe(SUBSCRIBER_ID)
end

return Sync
