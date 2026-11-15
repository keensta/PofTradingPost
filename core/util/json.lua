--[[
    Claude Used in the creation of this file. 
]]

local Json = {}

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(value)
    return '"' .. value:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(value)
    local count = 0

    for key in pairs(value) do
        if math.type(key) ~= "integer" or key < 1 then return false end
        count = count + 1
    end

    return count > 0 and count == #value
end

local encodeValue

local function encodeTable(value, seen)
    if seen[value] then error("Json.encode: circular table") end
    seen[value] = true

    local parts = {}

    if isArray(value) then
        for i = 1, #value do parts[i] = encodeValue(value[i], seen) end
        seen[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    for key, item in pairs(value) do
        if type(key) ~= "string" then error("Json.encode: object keys must be strings") end
        parts[#parts + 1] = encodeString(key) .. ":" .. encodeValue(item, seen)
    end

    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

encodeValue = function(value, seen)
    local valueType = type(value)

    if value == nil then return "null" end
    if valueType == "boolean" then return tostring(value) end
    if valueType == "string" then return encodeString(value) end
    if valueType == "table" then return encodeTable(value, seen) end

    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("Json.encode: can't encode " .. tostring(value))
        end
        if math.type(value) == "integer" then return string.format("%d", value) end
        return string.format("%.14g", value)
    end

    error("Json.encode: can't encode a " .. valueType)
end

function Json.encode(value)
    return encodeValue(value, {})
end

-- Decoder: recursive descent over the string, pos is the current index.

local decodeValue

local function skipWhitespace(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

local function decodeError(text, pos, message)
    error(string.format("Json.decode: %s at position %d", message, pos), 0)
end

local function codepointToUtf8(code)
    return utf8.char(code)
end

local function decodeString(text, pos)
    local parts = {}
    local i = pos + 1

    while true do
        local c = text:sub(i, i)

        if c == "" then decodeError(text, i, "unterminated string") end

        if c == '"' then
            return table.concat(parts), i + 1
        elseif c == "\\" then
            local escape = text:sub(i + 1, i + 1)
            local simple = ({ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" })[escape]

            if simple then
                parts[#parts + 1] = simple
                i = i + 2
            elseif escape == "u" then
                local hex = text:sub(i + 2, i + 5)
                local code = tonumber(hex, 16)

                if code == nil or #hex ~= 4 then decodeError(text, i, "bad unicode escape") end

                -- Surrogate pair
                if code >= 0xD800 and code <= 0xDBFF and text:sub(i + 6, i + 7) == "\\u" then
                    local low = tonumber(text:sub(i + 8, i + 11), 16)

                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        i = i + 6
                    end
                end

                parts[#parts + 1] = codepointToUtf8(code)
                i = i + 6
            else
                decodeError(text, i, "bad escape")
            end
        else
            local nextSpecial = text:find('["\\]', i) or #text + 1
            parts[#parts + 1] = text:sub(i, nextSpecial - 1)
            i = nextSpecial
        end
    end
end

local function decodeNumber(text, pos)
    local numberText = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)

    if numberText == nil or numberText == "" then decodeError(text, pos, "bad number") end

    local value = tonumber(numberText)

    if value == nil then decodeError(text, pos, "bad number") end

    -- Keep whole numbers as integers so IDs and prices stay exact
    if not numberText:find("[%.eE]") then
        value = math.tointeger(value) or value
    end

    return value, pos + #numberText
end

local function decodeArray(text, pos)
    local result = {}
    local index = 1

    pos = skipWhitespace(text, pos + 1)

    if text:sub(pos, pos) == "]" then return result, pos + 1 end

    while true do
        local value
        value, pos = decodeValue(text, pos)
        result[index] = value
        index = index + 1

        pos = skipWhitespace(text, pos)
        local c = text:sub(pos, pos)

        if c == "]" then return result, pos + 1 end
        if c ~= "," then decodeError(text, pos, "expected , or ]") end

        pos = skipWhitespace(text, pos + 1)
    end
end

local function decodeObject(text, pos)
    local result = {}

    pos = skipWhitespace(text, pos + 1)

    if text:sub(pos, pos) == "}" then return result, pos + 1 end

    while true do
        if text:sub(pos, pos) ~= '"' then decodeError(text, pos, "expected string key") end

        local key
        key, pos = decodeString(text, pos)

        pos = skipWhitespace(text, pos)
        if text:sub(pos, pos) ~= ":" then decodeError(text, pos, "expected :") end

        local value
        value, pos = decodeValue(text, skipWhitespace(text, pos + 1))
        result[key] = value

        pos = skipWhitespace(text, pos)
        local c = text:sub(pos, pos)

        if c == "}" then return result, pos + 1 end
        if c ~= "," then decodeError(text, pos, "expected , or }") end

        pos = skipWhitespace(text, pos + 1)
    end
end

decodeValue = function(text, pos)
    pos = skipWhitespace(text, pos)
    local c = text:sub(pos, pos)

    if c == "{" then return decodeObject(text, pos) end
    if c == "[" then return decodeArray(text, pos) end
    if c == '"' then return decodeString(text, pos) end
    if c == "-" or c:match("%d") then return decodeNumber(text, pos) end
    if text:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    if text:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    if text:sub(pos, pos + 3) == "null" then return nil, pos + 4 end

    decodeError(text, pos, "unexpected character '" .. c .. "'")
end

function Json.decode(text)
    if type(text) ~= "string" then return nil, "Json.decode: expected a string" end

    local ok, value, pos = pcall(decodeValue, text, 1)

    if not ok then return nil, value end

    pos = skipWhitespace(text, pos)
    if pos <= #text then return nil, "Json.decode: trailing characters at position " .. pos end

    return value
end

return Json
