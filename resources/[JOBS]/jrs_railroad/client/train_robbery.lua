-- ============================================================
--  jrs_railroad  |  train_robbery.lua
--  Self-contained train robbery system.
--  Handles both player-driven trains (mission-linked) and
--  ambient route trains (visual atmosphere).
-- ============================================================

-- ── Robbery state ────────────────────────────────────
local Robbery = {
    active    = false,
    outlaws   = {},
    horses    = {},
    companyId = nil,
}

local EnginePressure     = 100   -- 0-100, decays while outlaws alive
local PressureRecovering = false -- true while recovering post-robbery
local AmbientRobberyActive = false

-- ── Pressure HUD helpers ───────────────────────────────
local function ShowPressureHUD(pressure)
    SendNUIMessage({
        action   = 'showPressureHUD',
        pressure = pressure or 100,
        status   = L('robbery_pressure_attacking'),
    })
end

local function UpdatePressureHUD(pressure, status)
    SendNUIMessage({
        action   = 'updatePressureHUD',
        pressure = pressure,
        status   = status or '',
    })
end

local function HidePressureHUD()
    SendNUIMessage({ action = 'hidePressureHUD' })
end

-- ── Hostile relationship group (mirrors mack-outlaws approach) ────
-- NPCs won't attack the player without this.
local ROBBERY_GROUP = nil
CreateThread(function()
    Wait(600)
    AddRelationshipGroup('MACK_TRAIN_ROBBERS')
    ROBBERY_GROUP = GetHashKey('MACK_TRAIN_ROBBERS')
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(4, ROBBERY_GROUP, playerGroup)  -- 4 = HATE (hostile)
    SetRelationshipBetweenGroups(4, playerGroup,   ROBBERY_GROUP)
end)

-- ── Model loader with 5-second timeout (prevents infinite hang) ──
local function LoadModelSafe(modelHash)
    RequestModel(modelHash)
    local t = 0
    while not HasModelLoaded(modelHash) and t < 50 do
        Wait(100)
        t = t + 1
    end
    return HasModelLoaded(modelHash)
end

-- ── Spawn horse (mack-outlaws pattern) ─────────────────────
local function SpawnRobberyHorse(modelHash, coords)
    if not LoadModelSafe(modelHash) then
        DebugPrint('[TrainRobbery] WARN: Horse model failed: ' .. tostring(modelHash))
        return nil
    end
    local horse = CreatePed(modelHash, coords.x, coords.y, coords.z, math.random(0,359)+0.0, true, true, true, true)
    if not DoesEntityExist(horse) then return nil end
    Citizen.InvokeNative(0x283978A15512B2FE, horse, true)  -- network flag
    SetEntityAsMissionEntity(horse, true, true)
    SetEntityCanBeDamaged(horse, true)
    return horse
end

-- ── Spawn armed outlaw NPC (mack-outlaws pattern) ───────────
local function SpawnRobberyNPC(modelHash, coords, weaponHash, accuracy)
    if not LoadModelSafe(modelHash) then
        DebugPrint('[TrainRobbery] WARN: Outlaw model failed: ' .. tostring(modelHash))
        return nil
    end
    local npc = CreatePed(modelHash, coords.x, coords.y, coords.z, math.random(0,359)+0.0, true, true, true, true)
    if not DoesEntityExist(npc) then return nil end

    Citizen.InvokeNative(0x283978A15512B2FE, npc, true)  -- network flag
    SetEntityAsMissionEntity(npc, true, true)
    SetRandomOutfitVariation(npc, true)

    if ROBBERY_GROUP then
        SetPedRelationshipGroupHash(npc, ROBBERY_GROUP)
    end

    SetPedAccuracy(npc, accuracy)
    SetPedFleeAttributes(npc, 0, false)
    SetPedCombatAttributes(npc, 2,  true)   -- horseback drive-by shooting
    SetPedCombatAttributes(npc, 46, true)   -- fight to the death
    SetPedCombatRange(npc, 2)               -- far combat range
    SetPedSeeingRange(npc, 500.0)           -- spot player from 500m
    SetPedHearingRange(npc, 500.0)

    GiveWeaponToPed(npc, weaponHash, 50, true, true, 1, false, 0.5, 1.0, 1.0, true, 0, 0)
    SetCurrentPedWeapon(npc, weaponHash, true)
    return npc
end

-- ── Robbery-specific notification ───────────────────────
local function RobberyNotify(msg, nType, duration)
    JRS.NotifyT({
        title       = L('robbery_title'),
        description = msg,
        type        = nType   or 'error',
        duration    = duration or 7000,
        position    = 'top-right',
    })
end

-- ── Delete all robbery entities and clear state ──────────
local function CleanupRobbery()
    for _, e in ipairs(Robbery.outlaws) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    for _, e in ipairs(Robbery.horses) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    Robbery = { active = false, outlaws = {}, horses = {}, companyId = nil }
    DebugPrint('[TrainRobbery] Cleaned up')
end

-- ── Spawn one outlaw mounted on horseback ──────────────────
-- Uses the same pattern as mack-outlaws SpawnNPC / SpawnHorse.
-- Returns (outlaw, horse) or (nil, nil) on failure.
local function SpawnOutlawOnHorse(spawnCoords)
    local cfg        = Config.TrainRobbery
    local outlawName = cfg.OutlawModels [math.random(#cfg.OutlawModels )]
    local horseName  = cfg.HorseModels  [math.random(#cfg.HorseModels  )]
    local weaponHash = joaat(cfg.OutlawWeapons[math.random(#cfg.OutlawWeapons)])

    DebugPrint('[TrainRobbery] Spawning outlaw=' .. outlawName .. ' horse=' .. horseName)

    local horse = SpawnRobberyHorse(joaat(horseName), spawnCoords)
    if not horse then return nil, nil end

    local outlaw = SpawnRobberyNPC(joaat(outlawName), spawnCoords, weaponHash, cfg.OutlawAccuracy)
    if not outlaw then
        DeleteEntity(horse)
        return nil, nil
    end

    -- Mount (mack-outlaws native)
    Citizen.InvokeNative(0x028F76B6E78246EB, outlaw, horse, -1)

    -- After brief mount settle, follow the train entity directly (off-road, no pathfinding).
    -- Uses same TaskFollowToOffsetOfEntity pattern as mack-herding for animals.
    -- Shooting is disabled until aggressive phase.
    local outlawRef = outlaw
    CreateThread(function()
        Wait(1500)  -- allow mount animation to settle
        if DoesEntityExist(outlawRef) and not IsEntityDead(outlawRef) then
            SetBlockingOfNonTemporaryEvents(outlawRef, true)
            SetPedFleeAttributes(outlawRef, 0, true)
            SetPedAccuracy(outlawRef, Config.TrainRobbery.OutlawAccuracy)
            SetPedCombatAttributes(outlawRef, 2,  true)  -- horseback drive-by shooting
            SetPedCombatAttributes(outlawRef, 5,  true)  -- always fight
            SetPedCombatAttributes(outlawRef, 46, true)  -- fight to death
            -- Attack the player; RDR2 combat AI handles chase + horseback shooting
            TaskCombatPed(outlawRef, PlayerPedId(), 0, 16)
        end
    end)

    DebugPrint('[TrainRobbery] Outlaw+horse spawned OK')
    return outlaw, horse
end

-- ── Keep outlaws in combat with the player ────────────────────────
-- RDR2 combat AI handles chase + horseback shooting automatically.
-- We just re-issue TaskCombatPed if they ever drop out of combat.
local function StartFollowThreads()
    for _, outlaw in ipairs(Robbery.outlaws) do
        CreateThread(function()
            while Robbery.active and DoesEntityExist(outlaw) and not IsEntityDead(outlaw) do
                Wait(3000)
                if DoesEntityExist(outlaw) and not IsEntityDead(outlaw) then
                    if not IsPedInCombat(outlaw, PlayerPedId()) then
                        TaskCombatPed(outlaw, PlayerPedId(), 0, 16)
                    end
                end
            end
        end)
    end
end

-- ── Check if any outlaw is within radius of the train ────────
local function HasOutlawNearby(radius)
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return false end
    local tc = GetEntityCoords(ActiveTrain)
    for _, o in ipairs(Robbery.outlaws) do
        if DoesEntityExist(o) and not IsEntityDead(o) then
            if GetDistanceBetween(GetEntityCoords(o), tc) < radius then
                return true
            end
        end
    end
    return false
end

-- ── Player repairs engine pressure via the JRS interaction prompt ────────────
function FixEnginePressure()
    if not (Robbery.active or PressureRecovering) then return end
    local cfg = Config.TrainRobbery
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, joaat('WORLD_HUMAN_CROUCH_INSPECT'), 0, true, false, false, false)
    if JRS.ProgressBar({
        duration     = cfg.PressureRepairTime or 8000,
        label        = L('progress_repairing_engine_pressure'),
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, combat = true },
    }) then
        local gain = cfg.PressureRepairAmount or 30
        EnginePressure = math.min(100, EnginePressure + gain)
        local s = PressureRecovering and L('robbery_pressure_recovering') or L('robbery_pressure_attacking')
        UpdatePressureHUD(EnginePressure, s)
        Notify(L('engine_repaired_pressure', math.floor(EnginePressure)), 'success', 5000)
    end
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
end

-- ── Global: used by SetupTrainTarget canInteract ─────────────
function IsTrainUnderAttackOrRecovering()
    return Robbery.active or PressureRecovering
end

-- ── Global: checked by GetMaxTrainSpeed in train_control.lua ────
function IsRobberySpeedCapActive()
    return Robbery.active
end

-- ── Pressure recovery (runs after robbery resolves) ───────────
local function StartPressureRecovery()
    if PressureRecovering then return end
    PressureRecovering = true
    DebugPrint('[TrainRobbery] Pressure recovery started')
    local cfg = Config.TrainRobbery
    CreateThread(function()
        while EnginePressure < 100 do
            Wait(cfg.PressureRecoveryInterval)
            EnginePressure = math.min(100, EnginePressure + cfg.PressureRecoveryAmount)
            SendNUIMessage({
                action   = 'updatePressureHUD',
                pressure = EnginePressure,
                status   = L('robbery_pressure_recovering'),
                recovering = true,  -- tells JS to show recovery (amber) colour
            })
        end
        PressureRecovering = false
        HidePressureHUD()
        -- Engine can now be started again
        Notify(L('engine_pressure_restored'), 'success', 7000)
        DebugPrint('[TrainRobbery] Pressure fully recovered')
    end)
end

-- ── Global: can the engine start? Checked in ToggleEngine (train_control.lua) ──
function IsEnginePressureDamaged()
    return PressureRecovering
end

-- ── Board the train (detach from horse, attach to carriage) ─
-- sideOffset: positive = right side, negative = left side
local function BoardTrain(outlaw, horse, sideOffset)
    CreateThread(function()
        if not DoesEntityExist(outlaw) then return end

        -- Dismount
        ClearPedTasksImmediately(outlaw)
        Wait(500)

        if not DoesEntityExist(outlaw) then return end
        if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return end

        -- Place outlaw on the side of the locomotive
        local tc = GetEntityCoords(ActiveTrain)
        SetEntityCoords(outlaw, tc.x + sideOffset, tc.y, tc.z + 0.5, false, false, false, false)

        -- Attach to train so they ride with it
        AttachEntityToEntity(
            outlaw, ActiveTrain, 0,
            sideOffset, 0.0, 0.5,
            0.0, 0.0, 0.0,
            false, false, false, false, 2, true
        )

        -- Remove horse (no longer needed)
        if DoesEntityExist(horse) then DeleteEntity(horse) end

        Wait(300)

        -- Attack the driver
        if DoesEntityExist(outlaw) and ActiveTrain and DoesEntityExist(ActiveTrain) then
            SetBlockingOfNonTemporaryEvents(outlaw, true)
            TaskCombatPed(outlaw, PlayerPedId(), 0, 16)
        end

        DebugPrint('[TrainRobbery] Outlaw boarded the train (sideOffset=' .. sideOffset .. ')')
    end)
end

-- ── Watch mounted outlaw, board when close enough ────────
local function StartBoardingWatch(outlaw, horse, sideOffset)
    CreateThread(function()
        -- Give outlaws a few seconds to get alongside before checking boarding
        Wait(5000)
        while Robbery.active and DoesEntityExist(outlaw) and not IsEntityDead(outlaw) do
            Wait(500)
            if not ActiveTrain or not DoesEntityExist(ActiveTrain) then break end

            local dist = GetDistanceBetween(GetEntityCoords(outlaw), GetEntityCoords(ActiveTrain))
            if Config.TrainRobbery.BoardTrain and dist < Config.TrainRobbery.BoardDistance then
                -- Still mounted? Board the train
                local veh = GetVehiclePedIsIn(outlaw, false)
                if veh ~= 0 then
                    BoardTrain(outlaw, horse, sideOffset)
                    break
                end
            end
            -- Movement is handled by TaskFollowToOffsetOfEntity -- no fallback needed here
        end
    end)
end

-- ── Count outlaws still alive ────────────────────────────
local function CountAliveOutlaws()
    local n = 0
    for _, o in ipairs(Robbery.outlaws) do
        if DoesEntityExist(o) and not IsEntityDead(o) then n = n + 1 end
    end
    return n
end

-- ── Make all outlaws ride off after a peaceful robbery ────
local function OutlawsEscape()
    local pcoords = GetEntityCoords(PlayerPedId())
    local escX = pcoords.x + math.random(-600, 600)
    local escY = pcoords.y + math.random(-600, 600)
    local escZ = pcoords.z

    for _, o in ipairs(Robbery.outlaws) do
        if DoesEntityExist(o) and not IsEntityDead(o) then
            SetBlockingOfNonTemporaryEvents(o, false)
            SetPedFleeAttributes(o, 0, false)
            TaskGoToCoordAnyMeans(o, escX, escY, escZ, 5.0, 0, false, 786603, 0xbf800000)
        end
    end

    -- Despawn after escape time
    SetTimeout(Config.TrainRobbery.EscapeTimeMs, function()
        CleanupRobbery()
    end)
end

-- ── Tell the server to deduct from the cash register ─────
local function ExecuteRobbery()
    if not Robbery.companyId then return end
    TriggerServerEvent('jrs_railroad:robberyOccurred', Robbery.companyId)
    DebugPrint('[TrainRobbery] Robbery event fired for: ' .. tostring(Robbery.companyId))
end

-- ── Pressure-based robbery monitor ────────────────────────
-- Every tick: decay pressure by (aliveOutlaws x decay), update HUD.
-- Outcomes: all outlaws dead (win), driver dead (robbed), pressure≤0 (forced stop+robbed).
local function StartPressureMonitor()
    local cfg = Config.TrainRobbery
    CreateThread(function()
        while Robbery.active do
            Wait(cfg.PressureDecayInterval)

            if not ActiveTrain or not DoesEntityExist(ActiveTrain) then
                CleanupRobbery()
                HidePressureHUD()
                break
            end

            local aliveCount = CountAliveOutlaws()

            -- ── ALL OUTLAWS DEAD → driver wins ───────────────────
            if aliveCount == 0 then
                Robbery.active = false
                RobberyNotify(L('robbery_outlaws_defeated'), 'success', 9000)
                TriggerServerEvent('jrs_railroad:robberyDefeated', Robbery.companyId)
                CleanupRobbery()
                StartPressureRecovery()
                break
            end

            -- ── MANUAL STOP + OUTLAW CLOSE → peaceful robbery ───────
            local trainSpeed = GetEntitySpeed(ActiveTrain)
            if trainSpeed < cfg.TrainStopSpeed and HasOutlawNearby(cfg.ManualStopRobRadius) then
                Robbery.active = false
                Wait(cfg.PressureRecoveryInterval or 2000)
                RobberyNotify(L('robbery_stopped_train'), 'inform', 9000)
                ExecuteRobbery()
                OutlawsEscape()
                StartPressureRecovery()
                break
            end

            -- ── DRIVER DEAD → only robbed if outlaw is close ──────
            if IsEntityDead(PlayerPedId()) then
                Robbery.active = false
                Wait(3000)
                if HasOutlawNearby(cfg.ManualStopRobRadius) then
                    RobberyNotify(L('robbery_driver_killed'), 'error', 9000)
                    ExecuteRobbery()
                else
                    RobberyNotify(L('robbery_killed_too_far'), 'error', 7000)
                end
                OutlawsEscape()
                StartPressureRecovery()
                break
            end

            -- ── DECAY PRESSURE (proximity-based) ──────────────────
            -- Only outlaws within PressureAttackRadius actually drain pressure.
            local tc = GetEntityCoords(ActiveTrain)
            local nearbyCount = 0
            for _, o in ipairs(Robbery.outlaws) do
                if DoesEntityExist(o) and not IsEntityDead(o) then
                    if GetDistanceBetween(GetEntityCoords(o), tc) < cfg.PressureAttackRadius then
                        nearbyCount = nearbyCount + 1
                    end
                end
            end
            local decay = nearbyCount * cfg.PressureDecayPerOutlaw
            EnginePressure = math.max(0, EnginePressure - decay)

            local status = (EnginePressure <= 30)
                and L('robbery_pressure_critical')
                or  L('robbery_pressure_attacking')
            UpdatePressureHUD(EnginePressure, status)

            -- ── PRESSURE ZERO → forced stop ──────────────────────
            if EnginePressure <= 0 then
                Robbery.active = false
                EngineRunning = false
                SetTrainCruiseSpeed(ActiveTrain, 0.0)
                SetTrainSpeed(ActiveTrain, 0.0)
                Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, 0.0)
                Wait(2000)
                RobberyNotify(L('robbery_pressure_zero'), 'error', 10000)
                -- Only rob if an outlaw is close enough to board/take the cash
                if HasOutlawNearby(cfg.ManualStopRobRadius) then
                    ExecuteRobbery()
                end
                OutlawsEscape()
                StartPressureRecovery()
                break
            end
        end
    end)
end

-- ════════════════════════════════════════════════════════
--  PUBLIC API  –  called from missions.lua
-- ════════════════════════════════════════════════════════
function TriggerTrainRobbery(force)
    local cfg = Config.TrainRobbery
    if not cfg.Enabled                                       then return end
    if Robbery.active or PressureRecovering                  then return end
    if not ActiveTrain or not DoesEntityExist(ActiveTrain)  then return end

    if not force and math.random(100) > cfg.PlayerChance then
        DebugPrint('[TrainRobbery] Chance roll failed')
        return
    end

    local companyId   = ActiveTrainConfig and ActiveTrainConfig.company or nil
    local trainCoords = GetEntityCoords(ActiveTrain)
    local trainFwd    = GetEntityForwardVector(ActiveTrain)
    local count       = math.random(cfg.OutlawCount.min, cfg.OutlawCount.max)

    Robbery.active    = true
    Robbery.companyId = companyId
    EnginePressure    = 100

    DebugPrint('[TrainRobbery] Starting pressure robbery — company: ' .. tostring(companyId) .. ', outlaws: ' .. count)

    CreateThread(function()
        local trainSpeed      = GetEntitySpeed(ActiveTrain)
        local notifyDelaySec  = cfg.InitialMessageDelay / 1000
        local dynamicDistance = trainSpeed * notifyDelaySec * (cfg.SpawnMultiplier or 3.0)
        local spawnAhead      = math.max(cfg.SpawnAheadDistance, dynamicDistance + 50)

        -- Spawn outlaws ALONGSIDE the train (30-60m to the side, staggered behind)
        -- so they are immediately within visual range and combat AI engages instantly.
        local perpX =  trainFwd.y   -- perpendicular to train direction
        local perpY = -trainFwd.x

        for i = 1, count do
            local sideSign  = (i % 2 == 0) and 1.0 or -1.0
            local sideDist  = math.random(30, 60)          -- 30-60m to the side
            local behindDist = i * 15.0                    -- stagger 15m further behind per outlaw
            local sx = trainCoords.x + (perpX * sideSign * sideDist) - (trainFwd.x * behindDist)
            local sy = trainCoords.y + (perpY * sideSign * sideDist) - (trainFwd.y * behindDist)
            local sz = trainCoords.z  -- use train Z; safe cross-country
            local outlaw, horse = SpawnOutlawOnHorse(vector3(sx, sy, sz))
            if outlaw and horse then
                table.insert(Robbery.outlaws, outlaw)
                table.insert(Robbery.horses,  horse)
            end
            Wait(300)
        end

        if #Robbery.outlaws == 0 then
            DebugPrint('[TrainRobbery] No outlaws spawned — check models in Config.TrainRobbery')
            CleanupRobbery()
            return
        end

        -- Smoothly decelerate the train to RobberySlowSpeed.
        -- GetMaxTrainSpeed() already enforces the cap via the engine loop,
        -- but we also need to actively reduce current speed if it's too high.
        if ActiveTrain and DoesEntityExist(ActiveTrain) and EngineRunning then
            local slowSpeed = cfg.RobberySlowSpeed or 8
            local currentVel = GetEntitySpeed(ActiveTrain)
            if currentVel > slowSpeed then
                -- Gradual decel to slowSpeed
                CreateThread(function()
                    while Robbery.active and ActiveTrain and DoesEntityExist(ActiveTrain) do
                        local vel = GetEntitySpeed(ActiveTrain)
                        if vel <= slowSpeed + 0.5 then
                            SetTrainSpeed(ActiveTrain, slowSpeed)
                            SetTrainCruiseSpeed(ActiveTrain, slowSpeed)
                            break
                        end
                        local newVel = math.max(slowSpeed, vel * 0.88)
                        SetTrainSpeed(ActiveTrain, newVel)
                        Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, newVel + 0.1)
                        Wait(200)
                    end
                end)
                DebugPrint('[TrainRobbery] Decelerating train to ' .. slowSpeed .. ' m/s')
            else
                -- Already slow, just set cruise cap
                SetTrainCruiseSpeed(ActiveTrain, slowSpeed)
                DebugPrint('[TrainRobbery] Train already at/below ' .. slowSpeed .. ' m/s')
            end
        end

        -- Show pressure HUD then notify
        ShowPressureHUD(100)
        Wait(cfg.InitialMessageDelay)
        RobberyNotify(L('robbery_approaching'), 'error', 8000)

        -- Start follow + shoot threads, then pressure monitor
        StartFollowThreads()
        -- Also start boarding watches for close-range action
        for i, o in ipairs(Robbery.outlaws) do
            local h    = Robbery.horses[i]
            local side = (i % 2 == 0) and cfg.BoardSideOffset or -cfg.BoardSideOffset
            if h and DoesEntityExist(h) then
                StartBoardingWatch(o, h, side)
            end
        end
        StartPressureMonitor()
    end)
end

-- ════════════════════════════════════════════════════════
--  AMBIENT TRAIN ROBBERY
--  NPCs chase the route train for atmosphere
-- ════════════════════════════════════════════════════════
local function TriggerAmbientRobbery(trainEntity)
    if AmbientRobberyActive then return end
    if Robbery.active then return end  -- don't spawn ambient outlaws during a player robbery
    local cfg = Config.TrainRobbery

    -- Chance roll
    if math.random(100) > cfg.AmbientChance then return end

    AmbientRobberyActive = true
    DebugPrint('[TrainRobbery] Ambient robbery triggered')

    local trainCoords = GetEntityCoords(trainEntity)
    local count       = math.random(cfg.OutlawCount.min, cfg.OutlawCount.max)
    local aOutlaws    = {}
    local aHorses     = {}

    CreateThread(function()
        -- Spawn alongside the ambient train
        for i = 1, count do
            local side = (i % 2 == 0) and 22.0 or -22.0
            local sp   = vector3(trainCoords.x + side, trainCoords.y + (i * 18), trainCoords.z)
            local ok, gz = GetGroundZFor_3dCoord(sp.x, sp.y, sp.z + 50.0, false)
            if ok then sp = vector3(sp.x, sp.y, gz) end

            local o, h = SpawnOutlawOnHorse(sp)
            if o and h then
                table.insert(aOutlaws, o)
                table.insert(aHorses,  h)
            end
            Wait(400)
        end

        -- Chase + harass the train for AmbientFollowMs
        local startTime = GetGameTimer()
        while GetGameTimer() - startTime < cfg.AmbientFollowMs do
            Wait(3000)
            if not DoesEntityExist(trainEntity) then break end
            local tc = GetEntityCoords(trainEntity)
            for i, o in ipairs(aOutlaws) do
                if DoesEntityExist(o) and not IsEntityDead(o) then
                    local side = (i % 2 == 0) and 18.0 or -18.0
                    TaskGoToCoordAnyMeans(o, tc.x + side, tc.y, tc.z, 4.5, 0, false, 786603, 0xbf800000)
                    -- Outlaws fire toward the train for drama
                    if not IsPedInAnyVehicle(o, false) then
                        TaskShootAtCoord(o, tc.x, tc.y, tc.z, 3000, 0xC6EE6B4C)
                    end
                end
            end
        end

        -- Cleanup
        for _, o in ipairs(aOutlaws) do if DoesEntityExist(o) then DeleteEntity(o) end end
        for _, h in ipairs(aHorses)  do if DoesEntityExist(h) then DeleteEntity(h) end end
        AmbientRobberyActive = false
        DebugPrint('[TrainRobbery] Ambient robbery ended')
    end)
end

-- ── Continuous robbery trigger while player is driving ────────
-- Waits a random 3-5 minute interval then checks:
--   driver in seat + engine on + moving + far from all stations
-- 20% chance to trigger each check.
CreateThread(function()
    Wait(180000) -- 3 min after resource start before first possible check
    while true do
        -- Random interval: fires every 3-5 minutes
        Wait(math.random(180000, 300000))

        if not Config.TrainRobbery.Enabled then goto skipRobbery end
        if Robbery.active or PressureRecovering then goto skipRobbery end
        if not ActiveTrain or not DoesEntityExist(ActiveTrain) then goto skipRobbery end
        if not EngineRunning then goto skipRobbery end

        -- Must be in driver seat
        local ped = PlayerPedId()
        if IsVehicleSeatFree(ActiveTrain, -1) or GetPedInVehicleSeat(ActiveTrain, -1) ~= ped then
            goto skipRobbery
        end

        -- Must be moving
        if GetEntitySpeed(ActiveTrain) < 5.0 then goto skipRobbery end

        -- Must be far from every station (explicit math, no helper function)
        local tc = GetEntityCoords(ActiveTrain)
        local safe = Config.TrainRobbery.SafeZoneRadius or 500.0
        for _, station in ipairs(Config.Stations) do
            local dx = tc.x - station.coords.x
            local dy = tc.y - station.coords.y
            if math.sqrt(dx * dx + dy * dy) < safe then
                goto skipRobbery
            end
        end

        -- 20% chance
        if math.random(100) <= 20 then
            TriggerTrainRobbery(true)  -- force=true; chance already rolled above
        end

        ::skipRobbery::
    end
end)

-- ── Periodic check for ambient trains to rob ─────────────
CreateThread(function()
    Wait(60000) -- wait 1 min after resource start before first check
    while true do
        Wait(Config.TrainRobbery.AmbientCheckInterval)

        if not Config.TrainRobbery.Enabled or not Config.TrainRobbery.AmbientEnabled then
            break
        end
        if AmbientRobberyActive then goto nextCheck end

        -- Scan for a train that isn't the player's
        local found = false

        local function tryVeh(v)
            if not found and IsThisModelATrain(GetEntityModel(v)) and v ~= ActiveTrain then
                TriggerAmbientRobbery(v)
                found = true
            end
        end

        for _, veh in ipairs(GetGamePool('CVehicle')) do
            tryVeh(veh)
            if found then break end
        end

        ::nextCheck::
    end
end)

-- ════════════════════════════════════════════════════════
--  DEBUG COMMAND
--  Only available when Config.Debug = true
--  Usage: /trainrobbery   →  forces a robbery on the current train
-- ════════════════════════════════════════════════════════
RegisterCommand('trainrobbery', function()
    if not Config.Debug then return end

    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then
        print('[jrs_railroad] DEBUG: No active train to rob. Deploy a train first.')
        return
    end

    if Robbery.active then
        print('[jrs_railroad] DEBUG: A robbery is already in progress.')
        return
    end

    print('[jrs_railroad] DEBUG: Forcing train robbery...')
    TriggerTrainRobbery(true) -- force=true skips the chance roll
end, false)

-- ── Cleanup on resource stop ──────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CleanupRobbery()
    end
end)
