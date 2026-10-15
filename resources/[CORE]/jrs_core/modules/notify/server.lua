JRSServerToast = JRSServerToast or {}
local function JRSRegisterServerToast(name, fn) JRSServerToast[name] = fn end
-- ============================================================================
--  jrs_notify / server/server.lua
--  Server-side entry points. Anything server-authoritative (payouts, job
--  results, admin actions) notifies a player through here instead of inventing
--  its own client event.
-- ============================================================================

local function targetOf(source)
    local id = tonumber(source)
    if not id or id <= 0 then return nil end
    return id
end

--- exports.jrs_core:Toast(source, text, notifyType, duration, title)
JRSRegisterServerToast('Notify', function(source, text, notifyType, duration, title)
    local target = targetOf(source)
    if not target then return false end
    if text == nil or tostring(text) == '' then return false end

    TriggerClientEvent('jrs_notify:show', target, {
        text = text,
        type = notifyType,
        duration = duration,
        title = title,
        source = GetInvokingResource(),
    })
    return true
end)

--- exports.jrs_core:ShowNotification(source, payload)
JRSRegisterServerToast('Show', function(source, payload)
    local target = targetOf(source)
    if not target or type(payload) ~= 'table' then return false end
    if payload.source == nil then payload.source = GetInvokingResource() end

    TriggerClientEvent('jrs_notify:show', target, payload)
    return true
end)

--- exports.jrs_notify:NotifyAll(text, notifyType, duration, title)
JRSRegisterServerToast('NotifyAll', function(text, notifyType, duration, title)
    if text == nil or tostring(text) == '' then return false end

    TriggerClientEvent('jrs_notify:show', -1, {
        text = text,
        type = notifyType,
        duration = duration,
        title = title,
        source = GetInvokingResource(),
    })
    return true
end)

-- Event form, for scripts that cannot call an export from where they are.
RegisterNetEvent('jrs_notify:server:notify', function(target, text, notifyType, duration, title)
    -- Only trusted server-side callers may use this. A client triggering it
    -- would arrive with a real source, so refuse those outright: a player must
    -- never be able to push a notification onto another player.
    if source ~= nil and tonumber(source) and tonumber(source) > 0 then return end

    local id = targetOf(target)
    if not id then return end

    TriggerClientEvent('jrs_notify:show', id, {
        text = text,
        type = notifyType,
        duration = duration,
        title = title,
    })
end)
