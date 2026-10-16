-- jrs_goldclaim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_goldclaim | client
-- Gold rockers (placed by players): the prop, the menu, loading paydirt and water, the outputs that fall out,
-- repairing, claim zones with blips, and the police action against unlicensed rockers. The server owns all
-- values; this file shows things and asks.

local rockers = {}          -- prop id -> { obj }            streamed in near the player
local outputs = {}          -- output id -> { obj, rockerid } paydirt / gold lying next to a rocker
local zones = {}            -- prop id -> { coords, name, inside, blip }
local byId = {}             -- prop id -> prop data
local vegetation = {}       -- prop id -> vegetation modifier handle

local SMOKE = { 'scr_dm_ftb', 'scr_mp_chest_spawn_smoke' }
local SCENARIO_BUCKETS = { `p_bucket03x`, `p_bucket01x`, `p_cs_bucket01x`, `p_cs_bucket01bx` }
local TARGET_RANGE <const> = 3.0

-- the bucket scenario spawns a bucket that clearing the tasks leaves behind
local function removeBucketProp(ped)
    Wait(100)
    local at = GetEntityCoords(ped)
    for _, model in ipairs(SCENARIO_BUCKETS) do
        local bucket = GetClosestObjectOfType(at.x, at.y, at.z, 1.5, model, false, false, false)
        if bucket ~= 0 and DoesEntityExist(bucket) then
            if IsEntityAttachedToEntity(bucket, ped) then DetachEntity(bucket, true, false) end
            SetEntityAsMissionEntity(bucket, false, false)
            DeleteObject(bucket)
        end
    end
    ClearPedTasksImmediately(ped)
end

local function smokeAt(propid)
    local r = rockers[propid]
    if not r or not DoesEntityExist(r.obj) then return end
    local at = GetEntityCoords(r.obj)
    UseParticleFxAsset(SMOKE[1])
    StartParticleFxNonLoopedAtCoord(SMOKE[2], at.x, at.y, at.z, 0.0, 0.0, 0.0, 1.0, false, false, false, true)
end

local function rockerData(propid) return JRS.Await('jrs_goldclaim:server:getrockerdata', propid) end

local function ownsRocker(propid)
    local p = byId[propid]
    return p ~= nil and p.builder == MyCharId()
end

-- ------------------------------------------------------------------ the rocker prop

local function dropVegetation(propid)
    local handle = vegetation[propid]
    if handle then
        Citizen.InvokeNative(0x9CF1836C03FB67A2, handle, 0)
        vegetation[propid] = nil
    end
end

local function despawn(propid)
    local r = rockers[propid]
    if not r then return end
    if DoesEntityExist(r.obj) then
        JRS.RemoveEntityTarget(r.obj)
        SetEntityAsMissionEntity(r.obj, false, false)
        DeleteObject(r.obj)
    end
    rockers[propid] = nil
end

-- what can be done with the prop by looking at it
local function targetOptions(propid)
    local function option(name, label, icon, event, extra)
        local o = { name = name .. propid, label = L(label), icon = icon, distance = TARGET_RANGE,
                    onSelect = function() TriggerEvent(event, propid) end }
        for k, v in pairs(extra or {}) do o[k] = v end
        return o
    end
    return {
        option('rocker_menu_', 'rocker_target_menu', 'fa-solid fa-bars', 'jrs_goldclaim:rocker:client:mainmenu', { groupLabel = L('rocker_menu') }),
        option('add_paydirt_', 'rocker_target_add_paydirt', 'fa-solid fa-hill-rockslide', 'jrs_goldclaim:rocker:client:addpaydirt'),
        option('add_water_', 'rocker_target_add_water', 'fa-solid fa-droplet', 'jrs_goldclaim:rocker:client:addwater'),
        option('destroy_illegal_', 'rocker_destroy_illegal', 'fa-solid fa-gavel', 'jrs_goldclaim:rocker:client:destroyillegal', {
            -- looked at live, so job and licence changes count at once
            canInteract = function()
                local p = byId[propid]
                return p ~= nil and p.licensed ~= 1 and IsLeo()
            end,
        }),
    }
end

local function spawn(p)
    if not LoadModel(Config.GoldRocker) then return end

    local obj = CreateObject(Config.GoldRocker, p.x, p.y, p.z - 1.2, false, false, false)
    SetEntityHeading(obj, p.h or 0.0)
    SetEntityAsMissionEntity(obj, true, true)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(Config.GoldRocker)

    -- one vegetation modifier per rocker; adding it again on every stream-in would stack them
    if Config.EnableVegModifier and not vegetation[p.id] then
        vegetation[p.id] = Citizen.InvokeNative(0xFA50F79257745E74, p.x, p.y, p.z, 3.0, 1, 511, 0)
    end

    rockers[p.id] = { obj = obj }
    JRS.AddEntityTarget(obj, targetOptions(p.id))
end

CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        local wait = 3000
        for _, p in ipairs(Config.PlayerProps) do
            local away = #(here - vector3(p.x, p.y, p.z))
            if away < Config.PropDrawDistance then
                wait = 1000
                if not rockers[p.id] then spawn(p) end
            elseif rockers[p.id] and away > Config.PropDrawDistance + 15.0 then
                despawn(p.id)
            end
        end
        Wait(wait)
    end
end)

-- ------------------------------------------------------------------ claim zones

local function dropZone(propid)
    local z = zones[propid]
    if not z then return end
    if z.blip then RemoveBlip(z.blip) end
    zones[propid] = nil
end

local function makeZone(p)
    local was = zones[p.id] and zones[p.id].inside or false
    dropZone(p.id)
    local at = vector3(p.x, p.y, p.z)
    zones[p.id] = {
        coords = at, name = p.claimname, inside = was,
        blip = CreateNamedBlip(at, Config.ClaimBlip.blipSprite, Config.ClaimBlip.blipScale, p.claimname, Config.ClaimBlip.blipColour),
    }
end

-- licensed claims with a name get a zone; everything else loses its zone
local function syncZones()
    local wanted = {}
    for _, p in ipairs(Config.PlayerProps) do
        if p.licensed == 1 and p.claimname and p.claimname ~= '' then
            wanted[p.id] = true
            local z = zones[p.id]
            if not z or z.name ~= p.claimname then makeZone(p) end
        end
    end
    for propid in pairs(zones) do
        if not wanted[propid] then dropZone(propid) end
    end
end

CreateThread(function()
    while true do
        Wait(500)
        local here = GetEntityCoords(PlayerPedId())
        for _, z in pairs(zones) do
            local inside = #(here - z.coords) <= Config.ClaimZoneRadius
            if inside ~= z.inside then
                z.inside = inside
                JRS.Notify(z.name .. ': ' .. L(inside and 'rocker_entering_claim_desc' or 'rocker_leaving_claim_desc', z.name), inside and 7000 or 5000)
            end
        end
    end
end)

-- ------------------------------------------------------------------ data from the server

local function setProps(list)
    Config.PlayerProps = list or {}
    byId = {}
    for _, p in ipairs(Config.PlayerProps) do byId[p.id] = p end
    for propid in pairs(rockers) do if not byId[propid] then despawn(propid) end end
    for propid in pairs(vegetation) do if not byId[propid] then dropVegetation(propid) end end
    syncZones()
end

RegisterNetEvent('jrs_goldclaim:rocker:client:updatePropData', setProps)

local function clearOutputs(rockerid)
    for id, o in pairs(outputs) do
        if not rockerid or o.rockerid == rockerid then
            if DoesEntityExist(o.obj) then
                JRS.RemoveEntityTarget(o.obj)
                DeleteObject(o.obj)
            end
            outputs[id] = nil
        end
    end
end

local function loadAll()
    clearOutputs()                                       -- the previous character's leftovers
    setProps(JRS.Await('jrs_goldclaim:server:getprops'))
    -- outputs the server still holds for this character (relog, restart) come back as props
    for _, pending in ipairs(JRS.Await('jrs_goldclaim:server:getpending') or {}) do
        for _ = 1, pending.gold do TriggerEvent('jrs_goldclaim:rocker:client:spawnoutputprop', pending.propid, 'gold', true) end
        for _ = 1, pending.paydirt do TriggerEvent('jrs_goldclaim:rocker:client:spawnoutputprop', pending.propid, 'paydirt', true) end
    end
end

RegisterNetEvent('jrs:SelectedCharacter', loadAll)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() and LocalPlayer.state.isLoggedIn then loadAll() end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:removePropObject', function(propid)
    despawn(propid)
    dropVegetation(propid)
    dropZone(propid)
    clearOutputs(propid)
    if byId[propid] then
        for i = #Config.PlayerProps, 1, -1 do
            if Config.PlayerProps[i].id == propid then table.remove(Config.PlayerProps, i) end
        end
        byId[propid] = nil
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:refreshclaim', function(propid, name)
    local p = byId[propid]
    if p then
        p.claimname = name
        syncZones()
    end
end)

-- ------------------------------------------------------------------ menus

RegisterNetEvent('jrs_goldclaim:rocker:client:mainmenu', function(propid)
    local info = rockerData(propid)
    if not info then return end

    local mine = ownsRocker(propid)
    local args = { rockerid = propid }
    local options = { { title = L('rocker_equipment_info'), event = 'jrs_goldclaim:rocker:client:checkrocker', args = args } }
    local function add(option) option.args = args options[#options + 1] = option end

    if mine or not Config.OwnerOnlyProcessing then
        add({ title = L('rocker_start_processing'), description = info.processing and L('rocker_already_processing_desc') or nil,
              event = 'jrs_goldclaim:rocker:client:startprocessing', disabled = info.processing })
    end
    add({ title = L('rocker_repair_equipment', Config.RepairWoodAmount), event = 'jrs_goldclaim:rocker:client:repairrocker', disabled = info.quality >= 100 })
    if mine and info.licensed == 1 then add({ title = L('rocker_rename_claim'), event = 'jrs_goldclaim:rocker:client:renameclaim' }) end
    if mine then
        add({ title = L('rocker_packup_equipment'), description = info.quality < 100 and L('rocker_needs_repair') or nil,
              event = 'jrs_goldclaim:rocker:client:packuprocker', disabled = info.quality < 100 })
    end
    if info.licensed == 0 and IsLeo() then add({ title = L('rocker_destroy_illegal'), event = 'jrs_goldclaim:rocker:client:destroyillegal' }) end

    OpenContext({ id = 'goldclaim_main_menu', title = info.claimname or L('rocker_menu'), subtitle = L('rocker_menu'), options = options })
    ShowContext('goldclaim_main_menu')
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:checkrocker', function(data)
    local info = rockerData(data.rockerid)
    if not info then return end

    local licence = L(info.licensed == 1 and 'rocker_info_licensed' or 'rocker_info_unlicensed')
    OpenContext({
        id = 'goldclaim_info', title = L('rocker_info_title'), menu = 'goldclaim_main_menu',
        options = {
            { title = L('rocker_info_id', info.propid) },
            { title = L('rocker_info_owner', info.owner) },
            { title = L('rocker_info_condition', info.quality) },
            { title = L('rocker_info_water', info.water, Config.MaxWater) },
            { title = L('rocker_info_paydirt', info.paydirt, Config.MaxPaydirt) },
            { title = L('rocker_info_claim', info.claimname or L('rocker_info_none'), licence) },
        },
    })
    ShowContext('goldclaim_info')
end)

-- ------------------------------------------------------------------ working on a rocker

-- an action that needs an item, takes time (with a scenario), then reports to the server
local function work(item, count, missing, duration, scenario, serverEvent, ...)
    if IsBusy() then return end
    if not HasItem(item, count) then return Notify(missing, nil, 'error') end
    local args = { ... }
    if DoTimedAction({ duration = duration, scenario = scenario, onCleanup = removeBucketProp }) then
        TriggerServerEvent(serverEvent, table.unpack(args))
    end
end

RegisterNetEvent('jrs_goldclaim:rocker:client:addpaydirt', function(propid)
    work('paydirt', 1, L('rocker_no_paydirt'), Config.AddPaydirtTime, Config.Anims.add_paydirt, 'jrs_goldclaim:rocker:server:addpaydirt', propid)
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:addwater', function(propid)
    work('rocker_bucket_full', 1, L('rocker_no_fullbucket'), Config.AddWaterTime, Config.Anims.add_water, 'jrs_goldclaim:rocker:server:addwater', propid)
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:repairrocker', function(data)
    if IsBusy() then return end
    if not HasItem('wood', Config.RepairWoodAmount) then
        return Notify(L('rocker_not_enough_wood', Config.RepairWoodAmount), nil, 'error')
    end
    if DoTimedAction({ duration = Config.RepairTime, scenario = Config.Anims.crouch_inspect }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:repairrocker', data.rockerid)
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:startprocessing', function(data)
    TriggerServerEvent('jrs_goldclaim:rocker:server:processrocker', data.rockerid)
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:processingcomplete', function()
    Notify(L('rocker_processing_complete_title'), L('rocker_processing_complete_desc'), 'inform', 'coins', 7000)
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:renameclaim', function(data)
    OpenInputDialog(L('rocker_rename_title'), { { label = L('rocker_rename_label'), type = 'input' } }, function(answers)
        if answers and answers[1] and answers[1] ~= '' then
            TriggerServerEvent('jrs_goldclaim:rocker:server:renameclaim', data.rockerid, answers[1])
        end
    end)
end)

-- the three actions that remove the rocker with smoke
local function takeAway(propid, duration, serverEvent)
    if IsBusy() then return end
    if DoTimedAction({ duration = duration, scenario = Config.Anims.crouch_inspect }) then
        smokeAt(propid)
        TriggerServerEvent(serverEvent, propid)
    end
end

RegisterNetEvent('jrs_goldclaim:rocker:client:packuprocker', function(data)
    takeAway(data.rockerid, Config.PackUpTime, 'jrs_goldclaim:rocker:server:destroyProp')
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:destroyillegal', function(propid)
    if type(propid) == 'table' then propid = propid.rockerid end          -- from the menu
    takeAway(propid, Config.DestroyTime, 'jrs_goldclaim:rocker:server:leodestroy')
end)

-- ------------------------------------------------------------------ what falls out of the rocker

local function pickUp(id, serverEvent)
    local o = outputs[id]
    if not o or IsBusy() then return end
    if DoTimedAction({ duration = Config.PickupTime, scenario = Config.Anims.crouch_inspect, canCancel = true }) then
        if DoesEntityExist(o.obj) then
            JRS.RemoveEntityTarget(o.obj)
            DeleteObject(o.obj)
        end
        outputs[id] = nil
        TriggerServerEvent(serverEvent, o.rockerid)
    end
end

local counter = 0

RegisterNetEvent('jrs_goldclaim:rocker:client:spawnoutputprop', function(propid, kind, silent)
    local p = byId[propid]
    if not p then return end

    local gold = kind == 'gold'
    local model = gold and Config.GoldProp or Config.PaydirtProp

    if not silent then
        if gold then Notify(L('rocker_processing_gold_title'), L('rocker_processing_gold_desc'), 'success', 'coins')
        else Notify(L('rocker_processing_paydirt_title'), L('rocker_processing_paydirt_desc'), 'inform', 'box-open') end
    end
    if not LoadModel(model) then return end

    -- beside the rocker, jittered so several outputs do not sit on each other
    local angle = math.rad(p.h or 0.0) + math.pi / 2 + (math.random() - 0.5) * 0.6
    local away = Config.PropSpawnOffset + math.random() * 0.5
    local obj = CreateObject(model, p.x + away * math.cos(angle), p.y + away * math.sin(angle), p.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)

    counter = counter + 1
    local id = ('%s_%s'):format(propid, counter)
    outputs[id] = { obj = obj, rockerid = propid }

    JRS.AddEntityTarget(obj, { {
        name = 'pickup_' .. id, icon = 'fa-solid fa-hand', distance = TARGET_RANGE,
        label = L(gold and 'rocker_target_pickup_gold' or 'rocker_target_pickup_paydirt'),
        onSelect = function() pickUp(id, gold and 'jrs_goldclaim:rocker:server:pickupgold' or 'jrs_goldclaim:rocker:server:pickuppaydirt') end,
    } })
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:goldpickupresult', function(amount)
    Notify(L('rocker_gold_pickedup_title'), L('rocker_gold_pickedup_desc', amount, L('rocker_gold_nugget')), 'success', 'coins', 7000)
end)

-- ------------------------------------------------------------------ placing a new rocker

AddEventHandler('jrs_goldclaim:rocker:client:placeNewProp', function(spot, heading)
    if IsBusy() then return end
    if IsEntityInWater(PlayerPedId()) then return Notify(L('rocker_cant_place_here'), nil, 'error') end
    if JRS.Await('jrs_goldclaim:server:countprops') >= Config.MaxGoldRockers then
        return Notify(L('rocker_max_equipment'), nil, 'error')
    end
    if DoTimedAction({ duration = Config.PlaceTime, scenario = Config.Anims.crouch_inspect }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:newProp', spot, heading)
    end
end)

-- ------------------------------------------------------------------ gathering in the water

local function standInWater()
    if IsEntityInWater(PlayerPedId()) then return true end
    Notify(L('rocker_not_in_water'), nil, 'error')
    return false
end

-- a heap of dirt where the shovel went in, gone after a while
local function dirtHeap(ped)
    local heap = Config.DigDirtPile
    if not heap or not heap.enabled or not LoadModel(heap.model) then return end
    local at, ahead = GetEntityCoords(ped), GetEntityForwardVector(ped)
    local pile = CreateObject(heap.model, at.x + ahead.x * heap.offset, at.y + ahead.y * heap.offset, at.z - 1.0, false, false, false)
    SetModelAsNoLongerNeeded(heap.model)
    SetTimeout(heap.lifetime, function() if DoesEntityExist(pile) then DeleteObject(pile) end end)
end

RegisterNetEvent('jrs_goldclaim:rocker:client:useshovel', function()
    if IsBusy() or not standInWater() then return end
    local dig, shovel = Config.Anims.dig, Config.ShovelProp
    if not LoadModel(shovel.model) or not LoadAnimDict(dig.dict) then return end

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    local at = GetEntityCoords(ped)
    local tool = CreateObject(shovel.model, at.x, at.y, at.z, true, true, true)
    local o = shovel.offset
    AttachEntityToEntity(tool, ped, GetEntityBoneIndexByName(ped, shovel.bone), o[1], o[2], o[3], o[4], o[5], o[6], true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(shovel.model)
    TaskPlayAnim(ped, dig.dict, dig.name, 3.0, 3.0, -1, 1, 0, false, false, false)

    local done = DoTimedAction({
        duration = Config.ShovelDigTime,
        onCleanup = function()
            if DoesEntityExist(tool) then
                DetachEntity(tool, true, false)
                DeleteObject(tool)
            end
            RemoveAnimDict(dig.dict)
        end,
    })
    if done then
        dirtHeap(ped)
        TriggerServerEvent('jrs_goldclaim:rocker:server:digpaydirt')
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:usebucket', function()
    if IsBusy() or not standInWater() then return end
    if DoTimedAction({ duration = Config.BucketFillTime, scenario = Config.Anims.crouch_inspect }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:fillbucket')
    end
end)

-- ------------------------------------------------------------------ cleanup

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for propid in pairs(rockers) do despawn(propid) end
    for propid in pairs(vegetation) do dropVegetation(propid) end
    clearOutputs()
    for propid in pairs(zones) do dropZone(propid) end
    LocalPlayer.state:set('inv_busy', false, true)
end)
