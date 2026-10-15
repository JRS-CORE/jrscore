-- Every NUI callback in this resource must answer the page exactly once.
-- A Lua error inside a handler used to leave the fetch pending until the
-- browser timeout (10s, 40s for spawn/create), so the button that sent it
-- stayed busy and the creator looked frozen. Handlers run inside pcall
-- (yield-safe on lua54, so Wait() inside a handler still works); on error the
-- page gets { ok = false } and the error is printed with the callback name.
local rawRegisterNUICallback = RegisterNUICallback

RegisterNUICallback = function(name, handler)
    if type(handler) ~= 'function' and type(handler) ~= 'table' then
        return rawRegisterNUICallback(name, handler)
    end

    return rawRegisterNUICallback(name, function(data, cb)
        local answered = false
        local function reply(...)
            if answered then return end
            answered = true
            if cb then cb(...) end
        end

        local ok, err = pcall(handler, data, reply)
        if not ok then
            print(('^1[jrs_character] NUI callback "%s" failed: %s^7'):format(tostring(name), tostring(err)))
            reply({ ok = false, reason = 'error' })
        end
    end)
end
