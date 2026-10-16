-- jrs_usable_items | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_usable_items | client
-- Using an item (server side checks) starts the matching routine here: pipes and cigarettes are held in
-- the hand with a base pose; the "use" prompt plays a drag (tap) or a long drag (hold); "put away" ends it.
-- Cigars and pocket watches are simpler, pomade is applied once.

local shown = false                 -- the prompts are on screen

local PUT_AWAY <const>, USE <const> = 0x3B24C470, 0x07B8BEAF

local function setPrompts(on, ...)
    for _, getter in ipairs({ ... }) do
        local prompt = getter()
        if prompt then
            PromptSetEnabled(prompt, on)
            PromptSetVisible(prompt, on)
        end
    end
    shown = on
end

local function takeItem(name, data)
    if data.RemoveItemOnUse then TriggerServerEvent('jrs_usable_items:remove', name) end
end

-- ------------------------------------------------------------------ pipes and cigarettes
-- Animation names are game data. Per gender: `base` is the pose while smoking, `tap` a short drag,
-- `hold` a long one (anim dictionary, animation, how long to wait). `leave` plays when putting it away.

local ROOT <const> = 'amb_rest@world_human_smoking@'
local PIPE_TRANS <const> = 'amb_wander@code_human_smoking_wander@male_b@trans'

local styles = {
    pipe = {
        [0] = {
            base = { ROOT .. 'male_b@base', 'base' }, tap = { ROOT .. 'male_b@idle_a', 'idle_a', 22600 }, hold = { ROOT .. 'male_b@idle_b', 'idle_d', 15599 },
            enter = { PIPE_TRANS, 'nopipe_trans_pipe', 9000 }, leave = { PIPE_TRANS, 'pipe_trans_nopipe', 6066 },
        },
        [1] = {
            base = { ROOT .. 'female_b@base', 'base' }, tap = { ROOT .. 'female_b@idle_a', 'idle_a', 22600 }, hold = { ROOT .. 'female_b@idle_b', 'idle_d', 15599 },
        },
        hand = { 0.005, -0.045, 0.0, -170.0, 10.0, -15.0, true },
    },
    peace = {
        [0] = {
            base = { ROOT .. 'male_b@base', 'base' }, tap = { ROOT .. 'male_b@idle_a', 'idle_a', 22600 }, hold = { ROOT .. 'male_b@idle_b', 'idle_d', 15599 },
            leave = { PIPE_TRANS, 'pipe_trans_nopipe', 6066 },
        },
        [1] = {
            base = { ROOT .. 'female_b@base', 'base' }, tap = { ROOT .. 'female_b@idle_a', 'idle_a', 22600 }, hold = { ROOT .. 'female_b@idle_b', 'idle_d', 15599 },
        },
        hand = { -0.06, -0.025, 0.15, -170.0, 20.0, -22.0, false },
    },
    cigarette = {
        [0] = {
            base = { ROOT .. 'male_c@base', 'base' }, tap = { ROOT .. 'male_c@idle_a', 'idle_a', 8500 }, hold = { ROOT .. 'male_c@idle_a', 'idle_b', 21166 },
            leave = { ROOT .. 'male_a@stand_exit', 'exit_back', 2800 },
        },
        [1] = {
            base = { ROOT .. 'female_c@base', 'base' }, tap = { ROOT .. 'female_c@idle_b', 'idle_f', 8133 }, hold = { ROOT .. 'female_c@idle_a', 'idle_a', 9566 },
            leave = { ROOT .. 'female_b@trans', 'b_trans_fire_stand_a', 3800 },
        },
    },
}

local function play(ped, step, flags)
    Anim(ped, step[1], step[2], -1, flags or 30, 0)
end

-- the ped has the item in hand: react to the prompts until it is put away or the pose is lost
local function enjoy(ped, style, onLeave)
    local base = style.base
    while not IsEntityPlayingAnim(ped, base[1], base[2], 3) do Wait(100) end

    if not shown then setPrompts(true, GetPromptPutAway, GetPromptUse) end

    while IsEntityPlayingAnim(ped, base[1], base[2], 3) do
        Wait(5)
        if IsControlJustReleased(0, PUT_AWAY) then
            setPrompts(false, GetPromptPutAway, GetPromptUse)
            if style.leave then
                play(ped, style.leave, 1)
                Wait(style.leave[3])
            end
            onLeave()
            ClearPedSecondaryTask(ped)
            ClearPedTasks(ped)
            Wait(10)
        elseif IsControlJustReleased(0, USE) then
            Wait(500)
            local drag = IsControlPressed(0, USE) and style.hold or style.tap     -- held = long drag
            play(ped, drag, 30)
            Wait(drag[3])
            play(ped, base, 31)
            Wait(100)
        end
    end
    setPrompts(false, GetPromptPutAway, GetPromptUse)
end

local function dropAnimDicts(style)
    for _, key in ipairs({ 'base', 'tap', 'hold', 'enter', 'leave' }) do
        if style[key] then RemoveAnimDict(style[key][1]) end
    end
end

local function holdPipe(name, kind, data)
    local ped = PlayerPedId()
    local gender = IsPedMale(ped) and 0 or 1
    local style = styles[kind][gender]
    takeItem(name, data)

    LoadModel(data.Object)
    local at = GetEntityCoords(ped, true)
    local prop = CreateObject(joaat(data.Object), at.x, at.y, at.z + 0.2, true, true, true)
    local h = styles[kind].hand
    AttachEntityToEntity(prop, ped, GetEntityBoneIndexByName(ped, 'SKEL_R_Finger13'), h[1], h[2], h[3], h[4], h[5], h[6], true, true, false, h[7], 1, true)

    if style.enter then
        Anim(ped, style.enter[1], style.enter[2], -1, 30)
        Wait(style.enter[3])
    end
    Anim(ped, style.base[1], style.base[2], -1, 31)

    local function remove()
        DetachEntity(prop, true, true)
        RemoveEntityProperly(prop, joaat(data.Object))
    end
    enjoy(ped, style, remove)

    remove()
    ClearPedSecondaryTask(ped)
    if gender == 0 then RemoveAnimDict(PIPE_TRANS) end
    dropAnimDicts(style)
    Wait(100)
    ClearPedTasks(ped)
end

local function holdCigarette(name, data)
    local ped = PlayerPedId()
    local gender = IsPedMale(ped) and 0 or 1
    local style = styles.cigarette[gender]
    takeItem(name, data)

    LoadModel(data.Object)
    local at = GetEntityCoords(ped, true)
    local cig = CreateObject(joaat(data.Object), at.x, at.y, at.z + 0.2, true, true, true)
    local fingers, mouth = GetEntityBoneIndexByName(ped, 'SKEL_R_Finger13'), GetEntityBoneIndexByName(ped, 'skel_head')
    local function put(bone, x, y, z, rx, ry, rz) AttachEntityToEntity(cig, ped, bone, x, y, z, rx, ry, rz, true, true, false, true, 1, true) end

    -- taking it out, lighting it, putting it in the mouth
    put(mouth, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    if gender == 0 then
        Anim(ped, ROOT .. 'male_c@stand_enter', 'enter_back_rf', 9400, 0)
        Wait(1000)
        put(fingers, 0.03, -0.01, 0.0, 0.0, 90.0, 0.0)
        Wait(1000)
        put(mouth, -0.017, 0.1, -0.01, 0.0, 90.0, -90.0)
        Wait(3000)
        put(fingers, 0.017, -0.01, -0.01, 0.0, 120.0, 10.0)
        Wait(1000)
        Anim(ped, style.base[1], style.base[2], -1, 30)
        RemoveAnimDict(ROOT .. 'male_c@stand_enter')
        Wait(1000)
    else
        Anim(ped, style.base[1], style.base[2], -1, 30)
        Wait(1000)
        put(fingers, 0.01, 0.0, 0.01, 0.0, -160.0, -130.0)
        Wait(2500)
    end

    local function drop()
        DetachEntity(cig, true, true)
        if gender == 0 then SetEntityVelocity(cig, 0.0, 0.0, -1.0) end
    end
    enjoy(ped, style, function() drop() Wait(1500) end)

    DetachEntity(cig, true, true)
    ClearPedSecondaryTask(ped)
    dropAnimDicts(style)
    Wait(100)
    ClearPedTasks(ped)
end

-- ------------------------------------------------------------------ cigar, pomade, pocket watch

local function loadDict(dict)
    RequestAnimDict(dict)
    local waited = 0
    while not HasAnimDictLoaded(dict) do
        Wait(300)
        waited = waited + 300
        if waited > 5000 then print('RedM broke up this animation') break end
    end
end

local function smokeCigar(name, data)
    local ped = PlayerPedId()
    local dict, anim = 'amb_rest@world_human_smoke_cigar@male_a@idle_b', 'idle_d'
    takeItem(name, data)
    PlaySoundFrontend('Core_Full', 'Consumption_Sounds', true, 0)

    LoadModel(data.Object)
    local at = GetEntityCoords(ped, true)
    local prop = CreateObject(joaat(data.Object), at.x, at.y, at.z + 0.2, true, true, true)
    loadDict(dict)
    Wait(100)
    AttachEntityToEntity(prop, ped, GetEntityBoneIndexByName(ped, 'SKEL_R_Finger12'), 0.01, -0.005, 0.0155, 0.024, 300.0, -40.0, true, true, false, true, 1, true)
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 31, 0, true, 0, false, 0, false)
    Wait(1000)

    if not shown then setPrompts(true, GetPromptPutAway) end

    while true do
        if IsEntityPlayingAnim(ped, dict, anim, 3) then
            for _, control in ipairs({ 0x07CE1E61, 0xF84FA74F, 0xCEE12B50, 0xB2F377E8, 0x8FFC75D6, 0xD9D0E1C0 }) do
                DisableControlAction(0, control, true)
            end
            if IsControlPressed(0, PUT_AWAY) then break end
        else
            TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 31, 0, true, 0, false, 0, false)
        end
        Wait(0)
    end

    setPrompts(false, GetPromptPutAway)
    ClearPedSecondaryTask(ped)
    RemoveEntityProperly(prop, joaat(data.Object))
    RemoveAnimDict(dict)
end

local function applyPomade(name, data)
    local ped = PlayerPedId()
    local hat = Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, 0x9925C067)
    TaskItemInteraction(ped, 0, joaat(hat and 'APPLY_POMADE_WITH_HAT' or 'APPLY_POMADE_WITH_NO_HAT'), 1, 0, -1082130432)
    Wait(1500)
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, GetCurrentPedComponent(ped, 'hair'), joaat('POMADE'), 0, true, 1)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    takeItem(name, data)
end

local WATCH <const> = 'mech_inventory@item@pocketwatch@unarmed@base'

local function lookAtWatch(name, data)
    local ped = PlayerPedId()
    loadDict(WATCH)
    LoadModel(data.Object)

    local at = GetEntityCoords(ped, true)
    local prop = CreateObject(joaat(data.Object), at.x, at.y, at.z + 0.2, true, true, true)
    local bone = GetEntityBoneIndexByName(ped, 'SKEL_R_Hand')
    if IsPedMale(ped) then
        AttachEntityToEntity(prop, ped, bone, 0.085, 0.025, -0.035, 15.0, 190.0, -140.0, true, true, false, true, 1, true)
    else
        AttachEntityToEntity(prop, ped, bone, 0.075, 0.025, -0.045, 35.0, 200.0, -140.0, true, true, false, true, 1, true)
    end

    local pull = GetAnimDuration(WATCH, 'unholster') * 1000
    Anim(ped, WATCH, 'unholster', pull, 0)
    Wait(pull)
    Anim(ped, WATCH, 'inspect_base', -1, 31)
    Wait(100)

    if not shown then setPrompts(true, GetPromptPutAway) end

    -- the camera goes first person while the watch is out, until it is put away
    CreateThread(function()
        while true do
            Wait(1)
            local me = PlayerPedId()
            local out = IsEntityPlayingAnim(me, WATCH, 'inspect_base', 3)
            if out then Citizen.InvokeNative(0x90DA5BA5C2635416) end

            if IsControlJustReleased(0, PUT_AWAY) or not out then
                Citizen.InvokeNative(0x1CFB749AD4317BDE)
                StopAnimTask(me, WATCH, 'inspect_base', 1.0)
                Anim(me, WATCH, 'holster', 1000, 0)
                Wait(2000)
                setPrompts(false, GetPromptPutAway)
                StopAnimTask(me, WATCH, 'inspect_base', 1.0)
                RemoveEntityProperly(prop, joaat(data.Object))
                RemoveAnimDict(WATCH)
                return
            end
        end
    end)
end

-- ------------------------------------------------------------------ entry point

local routines = {
    POCKET_WATCH  = lookAtWatch,
    HAIR_POMADE   = applyPomade,
    CIGARETTE     = holdCigarette,
    CIGAR         = smokeCigar,
    PIPE_OF_PEACE = function(name, data) holdPipe(name, 'peace', data) end,
    PIPE          = function(name, data) holdPipe(name, 'pipe', data) end,
}

-- the server says this player used `name`
RegisterNetEvent('jrs_usable_items:client:use', function(name)
    local data = Config.UsableItems[name]
    if not data then return end

    if data.PutAwayPromptAction.Enabled then RegisterPutAwayPrompt(data.PutAwayPromptAction.Label) end
    if data.UsePromptAction.Enabled then RegisterUsePrompt(data.UsePromptAction.Label) end
    if data.ChangePromptAction.Enabled then RegisterChangePrompt(data.ChangePromptAction.Label) end

    local routine = routines[data.Type]
    if routine then routine(name, data) end
end)
