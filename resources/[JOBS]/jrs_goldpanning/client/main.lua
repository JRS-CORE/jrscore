-- jrs_goldpanning | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local busy = false
local PAN = `p_cs_miningpan01x`

local function inWater(ped)
    if not IsPedOnFoot(ped) or not IsEntityInWater(ped) or IsPedSwimming(ped) then return false end
    local c = GetEntityCoords(ped)
    return Config.Water[Citizen.InvokeNative(0x5BA7A68A346A5A91, c.x, c.y, c.z)] == true -- GetWaterMapZoneAtCoords
end

RegisterNetEvent('jrs_goldpanning:client:start', function()
    local ped = PlayerPedId()
    if busy then return TriggerServerEvent('jrs_goldpanning:server:finish', nil) end
    if not inWater(ped) then
        JRS.Notify(L('not_here'))
        return TriggerServerEvent('jrs_goldpanning:server:finish', nil)
    end
    busy = true
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true, 0, false, false)

    local pan
    if JRS.LoadModel(PAN) then
        local c = GetEntityCoords(ped)
        pan = CreateObject(PAN, c.x, c.y, c.z, true, false, false)
        SetModelAsNoLongerNeeded(PAN)
        AttachEntityToEntity(pan, ped, GetEntityBoneIndexByName(ped, 'SKEL_R_HAND'), 0.2, 0.0, -0.2, -100.0, -50.0, 0.0,
            false, false, false, true, 2, true)
    end

    if JRS.LoadDict('script_rc@cldn@ig@rsc2_ig1_questionshopkeeper') then
        TaskPlayAnim(ped, 'script_rc@cldn@ig@rsc2_ig1_questionshopkeeper', 'inspectfloor_player', 1.0, 8.0, -1, 1, 0, false, false, false)
    end
    JRS.Progress(L('panning'), 6000)
    if JRS.LoadDict('script_re@gold_panner@gold_success') then
        TaskPlayAnim(ped, 'script_re@gold_panner@gold_success', 'SEARCH02', 1.0, 8.0, -1, 1, 0, false, false, false)
    end

    local success = true
    for _ = 1, Config.Rounds do
        if exports['jrs_minigame']:taskBar(math.random(3000, 4500), 7) ~= 100 then
            success = false
            break
        end
    end

    ClearPedTasks(ped)
    if pan and DoesEntityExist(pan) then DeleteObject(pan) end
    busy = false
    TriggerServerEvent('jrs_goldpanning:server:finish', success)
end)
