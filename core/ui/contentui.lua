local TradingPostUI = require("core/ui/tradingpost")
local AuthHandler = require("core/handlers/authhandler")
local PofEvent = require("core/util/pofevent")

local ContentUI = {
    view = nil
}
local SUBSCRIBER_ID = "pofTradingPost_contentUI"

function ContentUI.init()
    Event.ContentLayerReady.Subscribe(SUBSCRIBER_ID, function(event)

        if ContentUI.view then
            PofEvent.AuthChanged.Unsubscribe(SUBSCRIBER_ID)
            pcall(function() ContentUI.view:Destroy() end)
        end

        local parent = event.component

        local view = prettyui.SimpleView.new(parent, {
            categoryID = "auto",
            width = parent.width,
            height = parent.height
        })

        ContentUI.view = view

        view:AddTitle("POF Trading Post")

        view:AddSimpleButton("Open Trading Post", function()
            TradingPostUI.toggle()
        end, { inline = false })

        local statusText = view:AddText({
            text = AuthHandler:getStatusText(),
            colour = AuthHandler:getStatusColour(),
        })

        local function setStatus(text, colour)
            statusText.content = text or ""
            statusText.rgba = colour or AuthHandler:getStatusColour()
        end

        local reconnectButton

        reconnectButton = view:AddSimpleButton("Reconnect", function()
            reconnectButton:SetDisabled(true)
            setStatus("Reconnecting...")

            AuthHandler:reconnect(function(ok, problem)
                if not ok then
                    setStatus(problem, AuthHandler.ERROR_COLOUR)
                end

                reconnectButton:SetDisabled(not AuthHandler:canReconnect())
            end)
        end, {
            inline = false,
            disabled = not AuthHandler:canReconnect(),
            tooltip = "Try connecting to the Trading Post server again.",
        })

        PofEvent.AuthChanged.Subscribe(SUBSCRIBER_ID, function(change)
            setStatus(change.text, AuthHandler:getStatusColour(change.status))
            reconnectButton:SetDisabled(not AuthHandler:canReconnect())
        end)
    end)
end

function ContentUI.shutdown()
    Event.ContentLayerReady.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.AuthChanged.Unsubscribe(SUBSCRIBER_ID)

    if ContentUI.view then
        pcall(function()
            ContentUI.view:Destroy()
        end)

        ContentUI.view = nil
    end
end

return ContentUI