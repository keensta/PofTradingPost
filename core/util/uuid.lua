--[[
    TEMPLATE is temp for testing purposing when it comes to creating new offers and listings this will be handled by our API Server later on.

    SecretKey is what's used when a user first uses the app we generate the secret key so we can use it to confirm who they are when they interact
    with the API server etc.
    Its also used whena user generates a new key. Old key and new key are sent to the server to confirm the change.
]]
local Uuid = {}

local TEMPLATE = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
local SECRETKEY_TEMPLATE = "xxxyxxxxx-SKxxxxxxyxxxxxxy"

function Uuid.generate()
    -- Replace each x with a random hex digit (0-f),
    -- and y with 8-b (the UUID v4 "variant" bits)
    return (string.gsub(TEMPLATE, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

function Uuid.generateKey()
    -- Replace each x with a random hex digit (0-f),
    -- and y with 8-b (the UUID v4 "variant" bits)
    return (string.gsub(SECRETKEY_TEMPLATE, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

return Uuid
