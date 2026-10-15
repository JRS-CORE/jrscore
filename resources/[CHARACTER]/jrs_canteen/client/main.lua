local Core = exports.jrs_core:GetCore()
local progressbar = exports.jrs_progressbar:initiate()
local busy = false

local DRINK_DICT  = 'amb_rest_drunk@world_human_drinking@female_a@idle_a'
local DRINK_ANIM  = 'idle_a'
local CANTEEN_PROP = `p_cs_canteen_hercule`

local function loadModel(model)
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(50) end
    return HasModelLoaded(model)
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(50) end
    return HasAnimDictLoaded(dict)
end

-- Blocks for `ms` while the JRS progress bar runs.
local function progress(label, ms)
    local p = promise.new()
    progressbar.start(label, ms, function() p:resolve(true) end, 'linear', nil, nil, false)
    return Citizen.Await(p)
end

local function inFreshWater(ped)
    if not IsEntityInWater(ped) or not IsPedOnFoot(ped) then return false end
    local c = GetEntityCoords(ped)
    return Config.FreshWater[GetWaterMapZoneAtCoords(c.x, c.y, c.z)] ~= nil
end

local function attachCanteen(ped)
    if not loadModel(CANTEEN_PROP) then return nil end
    local c = GetEntityCoords(ped)
    local prop = CreateObject(CANTEEN_PROP, c.x, c.y, c.z, true, false, false)
    SetModelAsNoLongerNeeded(CANTEEN_PROP)
    AttachEntityToEntity(prop, ped, GetEntityBoneIndexByName(ped, 'SKEL_R_HAND'),
        0.10, 0.09, -0.05, 306.0, 18.0, 0.0, true, true, false, true, 2, true)
    return prop
end

RegisterNetEvent('jrs_canteen:client:use', function(item)
    local ped = PlayerPedId()
    if busy or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
        Core.NotifyRightTip(L('not_here'), 3000)
        return TriggerServerEvent('jrs_canteen:server:finish', item, nil)
    end

    local refill = inFreshWater(ped) and item ~= Config.FullCanteen
    if not refill and item == Config.EmptyCanteen then
        Core.NotifyRightTip(L('empty'), 4000)
        return TriggerServerEvent('jrs_canteen:server:finish', item, nil)
    end

    busy = true
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true, 0, false, false)
    local prop = attachCanteen(ped)

    if refill then
        TaskStartScenarioInPlace(ped, `WORLD_HUMAN_CROUCH_INSPECT`, -1, true, false, false, false)
        progress(L('refilling'), Config.RefillTime)
    else
        if not IsPedOnMount(ped) and loadDict(DRINK_DICT) then
            TaskPlayAnim(ped, DRINK_DICT, DRINK_ANIM, 1.0, 1.0, -1, 31, 1.0, false, false, false)
        end
        progress(L('drinking'), Config.DrinkTime)
    end

    ClearPedTasks(ped)
    if prop and DoesEntityExist(prop) then DeleteObject(prop) end
    RemoveAnimDict(DRINK_DICT)
    busy = false

    TriggerServerEvent('jrs_canteen:server:finish', item, refill)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and busy then
        ClearPedTasks(PlayerPedId())
    end
end)
