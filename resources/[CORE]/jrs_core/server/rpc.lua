
-- ============================================================================
-- JRS bounded RPC service
-- ============================================================================
JRSRPC = JRSRPC or {}
local RPC = JRSRPC
local handlers = {}
local pendingClient = {}
local rate = {}
local sequence = 0

local LIMITS = {
    windowMs = 1000,
    maxCalls = 30,
    timeoutMs = 10000,
    maxPayloadBytes = 65536,
    maxDepth = 12,
    maxNodes = 2048,
}

local function validateValue(value, depth, stats)
    depth = depth or 0
    stats = stats or { nodes = 0 }
    if depth > LIMITS.maxDepth then return false end
    stats.nodes = stats.nodes + 1
    if stats.nodes > LIMITS.maxNodes then return false end

    local kind = type(value)
    if kind == 'nil' or kind == 'boolean' or kind == 'number' or kind == 'string' then return true end
    if kind ~= 'table' then return false end
    for k, v in pairs(value) do
        if not validateValue(k, depth + 1, stats) or not validateValue(v, depth + 1, stats) then return false end
    end
    return true
end

local function validPayload(payload)
    if not validateValue(payload, 0, { nodes = 0 }) then return false, 'invalid_payload' end
    local ok, encoded = pcall(json.encode, payload)
    if not ok then return false, 'encode_failed' end
    if #encoded > LIMITS.maxPayloadBytes then return false, 'payload_too_large' end
    return true
end

local function allow(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    local now = GetGameTimer()
    local bucket = rate[source]
    if not bucket or now - bucket.started >= LIMITS.windowMs then
        rate[source] = { started = now, count = 1 }
        return true
    end
    bucket.count = bucket.count + 1
    return bucket.count <= LIMITS.maxCalls
end

local function nextTicket()
    sequence = sequence + 1
    if sequence >= 2147483000 then sequence = 1 end
    return ('%d:%d'):format(GetGameTimer(), sequence)
end

function RPC.Register(name, callback)
    name = tostring(name or '')
    if name == '' or #name > 128 or type(callback) ~= 'function' then return false end
    handlers[name] = {
        callback = callback,
        resource = (type(GetInvokingResource) == 'function' and GetInvokingResource()) or GetCurrentResourceName()
    }
    return true
end

function RPC.Unregister(name)
    handlers[tostring(name or '')] = nil
    return true
end

RegisterNetEvent('jrs_core:rpc:serverRequest', function(ticket, name, args)
    local src = tonumber(source)
    ticket, name = tostring(ticket or ''), tostring(name or '')
    if not src or ticket == '' or name == '' or #ticket > 96 or #name > 128 then return end
    if not allow(src) then
        TriggerClientEvent('jrs_core:rpc:serverResponse', src, ticket, false, 'rate_limited')
        return
    end
    if args ~= nil and type(args) ~= 'table' then
        TriggerClientEvent('jrs_core:rpc:serverResponse', src, ticket, false, 'invalid_arguments')
        return
    end
    local valid, reason = validPayload(args or {})
    if not valid then
        TriggerClientEvent('jrs_core:rpc:serverResponse', src, ticket, false, reason)
        return
    end
    local entry = handlers[name]
    if not entry then
        TriggerClientEvent('jrs_core:rpc:serverResponse', src, ticket, false, 'not_registered')
        return
    end

    CreateThread(function()
        local ok, a, b, c, d = pcall(entry.callback, src, table.unpack(args or {}))
        TriggerClientEvent('jrs_core:rpc:serverResponse', src, ticket, ok, ok and { a, b, c, d } or tostring(a))
    end)
end)

RegisterNetEvent('jrs_core:rpc:clientResponse', function(ticket, ok, payload)
    local src = tonumber(source)
    local entry = pendingClient[tostring(ticket or '')]
    if not entry or tonumber(entry.source) ~= src then return end
    local valid, reason = validPayload(payload)
    pendingClient[tostring(ticket)] = nil
    entry.promise:resolve({ ok = valid and ok == true, payload = valid and payload or reason })
end)

function RPC.CallClient(source, name, ...)
    source = tonumber(source)
    name = tostring(name or '')
    if not source or source <= 0 or name == '' then return false, 'invalid_arguments' end
    local args = { ... }
    local valid, reason = validPayload(args)
    if not valid then return false, reason end
    local ticket = nextTicket()
    local p = promise.new()
    pendingClient[ticket] = { source = source, promise = p }
    TriggerClientEvent('jrs_core:rpc:clientRequest', source, ticket, name, args)

    SetTimeout(LIMITS.timeoutMs, function()
        local entry = pendingClient[ticket]
        if entry then
            pendingClient[ticket] = nil
            entry.promise:resolve({ ok = false, payload = 'timeout' })
        end
    end)

    local result = Citizen.Await(p)
    if not result or result.ok ~= true then return false, result and result.payload or 'timeout' end
    local values = type(result.payload) == 'table' and result.payload or { result.payload }
    return true, table.unpack(values)
end

exports('RegisterServerCallback', RPC.Register)
exports('UnregisterServerCallback', RPC.Unregister)
exports('TriggerClientCallback', RPC.CallClient)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    rate[src] = nil
    for ticket, entry in pairs(pendingClient) do
        if tonumber(entry.source) == src then
            pendingClient[ticket] = nil
            entry.promise:resolve({ ok = false, payload = 'player_dropped' })
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    for name, entry in pairs(handlers) do
        if entry.resource == resource then handlers[name] = nil end
    end
end)
