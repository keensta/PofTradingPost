-- Tiny event bus, this allows file to Subscribe and Unsubscribe, it allows communication between files without running into a Lua Cycle
local PofEvent = {}

local function newEvent(name)
    local event = {
        name = name,
        _order = {},
        _handlers = {}
    }

    -- For Consistence among RS3 API event system Subscribe, Unsubscribe & Fire don't follow camelCase.

    function event.Subscribe(ref, handler)
        if event._handlers[ref] == nil then
            table.insert(event._order, ref)
        end

        event._handlers[ref] = handler
    end

    function event.Unsubscribe(ref)
        if event._handlers[ref] == nil then
            return
        end
        event._handlers[ref] = nil
        for i, r in ipairs(event._order) do
            if r == ref then
                table.remove(event._order, i)
                break
            end
        end
    end

    function event.Fire(payload)
        -- Copy the order so a handler can unsubscribe while we're firing
        local order = table.move(event._order, 1, #event._order, 1, {})
        for _, ref in ipairs(order) do
            local handler = event._handlers[ref]
            if handler then
                -- pcall: one broken subscriber shouldn't stop the others
                local ok, err = pcall(handler, payload)
                if not ok then
                    print(formatStr("PofEvent.{} handler '{}' failed: {}", event.name, ref, err))
                end
            end
        end
    end

    return event
end

PofEvent.OffersUpdated = newEvent("OffersUpdated")
PofEvent.ListingsUpdated = newEvent("ListingsUpdated")
PofEvent.SettingChanged = newEvent("SettingChanged")
PofEvent.PlayerReady = newEvent("PlayerReady")
PofEvent.AuthChanged = newEvent("AuthChanged")

-- Typo guard PofEvent.OfersUpdated errors instead of silently being nil
setmetatable(PofEvent, {
    __index = function(_, key)
        error("Unknown PofEvent: " .. tostring(key), 2)
    end
})

return PofEvent
