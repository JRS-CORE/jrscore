-- jrs_outlaws | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_outlaws | client
-- Walk into a zone, maybe get ambushed. The server only decides who may be ambushed where; the bandits
-- are created and managed on the ambushed player's own client.

local Text = Config.Text[Config.Language] or Config.Text.en
local GROUP <const> = `bandits`

local ambush              -- the ambush running right now: { zone, peds, spawned }
local pausedUntil = 0     -- no new roll before this game time
local reply               -- result of the last claim request

-- ------------------------------------------------------------------ small helpers

local function zoneValue(zone, name)
    local v = zone[name]
    if v == nil then v = Config.Defaults[name] end
    return v
end

local function banner(title, body, ms)
    TriggerEvent('jrs:ShowTopNotification', title, body, ms)
end

local function alive(list)
    local n = 0
    for _, ped in ipairs(list) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) then n = n + 1 end
    end
    return n
end

local function release(list, remove)
    for _, ped in ipairs(list) do
        if DoesEntityExist(ped) then
            if remove then DeleteEntity(ped) end
            SetEntityAsMissionEntity(ped, false, false)
            SetEntityAsNoLongerNeeded(ped)
        end
    end
end

-- ------------------------------------------------------------------ bandits

local function spawnBandit(zone, at, target)
    local models = zoneValue(zone, 'models')
    local name = models[math.random(#models)]
    local model = joaat(name)

    if not IsModelInCdimage(model) then
        print(('[jrs_outlaws] model %s is not available'):format(name))
        return
    end
    RequestModel(model, false)
    local limit = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < limit do Wait(0) end
    if not HasModelLoaded(model) then return end

    local ped = CreatePed(model, at.x, at.y, at.z, 0.0, true, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(ped) then return end

    SetPedRelationshipGroupHash(ped, GROUP)
    SetRelationshipBetweenGroups(5, `PLAYER`, GROUP)
    SetRelationshipBetweenGroups(5, GROUP, `PLAYER`)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)                       -- make the ped visible / outfit ready
    Citizen.InvokeNative(0x23F74C2FDA6E7C61, zoneValue(zone, 'blipSprite'), ped) -- marker above the ped
    SetEntityAsMissionEntity(ped, true, true)
    Citizen.InvokeNative(0x740CB4F3F602C9F4, ped, true)
    TaskCombatPed(ped, target, 0, 0)
    return ped
end

-- bring the number of living bandits up to the zone's limits
local function topUp(run)
    local zone = run.zone
    local room = zoneValue(zone, 'maxAlive') - alive(run.peds)
    local left = zoneValue(zone, 'maxTotal') - run.spawned
    if room <= 0 or left <= 0 then return end

    local wave = zoneValue(zone, 'wave')
    local count = math.min(math.random(wave.min, wave.max), room, left)
    for _ = 1, count do
        local at = zone.spawns[math.random(#zone.spawns)]
        local ped = spawnBandit(zone, at, PlayerPedId())
        if ped then
            run.peds[#run.peds + 1] = ped
            run.spawned = run.spawned + 1
        end
    end
end

-- ------------------------------------------------------------------ running an ambush

local function finish(run, how)
    local zone = run.zone
    if how == 'won' then
        banner(Text.wonTitle, Text.wonBody, 4000)
        release(run.peds, false)
    elseif how == 'fled' then
        banner(Text.fledTitle, Text.fledBody, 4000)
        release(run.peds, true)
    else
        banner(Text.diedTitle, Text.diedBody, 4000)
        Wait(Config.LingerAfterDeath)
        release(run.peds, true)
    end
    TriggerServerEvent('jrs_outlaws:remove', zone.key)
    ambush = nil
    pausedUntil = GetGameTimer() + Config.Cooldown
end

local function runAmbush(run)
    local zone = run.zone
    local giveUp = zoneValue(zone, 'giveUpRadius')
    local total = zoneValue(zone, 'maxTotal')

    while ambush == run do
        topUp(run)

        if IsPlayerDead(PlayerId()) then return finish(run, 'died') end
        if #(GetEntityCoords(PlayerPedId()) - zone.center) > giveUp then return finish(run, 'fled') end
        if run.spawned >= total and alive(run.peds) == 0 then return finish(run, 'won') end

        Wait(250)
    end
end

-- ------------------------------------------------------------------ claiming a zone

RegisterNetEvent('jrs_outlaws:canstart', function(granted) reply = granted end)

local function claim(zone)
    reply = nil
    TriggerServerEvent('jrs_outlaws:check', zone.key)
    local limit = GetGameTimer() + 4000
    while reply == nil and GetGameTimer() < limit do Wait(50) end
    if reply == false then banner(Text.title, Text.busyBody, 2000) end
    return reply == true
end

-- ------------------------------------------------------------------ watching the zones

CreateThread(function()
    while true do
        Wait(250)

        if not ambush and GetGameTimer() >= pausedUntil and not IsPlayerDead(PlayerId()) then
            local here = GetEntityCoords(PlayerPedId())

            for _, zone in ipairs(Config.Zones) do
                if #(here - zone.center) <= zoneValue(zone, 'triggerRadius') then
                    pausedUntil = GetGameTimer() + Config.Cooldown       -- one roll per visit
                    if math.random(1, 100) <= zoneValue(zone, 'chance') and claim(zone) then
                        ambush = { zone = zone, peds = {}, spawned = 0 }
                        banner(Text.title, Text.body, 2000)
                        CreateThread(function() runAmbush(ambush) end)
                    end
                    break
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not ambush then return end
    release(ambush.peds, true)
    TriggerServerEvent('jrs_outlaws:remove', ambush.zone.key)
end)
