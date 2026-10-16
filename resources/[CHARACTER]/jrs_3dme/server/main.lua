-- jrs_3dme | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
RegisterNetEvent('jrs_3dme:server:display', function(text)
    local src = source
    if type(text) ~= 'string' or not JRS.Char(src) then return end
    text = text:gsub('[<>]', ''):gsub('%^%d', ''):match('^%s*(.-)%s*$'):sub(1, Config.MaxLength)
    if text == '' then return end
    if not JRS.Cooldown(src, 'me', Config.Cooldown) then return JRS.Notify(src, L('slow')) end

    local name = JRS.Name(src)
    local id = ('%d:%d'):format(src, GetGameTimer())
    local origin = GetEntityCoords(GetPlayerPed(src))
    for _, p in ipairs(GetPlayers()) do
        local target = tonumber(p)
        local ped = GetPlayerPed(target)
        if ped ~= 0 and #(GetEntityCoords(ped) - origin) <= Config.DisplayDistance then
            TriggerClientEvent('jrs_3dme:client:display', target, src, id, text)
            if Config.ChatCopy then
                TriggerClientEvent('chat:addMessage', target, {
                    template = '<div class="chat-message"><b>* {0}</b> {1}</div>',
                    args = { target == src and L('me') or name, text },
                })
            end
        end
    end
end)
