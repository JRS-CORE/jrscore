-- jrs_search | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_search | server
-- Opens another player's inventory for a search, after checking the target is really restrained or
-- surrendering, the searcher may search, the target is not protected and nobody else is searching them.

local protected = {}      -- char identifier -> true while a new character is protected
local beingSearched = {}  -- target source -> true
local searching = {}      -- searcher source -> target source

local function listHas(list, value)
    for _, item in pairs(list or {}) do
        if item == value then return true end
    end
    return false
end

local function refuse(src, key)
    local text = Locales[key]
    SendNotification(src, text.text, 'error', text.duration)
end

local function release(searcher, target)
    searching[searcher] = nil
    if target then beingSearched[target] = nil end
end

-- server-side only: a client must not be able to make itself unsearchable
AddEventHandler('jrs_search:server:protect', function(src)
    src = tonumber(src)
    local player = src and JRS.MethodPlayer(src)
    if player then protected[player.getCharacterIdentifier()] = true end
end)

RegisterServerEvent('jrs_search:server:reset_searched_target', function(targetId)
    local src, target = source, tonumber(targetId)
    -- only the one who is searching that target can free them
    if target and searching[src] == target then release(src, target) end
end)

-- is the target restrained or surrendering? checked here, not on the searcher's client
local function targetGaveUp(target, searcherJob)
    local flags = Player(target).state
    if (Config.SearchHandsUp and flags.jrs_handsup == true) or flags.jrs_robbery_cuffed == true then return true end
    return listHas(Config.LawJobs, searcherJob)
end

local function mayUseSearch(job)
    local only = Config.SearchByJobsOnly
    if only == false or JRS.TableLength(only) == 0 then return true end
    return listHas(only, job)
end

RegisterServerEvent('jrs_search:server:search', function(targetId)
    local src, target = source, tonumber(targetId)
    if not target or target == src or GetPlayerPed(target) == 0 or searching[src] then return end

    Wait(math.random(100, 1000))

    local me, them = JRS.MethodPlayer(src), JRS.MethodPlayer(target)
    if not me or not them then return end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) > 4.0 then return end

    local myJob = me.getJob()
    if not targetGaveUp(target, myJob) then return refuse(src, 'PLAYER_TARGET_NOT_SURRENDERED') end
    if not mayUseSearch(myJob) then return refuse(src, 'NOT_REQUIRED_JOB') end

    if protected[them.getCharacterIdentifier()] and not listHas(Config.NewCharacterSafeDurationJobBypass, myJob) then
        return refuse(src, 'PLAYER_TARGET_UNDER_PROTECTION')
    end
    if listHas(Config.BlacklistedJobs, them.getJob()) then return refuse(src, 'PLAYER_TARGET_BLACKLISTED_JOB') end
    if beingSearched[target] then return refuse(src, 'CANNOT_SEARCH_PLAYER_IS_BUSY') end

    beingSearched[target] = true
    searching[src] = target
    TriggerClientEvent('jrs_search:client:setSearchingState', src, true)
    exports.jrs_inventory:OpenPlayerInventoryAdmin(src, target, 4.0)
end)

-- the searcher closed the window: the target can be searched again
RegisterNetEvent('jrsCore:closestorage', function(id)
    local src = source
    local target = searching[src]
    if not target or tostring(id) ~= ('admin_search:%d'):format(target) then return end
    release(src, target)
    TriggerClientEvent('jrs_search:client:closed', src, false)
    TriggerClientEvent('jrs_search:client:setSearchingState', src, false)
end)

AddEventHandler('playerDropped', function()
    local src = source
    release(src, searching[src])
    beingSearched[src] = nil
end)
