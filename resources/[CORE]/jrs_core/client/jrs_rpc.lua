-- ===================================================================
-- JRS CORE | Native Client RPC & Callback Engine
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local ClientCallbacks = {}
local PendingServerRequests = {}
local NextRequestId = 0

local function generateRequestId()
    NextRequestId = (NextRequestId + 1) % 0x7FFFFFFF
    return NextRequestId
end

JRSRPC = JRSRPC or {}

--- Registers a client-side callback that the server can invoke.
function JRSRPC.RegisterCallback(name, handler)
    if type(name) ~= 'string' or type(handler) ~= 'function' then
        return print(('^1[JRS RPC]^7 Invalid client callback registration: %s^7'):format(tostring(name)))
    end
    ClientCallbacks[name] = handler
end

--- Asynchronously triggers a server callback.
--- Signature: `JRSRPC.TriggerServerCallback(name, function(success, ...) end, ...)`
function JRSRPC.TriggerServerCallback(name, cb, ...)
    local requestId = generateRequestId()
    PendingServerRequests[requestId] = {
        cb = cb,
        expiresAt = GetGameTimer() + 15000
    }
    TriggerServerEvent('jrs_core:rpc:serverRequest', requestId, name, ...)
end

--- Synchronously awaits a server callback via Citizen.Await / promise.
--- Signature: `local res1, res2 = JRSRPC.TriggerCallbackAwait(name, ...)`
function JRSRPC.TriggerCallbackAwait(name, ...)
    local p = promise.new()
    JRSRPC.TriggerServerCallback(name, function(success, ...)
        p:resolve(table.pack(success, ...))
    end, ...)

    local results = Citizen.Await(p)
    local success = results[1]
    if not success then
        return nil, results[2]
    end
    return table.unpack(results, 2, results.n)
end

-- Handle server responses
RegisterNetEvent('jrs_core:rpc:clientResponse', function(requestId, success, ...)
    local pending = PendingServerRequests[requestId]
    if not pending then return end

    PendingServerRequests[requestId] = nil
    if pending.cb then
        pcall(pending.cb, success, ...)
    end
end)

-- Handle server requests
RegisterNetEvent('jrs_core:rpc:clientRequest', function(requestId, name, ...)
    local handler = ClientCallbacks[name]
    if not handler then
        return TriggerServerEvent('jrs_core:rpc:serverResponse', requestId, false, 'client_callback_not_found')
    end

    local responded = false
    local function respond(...)
        if responded then return end
        responded = true
        TriggerServerEvent('jrs_core:rpc:serverResponse', requestId, true, ...)
    end

    local ok, directResult = pcall(handler, respond, ...)
    if not ok then
        print(('^1[JRS RPC]^7 Error executing client callback "%s": %s^7'):format(name, tostring(directResult)))
        if not responded then
            respond(nil)
        end
    elseif not responded and directResult ~= nil then
        respond(directResult)
    end
end)

-- Periodically clean expired requests
CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for id, req in pairs(PendingServerRequests) do
            if now >= req.expiresAt then
                PendingServerRequests[id] = nil
            end
        end
    end
end)

-- Client Exports
exports('RegisterClientCallback', JRSRPC.RegisterCallback)
exports('TriggerServerCallback', JRSRPC.TriggerServerCallback)
exports('TriggerCallbackAwait', JRSRPC.TriggerCallbackAwait)
