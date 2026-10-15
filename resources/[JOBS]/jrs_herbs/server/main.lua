-- jrs_herbs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_herbs | server
-- Checks that a pick is possible (player next to the plant, plant not picked recently) and pays out.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local pickedAt = {}          -- plant key -> GetGameTimer() until which it stays picked
local lastTry  = {}          -- player -> time of the last attempt

local function key(index, at)
    return ('%d:%.2f:%.2f:%.2f'):format(index, at.x, at.y, at.z)
end

local function plant(index)
    local list = Config.WildPlants
    if index > 0 and index <= #list then return list[index] end
    index = index - #list
    return Config.Spots[index]
end

-- plants are numbered: wild plants first, then the fixed spots
Core.Callback.Register('jrs_herbs:pick', function(src, cb, index, at)
    if type(index) ~= 'number' or index % 1 ~= 0 or type(at) ~= 'vector3' then return cb({ ok = false }) end
    local def = plant(index)
    if not def then return cb({ ok = false }) end

    local now = GetGameTimer()
    if lastTry[src] and now - lastTry[src] < 1500 then return cb({ ok = false }) end
    lastTry[src] = now

    local ped = GetEntityCoords(GetPlayerPed(src))
    if #(ped - at) > Config.Reach + 2.0 then return cb({ ok = false, why = Text.tooFar }) end
    if def.at and #(def.at - at) > 3.0 then return cb({ ok = false, why = Text.tooFar }) end

    local id = key(index, at)
    if pickedAt[id] and now < pickedAt[id] then return cb({ ok = false, why = Text.picked }) end

    local amount = math.random(def.min, def.max)
    local given = false
    for _, item in ipairs(def.reward) do
        if exports.jrs_inventory:canCarryItem(src, item, amount) then
            exports.jrs_inventory:addItem(src, item, amount)
            local info = exports.jrs_inventory:getItemDB(item)
            Core.NotifyRightTip(src, Text.got .. amount .. 'x ' .. (info and info.label or item), 4000)
            given = true
        else
            Core.NotifyRightTip(src, Text.noSpace, 4000)
        end
    end

    if not given then return cb({ ok = false }) end
    pickedAt[id] = now + def.cooldown * 60000
    cb({ ok = true })
end)

AddEventHandler('playerDropped', function() lastTry[source] = nil end)

-- forget plants that are ready again, so the table cannot grow for ever
CreateThread(function()
    while true do
        Wait(10 * 60000)
        local now = GetGameTimer()
        for id, until_ in pairs(pickedAt) do
            if now >= until_ then pickedAt[id] = nil end
        end
    end
end)
