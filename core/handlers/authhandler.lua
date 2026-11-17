local PofEvent = require("core/util/pofevent")
local PlayerData = require("core/data/player")
local Settings = require("core/data/settings")
local API = require("core/data/api")

--[[

    AuthHandler:
    Gets the player connected to the API.

    Once PlayerData knows who you are (PlayerReady Event fired in player.lua):
    - No saved secret key - POST /auth/register with the tracking ID. If the server has never seen that
      tracking ID it creates the player and hands back a new key, which we save. This is how every
      player gets their key the first time they use the plugin.

      409 means the tracking ID is already registered (example: a new PC, formatted pc, PDB gets wiped etc), players can enter 
      the key from there other device or contact myself to help reset it due to it being hashed on the server I can't pass them it. 

      Player table is checked by a automatic routiune every couple of days and existing players not seen for over 4 months are wiped. 

    - Saved key - POST /auth/session to check it and keep the display name updated.

    Fires PofEvent.AuthChanged({ ready, status, text }) whenever the state changes.

    Other handlers API calls only work once ready.
]]

local AuthHandler = {
    status = "waiting",
    message = nil,
    connecting = false,
}

AuthHandler.Status = {
    WAITING = "waiting",       
    CONNECTING = "connecting",
    CONNECTED = "connected",
    NEEDS_KEY = "needsKey",
    BAD_KEY = "badKey",     
    OFFLINE = "offline",
    NO_PERMISSION = "noPermission",
}

local STATUS_TEXT = {
    waiting = "Waiting for your player details...",
    connecting = "Connecting to the Trading Post...",
    connected = "Connected to the Trading Post.",
    needsKey = "This account is already registered. Enter the secret key from your other device below.",
    badKey = "Your secret key wasn't accepted. Enter the right one below.",
    offline = "Can't reach the Trading Post server, will try again shortly.",
    noPermission = "POF Trading Post needs the tracking and HTTP permissions enabled.",
}

local STATUS_COLOURS = {
    connected = 0x5FD35FFF,  -- green
    needsKey = 0xFFA040FF,   -- orange
    waiting = 0x5AA9FFFF,    -- blue
    connecting = 0x5AA9FFFF, -- blue
}

AuthHandler.ERROR_COLOUR = 0xE05050FF -- red

local SUBSCRIBER_ID = "pofTradingPost_authHandler"

local function setStatus(status, message)
    AuthHandler.status = status
    AuthHandler.message = message

    PofEvent.AuthChanged.Fire({
        ready = status == AuthHandler.Status.CONNECTED,
        status = status,
        text = AuthHandler:getStatusText(),
    })
end

function AuthHandler:canReconnect()
    return self.status ~= self.Status.CONNECTED and not self.connecting
end

function AuthHandler:init()
    PofEvent.PlayerReady.Subscribe(SUBSCRIBER_ID, function()
        self:connect()
    end)

    if not Plugin.HasPermission(PluginPermissions.trackingAccess) then
        setStatus(self.Status.NO_PERMISSION)
    end
end

function AuthHandler:isReady()
    return self.status == self.Status.CONNECTED
end

function AuthHandler:getStatus()
    return self.status
end

function AuthHandler:getStatusText()
    return self.message or STATUS_TEXT[self.status] or ""
end

function AuthHandler:getStatusColour(status)
    return STATUS_COLOURS[status or self.status] or self.ERROR_COLOUR
end

function AuthHandler:connect(onDone)
    onDone = onDone or function() end

    if self.connecting then
        onDone(false, "Already connecting.")
        return
    end

    if not PlayerData.isReady() then
        setStatus(self.Status.WAITING)
        onDone(false, STATUS_TEXT.waiting)
        return
    end

    if not Plugin.HasPermission(PluginPermissions.httpAccess) then
        setStatus(self.Status.NO_PERMISSION)
        onDone(false, STATUS_TEXT.noPermission)
        return
    end

    self.connecting = true
    setStatus(self.Status.CONNECTING)

    local key = Settings.get("secretKey")

    if key == nil or key == "" then
        self:register(onDone)
    else
        self:startSession(onDone)
    end
end

-- First time on this tracking ID the server makes the player and gives their key.
function AuthHandler:register(onDone)
    API.register(PlayerData.getTrackingId(), PlayerData.getName(), function(ok, data, code)
        self.connecting = false

        if ok and data.secretKey ~= nil then
            Settings.set("secretKey", data.secretKey)
            Settings.set("keyRegistered", true)
            setStatus(self.Status.CONNECTED)
            onDone(true)
        elseif code == 409 then
            setStatus(self.Status.NEEDS_KEY)
            onDone(false, STATUS_TEXT.needsKey)
        else
            setStatus(self.Status.OFFLINE, data)
            onDone(false, data)
        end
    end)
end

function AuthHandler:startSession(onDone)
    API.session(PlayerData.getName(), function(ok, data, code)
        if ok then
            self.connecting = false
            Settings.set("keyRegistered", true)
            setStatus(self.Status.CONNECTED)
            onDone(true)
        elseif code == 401 then
            self:registerAfterBadKey(onDone)
        else
            self.connecting = false
            setStatus(self.Status.OFFLINE, data)
            onDone(false, data)
        end
    end)
end

function AuthHandler:registerAfterBadKey(onDone)
    API.register(PlayerData.getTrackingId(), PlayerData.getName(), function(ok, data, code)
        self.connecting = false

        if ok and data.secretKey ~= nil then
            Settings.set("previousSecretKey", Settings.get("secretKey"))
            Settings.set("secretKey", data.secretKey)
            Settings.set("keyRegistered", true)
            setStatus(self.Status.CONNECTED)
            onDone(true)
        elseif code == 409 then
            setStatus(self.Status.BAD_KEY)
            onDone(false, STATUS_TEXT.badKey)
        else
            setStatus(self.Status.OFFLINE, data)
            onDone(false, data)
        end
    end)
end

-- Settings page "Set SecretKey" save the key the player typed in and try it.
function AuthHandler:useKey(key, onDone)
    onDone = onDone or function() end
    key = key and key:gsub("^%s+", ""):gsub("%s+$", "") or ""

    if key == "" then
        onDone(false, "Enter your secret key first.")
        return
    end

    local currentKey = Settings.get("secretKey")

    if currentKey ~= "" and currentKey ~= key then
        Settings.set("previousSecretKey", currentKey)
    end

    if not Settings.set("secretKey", key) and Settings.get("secretKey") ~= key then
        onDone(false, "Couldn't save the key, try again once you're logged in.")
        return
    end

    self:connect(onDone)
end

-- Settings page "New Key" server makes a new key, the old one stops working.
function AuthHandler:rotateKey(onDone)
    onDone = onDone or function() end

    if not self:isReady() then
        onDone(false, "Connect to the Trading Post first.")
        return
    end

    API.rotateKey(function(ok, data)
        if not ok then
            onDone(false, data)
            return
        end

        Settings.set("previousSecretKey", Settings.get("secretKey"))
        Settings.set("secretKey", data.secretKey)

        onDone(true, data.secretKey)
    end)
end

function AuthHandler:clearLocalData(onDone)
    onDone = onDone or function() end

    if self.connecting then
        onDone(false, "Still connecting, try again in a moment.")
        return
    end

    if not Settings.clearAll() then
        onDone(false, "Couldn't clear your data, try again once you're logged in.")
        return
    end

    setStatus(self.Status.OFFLINE, "Local data cleared. Press Reconnect to connect again.")
    onDone(true)
end

function AuthHandler:reconnect(onDone)
    onDone = onDone or function() end

    if self.connecting then
        onDone(false, "Already connecting, give it a moment.")
        return
    end

    self:connect(onDone)
end

function AuthHandler:shutdown()
    PofEvent.PlayerReady.Unsubscribe(SUBSCRIBER_ID)
end

return AuthHandler