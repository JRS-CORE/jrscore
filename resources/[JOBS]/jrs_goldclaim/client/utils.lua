

---------------------------------------------
-- shared client helpers (loaded first)
---------------------------------------------
function Notify(title, description, nType, icon, duration)
    JRS.Notify(description and (title .. ': ' .. description) or title, duration or Config.NotifyDuration)
end

function LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash)
end

function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local busy = false

function IsBusy()
    if busy then
        Notify(L('rocker_processing_busy'), nil, 'error', 'circle-xmark', 3000)
    end
    return busy
end

local function SetBusy(state)
    busy = state
    LocalPlayer.state:set('inv_busy', state, true)
end

local CANCEL_KEY   = 0x156F7119 -- INPUT_FRONTEND_CANCEL (backspace / esc)
local BLOCKED_KEYS = {
    0x07CE1E61, -- INPUT_ATTACK
    0xF84FA74F, -- INPUT_AIM
    0xB2F377E8, -- INPUT_MELEE_ATTACK
    0xAC4BD4F1, -- INPUT_OPEN_WHEEL_MENU
}

local MOVE_CANCEL_DIST = 1.0 -- walking further than this from the start point cancels the action
-- scenarios lock the ped in place, so pressing a movement key is treated as "walk away" and cancels
local MOVE_KEYS = {
    0x8FD015D8, -- INPUT_MOVE_UP_ONLY (W)
    0xD27782E3, -- INPUT_MOVE_DOWN_ONLY (S)
    0x7065027D, -- INPUT_MOVE_LEFT_ONLY (A)
    0xB4E465B4, -- INPUT_MOVE_RIGHT_ONLY (D)
}

local function MovePressed()
    for i = 1, #MOVE_KEYS do
        if IsControlJustPressed(0, MOVE_KEYS[i]) or IsDisabledControlJustPressed(0, MOVE_KEYS[i]) then return true end
    end
    return false
end

local function WaitForAction(ped, duration, canCancel)
    local start = GetEntityCoords(ped)
    local endTime = GetGameTimer() + duration
    while GetGameTimer() < endTime do
        Wait(0)
        for i = 1, #BLOCKED_KEYS do DisableControlAction(0, BLOCKED_KEYS[i], true) end
        if IsEntityDead(ped) then return false end
        if canCancel and (IsControlJustPressed(0, CANCEL_KEY) or MovePressed() or #(GetEntityCoords(ped) - start) > MOVE_CANCEL_DIST) then
            return false
        end
    end
    return true
end

--- Plays a scenario for opts.duration ms (no progress bar, player is not frozen).
--- Walking away or pressing backspace / esc cancels it (unless canCancel = false).
--- opts = { duration, scenario?, canCancel?, onCleanup? }
--- returns true if the action ran to completion
function DoTimedAction(opts)
    if busy then return false end
    SetBusy(true)

    local ped = PlayerPedId()
    if opts.scenario then
        TaskStartScenarioInPlace(ped, opts.scenario, 0, true)
    end

    -- pcall guarantees cleanup always runs, even if something errors mid-action
    local ok, completed = pcall(WaitForAction, ped, opts.duration, opts.canCancel ~= false)

    if completed then ClearPedTasks(ped) else ClearPedTasksImmediately(ped) end -- instant exit when cancelled
    if opts.onCleanup then pcall(opts.onCleanup, ped) end
    SetBusy(false)
    return ok and completed
end

-- character id + job, refreshed from the server
local me = { id = nil, job = nil, at = 0 }
local function refreshMe()
    if GetGameTimer() < me.at then return end
    me.at = GetGameTimer() + 30000
    local info = JRS.Await('jrs_goldclaim:server:me')
    if info then me.id, me.job = info.id, info.job end
end

function MyCharId()
    refreshMe()
    return me.id
end

function IsLeo()
    refreshMe()
    return me.job ~= nil and Config.LeoJobs[me.job] == true
end

function HasItem(item, amount)
    return JRS.Await('jrs_goldclaim:server:hasitem', item, amount or 1) == true
end

RegisterNetEvent('jrs:SelectedCharacter', function() me.at = 0 end)

function CreateNamedBlip(coords, sprite, scale, name, colour)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z) -- BlipAddForCoords
    SetBlipSprite(blip, joaat(sprite), true)
    SetBlipScale(blip, scale)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name) -- SetBlipName
    if colour then Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(colour)) end -- BlipAddModifier
    return blip
end
