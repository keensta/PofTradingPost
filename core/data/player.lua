local PofEvent = require("core/util/pofevent")

local PlayerData = {}

local SUBSCRIBER_ID = "pofTradingPost_playerID"
local trackingId = nil
local playerName = nil

function PlayerData.init()
    Event.ServerLogic.Subscribe(SUBSCRIBER_ID, function()
        if trackingId and playerName then
            return
        end
        if not Plugin.HasPermission(PluginPermissions.trackingAccess) then
            return
        end
        if not Player.IsAvailable() then
            return
        end

        if trackingId == nil then
            trackingId = Player.GetTrackingID()
        end

        if playerName == nil then
            local entity = Player.GetEntity()

            if entity ~= nil and entity.isValid then
                playerName = entity.displayName
            end
        end

        if trackingId and playerName then
           -- log("Got tracking ID")
            Event.ServerLogic.Unsubscribe(SUBSCRIBER_ID)

            PofEvent.PlayerReady.Fire({ trackingId = trackingId, name = playerName })
        end
    end)
end

function PlayerData.getTrackingId()
    return trackingId
end

function PlayerData.getName()
    return playerName
end

function PlayerData.isReady()
    return trackingId ~= nil and playerName ~= nil
end

function PlayerData.shutdown()
    Event.ServerLogic.Unsubscribe(SUBSCRIBER_ID)
end

return PlayerData
