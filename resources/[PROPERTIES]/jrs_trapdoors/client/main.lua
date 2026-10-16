-- jrs_trapdoors | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_trapdoors | client
-- Trapdoor props slide between a closed and an open pose. Open/closed state and who owns a passcode
-- come from the server through GlobalState; this file animates the prop and offers the menu.

local PUSH_DICT <const> = 'mech_cover@env@doors@unlocked@generic@base@push_return@bow@left@no_lean'

local door = {}                  -- id -> { prop, open, t (0 closed .. 1 open), run, moving, owner }
local myCharId

for id, cfg in pairs(Config.Trapdoors) do
    local open = GlobalState['trapdoor:' .. id] == true
    door[id] = { prop = 0, open = open, t = open and 1.0 or 0.0, run = 0, moving = false, owner = GlobalState['trapdoorCode:' .. id] or false }
end

-- ------------------------------------------------------------------ pose

local function mix(a, b, t) return a + (b - a) * t end

-- shortest way round between two angles
local function mixAngle(a, b, t)
    return a + ((b - a + 180.0) % 360.0 - 180.0) * t
end

-- the pose only ever comes from the config and `t`; reading the rotation back from the prop twists it
-- when it is pitched at -90 degrees (gimbal lock)
local function pose(prop, cfg, t)
    local from, to, rf, rt = cfg.closedPosition, cfg.openPosition, cfg.closedRotation, cfg.openRotation
    SetEntityCoordsNoOffset(prop, mix(from.x, to.x, t), mix(from.y, to.y, t), mix(from.z, to.z, t), false, false, false)
    SetEntityRotation(prop, mixAngle(rf.x, rt.x, t), mixAngle(rf.y, rt.y, t), mixAngle(rf.z, rt.z, t), 2, true)
end

local function snap(id)
    local d = door[id]
    d.t = d.open and 1.0 or 0.0
    if d.prop ~= 0 then pose(d.prop, Config.Trapdoors[id], d.t) end
end

local function slide(id)
    local d, cfg = door[id], Config.Trapdoors[id]
    local prop = d.prop
    if prop == 0 or not DoesEntityExist(prop) then return end

    d.run = d.run + 1
    local mine, from, goal = d.run, d.t, d.open and 1.0 or 0.0
    local span = math.max(Config.MoveDuration * math.abs(goal - from), 1)
    local began = GetGameTimer()
    d.moving = true

    CreateThread(function()
        local k = 0.0
        repeat
            if d.run ~= mine or not DoesEntityExist(prop) then return end
            k = math.min((GetGameTimer() - began) / span, 1.0)
            d.t = mix(from, goal, k * k * (3.0 - 2.0 * k))
            pose(prop, cfg, d.t)
            Wait(0)
        until k >= 1.0
        d.moving = false
    end)
end

-- ------------------------------------------------------------------ keeping props and state in step

for id in pairs(Config.Trapdoors) do
    AddStateBagChangeHandler('trapdoor:' .. id, 'global', function(_, _, value)
        door[id].open = value == true
        if door[id].prop ~= 0 then slide(id) end
    end)
    AddStateBagChangeHandler('trapdoorCode:' .. id, 'global', function(_, _, value)
        door[id].owner = value or false
    end)
end

local function propOf(cfg)
    local at = cfg.closedPosition
    local found = GetClosestObjectOfType(at.x, at.y, at.z, 3.0, joaat(cfg.model), false, false, false)
    return DoesEntityExist(found) and found or 0
end

CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        for id, cfg in pairs(Config.Trapdoors) do
            local d = door[id]
            if #(here - cfg.closedPosition) <= Config.StreamDistance then
                local prop = propOf(cfg)
                if prop ~= d.prop then
                    d.prop = prop
                    if prop ~= 0 then snap(id) end
                end
            else
                d.prop = 0
            end
        end
        Wait(1000)
    end
end)

-- ------------------------------------------------------------------ using a door

local function push()
    if JRS.LoadDict(PUSH_DICT) then
        TaskPlayAnim(PlayerPedId(), PUSH_DICT, 'open', 8.0, -8.0, -1, 0, 0, false, false, false)
        RemoveAnimDict(PUSH_DICT)
    end
end

local function askCode(title)
    local typed = JRS.Input(title, '0000', false)
    return typed and typed:gsub('%s', '') or nil
end

-- shows the server's message, true when the action worked
local function succeeded(reply)
    if reply and reply.msg then JRS.Notify(reply.msg) end
    return reply and reply.ok
end

local function tryOpen(id)
    local code
    if door[id].owner then
        code = askCode(L('enter_code'))
        if not code then return end
    end
    if succeeded(JRS.Await('jrs_trapdoors:open', id, code)) then push() end
end

local function changeCode(id)
    local current = askCode(L('current_code'))
    if not current then return end
    local fresh = askCode(L('new_code'))
    if fresh then succeeded(JRS.Await('jrs_trapdoors:changeCode', id, current, fresh)) end
end

local actions = {
    open  = tryOpen,
    close = function(id) push(); TriggerServerEvent('jrs_trapdoors:server:close', id) end,
    set   = function(id)
        local code = askCode(L('new_code'))
        if code then succeeded(JRS.Await('jrs_trapdoors:setCode', id, code)) end
    end,
    change = changeCode,
}

local function menu(id)
    local d = door[id]
    myCharId = myCharId or JRS.Await('jrs_trapdoors:myId')

    local rows = { { label = L(d.open and 'close' or 'open'), value = d.open and 'close' or 'open', desc = '' } }
    if not d.owner then
        rows[#rows + 1] = { label = L('set_code'), value = 'set', desc = '' }
    elseif myCharId and d.owner == myCharId then
        rows[#rows + 1] = { label = L('change_code'), value = 'change', desc = '' }
    end

    JRS.OpenMenu('jrs_trapdoors', L(Config.Trapdoors[id].label or id), L('menu_sub'), rows, function(row, m)
        m.close()
        if door[id].moving then return JRS.Notify(L('busy')) end
        local act = actions[row.value]
        if act then act(id) end
    end)
end

CreateThread(function()
    local prompts = JRS.Prompts()
    local use = prompts:add(0x760A9C6F, LE('menu_sub'))
    while true do
        local wait = 750
        local here = GetEntityCoords(PlayerPedId())
        for id, cfg in pairs(Config.Trapdoors) do
            local d = door[id]
            if d.prop ~= 0 and not d.moving and #(here - cfg.closedPosition) <= (cfg.interactDistance or 2.0) then
                wait = 0
                prompts:show(LE(cfg.label or id))
                if prompts:done(use) then menu(id) end
                break
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id, d in pairs(door) do
        d.run, d.open = d.run + 1, false
        snap(id)
    end
end)
