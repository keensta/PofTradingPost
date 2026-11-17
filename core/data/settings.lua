--[[
    Central Storage point for all settings, Wraps PersistentDB with typed access, defaults
    and in memeory cache.
    Fires PofEvent.SettingChanged whenever a value changes so other files can react.
]]

local PofEvent = require("core/util/pofevent")
local PlayerData = require("core/data/player")

local Settings = {}

--Declare every setting here its type and default value
--Valid Types: "string", "int", "float", "bool", "table"
local definitions = {
    secretKey = { type = "string", default = "" },
    previousSecretKey = { type = "string", default = "" },
    keyRegistered = { type = "bool", default = false },
}

local getters = {
    string = "GetString", int = "GetInt", float = "GetFloat",
    bool = "GetBool", table = "GetStructuredData",
}

local setters = {
    string = "SetString", int = "SetInt", float = "SetFloat",
    bool = "SetBool", table = "SetStructuredData",
}

local cache = {}
local playerID = PlayerData.getTrackingId()

local function getDefinition(key)
    local def = definitions[key]
    assert(def, "Unknown setting: " .. tostring(key))
    return def
end

local function isValidType(def, value)
    if def.type == "string" then return type(value) == "string" end
    if def.type == "bool"   then return type(value) == "boolean" end
    if def.type == "table"  then return type(value) == "table" end
    if def.type == "int"    then return math.type(value) == "integer" end
    if def.type == "float"  then return type(value) == "number" end
    return false
end

-- Settings are stored per player ("<trackingId>:<key>"), so nothing can be read or savedmuntil the tracking ID has arrived. Returns nil if it hasn't yet.
local function storageKey(key)
    if playerID == nil then
        playerID = PlayerData.getTrackingId()
    end

    if playerID == nil then return nil end

    return playerID .. ":" .. key
end

--Gets the current key. If its not set they we return default (also the default before the player has loaded)
function Settings.get(key)
    local def = getDefinition(key)
    local fullKey = storageKey(key)

    if fullKey == nil then return def.default end

    if cache[fullKey] == nil then
        local value = PersistentDB[getters[def.type]](PersistentDB, fullKey)

        if value == nil then value = def.default end

        cache[fullKey] = value
    end

    return cache[fullKey]
end

--Sets the key to a new value. Returns false if the player hasn't loaded yet, nothing changed, or saving failed.
function Settings.set(key, value)
    local def = getDefinition(key)

    assert(isValidType(def, value),
        formatStr("Setting '{}' expects type {}", key, def.type))

    local fullKey = storageKey(key)

    if fullKey == nil then
        log("Can't save setting {} before the player has loaded", key)
        return false
    end

    local oldValue = Settings.get(key)

    if def.type ~= "table" and oldValue == value then
        return false
    end

    if not PersistentDB[setters[def.type]](PersistentDB, fullKey, value) then
        log("Failed to save setting {}", key)
        return false
    end

    cache[fullKey] = value

    PofEvent.SettingChanged.Fire({
        key = key,
        newValue = value,
        oldValue = oldValue,
    })

    return true
end

--Resets the setting back to default.
function Settings.reset(key)
    return Settings.set(key, getDefinition(key).default)
end

function Settings.clearAll()
    local prefix = storageKey("")

    if prefix == nil then
        log("Can't clear settings before the player has loaded")
        return false
    end

    local toDelete = {}

    PersistentDB:IterateEntries(function(key)
        if key:sub(1, #prefix) == prefix then
            toDelete[#toDelete + 1] = key
        end
        return false
    end)

    for _, fullKey in ipairs(toDelete) do
        PersistentDB:Delete(fullKey)
        cache[fullKey] = nil
    end

    for key, def in pairs(definitions) do
        PofEvent.SettingChanged.Fire({ key = key, newValue = def.default, oldValue = nil })
    end

    return true
end

return Settings
