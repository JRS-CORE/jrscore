-- jrs_metabolism | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local talking, muted, range = false, false, 3.0
local function update()
    SendNUIMessage({action = 'voice', talking = talking, muted = muted, range = range})
end
RegisterNetEvent('SaltyChat_VoiceRangeChanged', function(value) range = tonumber(value) or range; update() end)
RegisterNetEvent('SaltyChat_TalkStateChanged', function(value) talking = value == true; update() end)
RegisterNetEvent('SaltyChat_MicStateChanged', function(value) muted = value ~= true; update() end)
RegisterNetEvent('pma-voice:setTalkingMode', function(mode) range = ({3.0, 8.0, 15.0, 32.0})[tonumber(mode)] or range; update() end)
RegisterNetEvent('hud:isTalking', function(value) talking = value == true; update() end)
AddEventHandler('jrshud:isTalking', function(value) talking = value == true or value == 1; update() end)
RegisterNetEvent('hud:changeRadius', function(mode) range = ({3.0, 8.0, 15.0, 32.0})[tonumber(mode)] or range; update() end)
CreateThread(function()
    while true do
        Wait(500)
        if GetResourceState('pma-voice') == 'started' then
            local changed = false
            if type(MumbleIsPlayerTalking) == 'function' then
                local result = MumbleIsPlayerTalking(PlayerId())
                local value = result == 1 or result == true
                if talking ~= value then talking = value; changed = true end
            end
            local proximity = LocalPlayer and LocalPlayer.state and LocalPlayer.state.proximity
            local distance = type(proximity) == 'table' and tonumber(proximity.distance)
            if distance and distance == distance and distance > 0 and distance < math.huge and range ~= distance then
                range = distance
                changed = true
            end
            if changed then update() end
        end
    end
end)
