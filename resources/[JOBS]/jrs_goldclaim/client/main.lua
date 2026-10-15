local SpawnedProps       = {} -- [propid] = { obj = entity }
local SpawnedOutputProps = {} -- [outputId] = { obj = entity, rockerid = propid }
local ClaimZones         = {} -- [propid] = { coords, name, inside, blip }
local PropsById          = {} -- [propid] = prop data (lookup for Config.PlayerProps)
local VegModifiers       = {} -- [propid] = veg modifier handle (added once, removed with the rocker)

local FX_GROUP, FX_NAME = 'scr_dm_ftb', 'scr_mp_chest_spawn_smoke'

local ScenarioBucketModels = { `p_bucket03x`, `p_bucket01x`, `p_cs_bucket01x`, `p_cs_bucket01bx` }


---------------------------------------------
-- helpers
---------------------------------------------
--- WORLD_HUMAN_BUCKET_POUR_LOW spawns its own bucket which ClearPedTasks does not remove
local function RemoveScenarioBucketProp(ped)
    Wait(100)
    local pos = GetEntityCoords(ped)
    for i = 1, #ScenarioBucketModels do
        local obj = GetClosestObjectOfType(pos.x, pos.y, pos.z, 1.5, ScenarioBucketModels[i], false, false, false)
        if obj ~= 0 and DoesEntityExist(obj) then
            if IsEntityAttachedToEntity(obj, ped) then DetachEntity(obj, true, false) end
            SetEntityAsMissionEntity(obj, false, false)
            DeleteObject(obj)
        end
    end
    ClearPedTasksImmediately(ped)
end

local function PlaySmoke(propid)
    local sp = SpawnedProps[propid]
    if not sp or not DoesEntityExist(sp.obj) then return end
    local c = GetEntityCoords(sp.obj)
    UseParticleFxAsset(FX_GROUP)
    StartParticleFxNonLoopedAtCoord(FX_NAME, c.x, c.y, c.z, 0.0, 0.0, 0.0, 1.0, false, false, false, true)
end

local function GetRockerData(propid)
    return JRS.Await('jrs_goldclaim:server:getrockerdata', propid)
end

local function IsOwner(propid)
    local p = PropsById[propid]
    return p ~= nil and p.builder == MyCharId()
end

---------------------------------------------
-- rocker props (streamed in / out by distance)
---------------------------------------------
local function RemoveVegModifier(propid)
    local handle = VegModifiers[propid]
    if handle then
        Citizen.InvokeNative(0x9CF1836C03FB67A2, handle, 0) -- RemoveVegModifierSphere
        VegModifiers[propid] = nil
    end
end

local function DespawnRocker(propid)
    local sp = SpawnedProps[propid]
    if not sp then return end
    if DoesEntityExist(sp.obj) then
        JRS.RemoveEntityTarget(sp.obj)
        SetEntityAsMissionEntity(sp.obj, false, false)
        DeleteObject(sp.obj)
    end
    SpawnedProps[propid] = nil
end

local function SetupRockerTarget(propid, obj)
    JRS.AddEntityTarget(obj, {
        {
            name = 'rocker_menu_' .. propid,
            groupLabel = L('rocker_menu'),
            label = L('rocker_target_menu'),
            icon = 'fa-solid fa-bars',
            distance = 3.0,
            onSelect = function() TriggerEvent('jrs_goldclaim:rocker:client:mainmenu', propid) end,
        },
        {
            name = 'add_paydirt_' .. propid,
            label = L('rocker_target_add_paydirt'),
            icon = 'fa-solid fa-hill-rockslide',
            distance = 3.0,
            onSelect = function() TriggerEvent('jrs_goldclaim:rocker:client:addpaydirt', propid) end,
        },
        {
            name = 'add_water_' .. propid,
            label = L('rocker_target_add_water'),
            icon = 'fa-solid fa-droplet',
            distance = 3.0,
            onSelect = function() TriggerEvent('jrs_goldclaim:rocker:client:addwater', propid) end,
        },
        {
            name = 'destroy_illegal_' .. propid,
            label = L('rocker_destroy_illegal'),
            icon = 'fa-solid fa-gavel',
            distance = 3.0,
            -- evaluated live, so job changes and licence state are always current
            canInteract = function()
                local p = PropsById[propid]
                return p ~= nil and p.licensed ~= 1 and IsLeo()
            end,
            onSelect = function() TriggerEvent('jrs_goldclaim:rocker:client:destroyillegal', propid) end,
        },
    })
end

local function SpawnRocker(p)
    if not LoadModel(Config.GoldRocker) then return end

    local obj = CreateObject(Config.GoldRocker, p.x, p.y, p.z - 1.2, false, false, false)
    SetEntityHeading(obj, p.h or 0.0)
    SetEntityAsMissionEntity(obj, true, true)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(Config.GoldRocker)

    -- add the vegetation modifier only once per rocker (re-adding on every stream-in stacked them up)
    if Config.EnableVegModifier and not VegModifiers[p.id] then
        VegModifiers[p.id] = Citizen.InvokeNative(0xFA50F79257745E74, p.x, p.y, p.z, 3.0, 1, 511, 0) -- AddVegModifierSphere
    end

    SpawnedProps[p.id] = { obj = obj }
    SetupRockerTarget(p.id, obj)
end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local sleep = 3000

        for i = 1, #Config.PlayerProps do
            local p = Config.PlayerProps[i]
            local dist = #(pos - vector3(p.x, p.y, p.z))
            if dist < Config.PropDrawDistance then
                sleep = 1000
                if not SpawnedProps[p.id] then SpawnRocker(p) end
            elseif SpawnedProps[p.id] and dist > Config.PropDrawDistance + 15.0 then
                DespawnRocker(p.id)
            end
        end

        Wait(sleep)
    end
end)

---------------------------------------------
-- claim zones & blips (single thread for all licensed claims)
---------------------------------------------
local function RemoveClaimZone(propid)
    local z = ClaimZones[propid]
    if not z then return end
    if z.blip then RemoveBlip(z.blip) end
    ClaimZones[propid] = nil
end

local function SetupClaimZone(p)
    local wasInside = ClaimZones[p.id] and ClaimZones[p.id].inside or false
    RemoveClaimZone(p.id)
    local coords = vector3(p.x, p.y, p.z)
    ClaimZones[p.id] = {
        coords = coords,
        name   = p.claimname,
        inside = wasInside,
        blip   = CreateNamedBlip(coords, Config.ClaimBlip.blipSprite, Config.ClaimBlip.blipScale, p.claimname, Config.ClaimBlip.blipColour),
    }
end

local function SyncClaimZones()
    local keep = {}
    for i = 1, #Config.PlayerProps do
        local p = Config.PlayerProps[i]
        if p.licensed == 1 and p.claimname and p.claimname ~= '' then
            keep[p.id] = true
            local z = ClaimZones[p.id]
            if not z or z.name ~= p.claimname then SetupClaimZone(p) end
        end
    end
    for propid in pairs(ClaimZones) do
        if not keep[propid] then RemoveClaimZone(propid) end
    end
end

CreateThread(function()
    while true do
        Wait(500)
        local pos = GetEntityCoords(PlayerPedId())
        for _, z in pairs(ClaimZones) do
            local inside = #(pos - z.coords) <= Config.ClaimZoneRadius
            if inside ~= z.inside then
                z.inside = inside
                JRS.Notify(z.name .. ': ' .. L(inside and 'rocker_entering_claim_desc' or 'rocker_leaving_claim_desc', z.name), inside and 7000 or 5000)
            end
        end
    end
end)

---------------------------------------------
-- prop data sync
---------------------------------------------
local function SetPropData(data)
    Config.PlayerProps = data or {}
    PropsById = {}
    for i = 1, #Config.PlayerProps do
        PropsById[Config.PlayerProps[i].id] = Config.PlayerProps[i]
    end
    for propid in pairs(SpawnedProps) do
        if not PropsById[propid] then DespawnRocker(propid) end
    end
    for propid in pairs(VegModifiers) do
        if not PropsById[propid] then RemoveVegModifier(propid) end
    end
    SyncClaimZones()
end

RegisterNetEvent('jrs_goldclaim:rocker:client:updatePropData', SetPropData)

local function ClearOutputProps(rockerid)
    for outputId, o in pairs(SpawnedOutputProps) do
        if not rockerid or o.rockerid == rockerid then
            if DoesEntityExist(o.obj) then
                JRS.RemoveEntityTarget(o.obj)
                DeleteObject(o.obj)
            end
            SpawnedOutputProps[outputId] = nil
        end
    end
end

local function RequestProps()
    ClearOutputProps() -- character switch: drop the previous character's outputs
    SetPropData(JRS.Await('jrs_goldclaim:server:getprops'))
    -- respawn any outputs the server still holds for this character (relog / resource restart)
    for _, p in ipairs(JRS.Await('jrs_goldclaim:server:getpending') or {}) do
        for _ = 1, p.gold do TriggerEvent('jrs_goldclaim:rocker:client:spawnoutputprop', p.propid, 'gold', true) end
        for _ = 1, p.paydirt do TriggerEvent('jrs_goldclaim:rocker:client:spawnoutputprop', p.propid, 'paydirt', true) end
    end
end

RegisterNetEvent('jrs:SelectedCharacter', RequestProps)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then RequestProps() end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:removePropObject', function(propid)
    DespawnRocker(propid)
    RemoveVegModifier(propid)
    RemoveClaimZone(propid)
    ClearOutputProps(propid)
    if PropsById[propid] then
        for i = #Config.PlayerProps, 1, -1 do
            if Config.PlayerProps[i].id == propid then table.remove(Config.PlayerProps, i) end
        end
        PropsById[propid] = nil
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:refreshclaim', function(propid, newname)
    local p = PropsById[propid]
    if not p then return end
    p.claimname = newname
    SyncClaimZones()
end)

---------------------------------------------
-- main menu
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:mainmenu', function(propid)
    local result = GetRockerData(propid)
    if not result then return end

    local isOwner = IsOwner(propid)
    local args = { rockerid = propid }
    local options = {
        { title = L('rocker_equipment_info'), icon = 'fa-solid fa-circle-info', event = 'jrs_goldclaim:rocker:client:checkrocker', args = args, arrow = true },
    }

    if isOwner or not Config.OwnerOnlyProcessing then
        options[#options + 1] = {
            title = L('rocker_start_processing'),
            description = result.processing and L('rocker_already_processing_desc') or nil,
            icon = 'fa-solid fa-cogs',
            event = 'jrs_goldclaim:rocker:client:startprocessing',
            args = args,
            disabled = result.processing,
        }
    end

    options[#options + 1] = {
        title = L('rocker_repair_equipment', Config.RepairWoodAmount),
        icon = 'fa-solid fa-screwdriver-wrench',
        event = 'jrs_goldclaim:rocker:client:repairrocker',
        args = args,
        disabled = result.quality >= 100,
    }

    if isOwner and result.licensed == 1 then
        options[#options + 1] = { title = L('rocker_rename_claim'), icon = 'fa-solid fa-pen', event = 'jrs_goldclaim:rocker:client:renameclaim', args = args }
    end

    if isOwner then
        options[#options + 1] = {
            title = L('rocker_packup_equipment'),
            description = result.quality < 100 and L('rocker_needs_repair') or nil,
            icon = 'fa-solid fa-box-open',
            event = 'jrs_goldclaim:rocker:client:packuprocker',
            args = args,
            disabled = result.quality < 100,
        }
    end

    if result.licensed == 0 and IsLeo() then
        options[#options + 1] = { title = L('rocker_destroy_illegal'), icon = 'fa-solid fa-gavel', event = 'jrs_goldclaim:rocker:client:destroyillegal', args = args }
    end

    OpenContext({
        id = 'goldclaim_main_menu',
        title = result.claimname or L('rocker_menu'),
        subtitle = L('rocker_menu'),
        options = options,
    })
    ShowContext('goldclaim_main_menu')
end)

---------------------------------------------
-- equipment info
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:checkrocker', function(data)
    local result = GetRockerData(data.rockerid)
    if not result then return end

    local status = L(result.licensed == 1 and 'rocker_info_licensed' or 'rocker_info_unlicensed')

    OpenContext({
        id = 'goldclaim_info',
        title = L('rocker_info_title'),
        menu = 'goldclaim_main_menu',
        options = {
            { title = L('rocker_info_id', result.propid), icon = 'fa-solid fa-fingerprint' },
            { title = L('rocker_info_owner', result.owner), icon = 'fa-solid fa-user' },
            { title = L('rocker_info_condition', result.quality), progress = result.quality, colorScheme = 'green', icon = 'fa-solid fa-screwdriver-wrench' },
            { title = L('rocker_info_water', result.water, Config.MaxWater), progress = result.water / Config.MaxWater * 100, colorScheme = 'blue', icon = 'fa-solid fa-droplet' },
            { title = L('rocker_info_paydirt', result.paydirt, Config.MaxPaydirt), progress = result.paydirt / Config.MaxPaydirt * 100, colorScheme = 'orange', icon = 'fa-solid fa-hill-rockslide' },
            { title = L('rocker_info_claim', result.claimname or L('rocker_info_none'), status), icon = 'fa-solid fa-scroll' },
        },
    })
    ShowContext('goldclaim_info')
end)

---------------------------------------------
-- add paydirt / water
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:addpaydirt', function(propid)
    if IsBusy() then return end
    if not HasItem('paydirt', 1) then
        return Notify(L('rocker_no_paydirt'), nil, 'error', 'circle-xmark')
    end

    if DoTimedAction({
        duration = Config.AddPaydirtTime,
        scenario = Config.Anims.add_paydirt,
        onCleanup = RemoveScenarioBucketProp,
    }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:addpaydirt', propid)
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:addwater', function(propid)
    if IsBusy() then return end
    if not HasItem('rocker_bucket_full', 1) then
        return Notify(L('rocker_no_fullbucket'), nil, 'error', 'circle-xmark')
    end

    if DoTimedAction({
        duration = Config.AddWaterTime,
        scenario = Config.Anims.add_water,
        onCleanup = RemoveScenarioBucketProp,
    }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:addwater', propid)
    end
end)

---------------------------------------------
-- start processing (server runs the cycles)
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:startprocessing', function(data)
    TriggerServerEvent('jrs_goldclaim:rocker:server:processrocker', data.rockerid)
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:processingcomplete', function()
    Notify(L('rocker_processing_complete_title'), L('rocker_processing_complete_desc'), 'inform', 'coins', 7000)
end)

---------------------------------------------
-- output props
---------------------------------------------
local function PickupOutput(outputId, serverEvent)
    local o = SpawnedOutputProps[outputId]
    if not o or IsBusy() then return end

    if DoTimedAction({
        duration = Config.PickupTime,
        scenario = Config.Anims.crouch_inspect,
        canCancel = true,
    }) then
        if DoesEntityExist(o.obj) then
            JRS.RemoveEntityTarget(o.obj)
            DeleteObject(o.obj)
        end
        SpawnedOutputProps[outputId] = nil
        TriggerServerEvent(serverEvent, o.rockerid)
    end
end

local outputCounter = 0

RegisterNetEvent('jrs_goldclaim:rocker:client:spawnoutputprop', function(propid, resultType, silent)
    local p = PropsById[propid]
    if not p then return end

    local isGold = resultType == 'gold'
    local model = isGold and Config.GoldProp or Config.PaydirtProp

    if silent then
        -- respawned (inventory was full / relog), no "found" notification
    elseif isGold then
        Notify(L('rocker_processing_gold_title'), L('rocker_processing_gold_desc'), 'success', 'coins')
    else
        Notify(L('rocker_processing_paydirt_title'), L('rocker_processing_paydirt_desc'), 'inform', 'box-open')
    end

    if not LoadModel(model) then return end

    -- offset to the side of the rocker, with a little jitter so stacked outputs don't overlap
    local heading = math.rad(p.h or 0.0) + math.pi / 2 + (math.random() - 0.5) * 0.6
    local dist = Config.PropSpawnOffset + math.random() * 0.5
    local x = p.x + dist * math.cos(heading)
    local y = p.y + dist * math.sin(heading)

    local obj = CreateObject(model, x, y, p.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)

    outputCounter = outputCounter + 1
    local outputId = ('%s_%s'):format(propid, outputCounter)
    SpawnedOutputProps[outputId] = { obj = obj, rockerid = propid }

    JRS.AddEntityTarget(obj, {
        {
            name = 'pickup_' .. outputId,
            label = L(isGold and 'rocker_target_pickup_gold' or 'rocker_target_pickup_paydirt'),
            icon = 'fa-solid fa-hand',
            distance = 3.0,
            onSelect = function()
                PickupOutput(outputId, isGold and 'jrs_goldclaim:rocker:server:pickupgold' or 'jrs_goldclaim:rocker:server:pickuppaydirt')
            end,
        },
    })
end)

RegisterNetEvent('jrs_goldclaim:rocker:client:goldpickupresult', function(amount)
    local label = L('rocker_gold_nugget')
    Notify(L('rocker_gold_pickedup_title'), L('rocker_gold_pickedup_desc', amount, label), 'success', 'coins', 7000)
end)

---------------------------------------------
-- repair
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:repairrocker', function(data)
    if IsBusy() then return end
    if not HasItem('wood', Config.RepairWoodAmount) then
        return Notify(L('rocker_not_enough_wood', Config.RepairWoodAmount), nil, 'error', 'circle-xmark')
    end

    if DoTimedAction({
        duration = Config.RepairTime,
        scenario = Config.Anims.crouch_inspect,
    }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:repairrocker', data.rockerid)
    end
end)

---------------------------------------------
-- rename claim
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:renameclaim', function(data)
    OpenInputDialog(L('rocker_rename_title'), {
        {
            label = L('rocker_rename_label'),
            description = L('rocker_rename_desc', Config.MaxClaimNameLength),
            type = 'input',
            icon = 'fa-solid fa-pen',
            required = true,
            maxLength = Config.MaxClaimNameLength,
        },
    }, function(input)
        if input and input[1] and input[1] ~= '' then
            TriggerServerEvent('jrs_goldclaim:rocker:server:renameclaim', data.rockerid, input[1])
        end
    end)
end)

---------------------------------------------
-- pack up rocker
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:packuprocker', function(data)
    if IsBusy() then return end

    if DoTimedAction({
        duration = Config.PackUpTime,
        scenario = Config.Anims.crouch_inspect,
    }) then
        PlaySmoke(data.rockerid)
        TriggerServerEvent('jrs_goldclaim:rocker:server:destroyProp', data.rockerid)
    end
end)

---------------------------------------------
-- LEO destroy illegal claim
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:destroyillegal', function(propid)
    if type(propid) == 'table' then propid = propid.rockerid end -- from context menu
    if IsBusy() then return end

    if DoTimedAction({
        duration = Config.DestroyTime,
        scenario = Config.Anims.crouch_inspect,
    }) then
        PlaySmoke(propid)
        TriggerServerEvent('jrs_goldclaim:rocker:server:leodestroy', propid)
    end
end)

---------------------------------------------
-- place gold rocker (called by placeprop.lua)
---------------------------------------------
AddEventHandler('jrs_goldclaim:rocker:client:placeNewProp', function(pos, heading)
    if IsBusy() then return end

    if IsEntityInWater(PlayerPedId()) then
        return Notify(L('rocker_cant_place_here'), nil, 'error', 'circle-xmark')
    end

    local count = JRS.Await('jrs_goldclaim:server:countprops')
    if count >= Config.MaxGoldRockers then
        return Notify(L('rocker_max_equipment'), nil, 'error', 'circle-xmark')
    end

    if DoTimedAction({
        duration = Config.PlaceTime,
        scenario = Config.Anims.crouch_inspect,
    }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:newProp', pos, heading)
    end
end)

---------------------------------------------
-- shovel (dig paydirt in water)
---------------------------------------------
local function SpawnDigDirtPile(ped)
    local cfg = Config.DigDirtPile
    if not cfg or not cfg.enabled or not LoadModel(cfg.model) then return end
    local pos, fwd = GetEntityCoords(ped), GetEntityForwardVector(ped)
    local pile = CreateObject(cfg.model, pos.x + fwd.x * cfg.offset, pos.y + fwd.y * cfg.offset, pos.z - 1.0, false, false, false)
    SetModelAsNoLongerNeeded(cfg.model)
    SetTimeout(cfg.lifetime, function()
        if DoesEntityExist(pile) then DeleteObject(pile) end
    end)
end

RegisterNetEvent('jrs_goldclaim:rocker:client:useshovel', function()
    if IsBusy() then return end
    if not IsEntityInWater(PlayerPedId()) then
        return Notify(L('rocker_not_in_water'), nil, 'error', 'circle-xmark')
    end
    local dig = Config.Anims.dig
    if not LoadModel(Config.ShovelProp.model) or not LoadAnimDict(dig.dict) then return end

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    local coords = GetEntityCoords(ped)
    local shovel = CreateObject(Config.ShovelProp.model, coords.x, coords.y, coords.z, true, true, true)
    local o = Config.ShovelProp.offset
    AttachEntityToEntity(shovel, ped, GetEntityBoneIndexByName(ped, Config.ShovelProp.bone),
        o[1], o[2], o[3], o[4], o[5], o[6], true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(Config.ShovelProp.model)
    TaskPlayAnim(ped, dig.dict, dig.name, 3.0, 3.0, -1, 1, 0, false, false, false)

    local completed = DoTimedAction({
        duration = Config.ShovelDigTime,
        onCleanup = function()
            if DoesEntityExist(shovel) then
                DetachEntity(shovel, true, false)
                DeleteObject(shovel)
            end
            RemoveAnimDict(dig.dict)
        end,
    })

    if completed then
        SpawnDigDirtPile(ped)
        TriggerServerEvent('jrs_goldclaim:rocker:server:digpaydirt')
    end
end)

---------------------------------------------
-- bucket (fill with water)
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:client:usebucket', function()
    if IsBusy() then return end
    if not IsEntityInWater(PlayerPedId()) then
        return Notify(L('rocker_not_in_water'), nil, 'error', 'circle-xmark')
    end

    if DoTimedAction({
        duration = Config.BucketFillTime,
        scenario = Config.Anims.crouch_inspect,
    }) then
        TriggerServerEvent('jrs_goldclaim:rocker:server:fillbucket')
    end
end)

---------------------------------------------
-- cleanup
---------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for propid in pairs(SpawnedProps) do DespawnRocker(propid) end
    for propid in pairs(VegModifiers) do RemoveVegModifier(propid) end
    ClearOutputProps()
    for propid in pairs(ClaimZones) do RemoveClaimZone(propid) end
    LocalPlayer.state:set('inv_busy', false, true)
end)
