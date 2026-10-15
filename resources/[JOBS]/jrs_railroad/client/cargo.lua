---------------------------------------------------------------
-- DELIVERY CARGO (physical barrel props)
--
-- Ported from mack-oilcompany's proven wagon-loading workflow
-- (client/barrel.lua): barrels are NEVER targeted directly while
-- attached to the train -- the JRS interaction prompt/collision on props attached
-- to a moving train proved unreliable in testing. Instead:
--   1. Barrels spawn loose at Config.CargoDelivery.PlatformSpawnCoords
--      at job start.
--   2. Player targets a loose barrel to pick it up and carry it.
--   3. Player targets the TRAIN (flatbed) to load the carried
--      barrel aboard ("Load Barrel Onto Train").
--   4. At each leg's destination, player targets the TRAIN again
--      to take a barrel back into their hands ("Unload Cargo")
--      and carries it the rest of the way to the drop point.
--
-- Public functions (called from client/missions.lua and
-- client/train_spawn.lua): SpawnDeliveryCargo, SetCargoDestination,
-- CleanupDeliveryCargo. Everything else is internal but left
-- global for consistency with the rest of this resource's client
-- scripts.
---------------------------------------------------------------

local looseBarrels = {}   -- list of loose ground barrel entities awaiting pickup
local loadedBarrels = {}  -- list of barrel entities currently attached to the flatbed
local carryState = nil    -- { entity, mode = 'platform'|'delivery', dest, active }
local flatbedEntity = nil -- resolved flatbed carriage for the current mission
local trainTargetAdded = false
local currentDest = nil   -- current leg's destination, set via SetCargoDestination
local lastDeliverySpot = nil -- coords of the last completed drop-off; train must move away before the next "Unload Cargo"

---------------------------------------------------------------
-- SHARED CARRY HELPERS
---------------------------------------------------------------
local function AttachBarrelToPed(entity)
    local ped = PlayerPedId()
    SetEntityAsMissionEntity(entity, true, true)

    -- CP_BeltFront prop-attach point + fallback bone, ported verbatim from
    -- mack-oilcompany's AttachBarrelToPlayer (client/barrel.lua) since it's
    -- confirmed working in-game.
    local co = Config.CargoDelivery.CarryOffset
    local attachResult = Citizen.InvokeNative(0x6B9BBD38AB0796DF, entity, ped,
        Citizen.InvokeNative(0xFB71170B7E76ACBA, ped, "CP_BeltFront"),
        co.x, co.y, co.z, 0.0, 0.0, 0.0,
        false, false, false, false, 0, true)

    if not attachResult then
        AttachEntityToEntity(entity, ped, GetPedBoneIndex(ped, 0x60F0),
            co.x, co.y, co.z, 0.0, 0.0, 0.0,
            true, true, false, true, 1, true)
    end

    local animCfg = Config.CargoDelivery.CarryAnim
    RequestAnimDict(animCfg.dict)
    while not HasAnimDictLoaded(animCfg.dict) do Wait(10) end
    TaskPlayAnim(ped, animCfg.dict, animCfg.name, 8.0, -8.0, -1, 31, 0, false, false, false)

    SetPedMoveRateOverride(ped, Config.CargoDelivery.CarryMoveRate or 0.7)
end

local function ReleaseCarryAnim()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    SetPedMoveRateOverride(ped, -1.0)
    if Config.CargoDelivery and Config.CargoDelivery.CarryAnim then
        RemoveAnimDict(Config.CargoDelivery.CarryAnim.dict)
    end
end

---------------------------------------------------------------
-- RESOLVE THE FLATBED CARRIAGE ENTITY
-- RedM trains are multiple separately-linked entities (engine,
-- tender, coupled cars...). ActiveTrain only refers to ONE of
-- them, so attaching offsets to its root can land on the wrong
-- car (e.g. the coal/tender car instead of the flatbed).
--
-- GetTrainCarriageEngine/GetTrainCarriage natives aren't exposed
-- as callable globals on this build (confirmed by a runtime
-- error), and guessing raw native hashes risks a hard client
-- crash rather than a clean Lua error, so instead this scans the
-- loaded vehicle pool (a standard, always-available function) for
-- the closest privateflatcar01x to our train -- that's reliably
-- the flatbed coupled to it.
---------------------------------------------------------------
function ResolveFlatbedCarriage()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return nil end

    local flatbedHash = joaat(Config.CargoDelivery.FlatbedCarModel)
    local trainCoords = GetEntityCoords(ActiveTrain)

    local closest, closestDist
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and GetEntityModel(veh) == flatbedHash then
            local dist = GetDistanceBetween(trainCoords, GetEntityCoords(veh))
            if dist < 60.0 and (not closestDist or dist < closestDist) then
                closest = veh
                closestDist = dist
            end
        end
    end

    return closest -- nil if no matching flatbed found near this train
end

---------------------------------------------------------------
-- LOOSE PLATFORM BARREL TARGET (pickup)
---------------------------------------------------------------
local function AddLooseBarrelTarget(barrel)
    JRS.AddEntityTarget(barrel, {
        {
            name = 'railroad_cargo_platform_' .. barrel,
            label = L('menu_pickup_barrel'),
            icon = 'fas fa-box',
            distance = 2.5,
            canInteract = function()
                return not carryState and DoesEntityExist(barrel)
            end,
            onSelect = function()
                PickupLooseBarrel(barrel)
            end,
        },
    })
end

function PickupLooseBarrel(barrel)
    if carryState then return end
    if not DoesEntityExist(barrel) then return end

    JRS.RemoveEntityTarget(barrel, 'railroad_cargo_platform_' .. barrel)
    for idx, b in ipairs(looseBarrels) do
        if b == barrel then table.remove(looseBarrels, idx) break end
    end

    AttachBarrelToPed(barrel)
    carryState = { entity = barrel, mode = 'platform', active = true }
    Notify(L('cargo_picked_up'), 'inform', 6000)
end

---------------------------------------------------------------
-- TRAIN TARGET: LOAD BARREL ONTO TRAIN / UNLOAD CARGO
-- Mirrors mack-oilcompany's AddTargetModel on the wagon itself
-- rather than on individual barrel props.
---------------------------------------------------------------
local function AddTrainCargoTarget()
    if trainTargetAdded or not flatbedEntity or not DoesEntityExist(flatbedEntity) then return end
    trainTargetAdded = true

    JRS.AddEntityTarget(flatbedEntity, {
        {
            name = 'railroad_cargo_load',
            label = L('menu_load_barrel'),
            icon = 'fas fa-dolly',
            distance = 4.0,
            canInteract = function()
                return carryState ~= nil and carryState.mode == 'platform'
                    and #loadedBarrels < (Config.CargoDelivery.MaxSimultaneous or 3)
            end,
            onSelect = function()
                LoadBarrelOntoTrain()
            end,
        },
        {
            name = 'railroad_cargo_unload',
            label = L('menu_unload_cargo'),
            icon = 'fas fa-box-open',
            distance = 4.0,
            canInteract = function()
                if carryState then return false end
                if #loadedBarrels == 0 then return false end
                if Config.CargoDelivery.PickupRequiresStopped and ActiveTrain and DoesEntityExist(ActiveTrain) then
                    if GetEntitySpeed(ActiveTrain) > Config.CargoDelivery.MaxTrainSpeedToPickup then return false end
                end
                -- Only one barrel can be unloaded per drop-off: after a delivery, the
                -- train must physically move away from that spot before the next
                -- "Unload Cargo" becomes available again.
                if lastDeliverySpot and flatbedEntity and DoesEntityExist(flatbedEntity) then
                    local dist = GetDistanceBetween(GetEntityCoords(flatbedEntity), lastDeliverySpot)
                    if dist < (Config.CargoDelivery.MinMoveDistance or 15.0) then return false end
                end
                return true
            end,
            onSelect = function()
                UnloadBarrelFromTrain()
            end,
        },
    })
end

function LoadBarrelOntoTrain()
    if not carryState or carryState.mode ~= 'platform' then return end
    if not flatbedEntity or not DoesEntityExist(flatbedEntity) then return end
    if #loadedBarrels >= (Config.CargoDelivery.MaxSimultaneous or 3) then
        Notify(L('cargo_train_full'), 'error')
        return
    end

    local carried = carryState.entity
    ReleaseCarryAnim()
    if DoesEntityExist(carried) then DeleteEntity(carried) end
    carryState = nil

    local slot = #loadedBarrels + 1
    local offsets = Config.CargoDelivery.TrainAttachOffsets
    local offset = offsets[slot] or offsets[#offsets]
    local flatbedCoords = GetEntityCoords(flatbedEntity)

    local propHash = joaat(Config.CargoDelivery.PropModel)
    LoadModel(propHash)

    local barrel = CreateObject(propHash, flatbedCoords.x, flatbedCoords.y, flatbedCoords.z, true, true, false)
    SetEntityCollision(barrel, true, true)
    AttachEntityToEntity(barrel, flatbedEntity, 0,
        offset.x, offset.y, offset.z,
        0.0, 0.0, 0.0,
        true, true, false, true, 1, true)

    SetModelAsNoLongerNeeded(propHash)
    table.insert(loadedBarrels, barrel)

    Notify(L('cargo_loaded'), 'success', 6000)
end

function UnloadBarrelFromTrain()
    if carryState then return end
    local barrel = table.remove(loadedBarrels) -- take the last-loaded one
    if not barrel then return end

    if DoesEntityExist(barrel) then DetachEntity(barrel, true, false) end
    AttachBarrelToPed(barrel)

    carryState = { entity = barrel, mode = 'delivery', dest = currentDest, active = true }
    Notify(L('cargo_picked_up'), 'inform', 6000)

    local myCarry = carryState
    CreateThread(function()
        -- Ported from mack-oilcompany's carry thread (client/barrel.lua): while
        -- carrying, poll for the drop key each frame. E (0xCEFD9220) only
        -- completes the delivery while within DropRadius of the destination;
        -- a "[E] Drop Barrel" prompt is shown/hidden as the player enters/leaves
        -- that radius instead of auto-completing on proximity alone.
        local promptShown = false
        while carryState == myCarry and myCarry.active do
            local ped2 = PlayerPedId()

            if IsEntityDead(ped2) or not DoesEntityExist(myCarry.entity) then
                if promptShown then JRS.HideText() end
                FailCargoCarry()
                break
            end

            if IsPedInAnyVehicle(ped2, false) then
                if promptShown then JRS.HideText() end
                FailCargoCarry()
                break
            end

            local inDropRange = false
            if myCarry.dest then
                local pcoords = GetEntityCoords(ped2)
                local distToDest = GetDistanceBetween(pcoords, myCarry.dest.coords)
                inDropRange = distToDest < Config.CargoDelivery.DropRadius

                if not inDropRange and distToDest > Config.CargoDelivery.AbandonDistance then
                    if promptShown then JRS.HideText() end
                    FailCargoCarry()
                    break
                end
            end

            if inDropRange then
                if not promptShown then
                    JRS.ShowText(L('cargo_drop_prompt'))
                    promptShown = true
                end
                if IsControlJustPressed(0, 0xCEFD9220) then -- INPUT_CONTEXT (E)
                    JRS.HideText()
                    DeliverCargo(myCarry)
                    break
                end
            elseif promptShown then
                JRS.HideText()
                promptShown = false
            end

            Wait(inDropRange and 0 or 500)
        end
    end)
end

---------------------------------------------------------------
-- SET THE CURRENT LEG'S DESTINATION (called from client/missions.lua
-- at the start of each leg, so "Unload Cargo" knows where the
-- carried barrel needs to go).
---------------------------------------------------------------
function SetCargoDestination(dest)
    currentDest = dest
    if carryState and carryState.mode == 'delivery' then
        carryState.dest = dest
    end
end

---------------------------------------------------------------
-- SPAWN LOOSE BARRELS AT THE PLATFORM + SET UP TRAIN TARGET
---------------------------------------------------------------
function SpawnDeliveryCargo(count, station)
    CleanupDeliveryCargo() -- safety: clear any leftovers from a previous job

    if not Config.CargoDelivery or not Config.CargoDelivery.Enabled then return {} end
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return {} end
    if not count or count <= 0 then return {} end

    flatbedEntity = ResolveFlatbedCarriage()
    if not flatbedEntity then
        Notify(L('cargo_no_flatbed'), 'error', 8000)
        DebugPrint('[cargo] Could not resolve ' .. tostring(Config.CargoDelivery.FlatbedCarModel) .. ' on this train')
        return {}
    end

    local propHash = joaat(Config.CargoDelivery.PropModel)
    LoadModel(propHash)

    -- Per-station placeholder: default to the station's own coords (every
    -- station already has these), overridden per-station-id in
    -- Config.CargoDelivery.PlatformOverrides once you've checked/tuned an
    -- exact spot in-game.
    local overrides = Config.CargoDelivery.PlatformOverrides or {}
    local base = (station and overrides[station.id])
        or (station and station.coords and vector4(station.coords.x, station.coords.y, station.coords.z, 0.0))
        or Config.CargoDelivery.PlatformFallbackCoords
    local offsets = Config.CargoDelivery.PlatformBarrelOffsets

    for i = 1, count do
        local off = offsets[i] or offsets[#offsets]
        local barrel = CreateObject(propHash, base.x + off.x, base.y + off.y, base.z + off.z, true, true, false)
        SetEntityHeading(barrel, base.w or 0.0)
        SetEntityCollision(barrel, true, true)
        table.insert(looseBarrels, barrel)
        AddLooseBarrelTarget(barrel)
    end

    SetModelAsNoLongerNeeded(propHash)
    AddTrainCargoTarget()

    DebugPrint('Spawned ' .. count .. ' loose delivery barrel(s) at the platform')
    return looseBarrels
end

---------------------------------------------------------------
-- DELIVERED SUCCESSFULLY
---------------------------------------------------------------
function DeliverCargo(carry)
    if not carry or carry ~= carryState then return end

    JRS.HideText()
    ReleaseCarryAnim()
    if carry.entity and DoesEntityExist(carry.entity) then
        DeleteEntity(carry.entity)
    end

    if carry.dest then lastDeliverySpot = carry.dest.coords end
    carryState = nil
    Notify(L('cargo_delivered'), 'success', 6000)

    if CompleteDeliveryLeg then CompleteDeliveryLeg() end
end

---------------------------------------------------------------
-- CARRY FAILED / ABANDONED
---------------------------------------------------------------
function FailCargoCarry()
    if not carryState then return end

    JRS.HideText()
    ReleaseCarryAnim()
    if carryState.entity and DoesEntityExist(carryState.entity) then
        DeleteEntity(carryState.entity)
    end

    carryState.active = false
    carryState = nil

    Notify(L('cargo_abandoned'), 'error', 6000)

    if FailMission then FailMission() end
end

---------------------------------------------------------------
-- FULL CLEANUP (mission end, train despawn/park/recall)
---------------------------------------------------------------
function CleanupDeliveryCargo()
    if carryState then
        JRS.HideText()
        ReleaseCarryAnim()
        if carryState.entity and DoesEntityExist(carryState.entity) then
            DeleteEntity(carryState.entity)
        end
        carryState.active = false
        carryState = nil
    end

    for _, barrel in ipairs(looseBarrels) do
        if DoesEntityExist(barrel) then
            JRS.RemoveEntityTarget(barrel, 'railroad_cargo_platform_' .. barrel)
            DeleteEntity(barrel)
        end
    end
    looseBarrels = {}

    for _, barrel in ipairs(loadedBarrels) do
        if DoesEntityExist(barrel) then DeleteEntity(barrel) end
    end
    loadedBarrels = {}

    if trainTargetAdded and flatbedEntity and DoesEntityExist(flatbedEntity) then
        JRS.RemoveEntityTarget(flatbedEntity, 'railroad_cargo_load')
        JRS.RemoveEntityTarget(flatbedEntity, 'railroad_cargo_unload')
    end
    trainTargetAdded = false
    flatbedEntity = nil
    currentDest = nil
    lastDeliverySpot = nil
end
