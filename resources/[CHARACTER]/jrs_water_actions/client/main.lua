-- jrs_water_actions | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local enabled, busy, fishing = true, false, false

-- other scripts (fishing) can hide the prompts while they run
RegisterNetEvent('jrs_water_actions:setFishingState', function(state) fishing = state == true end)

RegisterCommand(Config.ToggleCommand, function()
    enabled = not enabled
    JRS.Notify(L(enabled and 'on' or 'off'))
end, false)

local function playFor(dict, anim, ms, flag)
    local ped = PlayerPedId()
    if JRS.LoadDict(dict) then
        TaskPlayAnim(ped, dict, anim, 1.0, 8.0, -1, flag or 1, 0.0, false, false, false)
    end
    Wait(ms)
    StopAnimTask(ped, dict, anim, 1.0)
    ClearPedTasks(ped)
end

local function wash()
    local ped = PlayerPedId()
    if IsPedMale(ped) then
        playFor('amb_misc@world_human_wash_face_bucket@ground@male_a@idle_d', 'idle_l', Config.WashTime)
    else
        playFor('amb_misc@world_human_wash_face_bucket@ground@female_a@idle_d', 'idle_l', Config.WashTime)
    end
    ClearPedEnvDirt(ped)
    ClearPedBloodDamage(ped)
    ClearPedDamageDecalByZone(ped, 10, 'ALL')
    Citizen.InvokeNative(0x7F5D88333EE8A86F, ped, 1)
    ClearPedWetness(ped)
end

local function drink(waterType)
    local ped = PlayerPedId()
    if IsPedMale(ped) then
        playFor('amb_rest_drunk@world_human_bucket_drink@ground@male_a@idle_a', 'idle_a', Config.DrinkTime)
    else
        playFor('amb_rest_drunk@world_human_bucket_drink_ladle@ground@female_b@idle_a', 'idle_c', Config.DrinkTime)
    end
    PlaySoundFrontend('Core_Fill_Up', 'Consumption_Sounds', true, 0)
    TriggerEvent('jrsmetabolism:changeValue', 'Thirst', Config.Thirst)
    if waterType == 'swamp' and math.random(1, 100) <= Config.SwampSickChance then
        PlayPain(ped, 9, 1, true, true)
        SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - Config.SwampDamage))
        JRS.Notify(L('sick'))
    end
end

CreateThread(function()
    local prompts = JRS.Prompts()
    local pWash = prompts:add(Config.WashKey, LE('wash'), 1000)
    local pDrink = prompts:add(Config.DrinkKey, LE('drink'), 1000)
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        if enabled and not busy and not fishing and not IsEntityDead(ped) and IsPedOnFoot(ped)
            and IsEntityInWater(ped) and not IsPedSwimming(ped) then
            local c = GetEntityCoords(ped)
            local waterType = Config.WaterTypes[Citizen.InvokeNative(0x5BA7A68A346A5A91, c.x, c.y, c.z)] -- GetWaterMapZoneAtCoords
            if waterType then
                wait = 0
                prompts:show(LE('title'))
                if prompts:done(pWash) then
                    busy = true; ClearPedTasksImmediately(ped); wash(); busy = false
                elseif prompts:done(pDrink) then
                    busy = true; ClearPedTasksImmediately(ped); drink(waterType); busy = false
                end
            end
        end
        Wait(wait)
    end
end)
