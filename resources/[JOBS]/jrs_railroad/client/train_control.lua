-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: driving the train
--   engine and speed limit, cruise control forward and backward, the emergency brake and the driver HUD.
--   X = emergency brake, R = cruise forward, B = cruise backward, [ = show or hide the HUD.
--   Starting and stopping the engine is done from the look-at menu on the train.

local cruise = { forward = false, backward = false, speed = 0 }
local hud = { open = false, hidden = false }          -- hidden: the player switched it off with [
local inSeat = false

local KEY = { brake = 0x8CC9CD42, forward = 0xE30CD707, backward = 0x4CC0E2FE, hud = 0x430593AA }
local SET_CRUISE = 0x9F29999DFDF2AEB8

local function trainAlive() return ActiveTrain and DoesEntityExist(ActiveTrain) end
local function setCruiseLimit(speed) Citizen.InvokeNative(SET_CRUISE, ActiveTrain, speed) end
local function dropCruise() cruise.forward, cruise.backward, cruise.speed = false, false, 0 end

-- ------------------------------------------------------------------ the driver seat and the HUD

local function seatLeft()
    if not inSeat then return end
    inSeat, hud.open, hud.hidden = false, false, false
    CloseTrainHUD()
end

CreateThread(function()
    while true do
        Wait(500)
        if not trainAlive() then
            seatLeft()                                              -- the train is gone
        elseif GetPedInVehicleSeat(ActiveTrain, -1) == PlayerPedId() then
            inSeat = true
            if not hud.hidden then
                if not hud.open then
                    hud.open = true
                    OpenTrainHUD()
                end
                UpdateTrainHUDData()
            end
        else
            seatLeft()
        end
    end
end)

-- ------------------------------------------------------------------ engine and speed limit

-- keeps the speed limit of the train in step with the engine; the train rolls on even when the driver is away
CreateThread(function()
    while true do
        Wait(100)
        if trainAlive() then
            if EngineRunning then
                if TrainFuel <= 0 then
                    EngineRunning = false
                    dropCruise()
                else
                    setCruiseLimit(GetMaxTrainSpeed() + 0.1)
                end
            elseif not cruise.forward and not cruise.backward then
                setCruiseLimit(0.0)
            end
        end
    end
end)

-- cruise control: holds the speed with both the cruise speed and the speed itself, so the game does not slow the train
CreateThread(function()
    while true do
        Wait(50)
        if trainAlive() and EngineRunning and cruise.speed > 0 and TrainFuel > 0 then
            local direction = cruise.forward and 1 or cruise.backward and -1 or 0
            if direction ~= 0 then
                SetTrainCruiseSpeed(ActiveTrain, cruise.speed * direction)
                if GetEntitySpeed(ActiveTrain) < cruise.speed - 0.5 then SetTrainSpeed(ActiveTrain, cruise.speed * direction) end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if inSeat and trainAlive() then
            if IsControlJustPressed(0, KEY.hud) then
                hud.hidden = not hud.hidden
                hud.open = not hud.hidden
                if hud.hidden then CloseTrainHUD() else OpenTrainHUD() end
            end
            if IsControlJustPressed(0, KEY.brake) then EmergencyBrake() end
            if IsControlJustPressed(0, KEY.forward) then ToggleCruiseForward() end
            if IsControlJustPressed(0, KEY.backward) then ToggleCruiseBackward() end
        else
            Wait(200)
        end
    end
end)

-- ------------------------------------------------------------------ actions

function ToggleEngine()
    if not trainAlive() then return end

    if EngineRunning then
        EngineRunning = false
        dropCruise()
        SetTrainCruiseSpeed(ActiveTrain, 0.0)
        SetTrainSpeed(ActiveTrain, 0.0)
        setCruiseLimit(0.0)
        return Notify(L('engine_stopped'), 'inform')
    end

    if TrainFuel <= 0 then return Notify(L('fuel_empty'), 'error') end
    EngineRunning = true
    setCruiseLimit(GetMaxTrainSpeed() + 0.1)
    Notify(L('engine_started'), 'success')
end

-- stops the cruise and slows the train smoothly over about three seconds
function EmergencyBrake()
    if not trainAlive() then return end
    dropCruise()
    SetTrainCruiseSpeed(ActiveTrain, 0.0)
    Notify(L('brake_applied'), 'warning')

    CreateThread(function()
        for _ = 1, 30 do
            if not trainAlive() then return end
            local speed = GetEntitySpeed(ActiveTrain)
            if speed < 0.5 then break end
            local slower = speed * 0.85
            SetTrainSpeed(ActiveTrain, slower)
            setCruiseLimit(slower + 0.1)
            Wait(100)
        end
        if trainAlive() then
            SetTrainSpeed(ActiveTrain, 0.0)
            setCruiseLimit(EngineRunning and GetMaxTrainSpeed() + 0.1 or 0.0)
        end
    end)
end

-- `direction` is 'forward' or 'backward'; the other one must be off
local function toggleCruise(direction, label)
    local other = direction == 'forward' and 'backward' or 'forward'
    if not EngineRunning then return Notify(L('engine_stopped'), 'error') end
    if cruise[other] then return Notify(L('cruise_conflict'), 'error') end
    if TrainFuel <= 0 then return Notify(L('cruise_no_fuel'), 'error') end

    cruise[direction] = not cruise[direction]
    if cruise[direction] then
        -- hold the speed the train has now (or half of the top speed from a standstill)
        local speed = GetEntitySpeed(ActiveTrain)
        cruise.speed = speed > 1 and speed or GetMaxTrainSpeed() * 0.5
        Notify(L('cruise_enabled', L(label)), 'success')
    else
        cruise.speed = 0
        SetTrainCruiseSpeed(ActiveTrain, 0.0)
        Notify(L('cruise_disabled'), 'inform')
    end
end

function ToggleCruiseForward() toggleCruise('forward', 'hud_forward') end
function ToggleCruiseBackward() toggleCruise('backward', 'hud_reverse') end

-- ------------------------------------------------------------------ values for other files

-- base speed plus the speed upgrade, capped at the game's limit, scaled by condition
-- (full speed at 100%, Config.Condition.lowConditionSpeedCap of it at 0%)
function GetMaxTrainSpeed()
    if not ActiveTrainConfig then return 15 end

    local bonus = 0
    local tier = ActiveTrainData and ActiveTrainData.upgrade_speed or 0
    if tier > 0 and Config.Upgrades.speed[tier] then bonus = Config.Upgrades.speed[tier].bonus end
    local top = math.min(ActiveTrainConfig.maxSpeed + bonus, 30)

    local health = math.max(0, math.min(1, (TrainCondition or 0) / (ActiveTrainConfig.maxCondition or 100)))
    local floor = Config.Condition.lowConditionSpeedCap
    return math.max(1, math.floor(top * (floor + (1 - floor) * health) + 0.5))
end

function GetCurrentSpeed()
    return trainAlive() and math.floor(GetEntitySpeed(ActiveTrain) + 0.5) or 0
end

function IsCruiseForward() return cruise.forward end
function IsCruiseBackward() return cruise.backward end
