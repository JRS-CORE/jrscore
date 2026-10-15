-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | the boosters section: god mode, no-clip, cores, ammo, spawns, healing

local T = Translation.Current()

local on = { god = false, cores = false, ammo = false, noclip = false, invisible = false }
local ammoWeapon = nil

-- ------------------------------------------------------------------ toggles

local function announce(state)
    TriggerEvent('jrs:TipRight', state and T.Notify.switchedOn or T.Notify.switchedOff, 3000)
end

local function applyGod(state)
    local ped = PlayerPedId()
    SetEntityCanBeDamaged(ped, not state)
    SetEntityInvincible(ped, state)
    SetPedConfigFlag(ped, 2, state)                            -- no critical hits
    SetPedCanRagdoll(ped, not state)
    SetPedCanBeTargetted(ped, not state)
    Citizen.InvokeNative(0x5240864E847C691C, ped, not state)   -- can be incapacitated
    SetPlayerInvincible(PlayerId(), state)
    Citizen.InvokeNative(0xFD6943B6DF77E449, ped, not state)   -- can be lassoed
end

function GODmode()
    on.god = not on.god
    applyGod(on.god)
    announce(on.god)
    if on.god then TriggerServerEvent('jrs_admin:GodMode') end
end

local SET_INNER, SET_OUTER, SET_OUTER_B = 0xC6258F41D86676E0, 0x4AF5A4C7B9157D14, 0xF6A7C08DF2E28B28

function GoldenCores()
    local ped = PlayerPedId()
    on.cores = not on.cores
    announce(on.cores)
    if on.cores then
        for _, core in ipairs({ 0, 1 }) do
            Citizen.InvokeNative(SET_INNER, ped, core, 100)
            Citizen.InvokeNative(SET_OUTER, ped, core, 5000.0)
            Citizen.InvokeNative(SET_OUTER_B, ped, core, 5000.0)
        end
        TriggerServerEvent('jrs_admin:GoldenCores')
    else
        for _, core in ipairs({ 0, 1, 2 }) do
            Citizen.InvokeNative(SET_INNER, ped, core, 100)
            Citizen.InvokeNative(SET_OUTER, ped, core, 0.0)
            Citizen.InvokeNative(SET_OUTER_B, ped, core, 0.0)
        end
    end
end

local UNARMED <const> = -1569615261

function InfiAmmo()
    local ped = PlayerPedId()
    if on.ammo then
        on.ammo = false
        SetPedInfiniteAmmo(ped, false, ammoWeapon)
        ammoWeapon = nil
        return announce(false)
    end
    local _, weapon = GetCurrentPedWeapon(ped, false, 0, false)
    if weapon == UNARMED then return TriggerEvent('jrs:Tip', T.Notify.needWeaponInHands, 3000) end
    on.ammo, ammoWeapon = true, weapon
    SetPedInfiniteAmmo(ped, true, weapon)
    announce(true)
    TriggerServerEvent('jrs_admin:InfiAmmo')
end

local function toggleInvisible()
    on.invisible = not on.invisible
    SetEntityVisible(PlayerPedId(), not on.invisible)
end

-- ------------------------------------------------------------------ no-clip

function ResetNoclip(ped)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, on.god)
    SetEntityVisible(ped, not on.invisible)
    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPedCanBeTargetted(ped, not on.god)
    SetGameplayCamInitialHeading(0.0)
    SetPlayerLockon(PlayerId(), true)
    ClearPedTasks(ped, true, true)
end

function EnableNoclip(ped)
    ClearPedTasks(ped, true, true)
    SetGameplayCamInitialHeading(0.0)
    SetPlayerLockon(PlayerId(), false)
    SetEntityCollision(ped, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false)
    SetEveryoneIgnorePlayer(PlayerId(), true)
    SetPedCanBeTargetted(ped, false)
end

-- after leaving no-clip in the air, push the ped down and keep it from ragdolling on landing
function DisableRagdollingWhileFall()
    CreateThread(function()
        local ped = PlayerPedId()
        local height = GetEntityHeightAboveGround(ped)
        if not height or height < 4.0 then return end

        local function settle() SetEntityInvincible(ped, on.god or on.noclip) end

        SetEntityInvincible(ped, true)
        SetRagdollBlockingFlags(ped, 1 << 9)
        local force = 1.6428571428571428 * height + 3.5714285714285836
        ApplyForceToEntity(ped, 3, 0.0, 0.0, -force, 0.0, 0.0, 0.0, 0, true, true, false, true, false)

        local waited = 0
        while not IsPedFalling(ped) do
            if waited >= 1000 then return settle() end
            waited = waited + 25
            Wait(25)
        end
        repeat Wait(50) until not IsPedFalling(ped)
        Wait(750)
        settle()
        ClearRagdollBlockingFlags(ped, 1 << 9)
    end)
end

local function toggleNoclip()
    local ped = PlayerPedId()
    MenuData.CloseAll()
    if on.noclip then
        on.noclip = false
        ResetNoclip(ped)
        DisableRagdollingWhileFall()
        return JRS.NotifyObjective(T.Notify.switchedOff, 5000)
    end
    EnableNoclip(ped)
    on.noclip = true
    JRS.NotifyObjective(T.Notify.switchedOn, -1)
    TriggerServerEvent('jrs_admin:NoClip')
end

local promptGroup = GetRandomIntInRange(0, 0xffffff)

local function makePrompt(text, ...)
    local prompt = UiPromptRegisterBegin()
    for _, control in ipairs({ ... }) do UiPromptSetControlAction(prompt, control) end
    UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', text))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    UiPromptSetStandardMode(prompt, true)
    UiPromptSetGroup(prompt, promptGroup, 0)
    UiPromptRegisterEnd(prompt)
    return prompt
end

CreateThread(function()
    repeat Wait(1000) until LocalPlayer.state.IsInSession
    local P, C = T.Menus.MainBoostOptions.Prompts, Config.Controls
    makePrompt(P.down .. '/' .. P.up, C.goDown, C.goUp)
    makePrompt(P.speed, C.changeSpeed)
    makePrompt(P.backward .. '/' .. P.forward, C.goBackward, C.goForward)
    makePrompt(P.cancel, C.Cancel)
end)

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local speeds, C, step = Config.Speeds, Config.Controls, Config.Offsets
    local at = 1

    while true do
        if not on.noclip then
            Wait(1000)
        else
            Wait(0)
            local ped = PlayerPedId()
            local speed = speeds[at].speed

            DisableControlAction(0, 0xB238FE0B, true)
            DisableControlAction(0, 0x3C0A40F2, true)
            SetEntityVisible(ped, false)

            local label = speeds[at].label
            UiPromptSetActiveGroupThisFrame(promptGroup,
                VarString(10, 'LITERAL_STRING', T.Menus.MainBoostOptions.Prompts.speed_desc .. (T.Menus.Speeds[label] or label) .. ' ' .. speed), 0, 0, 0, 0)

            if IsDisabledControlJustPressed(1, C.changeSpeed) then at = at % #speeds + 1 end

            local forward, vertical = 0.0, 0.0
            if IsDisabledControlPressed(0, C.goForward) then forward = step.y end
            if IsDisabledControlPressed(0, C.goBackward) then forward = -step.y end
            if forward ~= 0.0 then
                SetEntityRotation(ped, 0.0, 0.0, 0.0, 2, false)
                SetEntityHeading(ped, GetGameplayCamRelativeHeading())
            end
            if IsDisabledControlPressed(0, C.goUp) then vertical = step.z end
            if IsDisabledControlPressed(0, C.goDown) then vertical = -step.z end

            if IsDisabledControlPressed(0, C.Cancel) then
                JRS.NotifyObjective(T.Notify.switchedOff, 5000)
                on.noclip = false
                MenuData.CloseAll()
                ResetNoclip(ped)
                DisableRagdollingWhileFall()
            end

            local scale = speed + 0.3
            local to = GetOffsetFromEntityInWorldCoords(ped, 0.0, forward * scale, vertical * scale)
            SetEntityCoordsNoOffset(ped, to.x, to.y, to.z, on.noclip, on.noclip, on.noclip)
        end
    end
end)

-- ------------------------------------------------------------------ spawns and healing

local function spawnHorse()
    local spec = T.Menus.MainBoostOptions.SpawnHorseInput
    MenuData.CloseAll()
    Kit.ask(spec, '[A-Za-z0-9_ \\-]{5,60}', function(answer)
        local model = answer:lower()
        if not model:match('^a_c_horse_') then return JRS.NotifyRightTip(T.Notify.invalidModel, 4000) end
        if not AdminLoadModel(model) then return end

        local ped = PlayerPedId()
        local at = GetEntityCoords(ped) + 1
        local horse = CreatePed(joaat(model), at.x, at.y, at.z, 0.0, true, true, false, false)
        if not AdminWaitEntity(horse) then return end

        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, horse, 1, 0)
        Citizen.InvokeNative(0x028F76B6E78246EB, ped, horse, -1, true)
        TriggerServerEvent('jrs_admin:spawnHorse', model)
    end, { empty = 3000 })
end

local function spawnWagon()
    local spec = T.Menus.MainBoostOptions.SpawnWagonInput
    MenuData.CloseAll()
    Kit.ask(spec, '[A-Za-z0-9_ \\-]{5,60}', function(model)
        if not AdminLoadModel(model) then return end

        local ped = PlayerPedId()
        local at = GetEntityCoords(ped)
        local wagon = CreateVehicle(model, at.x, at.y, at.z, 0, true, true, false, false)
        if not AdminWaitEntity(wagon) then return end

        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, wagon, 1, 0)
        SetPedIntoVehicle(ped, wagon, -1)
        TriggerServerEvent('jrs_admin:spawnWagon', model)
    end, { empty = 3000 })
end

local function healSelf()
    TriggerServerEvent('jrs_admin:HealSelf', 'selfheal')
    local horse = GetMount(PlayerPedId())
    if horse ~= 0 then
        Citizen.InvokeNative(SET_INNER, horse, 0, 600)
        Citizen.InvokeNative(SET_INNER, horse, 1, 600)
    end
end

-- ------------------------------------------------------------------ the menu

function Boost()
    local O = T.Menus.MainBoostOptions
    local noclipDesc = ('<span>%s</span><br><span>%s</span><br><span>%s</span><br>%s'):format(O.selfNoClip_desc, O.move, O.speedMode, O.cammode)

    Kit.open('Boost', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleBooster,
        back = 'OpenMenu',
        items = {
            { label = O.selfGodMode, value = 'god', gate = 'godmode', desc = O.selfGodMode_desc, go = GODmode },
            { label = O.selfNoClip, value = 'noclip', gate = 'noclip', desc = noclipDesc, go = toggleNoclip },
            { label = O.selfGoldCores, value = 'goldcores', gate = 'golden_cores', desc = O.selfGoldCores_desc, go = GoldenCores },
            { label = O.enabledInfinityAmmo, value = 'infiniteammo', gate = 'infinite_ammo', desc = O.enabledInfinityAmmo_desc, go = InfiAmmo },
            { label = O.spawnWagon, value = 'spawnwagon', gate = 'spawn_wagon', desc = O.spawnWagon_desc, go = spawnWagon },
            { label = O.spawnHorse, value = 'spawnhorse', gate = 'spawn_horse', desc = O.spawnHorse_desc, go = spawnHorse },
            { label = O.selfHeal, value = 'selfheal', gate = 'selfheal', desc = O.selfHeal_desc, go = healSelf },
            { label = O.selfRevive, value = 'selfrevive', gate = 'selfrevive', desc = O.selfRevive_desc,
              go = function() TriggerServerEvent('jrs_admin:ReviveSelf') end },
            { label = O.selfInvisible, value = 'invisibility', gate = 'invisibility', desc = O.selfInvisible_desc, go = toggleInvisible },
        },
    })
end

-- ------------------------------------------------------------------ for other files

function AdminIsInvincible() return on.god or on.noclip end

function AdminResetBoosters()
    local ped = PlayerPedId()
    if on.noclip then on.noclip = false; ResetNoclip(ped) end
    if on.god then on.god = false; applyGod(false) end
    if on.invisible then on.invisible = false; SetEntityVisible(ped, true) end
    if on.cores then GoldenCores() end
    if on.ammo then on.ammo = false; SetPedInfiniteAmmo(ped, false, ammoWeapon); ammoWeapon = nil end
end
