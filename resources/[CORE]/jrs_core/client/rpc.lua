
-- ============================================================================
-- JRS client RPC service
-- ============================================================================
JRSRPCClient = JRSRPCClient or {}
local RPC = JRSRPCClient
local handlers = {}
local pending = {}
local sequence = 0
local TIMEOUT_MS = 10000

local function nextTicket()
    sequence = sequence + 1
    if sequence >= 2147483000 then sequence = 1 end
    return ('%d:%d'):format(GetGameTimer(), sequence)
end

function RPC.Register(name, callback)
    name = tostring(name or '')
    if name == '' or #name > 128 or type(callback) ~= 'function' then return false end
    handlers[name] = callback
    return true
end

function RPC.Unregister(name)
    handlers[tostring(name or '')] = nil
    return true
end

function RPC.CallServer(name, ...)
    name = tostring(name or '')
    if name == '' then return false, 'invalid_name' end
    local ticket = nextTicket()
    local p = promise.new()
    pending[ticket] = p
    TriggerServerEvent('jrs_core:rpc:serverRequest', ticket, name, { ... })
    SetTimeout(TIMEOUT_MS, function()
        if pending[ticket] then
            pending[ticket] = nil
            p:resolve({ ok = false, payload = 'timeout' })
        end
    end)
    local result = Citizen.Await(p)
    if not result or result.ok ~= true then return false, result and result.payload or 'timeout' end
    local values = type(result.payload) == 'table' and result.payload or { result.payload }
    return true, table.unpack(values)
end

RegisterNetEvent('jrs_core:rpc:serverResponse', function(ticket, ok, payload)
    ticket = tostring(ticket or '')
    local p = pending[ticket]
    if not p then return end
    pending[ticket] = nil
    p:resolve({ ok = ok == true, payload = payload })
end)

RegisterNetEvent('jrs_core:rpc:clientRequest', function(ticket, name, args)
    ticket, name = tostring(ticket or ''), tostring(name or '')
    local callback = handlers[name]
    if not callback then
        TriggerServerEvent('jrs_core:rpc:clientResponse', ticket, false, 'not_registered')
        return
    end
    CreateThread(function()
        local ok, a, b, c, d = pcall(callback, table.unpack(type(args) == 'table' and args or {}))
        TriggerServerEvent('jrs_core:rpc:clientResponse', ticket, ok, ok and { a, b, c, d } or tostring(a))
    end)
end)

exports('RegisterClientCallback', RPC.Register)
exports('UnregisterClientCallback', RPC.Unregister)
exports('TriggerServerCallback', RPC.CallServer)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for ticket, p in pairs(pending) do
        p:resolve({ ok = false, payload = 'resource_stopped' })
    end
    pending = {}
end)
