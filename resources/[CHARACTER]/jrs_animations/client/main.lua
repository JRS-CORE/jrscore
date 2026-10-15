-- jrs_animations | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_animations | client
-- Plays catalogue animations (with optional attached props) for other resources.
--
--   local anim = exports.jrs_animations:initiate()
--   anim.playAnimation('craft', 5000)       -- start, wait, stop
--   anim.startAnimation('hoeing')           -- ... later ...
--   anim.endAnimation('hoeing')
--   anim.endAnimations()                    -- clear everything the ped is doing
--   anim.setCustomProp({ model=, bone=, coords={x,y,z,xr,yr,zr} })   -- replaces the next prop
--   anim.registerAnimation(name, def) / anim.registerAnimations({ name = def })
--   anim.forceRestScenario(bool)

local catalogue = Config.Animations
local props = {}            -- entities currently attached for the running animation
local override              -- one-shot prop replacement
local playing               -- name of the animation started last

-- ------------------------------------------------------------------ props

local function dropProps()
    for i = #props, 1, -1 do
        local obj = props[i]
        if DoesEntityExist(obj) then
            DetachEntity(obj, true, true)
            DeleteObject(obj)
        end
        props[i] = nil
    end
end

local function attach(ped, part, bone, pos)
    local model = joaat(part.model)
    RequestModel(model)
    local limit = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < limit do Wait(0) end
    if not HasModelLoaded(model) then return end

    local here = GetEntityCoords(ped)
    local obj = CreateObject(model, here.x, here.y, here.z, true, true, false, false, true)
    SetModelAsNoLongerNeeded(model)
    AttachEntityToEntity(obj, ped, GetEntityBoneIndexByName(ped, bone), pos.x, pos.y, pos.z,
        pos.xr, pos.yr, pos.zr, true, true, false, true, 1, true)
    props[#props + 1] = obj
    return obj
end

local function spawnProps(ped, def)
    local main = override or def.prop
    override = nil
    if not main then return end
    attach(ped, main, main.bone, main.coords)
    for _, extra in ipairs(main.subprops or {}) do
        attach(ped, extra, main.bone, extra.coords)
    end
end

-- ------------------------------------------------------------------ playback

local function begin(name)
    local def = catalogue[name]
    if not def then return false end
    local ped = PlayerPedId()

    if def.type == 'scenario' then
        spawnProps(ped, def)
        TaskStartScenarioInPlace(ped, joaat(def.hash), 12000, true, false, false, false)
    else
        if not DoesAnimDictExist(def.dict) then return false end
        RequestAnimDict(def.dict)
        local limit = GetGameTimer() + 5000
        while not HasAnimDictLoaded(def.dict) and GetGameTimer() < limit do Wait(0) end
        if not HasAnimDictLoaded(def.dict) then return false end
        spawnProps(ped, def)
        TaskPlayAnim(ped, def.dict, def.name, 1.0, 1.0, -1, def.flag or 0, 1.0, false, false, false, '', false)
    end

    playing = name
    return true
end

local function stop(name)
    local def = catalogue[name or playing]
    local ped = PlayerPedId()
    if def and def.dict then
        StopAnimTask(ped, def.dict, def.name, 1.0)
        RemoveAnimDict(def.dict)
    end
    dropProps()
    override = nil
    if not name or name == playing then playing = nil end
end

local api = {
    startAnimation = begin,
    endAnimation = stop,

    endAnimations = function()
        ClearPedTasksImmediately(PlayerPedId())
        dropProps()
        override, playing = nil, nil
    end,

    playAnimation = function(name, ms)
        if begin(name) then
            Wait(tonumber(ms) or Config.DefaultPlayTime)
            stop(name)
        end
    end,

    setCustomProp = function(prop) override = prop end,

    registerAnimation = function(name, def) catalogue[name] = def end,

    registerAnimations = function(list)
        for name, def in pairs(list or {}) do catalogue[name] = def end
    end,

    forceRestScenario = function(on)
        Citizen.InvokeNative(0xE5A3DD2FF84E1A4B, on)
    end,
}

exports('initiate', function() return api end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then dropProps() end
end)

-- ------------------------------------------------------------------ dev tools (chat commands)

if Config.DevTools then
    local fields = { x = true, y = true, z = true, xr = true, yr = true, zr = true }
    local subject            -- catalogue entry being tuned

    local function reposition()
        if not subject or not subject.prop or not props[1] then return end
        local c, bone = subject.prop.coords, subject.prop.bone
        AttachEntityToEntity(props[1], PlayerPedId(), GetEntityBoneIndexByName(PlayerPedId(), bone),
            c.x, c.y, c.z, c.xr, c.yr, c.zr, true, true, false, true, 1, true)
    end

    RegisterCommand('animdev', function(_, args)
        local name = args[1]
        if not name or not catalogue[name] then return print('[jrs_animations] unknown animation') end
        stop()
        subject = catalogue[name]
        begin(name)
    end, false)

    -- /animnudge x 0.01   or   /animnudge zr -5
    RegisterCommand('animnudge', function(_, args)
        local field, step = args[1], tonumber(args[2])
        if not (subject and subject.prop and fields[field] and step) then return end
        subject.prop.coords[field] = subject.prop.coords[field] + step
        reposition()
    end, false)

    RegisterCommand('animdump', function()
        if not (subject and subject.prop) then return end
        local c = subject.prop.coords
        print(('{ x = %.4f, y = %.4f, z = %.4f, xr = %.4f, yr = %.4f, zr = %.4f }')
            :format(c.x, c.y, c.z, c.xr, c.yr, c.zr))
    end, false)

    RegisterCommand('animstop', function() stop() subject = nil end, false)
end
