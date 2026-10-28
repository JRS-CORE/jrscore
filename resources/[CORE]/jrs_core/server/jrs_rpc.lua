-- ===================================================================
-- JRS CORE | Native Server RPC & Callback Engine
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local ServerCallbacks = {}
local PendingClientRequests = {}
local NextRequestId = 0

local function generateRequestId()
    NextRequestId = (NextRequestId + 1) % 0x7FFFFFFF
    return NextRequestId
end

JRSRPC = JRSRPC or {}

--- Registers a server-side callback that clients can invoke.
--- Handler signature: `handler(source, cb, ...)` or returns direct value.
function JRSRPC.RegisterCallback(name, handler)
    if type(name) ~= 'string' or type(handler) ~= 'function' then
        return print(('^1[JRS RPC]^7 Invalid callback registration: %s^7'):format(tostring(name)))
    end
    ServerCallbacks[name] = handler
end

--- Invokes a registered client-side callback from the server.
function JRSRPC.TriggerClientCallback(source, name, cb, ...)
    local src = tonumber(source)
    if not src or src <= 0 then return end

    local requestId = generateRequestId()
    if type(cb) == 'function' then
        PendingClientRequests[requestId] = {
            cb = cb,
            source = src,
            expiresAt = GetGameTimer() + 15000
        }
    end

    TriggerClientEvent('jrs_core:rpc:clientRequest', src, requestId, name, ...)
end

-- Handle incoming client requests
RegisterNetEvent('jrs_core:rpc:serverRequest', function(requestId, name, ...)
    local src = source
    local handler = ServerCallbacks[name]

    if not handler then
        return TriggerClientEvent('jrs_core:rpc:clientResponse', src, requestId, false, 'callback_not_found')
    end

    local responded = false
    local function respond(...)
        if responded then return end
        responded = true
        TriggerClientEvent('jrs_core:rpc:clientResponse', src, requestId, true, ...)
    end

    local ok, directResult = pcall(handler, src, respond, ...)
    if not ok then
        print(('^1[JRS RPC]^7 Error executing callback "%s" from player %s: %s^7'):format(name, src, tostring(directResult)))
        if not responded then
            respond(nil)
        end
    elseif not responded and directResult ~= nil then
        respond(directResult)
    end
end)

-- Handle incoming responses from clients
RegisterNetEvent('jrs_core:rpc:serverResponse', function(requestId, success, ...)
    local pending = PendingClientRequests[requestId]
    if not pending then return end

    PendingClientRequests[requestId] = nil
    if pending.cb then
        pcall(pending.cb, success, ...)
    end
end)

-- Periodically clean expired requests
CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for id, req in pairs(PendingClientRequests) do
            if now >= req.expiresAt then
                PendingClientRequests[id] = nil
            end
        end
    end
end)

-- Server Exports
exports('RegisterServerCallback', JRSRPC.RegisterCallback)
exports('RegisterCallback', JRSRPC.RegisterCallback)
exports('TriggerClientCallback', JRSRPC.TriggerClientCallback)
