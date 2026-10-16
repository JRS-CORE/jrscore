-- jrs_death_logs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_death_logs | client
-- Watches for the ped dying and tells the server how: killed by a player, suicide, drowning, thirst, hunger.

-- weapons that can be named in the log; the label is the key without WEAPON_ and with spaces
local weaponKeys = {
    'WEAPON_UNARMED', 'WEAPON_LASSO', 'WEAPON_FISHINGROD', 'WEAPON_BOW', 'WEAPON_MOONSHINEJUG', 'OBJECT',
    'WEAPON_MELEE_KNIFE', 'WEAPON_MELEE_KNIFE_BEAR', 'WEAPON_MELEE_KNIFE_CIVIL_WAR', 'WEAPON_MELEE_KNIFE_JAWBONE', 'WEAPON_MELEE_KNIFE_JOHN',
    'WEAPON_MELEE_KNIFE_MINER', 'WEAPON_MELEE_KNIFE_VAMPIRE', 'WEAPON_MELEE_LANTERN_ELECTRIC', 'WEAPON_MELEE_MACHETE', 'WEAPON_MELEE_TORCH',
    'WEAPON_MELEE_HATCHET', 'WEAPON_MELEE_HATCHET_VIKING', 'WEAPON_MELEE_HATCHET_HUNTER', 'WEAPON_MELEE_HATCHET_HUNTER_RUSTED',
    'WEAPON_MELEE_HATCHET_HEWING', 'WEAPON_MELEE_HATCHET_DOUBLE_BIT', 'WEAPON_MELEE_HATCHET_DOUBLE_BIT_RUSTED', 'WEAPON_MELEE_ANCIENT_HATCHET',
    'WEAPON_MELEE_CLEAVER', 'WEAPON_MELEE_BROKEN_SWORD',
    'WEAPON_PISTOL_M1899', 'WEAPON_PISTOL_MAUSER', 'WEAPON_PISTOL_MAUSER_DRUNK', 'WEAPON_PISTOL_SEMIAUTO', 'WEAPON_PISTOL_VOLCANIC',
    'WEAPON_REPEATER_CARBINE', 'WEAPON_REPEATER_EVANS', 'WEAPON_REPEATER_HENRY', 'WEAPON_REPEATER_WINCHESTER',
    'WEAPON_REVOLVER_CATTLEMAN', 'WEAPON_REVOLVER_CATTLEMAN_JOHN', 'WEAPON_REVOLVER_CATTLEMAN_MEXICAN', 'WEAPON_REVOLVER_CATTLEMAN_PIG',
    'WEAPON_REVOLVER_DOUBLEACTION', 'WEAPON_REVOLVER_DOUBLEACTION_EXOTIC', 'WEAPON_REVOLVER_DOUBLEACTION_GAMBLER', 'WEAPON_REVOLVER_DOUBLEACTION_MICAH',
    'WEAPON_REVOLVER_LEMAT', 'WEAPON_REVOLVER_SCHOFIELD', 'WEAPON_REVOLVER_SCHOFIELD_CALLOWAY', 'WEAPON_REVOLVER_SCHOFIELD_GOLDEN',
    'WEAPON_RIFLE_BOLTACTION', 'WEAPON_RIFLE_SPRINGFIELD', 'WEAPON_RIFLE_VARMINT',
    'WEAPON_SHOTGUN_DOUBLEBARREL', 'WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC', 'WEAPON_SHOTGUN_PUMP', 'WEAPON_SHOTGUN_REPEATING',
    'WEAPON_SHOTGUN_SAWEDOFF', 'WEAPON_SHOTGUN_SEMIAUTO',
    'WEAPON_SNIPERRIFLE_CARCANO', 'WEAPON_SNIPERRIFLE_ROLLINGBLOCK', 'WEAPON_SNIPERRIFLE_ROLLINGBLOCK_EXOTIC',
    'WEAPON_THROWN_DYNAMITE', 'WEAPON_THROWN_MOLOTOV', 'WEAPON_THROWN_THROWING_KNIVES', 'WEAPON_THROWN_TOMAHAWK', 'WEAPON_THROWN_TOMAHAWK_ANCIENT',
}

local weaponLabel = {}
for _, key in ipairs(weaponKeys) do
    weaponLabel[joaat(key)] = key:gsub('^WEAPON_', ''):gsub('^MELEE_', ''):gsub('^THROWN_', ''):gsub('_', ' ')
end

local triggered = false

-- a fresh life starts when the ped is alive again
local function metabolism(key)
    if GetResourceState('jrs_metabolism') ~= 'started' then return 100 end
    local p = promise.new()
    TriggerEvent('jrsmetabolism:getValue', key, function(v) p:resolve(tonumber(v) or 100) end)
    SetTimeout(500, function() p:resolve(100) end)
    return Citizen.Await(p)
end

CreateThread(function()
    while true do
        Wait(1500)
        local ped = PlayerPedId()
        if not IsEntityDead(ped) then
            triggered = false
        elseif not triggered then
            triggered = true
            local killer = GetPedSourceOfDeath(ped)
            local cause = GetPedCauseOfDeath(ped)
            local killerPlayer
            if IsEntityAPed(killer) and IsPedAPlayer(killer) then
                killerPlayer = NetworkGetPlayerIndexFromPed(killer)
            elseif IsEntityAVehicle(killer) then
                local driver = GetPedInVehicleSeat(killer, -1)
                if IsEntityAPed(driver) and IsPedAPlayer(driver) then killerPlayer = NetworkGetPlayerIndexFromPed(driver) end
            end

            local reason = 'DIED'
            if killerPlayer == PlayerId() then
                reason = 'SUICIDE'
            elseif killerPlayer then
                reason = 'KILLED'
            elseif IsEntityUnderwater(ped) or IsEntityInWater(ped) then
                reason = 'DROWNED'
            elseif metabolism('Thirst') <= 0 then
                reason = 'THIRST'
            elseif metabolism('Hunger') <= 0 then
                reason = 'HUNGER'
            end

            TriggerServerEvent('jrs_death_logs:server:died', reason,
                killerPlayer and GetPlayerServerId(killerPlayer) or nil,
                weaponLabel[cause] or tostring(cause))
        end
    end
end)
