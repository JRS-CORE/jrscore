-- jrs_saloons | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_saloons | server
-- Registers one shared storage per saloon and opens it for that saloon's staff (checked server-side).

local Core = exports.jrs_core:GetCore()

local byJob = {}
for _, s in ipairs(Config.Saloons) do byJob[s.job] = s end

CreateThread(function()
    for _, s in ipairs(Config.Saloons) do
        exports.jrs_inventory:registerInventory({
            id = s.job,
            name = s.name,
            limit = Config.StorageLimit,
            acceptWeapons = false,
            shared = true,
            ignoreItemStackLimit = true,
            whitelistItems = false,
            whitelistWeapons = false,
            UsePermissions = false,
            UseBlackList = false,
        })
    end
end)

local function jobOf(src)
    local user = Core.getUser(src)
    local character = user and user.getUsedCharacter
    return character and character.job
end

RegisterNetEvent('jrsSaloon:GetInventory', function(job)
    local src = source
    local saloon = type(job) == 'string' and byJob[job]
    if not saloon then return end
    if jobOf(src) ~= saloon.job then return end

    -- the player must really be at the storage point, not just claim it
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - saloon.storage) > Config.UseDistance + 3.0 then return end

    exports.jrs_inventory:openInventory(src, saloon.job)
end)

-- Tell the crafting script where each saloon can cook, once a character is picked.
AddEventHandler('jrs:SelectedCharacter', function(src)
    for _, s in ipairs(Config.Saloons) do
        TriggerClientEvent('jrs:AddCraftLocation', src, {
            id = s.job,
            name = s.cookName,
            Job = { s.job },
            x = s.cook.x, y = s.cook.y, z = s.cook.z,
            Categories = { 'food' },
        })
    end
end)
