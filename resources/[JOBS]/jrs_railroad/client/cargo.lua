-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: delivery cargo (barrels you carry by hand)
-- 1. barrels stand loose on the platform when the job starts, 2. the player picks one up and carries it,
-- 3. "load" on the flat car puts it on the train, 4. at a stop "unload" takes one off again and it is carried
-- to the drop point. The barrels on the train are never targeted directly: targets on props that ride a
-- moving train do not work reliably, so the flat car itself carries the options.
--
-- Used from missions.lua and train_spawn.lua: SpawnDeliveryCargo, SetCargoDestination, CleanupDeliveryCargo.

local loose = {}               -- barrels waiting on the platform
local onTrain = {}             -- barrels attached to the flat car
local carrying                 -- { entity, mode = 'platform' | 'delivery', dest, active }
local flatcar                  -- the flat car of the current job
local flatcarTargeted = false
local destination              -- where the carried barrel has to go
local lastDrop                 -- where the last barrel was delivered: the train has to move on before the next unload

local DROP_KEY <const> = 0xCEFD9220                    -- E
local cfg = function() return Config.CargoDelivery end

-- ------------------------------------------------------------------ carrying

local function holdBarrel(entity)
    local ped = PlayerPedId()
    SetEntityAsMissionEntity(entity, true, true)

    -- the belt attach point is tried first; if it fails the barrel goes on the hip bone
    local at = cfg().CarryOffset
    local attached = Citizen.InvokeNative(0x6B9BBD38AB0796DF, entity, ped, Citizen.InvokeNative(0xFB71170B7E76ACBA, ped, 'CP_BeltFront'),
        at.x, at.y, at.z, 0.0, 0.0, 0.0, false, false, false, false, 0, true)
    if not attached then
        AttachEntityToEntity(entity, ped, GetPedBoneIndex(ped, 0x60F0), at.x, at.y, at.z, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end

    local anim = cfg().CarryAnim
    RequestAnimDict(anim.dict)
    while not HasAnimDictLoaded(anim.dict) do Wait(10) end
    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 31, 0, false, false, false)
    SetPedMoveRateOverride(ped, cfg().CarryMoveRate or 0.7)
end

local function putDown()
    ClearPedTasks(PlayerPedId())
    SetPedMoveRateOverride(PlayerPedId(), -1.0)
    if cfg() and cfg().CarryAnim then RemoveAnimDict(cfg().CarryAnim.dict) end
end

local function dropCarried()
    if not carrying then return end
    JRS.HideText()
    putDown()
    if carrying.entity and DoesEntityExist(carrying.entity) then DeleteEntity(carrying.entity) end
    carrying.active = false
    carrying = nil
end

-- ------------------------------------------------------------------ finding the flat car

-- A train is several linked entities and ActiveTrain is only one of them. The carriage natives are not
-- available here, so the loaded vehicles are searched for the flat car model nearest to the train.
function ResolveFlatbedCarriage()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return nil end

    local model, trainAt = joaat(cfg().FlatbedCarModel), GetEntityCoords(ActiveTrain)
    local best, bestAway
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and GetEntityModel(vehicle) == model then
            local away = GetDistanceBetween(trainAt, GetEntityCoords(vehicle))
            if away < 60.0 and (not bestAway or away < bestAway) then best, bestAway = vehicle, away end
        end
    end
    return best
end

-- ------------------------------------------------------------------ loose barrels

function PickupLooseBarrel(barrel)
    if carrying or not DoesEntityExist(barrel) then return end

    JRS.RemoveEntityTarget(barrel, 'railroad_cargo_platform_' .. barrel)
    for i, b in ipairs(loose) do
        if b == barrel then table.remove(loose, i) break end
    end

    holdBarrel(barrel)
    carrying = { entity = barrel, mode = 'platform', active = true }
    Notify(L('cargo_picked_up'), 'inform', 6000)
end

local function targetLoose(barrel)
    JRS.AddEntityTarget(barrel, { {
        name = 'railroad_cargo_platform_' .. barrel, label = L('menu_pickup_barrel'), icon = 'fas fa-box', distance = 2.5,
        canInteract = function() return not carrying and DoesEntityExist(barrel) end,
        onSelect = function() PickupLooseBarrel(barrel) end,
    } })
end

-- ------------------------------------------------------------------ loading and unloading at the flat car

local function maxLoad() return cfg().MaxSimultaneous or 3 end

function LoadBarrelOntoTrain()
    if not carrying or carrying.mode ~= 'platform' then return end
    if not flatcar or not DoesEntityExist(flatcar) then return end
    if #onTrain >= maxLoad() then return Notify(L('cargo_train_full'), 'error') end

    dropCarried()

    local slots = cfg().TrainAttachOffsets
    local slot = slots[#onTrain + 1] or slots[#slots]
    local at = GetEntityCoords(flatcar)

    local model = joaat(cfg().PropModel)
    LoadModel(model)
    local barrel = CreateObject(model, at.x, at.y, at.z, true, true, false)
    SetEntityCollision(barrel, true, true)
    AttachEntityToEntity(barrel, flatcar, 0, slot.x, slot.y, slot.z, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)

    onTrain[#onTrain + 1] = barrel
    Notify(L('cargo_loaded'), 'success', 6000)
end

-- the barrel arrived: it is gone, the leg of the mission is done
function DeliverCargo(carry)
    if not carry or carry ~= carrying then return end

    JRS.HideText()
    putDown()
    if carry.entity and DoesEntityExist(carry.entity) then DeleteEntity(carry.entity) end
    if carry.dest then lastDrop = carry.dest.coords end
    carrying = nil
    Notify(L('cargo_delivered'), 'success', 6000)
    if CompleteDeliveryLeg then CompleteDeliveryLeg() end
end

-- the carry went wrong (died, got on a horse, walked off): the barrel and the job are lost
function FailCargoCarry()
    if not carrying then return end
    dropCarried()
    Notify(L('cargo_abandoned'), 'error', 6000)
    if FailMission then FailMission() end
end

-- while a barrel is carried: E drops it at the destination, anything wrong fails the job
local function watchCarry(carry)
    local shown = false
    local function hint(on)
        if on and not shown then JRS.ShowText(L('cargo_drop_prompt')) elseif not on and shown then JRS.HideText() end
        shown = on
    end

    while carrying == carry and carry.active do
        local ped = PlayerPedId()
        if IsEntityDead(ped) or not DoesEntityExist(carry.entity) or IsPedInAnyVehicle(ped, false) then
            hint(false)
            return FailCargoCarry()
        end

        local inRange = false
        if carry.dest then
            local away = GetDistanceBetween(GetEntityCoords(ped), carry.dest.coords)
            inRange = away < cfg().DropRadius
            if not inRange and away > cfg().AbandonDistance then
                hint(false)
                return FailCargoCarry()
            end
        end

        hint(inRange)
        if inRange and IsControlJustPressed(0, DROP_KEY) then
            hint(false)
            return DeliverCargo(carry)
        end
        Wait(inRange and 0 or 500)
    end
end

function UnloadBarrelFromTrain()
    if carrying then return end
    local barrel = table.remove(onTrain)                   -- the last one loaded
    if not barrel then return end

    if DoesEntityExist(barrel) then DetachEntity(barrel, true, false) end
    holdBarrel(barrel)

    carrying = { entity = barrel, mode = 'delivery', dest = destination, active = true }
    Notify(L('cargo_picked_up'), 'inform', 6000)

    local mine = carrying
    CreateThread(function() watchCarry(mine) end)
end

local function canUnload()
    if carrying or #onTrain == 0 then return false end
    if cfg().PickupRequiresStopped and ActiveTrain and DoesEntityExist(ActiveTrain) and GetEntitySpeed(ActiveTrain) > cfg().MaxTrainSpeedToPickup then
        return false
    end
    -- one barrel per stop: after a delivery the train has to move away first
    if lastDrop and flatcar and DoesEntityExist(flatcar) and GetDistanceBetween(GetEntityCoords(flatcar), lastDrop) < (cfg().MinMoveDistance or 15.0) then
        return false
    end
    return true
end

local function targetFlatcar()
    if flatcarTargeted or not flatcar or not DoesEntityExist(flatcar) then return end
    flatcarTargeted = true

    JRS.AddEntityTarget(flatcar, {
        {
            name = 'railroad_cargo_load', label = L('menu_load_barrel'), icon = 'fas fa-dolly', distance = 4.0,
            canInteract = function() return carrying ~= nil and carrying.mode == 'platform' and #onTrain < maxLoad() end,
            onSelect = LoadBarrelOntoTrain,
        },
        { name = 'railroad_cargo_unload', label = L('menu_unload_cargo'), icon = 'fas fa-box-open', distance = 4.0, canInteract = canUnload, onSelect = UnloadBarrelFromTrain },
    })
end

-- ------------------------------------------------------------------ the job

-- where the carried barrel has to go (called at the start of every leg)
function SetCargoDestination(dest)
    destination = dest
    if carrying and carrying.mode == 'delivery' then carrying.dest = dest end
end

-- puts `count` barrels on the platform of `station` and prepares the flat car
function SpawnDeliveryCargo(count, station)
    CleanupDeliveryCargo()

    if not cfg() or not cfg().Enabled or not ActiveTrain or not DoesEntityExist(ActiveTrain) or not count or count <= 0 then return {} end

    flatcar = ResolveFlatbedCarriage()
    if not flatcar then
        Notify(L('cargo_no_flatbed'), 'error', 8000)
        DebugPrint('[cargo] Could not resolve ' .. tostring(cfg().FlatbedCarModel) .. ' on this train')
        return {}
    end

    local model = joaat(cfg().PropModel)
    LoadModel(model)

    -- the spot of the platform: a tuned one per station, else the station itself
    local overrides = cfg().PlatformOverrides or {}
    local base = (station and overrides[station.id])
        or (station and station.coords and vector4(station.coords.x, station.coords.y, station.coords.z, 0.0))
        or cfg().PlatformFallbackCoords
    local spots = cfg().PlatformBarrelOffsets

    for i = 1, count do
        local o = spots[i] or spots[#spots]
        local barrel = CreateObject(model, base.x + o.x, base.y + o.y, base.z + o.z, true, true, false)
        SetEntityHeading(barrel, base.w or 0.0)
        SetEntityCollision(barrel, true, true)
        loose[#loose + 1] = barrel
        targetLoose(barrel)
    end

    SetModelAsNoLongerNeeded(model)
    targetFlatcar()
    DebugPrint('Spawned ' .. count .. ' loose delivery barrel(s) at the platform')
    return loose
end

-- the job ends or the train goes away: remove everything
function CleanupDeliveryCargo()
    dropCarried()

    for _, barrel in ipairs(loose) do
        if DoesEntityExist(barrel) then
            JRS.RemoveEntityTarget(barrel, 'railroad_cargo_platform_' .. barrel)
            DeleteEntity(barrel)
        end
    end
    for _, barrel in ipairs(onTrain) do
        if DoesEntityExist(barrel) then DeleteEntity(barrel) end
    end
    loose, onTrain = {}, {}

    if flatcarTargeted and flatcar and DoesEntityExist(flatcar) then
        JRS.RemoveEntityTarget(flatcar, 'railroad_cargo_load')
        JRS.RemoveEntityTarget(flatcar, 'railroad_cargo_unload')
    end
    flatcarTargeted, flatcar, destination, lastDrop = false, nil, nil, nil
end
