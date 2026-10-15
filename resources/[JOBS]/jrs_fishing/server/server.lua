-- jrs_fishing | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_fishing | server
-- Baits are usable items. Using one asks the client whether a rod is in hand; the bait is only spent when it is.
-- The client reports a landed fish, and the server checks that the fish really exists next to the player
-- before paying it out as an inventory item.

local Core = exports.jrs_core:GetCore()
local T = Translation.Langs[Config.Lang]

-- model hash -> { item = inventory item, name = label, texture = icon }, built from config/fishData.lua
local fishByModel = {}
for model, row in pairs(FishData) do
    fishByModel[joaat(model)] = { item = model:lower(), name = row[1], texture = row[2] }
end

local fishing = {}               -- server id -> true while this player fishes
local counted = {}               -- fish entity -> true once it has been paid
local lastCatchAt = {}           -- server id -> game timer of the last payout

local CATCH_RANGE, CATCH_GAP = 30.0, 3000

AddEventHandler('entityRemoved', function(entity) counted[entity] = nil end)

CreateThread(function()
    for _, bait in ipairs(Baits) do
        exports.jrs_inventory:registerUsableItem(bait, function(data)
            local src = data.source
            fishing[src] = true
            exports.jrs_inventory:closeInventory(src)

            local ok, usedBait = table.unpack(Core.Callback.TriggerAwait('jrs_fishing:checkRodAndBait', src, bait) or {})
            if not ok then return end
            exports.jrs_inventory:subItem(src, usedBait, 1)
            TriggerClientEvent('jrs_fishing:UseBait', src, usedBait)
        end, GetCurrentResourceName())
    end
end)

RegisterServerEvent('jrs_fishing:stopFishing', function()
    fishing[source] = nil
end)

local function landedFishIsReal(src, netId, model)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if entity == 0 or not DoesEntityExist(entity) then
        print('Entity does not exist', netId)
        return false
    end
    if GetEntityModel(entity) ~= model or counted[entity] then return false end
    if #(GetEntityCoords(entity) - GetEntityCoords(GetPlayerPed(src))) > CATCH_RANGE then return false end

    local now = GetGameTimer()
    if lastCatchAt[src] and now - lastCatchAt[src] < CATCH_GAP then return false end
    lastCatchAt[src] = now
    counted[entity] = true
    return true
end

RegisterServerEvent('jrs_fishing:FishToInventory', function(netId, model, weight, status)
    local src = source
    if not fishing[src] then
        return print('Player is not fishing and tried to give item to inventory', GetPlayerName(src))
    end
    if not landedFishIsReal(src, tonumber(netId), model) then return end

    local fish = fishByModel[model]
    if not fish then return print('Fish model not found in fish data', model) end

    if not exports.jrs_inventory:canCarryItem(src, fish.item, 1) then
        return Core.NotifyObjective(src, T.CannotCarryMore, 4000)
    end

    if Config.DiscordIntegration then
        TriggerEvent('jrs_fishing:discord', model, weight, status, src)
    end

    exports.jrs_inventory:addItem(src, fish.item, 1)
    Core.NotifyAvanced(src, T.YourGot .. ' ' .. fish.name, 'inventory_items', fish.texture, 'COLOR_PURE_WHITE', 4000)
end)

AddEventHandler('playerDropped', function()
    local src = source
    fishing[src], lastCatchAt[src] = nil, nil
end)

-- local only: a net event here would let anybody post to the webhook
AddEventHandler('jrs_fishing:discord', function(model, weight, status, src)
    local fish = fishByModel[model]
    if not fish then return print('Fish model not found in fish data', model) end

    local user = Core.getUser(src)
    local character = user and user.getUsedCharacter
    local who = character and (character.firstname .. ' ' .. character.lastname) or 'Unknown Player'

    local outcome = status == 'keep' and T.discord_fishKept or status == 'throw' and T.discord_fishThrow or ''
    local lines = {
        outcome,
        T.discord_fieldFishName .. ': ' .. fish.name,
        T.discord_fieldFishWeight .. ': ' .. string.format('%.2f%%', weight * 54.25) .. 'Kg',
    }

    local webhook = ''           -- put the webhook link here
    Core.AddWebhook(who .. ' ' .. T.discord_fishCaught, webhook, table.concat(lines, '\n'), 4777493,
        Config.DiscordBotName, Config.DiscordFooterLogo, Config.DiscordAvatar)
end)
