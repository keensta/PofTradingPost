local Settings = require("core/data/settings")
local PofEvent = require("core/util/pofevent")
local AuthHandler = require("core/handlers/authhandler")

local SettingsUI = {
    view = nil
}
local SUBSCRIBER_ID = "pofTradingPost_settingsUI"

local STATUS_COLOURS = {
    connected = 0x5FD35FFF,  -- green
    needsKey = 0xFFA040FF,   -- orange
    waiting = 0x5AA9FFFF,    -- blue
    connecting = 0x5AA9FFFF, -- blue
}

local ERROR_COLOUR = 0xE05050FF -- red

local function statusColour(status)
    return STATUS_COLOURS[status] or ERROR_COLOUR
end

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
            colour = statusColour(AuthHandler:getStatus()),
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
            statusText.rgba = colour or statusColour(AuthHandler:getStatus())
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

        PofEvent.AuthChanged.Subscribe(SUBSCRIBER_ID, function(change)
            setStatus(change.text, statusColour(change.status))

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
