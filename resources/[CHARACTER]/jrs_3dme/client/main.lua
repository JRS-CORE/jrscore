local messages = {}   -- serverId -> { { id, text, untilAt } }

RegisterCommand(Config.Command, function(_, args)
    local text = table.concat(args, ' ')
    if text ~= '' then TriggerServerEvent('jrs_3dme:server:display', text) end
end, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.Command, L('help'), { { name = L('param'), help = L('help') } })

RegisterNetEvent('jrs_3dme:client:display', function(serverId, id, text)
    messages[serverId] = messages[serverId] or {}
    table.insert(messages[serverId], { id = id, text = text, untilAt = GetGameTimer() + Config.Duration })
end)

local function draw(x, y, z, text)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end
    local c = Config.Color
    SetTextScale(0.30, 0.30)
    SetTextFontForCurrentCommand(1)
    SetTextColor(c.r, c.g, c.b, c.a)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 255)
    DisplayText(VarString(10, 'LITERAL_STRING', text), sx, sy)
end

CreateThread(function()
    while true do
        local wait = 500
        if next(messages) then
            wait = 0
            local now = GetGameTimer()
            local myPos = GetEntityCoords(PlayerPedId())
            for serverId, list in pairs(messages) do
                for i = #list, 1, -1 do
                    if now > list[i].untilAt then table.remove(list, i) end
                end
                local player = GetPlayerFromServerId(serverId)
                if #list == 0 or player == -1 then
                    messages[serverId] = nil
                else
                    local ped = GetPlayerPed(player)
                    local pos = GetEntityCoords(ped)
                    if #(myPos - pos) < Config.DisplayDistance then
                        local base = IsPedOnMount(ped) and 1.3 or 1.0
                        for i, msg in ipairs(list) do
                            draw(pos.x, pos.y, pos.z + base + (i - 1) * 0.15, msg.text)
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)
