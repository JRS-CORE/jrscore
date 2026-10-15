local cruiseForward = false
local cruiseBackward = false
local cruiseSpeed = 0
local HUDOpen = false
local HUDHidden = false  -- player toggled HUD off with T
local InDriverSeat = false

-- Key hashes from jrs_core/shared/keybinds.lua
local Keys = {
    ['E'] = 0xCEFD9220,
    ['R'] = 0xE30CD707,
    ['X'] = 0x8CC9CD42,
    ['Q'] = 0xDE794E3E,
    ['B'] = 0x4CC0E2FE,
}

---------------------------------------------------------------
-- DRIVER SEAT / PROXIMITY DETECTION + HUD TOGGLE
-- Regular trains: player must be in driver seat (-1)
-- Trams: player just needs to be near the tram (NPC conductor drives)
---------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(500)
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            local ped = PlayerPedId()
            local active = (not IsVehicleSeatFree(ActiveTrain, -1) and GetPedInVehicleSeat(ActiveTrain, -1) == ped)

            if active then
                InDriverSeat = true
                if not HUDOpen and not HUDHidden then
                    HUDOpen = true
                    OpenTrainHUD()
                end
                if HUDOpen and not HUDHidden then
                    UpdateTrainHUDData()
                end
            else
                if InDriverSeat then   -- just left the seat
                    InDriverSeat = false
                    HUDOpen = false
                    HUDHidden = false
                    CloseTrainHUD()
                end
            end
        else
            if InDriverSeat then   -- train gone
                InDriverSeat = false
                HUDOpen = false
                HUDHidden = false
                CloseTrainHUD()
            end
        end
    end
end)

---------------------------------------------------------------
-- ENGINE STATE + MAX SPEED ENFORCEMENT
-- Runs regardless of whether player is in seat
-- Train keeps moving on cruise even when driver leaves seat
-- Trams: skip this loop entirely (tram movement loop handles it)
---------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(100)
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            if EngineRunning then
                local maxSpd = GetMaxTrainSpeed()
                if TrainFuel <= 0 then
                    EngineRunning = false
                    cruiseForward = false
                    cruiseBackward = false
                    cruiseSpeed = 0
                else
                    Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, maxSpd + 0.1)
                end
            else
                if not cruiseForward and not cruiseBackward then
                    Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, 0.0)
                end
            end
        end
    end
end)

---------------------------------------------------------------
-- KEYBOARD CONTROLS (custom keys, non-conflicting with native)
-- Native:  L SHIFT = Accelerate, L CTRL = Brake/Reverse
--          Left Mouse = Bell, G = Whistle
-- Custom:  E = Toggle engine, X = Emergency stop
--          R = Cruise forward, B = Cruise backward
--          Q = Toggle track switches
---------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)
        if InDriverSeat and ActiveTrain and DoesEntityExist(ActiveTrain) then

            -- E key removed: conflicts with enter/exit vehicle
            -- Use the JRS interaction prompt 'Start / Stop Engine' instead

            -- [ = Toggle HUD
            if IsControlJustPressed(0, 0x430593AA) then -- LEFTBRACKET key
                HUDHidden = not HUDHidden
                if HUDHidden then
                    HUDOpen = false
                    CloseTrainHUD()
                else
                    HUDOpen = true
                    OpenTrainHUD()
                end
            end

            -- X = Emergency Brake (full stop + kill cruise)
            if IsControlJustPressed(0, Keys['X']) then
                EmergencyBrake()
            end

            -- R = Cruise Forward toggle
            if IsControlJustPressed(0, Keys['R']) then
                ToggleCruiseForward()
            end

            -- B = Cruise Backward toggle
            if IsControlJustPressed(0, Keys['B']) then
                ToggleCruiseBackward()
            end

        else
            Wait(200)
        end
    end
end)

---------------------------------------------------------------
-- CRUISE CONTROL LOOP
-- Forces speed maintenance using both CruiseSpeed AND Speed
---------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(50)
        if ActiveTrain and DoesEntityExist(ActiveTrain) and EngineRunning then
            if cruiseForward and cruiseSpeed > 0 and TrainFuel > 0 then
                SetTrainCruiseSpeed(ActiveTrain, cruiseSpeed)
                -- Force maintain speed - prevents native deceleration
                local vel = GetEntitySpeed(ActiveTrain)
                if vel < cruiseSpeed - 0.5 then
                    SetTrainSpeed(ActiveTrain, cruiseSpeed)
                end
            elseif cruiseBackward and cruiseSpeed > 0 and TrainFuel > 0 then
                SetTrainCruiseSpeed(ActiveTrain, -cruiseSpeed)
                local vel = GetEntitySpeed(ActiveTrain)
                if vel < cruiseSpeed - 0.5 then
                    SetTrainSpeed(ActiveTrain, -cruiseSpeed)
                end
            end
        end
    end
end)

---------------------------------------------------------------
-- CONTROL FUNCTIONS
---------------------------------------------------------------
function ToggleEngine()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return end
    if EngineRunning then
        EngineRunning = false
        cruiseForward = false
        cruiseBackward = false
        cruiseSpeed = 0
        SetTrainCruiseSpeed(ActiveTrain, 0.0)
        SetTrainSpeed(ActiveTrain, 0.0)
        Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, 0.0)
        Notify(L('engine_stopped'), 'inform')
    else
        if TrainFuel <= 0 then
            Notify(L('fuel_empty'), 'error')
            return
        end
        EngineRunning = true
        local maxSpd = GetMaxTrainSpeed()
        Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, maxSpd + 0.1)

        Notify(L('engine_started'), 'success')
    end
end

function EmergencyBrake()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return end
    cruiseForward = false
    cruiseBackward = false
    cruiseSpeed = 0
    SetTrainCruiseSpeed(ActiveTrain, 0.0)

    Notify(L('brake_applied'), 'warning')
    -- Gradual deceleration over ~3 seconds
    CreateThread(function()
        for i = 1, 30 do
            if not ActiveTrain or not DoesEntityExist(ActiveTrain) then break end
            local currentVel = GetEntitySpeed(ActiveTrain)
            if currentVel < 0.5 then
                SetTrainSpeed(ActiveTrain, 0.0)
                break
            end
            local newVel = currentVel * 0.85 -- reduce by 15% each tick
            SetTrainSpeed(ActiveTrain, newVel)
            Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, newVel + 0.1)
            Wait(100)
        end
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            SetTrainSpeed(ActiveTrain, 0.0)
            if EngineRunning then
                Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, GetMaxTrainSpeed() + 0.1)
            else
                Citizen.InvokeNative(0x9F29999DFDF2AEB8, ActiveTrain, 0.0)
            end
        end
    end)
end

function ToggleCruiseForward()
    if not EngineRunning then
        Notify(L('engine_stopped'), 'error')
        return
    end
    if cruiseBackward then
        Notify(L('cruise_conflict'), 'error')
        return
    end
    if TrainFuel <= 0 then
        Notify(L('cruise_no_fuel'), 'error')
        return
    end
    cruiseForward = not cruiseForward
    if cruiseForward then
        -- Lock in the current speed as cruise speed
        local vel = GetEntitySpeed(ActiveTrain)
        cruiseSpeed = vel > 1 and vel or (GetMaxTrainSpeed() * 0.5)
        Notify(L('cruise_enabled', L('hud_forward')), 'success')
    else
        cruiseSpeed = 0
        SetTrainCruiseSpeed(ActiveTrain, 0.0)
        Notify(L('cruise_disabled'), 'inform')
    end
end

function ToggleCruiseBackward()
    if not EngineRunning then
        Notify(L('engine_stopped'), 'error')
        return
    end
    if cruiseForward then
        Notify(L('cruise_conflict'), 'error')
        return
    end
    if TrainFuel <= 0 then
        Notify(L('cruise_no_fuel'), 'error')
        return
    end
    cruiseBackward = not cruiseBackward
    if cruiseBackward then
        local vel = GetEntitySpeed(ActiveTrain)
        cruiseSpeed = vel > 1 and vel or (GetMaxTrainSpeed() * 0.5)
        Notify(L('cruise_enabled', L('hud_reverse')), 'success')
    else
        cruiseSpeed = 0
        SetTrainCruiseSpeed(ActiveTrain, 0.0)
        Notify(L('cruise_disabled'), 'inform')
    end
end

---------------------------------------------------------------
-- GET MAX SPEED (with upgrades + condition)
---------------------------------------------------------------
function GetMaxTrainSpeed()
    if not ActiveTrainConfig then return 15 end
    local base = ActiveTrainConfig.maxSpeed
    local upgradeBonus = 0
    if ActiveTrainData and ActiveTrainData.upgrade_speed > 0 then
        local tier = ActiveTrainData.upgrade_speed
        if Config.Upgrades.speed[tier] then
            upgradeBonus = Config.Upgrades.speed[tier].bonus
        end
    end
    local max = math.min(base + upgradeBonus, 30) -- native cap

    -- Gradual condition penalty:
    -- 100% condition = full speed, 0% condition = 25% speed
    -- Formula: multiplier = 0.25 + (0.75 * conditionPercent)
    local maxCond = ActiveTrainConfig.maxCondition or 100
    local condPct = math.max(0, math.min(1, (TrainCondition or 0) / maxCond))
    local condMultiplier = Config.Condition.lowConditionSpeedCap + ((1 - Config.Condition.lowConditionSpeedCap) * condPct)
    max = max * condMultiplier

    return math.max(1, math.floor(max + 0.5)) -- minimum speed of 1, rounded
end

---------------------------------------------------------------
-- GETTERS FOR HUD
---------------------------------------------------------------
function GetCurrentSpeed()
    if ActiveTrain and DoesEntityExist(ActiveTrain) then
        return math.floor(GetEntitySpeed(ActiveTrain) + 0.5)
    end
    return 0
end

function IsCruiseForward()
    return cruiseForward
end

function IsCruiseBackward()
    return cruiseBackward
end
