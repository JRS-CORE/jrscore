-- jrs_wildhorse | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_wildhorse | server
-- A player who breaks a wild horse in can sell it to a trainer. The server remembers which player broke which
-- horse, and pays only when that same player is at a trainer with that very horse.

local Core = exports.jrs_core:GetCore()

local brokenBy = {}                  -- horse network id -> player who broke it in

-- ------------------------------------------------------------------ remembering who broke a horse

RegisterNetEvent('jrs_sellhorse:brokeHorse', function(netId)
    local src = source
    netId = tonumber(netId)
    local horse = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if horse == 0 or not DoesEntityExist(horse) then return end

    local isPed = GetEntityType(horse) == 1 and not IsPedAPlayer(horse)
    local close = #(GetEntityCoords(horse) - GetEntityCoords(GetPlayerPed(src))) <= 10.0
    if isPed and close and not brokenBy[netId] then brokenBy[netId] = src end
end)

-- ------------------------------------------------------------------ paying

local function cheatLog(character, src, trainer, why)
    Core.AddWebhook('Possible Cheater', Config.WebhookCheatLog,
        ('player %s (id %d) at %s: %s'):format(character.identifier, src, json.encode(trainer.coords), why))
end

-- the pay of this animal after the horse-taming skill bonus (if the core has that skill)
local function payFor(animal, character)
    local pay = { money = animal.money or 0, gold = animal.gold or 0, points = animal.rolPoints or 0, xp = animal.xp or 0 }

    local skills = type(character.skills) == 'table' and character.skills[Config.SkillName]
    if skills then
        local level = tonumber(skills.Level) or 0
        local top = tonumber(skills.MaxLevel) or math.huge
        local steps = #Config.SkillsLevel
        if Config.SkillsLevel[level] or steps >= top then
            local row = Config.SkillsLevel[level] or Config.SkillsLevel[steps]
            local bonus = row and row.percentage or 0
            pay.money = pay.money + pay.money * bonus
            pay.gold = pay.gold + pay.gold * bonus
            pay.points = pay.points + pay.points * bonus
        end
    end

    pay.money = math.floor(pay.money * 100 + 0.5) / 100
    pay.gold = math.floor(pay.gold)
    return pay, skills
end

RegisterNetEvent('jrs_sellhorse:giveReward', function(request)
    local src = source
    local user = Core.getUser(src)
    if not user or type(request) ~= 'table' then return end
    local character = user.getUsedCharacter

    local netId = tonumber(request.netid)
    local index = tonumber(request.index)
    local trainer = index and Config.trainers[index]
    if not (netId and trainer) then return end

    -- the player has to be at that trainer
    local here = GetEntityCoords(GetPlayerPed(src))
    if #(trainer.coords - here) - ((trainer.radius or 3.0) + 5.0) > 5 then
        return cheatLog(character, src, trainer, 'too far from the trainer')
    end

    if Config.joblocked and not trainer.trainerjob[character.job] then
        return TriggerClientEvent('jrs_wildhorse:notify', src, L('not_trainer'))
    end

    local horse = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(horse) then return print('horse not found, network id', netId) end
    if brokenBy[netId] ~= src then return print('horse was not broken in by this player, network id', netId) end

    local animal = Config.Animals[request.model]
    if not animal or GetEntityModel(horse) ~= request.model then return print('this horse model is not bought') end
    brokenBy[netId] = nil

    local pay, skill = payFor(animal, character)
    if pay.money ~= 0 then character.addCurrency(0, pay.money) end
    if pay.gold ~= 0 then character.addCurrency(1, pay.gold) end
    if pay.points ~= 0 then character.addCurrency(2, pay.points) end
    if skill and type(character.setSkills) == 'function' then pcall(character.setSkills, Config.SkillName, pay.xp) end

    TriggerClientEvent('jrs_wildhorse:notify', src, L('sold', pay.money) .. (pay.gold > 0 and L('sold_gold', pay.gold) or ''))
    Core.AddWebhook('Animal Sold', Config.WebhookAnimalSold,
        ('player %s (id %d) sold %s for $%s, %s gold, %s points'):format(character.identifier, src, animal.name, pay.money, pay.gold, pay.points))

    SetTimeout(4000, function()
        if DoesEntityExist(horse) then DeleteEntity(horse) end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for netId, owner in pairs(brokenBy) do
        if owner == src then brokenBy[netId] = nil end
    end
end)
