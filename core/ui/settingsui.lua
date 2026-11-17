local Settings = require("core/data/settings")
local PofEvent = require("core/util/pofevent")
local AuthHandler = require("core/handlers/authhandler")

local SettingsUI = {
    view = nil
}
local SUBSCRIBER_ID = "pofTradingPost_settingsUI"

function SettingsUI.init()
    Event.SettingsLayerReady.Subscribe(SUBSCRIBER_ID, function(event)
        if SettingsUI.view then
            pcall(function() SettingsUI.view:Destroy() end)
        end

        local parent = event.component
        local view = prettyui.SimpleView.new(parent, {
            width = parent.width,
            height = parent.height
        })

        SettingsUI.view = view

        view:AddTitle("POF Trading Post Settings")

        local statusText = view:AddText({
            text = AuthHandler:getStatusText(),
            colour = AuthHandler:getStatusColour(),
        })

        view:AddText("Your secret key is generated the first time you use the Trading Post. It's sent to the API to confirm your identity, do not share it with anyone else. Using another PC? Copy the key here and enter it on the other one.")

        local keyField = view:AddTextField({
            text = Settings.get("secretKey"),
            width = 300,
            placeholder = "Enter your secret key here",
            maxLength = 40,
        })

        local function setStatus(text, colour)
            statusText.content = text or ""
            statusText.rgba = colour or AuthHandler:getStatusColour()
        end

        view:AddSimpleButton("Set SecretKey", function()
            local newKey = keyField:GetText()

            if newKey == Settings.get("secretKey") and AuthHandler:isReady() then
                setStatus("That's already your key.")
                return
            end

            setStatus("Checking key...")

            AuthHandler:useKey(newKey, function(ok, problem)
                if ok then
                    setStatus("Key accepted, connected to the Trading Post.")
                else
                    setStatus(problem)
                end
            end)
        end, { inline = true })

        view:AddSimpleButton("Generate New Key", function()
            setStatus("Generating a new key...")

            AuthHandler:rotateKey(function(ok, result)
                if ok then
                    keyField:SetText(result)
                    setStatus("New key saved. Your old key no longer works.")
                else
                    setStatus(result, ERROR_COLOUR)
                end
            end)
        end, { tooltip = "Makes a new key and stops the old one working. Use this if your key has been shared." })

        view:AddDivider({
            marginTop = 12,
            marginBottom = 12,
        })

        view:AddSimpleButton("Clear Local Data", function()
            prettyui.Confirm.new(parent, {
                title = "CLEAR LOCAL DATA",
                height = 200,
                body = "This deletes your saved secret key from this PC. If your account still exists on the server you will need your key to get back in, copy it first. This can't be undone.",
                confirmLabel = "Clear",
                confirmVariant = "negative",
                onConfirm = function()
                    setStatus("Clearing local data...")
                    keyField:SetText("")

                    AuthHandler:clearLocalData(function(ok, problem)
                        if ok then
                            setStatus("Data cleared, please use the reconnect button below")
                        else
                            setStatus(problem)
                        end
                    end)
                end,
            })
        end, {tooltip = "Deletes your saved key and settings on this PC." })

        view:AddSimpleButton("Reconnect", function()
            setStatus("Reconnecting...")

            AuthHandler:reconnect(function(ok, problem)
                if ok then
                    setStatus("Connected to the Trading Post.")
                else
                    setStatus(problem)
                end
            end)
        end, { inline = true, tooltip = "Try connecting to the Trading Post server again." })

        PofEvent.AuthChanged.Subscribe(SUBSCRIBER_ID, function(change)
            setStatus(change.text, AuthHandler:getStatusColour())

            if change.ready then
                keyField:SetText(Settings.get("secretKey"))
            end
        end)
    end)
end

function SettingsUI.shutdown()
    Event.SettingsLayerReady.Unsubscribe(SUBSCRIBER_ID)
    PofEvent.AuthChanged.Unsubscribe(SUBSCRIBER_ID)

    if SettingsUI.view then
        pcall(function()
            SettingsUI.view:Destroy()
        end)

        SettingsUI.view = nil
    end
end

return SettingsUI
