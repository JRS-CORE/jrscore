local heartbeats = {}
local stalePlayers = {}

local function cfg()
    return Config.NetworkGuard or {}
end

RegisterNetEvent('jrs_core:networkGuard:heartbeat', function()
    local c = cfg()
    if c.Enabled ~= true then return end

    local src = tonumber(source)
    if not src then return end

    heartbeats[src] = GetGameTimer()
    if stalePlayers[src] then
        stalePlayers[src] = nil
        TriggerEvent('jrs_core:networkGuard:stateChanged', src, false)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    heartbeats[src] = nil
    stalePlayers[src] = nil
end)

CreateThread(function()
    while true do
        local c = cfg()
        if c.Enabled ~= true then
            Wait(5000)
        else
            local now = GetGameTimer()
            local timeout = math.max(5000, tonumber(c.TimeoutMs) or 20000)

            for src, lastSeen in pairs(heartbeats) do
                if GetPlayerName(src) == nil then
                    heartbeats[src] = nil
                    stalePlayers[src] = nil
                elseif (now - lastSeen) > timeout then
                    if not stalePlayers[src] then
                        stalePlayers[src] = true
                        TriggerEvent('jrs_core:networkGuard:stateChanged', src, true)

                        if c.Debug then
                            print(('[jrs_core][network] heartbeat timeout for source %s'):format(src))
                        end

                        if c.KickOnTimeout == true then
                            DropPlayer(src, tostring(c.KickMessage or 'Your network connection stopped responding.'))
                        end
                    end
                end
            end

            Wait(1000)
        end
    end
end)

exports('IsConnectionStale', function(source)
    return stalePlayers[tonumber(source)] == true
end)

exports('GetLastHeartbeatAge', function(source)
    source = tonumber(source)
    local lastSeen = source and heartbeats[source]
    if not lastSeen then return nil end
    return math.max(0, GetGameTimer() - lastSeen)
end)
