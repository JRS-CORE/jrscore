-- jrs_outlaws | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_outlaws | server
-- Makes sure only one player at a time is being ambushed in a zone. Claims are released when the
-- ambush ends, when the player leaves the server, or after Config.ClaimTimeout.

local claims = {}     -- zone key -> { src = playerId, at = os.time() }

local known = {}
for _, zone in ipairs(Config.Zones) do known[zone.key] = true end

local function free(key)
    local claim = claims[key]
    if not claim then return true end
    if os.time() - claim.at > Config.ClaimTimeout then
        claims[key] = nil
        return true
    end
    return false
end

RegisterNetEvent('jrs_outlaws:check', function(key)
    local src = source
    if not known[key] then return end

    if free(key) then
        claims[key] = { src = src, at = os.time() }
        TriggerClientEvent('jrs_outlaws:canstart', src, true)
    else
        TriggerClientEvent('jrs_outlaws:canstart', src, false)
    end
end)

RegisterNetEvent('jrs_outlaws:remove', function(key)
    local claim = claims[key]
    if claim and claim.src == source then          -- only the player who holds the zone can release it
        claims[key] = nil
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for key, claim in pairs(claims) do
        if claim.src == src then claims[key] = nil end
    end
end)
