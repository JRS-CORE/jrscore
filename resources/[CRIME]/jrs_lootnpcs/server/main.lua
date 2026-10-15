-- jrs_lootnpcs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_lootnpcs | server
-- Receives "I looted body X" from a client, verifies it, then rolls the rewards from Config.Rewards.

local Core   = exports.jrs_core:GetCore()
local Text   = Config.Text[Config.Language] or Config.Text.en
local paid   = {}                    -- network ids that already paid out during the loot window

local function suspect(src, why)
    print(('^3[jrs_lootnpcs]^7 %s (player %s, id %d)'):format(why, GetPlayerName(src) or '?', src))
end

local function say(src, good, message)
    if Config.UseRightTip then
        Core.NotifyRightTip(src, message, 3000)
    elseif good then
        Core.NotifyLeft(src, Text.title, message, 'BLIPS', 'blip_ambient_bounty_target', 3000, 'COLOR_GREEN')
    else
        Core.NotifyLeft(src, Text.title, message, 'BLIPS', 'blip_destroy', 3000, 'COLOR_RED')
    end
end

local function roll(percent)
    return math.random(1, 100) <= percent
end

local function pick(list)
    return list[math.random(1, #list)]
end

-- one handler per reward kind: returns the text to show when the reward was given
local givers = {
    items = function(src, _, rule)
        local choice = pick(rule.pool)
        local amount = rule.amount or 1
        if not exports.jrs_inventory:canCarryItem(src, choice.name, amount) then
            return nil, Text.full.items
        end
        exports.jrs_inventory:addItem(src, choice.name, amount)
        return Text.got .. choice.label
    end,

    weapons = function(src, _, rule)
        local choice = pick(rule.pool)
        if not exports.jrs_inventory:canCarryWeapons(src, 1, nil, choice.name) then
            return nil, Text.full.weapons
        end
        exports.jrs_inventory:createWeapon(src, choice.name, { nothing = 0 }, {})
        return Text.got .. choice.label
    end,

    money = function(_, character, rule)
        local amount = pick(rule.pool)
        character.addCurrency(0, amount)
        return Text.got .. ('%.2f'):format(amount) .. Text.dollars
    end,

    gold = function(_, character, rule)
        local amount = pick(rule.pool)
        character.addCurrency(1, amount)
        return Text.got .. amount .. Text.nuggets
    end,
}

local ORDER = { 'weapons', 'money', 'gold', 'items' }

RegisterNetEvent('npcloot:give_reward', function(netId)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    netId = tonumber(netId)
    local body = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if body == 0 or not DoesEntityExist(body) then
        return suspect(src, 'loot reported for a body that does not exist')
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(body)) > Config.MaxDistance then
        return suspect(src, 'loot reported from too far away')
    end

    -- must be a dead ped that is not a player
    if GetEntityType(body) ~= 1 or IsPedAPlayer(body) or GetEntityHealth(body) > 0 then return end

    if paid[netId] then
        return suspect(src, 'body looted twice')
    end
    paid[netId] = true
    SetTimeout(Config.LootWindow * 60000, function()
        paid[netId] = nil
        if GetPlayerName(src) then
            TriggerClientEvent('npcloot:looted', src, netId)
        end
    end)

    local character = user.getUsedCharacter
    for _, kind in ipairs(ORDER) do
        local rule = Config.Rewards[kind]
        if rule and rule.enabled then
            if roll(rule.chance) then
                local won, problem = givers[kind](src, character, rule)
                if won then say(src, true, won) else say(src, false, problem) end
            else
                say(src, false, Text.nothing[kind])
            end
        end
    end
end)
