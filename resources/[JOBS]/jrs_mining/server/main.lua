-- jrs_mining | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_mining | server
-- Owns every decision: whether a rock may be mined (pickaxe, range, cooldown), how many swings it takes,
-- pickaxe wear, and the loot. The client only plays the animation and the skill bar.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local sessions = {}      -- player -> { at = vector3, swings = n, done = n, lastSwing = time }
local resting  = {}      -- spot key -> os.time() when it may be mined again

-- rocks closer than ~3 m count as the same spot
local function spot(at)
    return ('%d,%d'):format(math.floor(at.x / 3.0), math.floor(at.y / 3.0))
end

local function spotReady(key)
    local since = resting[key]
    if not since then return true end
    if os.time() - since > Config.Cooldown * 60 then
        resting[key] = nil
        return true
    end
    return false
end

-- ------------------------------------------------------------------ pickaxe

-- returns true when the pickaxe survived this use
local function usePickaxe(src)
    local pickaxe = exports.jrs_inventory:getItem(src, Config.Pickaxe)
    if not pickaxe then
        Core.NotifyObjective(src, Text.noPickaxe, 5000)
        return false
    end

    local wear = Config.Wear
    local meta = pickaxe.metadata
    local durability = (meta and meta.durability or (wear.startsAt + 1)) - 1

    if durability < wear.riskBelow and math.random(wear.breakOneIn.min, wear.breakOneIn.max) == 1 then
        exports.jrs_inventory:subItem(src, Config.Pickaxe, 1, meta)
        Core.NotifyObjective(src, Text.pickBroke, 5000)
        return false
    end

    exports.jrs_inventory:setItemMetadata(src, pickaxe.id,
        { durability = durability, description = Text.durability .. ' ' .. durability }, 1)
    return true
end

-- ------------------------------------------------------------------ starting a rock

RegisterNetEvent('jrs_mining:start', function(at)
    local src = source
    if type(at) ~= 'vector3' or sessions[src] then return TriggerClientEvent('jrs_mining:refused', src) end
    if #(GetEntityCoords(GetPlayerPed(src)) - at) > 5.0 then return TriggerClientEvent('jrs_mining:refused', src) end

    local key = spot(at)
    if not spotReady(key) then
        Core.NotifyObjective(src, Text.cooling, 5000)
        return TriggerClientEvent('jrs_mining:refused', src)
    end
    if not usePickaxe(src) then return TriggerClientEvent('jrs_mining:refused', src) end

    local swings = math.random(Config.Swings.min, Config.Swings.max)
    sessions[src] = { at = at, key = key, swings = swings, done = 0, last = 0 }
    TriggerClientEvent('jrs_mining:go', src, at, swings)
end)

-- ------------------------------------------------------------------ one good swing

local function roll()
    local roll = math.random(1, Config.ChanceRange)
    local pool = {}
    for _, entry in ipairs(Config.Loot) do
        if entry.chance >= roll then pool[#pool + 1] = entry end
    end
    return pool[math.random(#pool > 0 and #pool or 1)]
end

RegisterNetEvent('jrs_mining:swing', function()
    local src = source
    local run = sessions[src]
    if not run then return end

    if #(GetEntityCoords(GetPlayerPed(src)) - run.at) > 10.0 then return end
    local now = GetGameTimer()
    if now - run.last < 1500 then return end            -- one swing takes a couple of seconds
    run.last = now

    run.done = run.done + 1
    if run.done >= run.swings then
        resting[run.key] = os.time()
        sessions[src] = nil
    end

    local drop = roll()
    if not drop then return Core.NotifyObjective(src, Text.nothing, 5000) end

    local amount = math.random(1, drop.most)
    if not exports.jrs_inventory:canCarryItem(src, drop.name, amount) then
        return Core.NotifyObjective(src, Text.bagFull .. drop.label, 5000)
    end
    exports.jrs_inventory:addItem(src, drop.name, amount)
    Core.NotifyObjective(src, Text.got .. drop.label, 3000)
end)

-- the player stopped (cancelled, died, left the rock)
RegisterNetEvent('jrs_mining:stop', function() sessions[source] = nil end)
AddEventHandler('playerDropped', function() sessions[source] = nil end)
