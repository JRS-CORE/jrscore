local enabled = true

-- 0xDAABF7FD = FEED_TOAST
-- 0xD211C444 = FEED_LHM_TOAST
-- Channel 6 = toast / award. Channel 1 = Hold F1 app-link toast.
local TOAST_CHANNELS = { 1, 6 }

-- EVENT_CHALLENGE_REWARD                  0xDB3269D0
-- EVENT_CHALLENGE_GOAL_COMPLETE           0x50870403
-- EVENT_CHALLENGE_GOAL_UPDATE             0x63813030
-- EVENT_DAILY_CHALLENGE_STREAK_COMPLETED  0xBC9A051D
-- EVENT_NETWORK_AWARD_CLAIMED             0x67D36B9D
local AWARD_EVENTS = {
    [0xDB3269D0] = true,
    [0x50870403] = true,
    [0x63813030] = true,
    [0xBC9A051D] = true,
    [0x67D36B9D] = true,
}

local function getFeedConfig()
    return Config and Config.Feed or {}
end

local function hideToastHud()
    local cfg = getFeedConfig()
    if cfg.HideFeedToast ~= false then
        Citizen.InvokeNative(0x4CC5F2FC1332577F, 0xDAABF7FD) -- _ENABLE_HUD_CONTEXT FEED_TOAST
        Citizen.InvokeNative(0xC9CAEAEEC1256E54, 0xDAABF7FD) -- _ENABLE_HUD_CONTEXT_THIS_FRAME
    end

    if cfg.HideFeedLhmToast ~= false then
        Citizen.InvokeNative(0x4CC5F2FC1332577F, 0xD211C444) -- _ENABLE_HUD_CONTEXT FEED_LHM_TOAST
        Citizen.InvokeNative(0xC9CAEAEEC1256E54, 0xD211C444)
    end
end

local function clearToastChannels()
    for i = 1, #TOAST_CHANNELS do
        Citizen.InvokeNative(0xDD1232B332CBB9E7, TOAST_CHANNELS[i], true, true)
    end
end

local function disableToastChannels()
    local cfg = getFeedConfig()
    if cfg.DisableToastChannels == false then
        return
    end

    for i = 1, #TOAST_CHANNELS do
        Citizen.InvokeNative(0x6D85126F6CCF02C9, TOAST_CHANNELS[i], 1, true)
    end
end

local function suppressAwards()
    if not enabled then
        return
    end

    hideToastHud()
    clearToastChannels()
end

local function toastIsShowing()
    for i = 1, #TOAST_CHANNELS do
        local message = Citizen.InvokeNative(0xC17F69E1418CD11F, TOAST_CHANNELS[i], Citizen.ResultAsInteger())
        if message and message ~= 0 then
            return true
        end
    end

    return false
end

local function setEnabled(state)
    enabled = state and true or false

    if enabled then
        disableToastChannels()
        suppressAwards()
    end

    return enabled
end

Citizen.CreateThread(function()
    local cfg = getFeedConfig()
    if cfg.Enabled == false then
        enabled = false
    end

    while not Citizen.InvokeNative(0x9DE624D2FC4B603F) do -- NETWORK_IS_SESSION_STARTED
        Citizen.Wait(100)
    end

    Citizen.Wait(500)
    if enabled then
        disableToastChannels()
        suppressAwards()
    end
end)

Citizen.CreateThread(function()
    while true do
        local cfg = getFeedConfig()
        if enabled and (cfg.KeepHidden ~= false) then
            local interval = cfg.HideInterval or 0
            hideToastHud()
            disableToastChannels()

            if toastIsShowing() then
                clearToastChannels()
            end

            Citizen.Wait(interval)
        else
            Citizen.Wait(500)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        local cfg = getFeedConfig()
        if enabled and (cfg.ClearOnChallengeEvents ~= false) then
            local count = GetNumberOfEvents(0)

            if count and count > 0 then
                for i = 0, count - 1 do
                    local eventHash = GetEventAtIndex(0, i)
                    if AWARD_EVENTS[eventHash] then
                        suppressAwards()
                        break
                    end
                end
            end

            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- Exports
exports('IsFeedBlocked', function()
    return enabled
end)

exports('SetFeedBlocked', setEnabled)

exports('HideFeedNow', function()
    suppressAwards()
end)

-- Legacy / backward compatible exports from jrs_feed
exports('IsEnabled', function()
    return enabled
end)

exports('SetEnabled', setEnabled)

exports('HideNow', function()
    suppressAwards()
end)

local cfg = getFeedConfig()
if cfg.ToggleCommand and cfg.ToggleCommand ~= '' then
    RegisterCommand(cfg.ToggleCommand, function()
        local state = setEnabled(not enabled)
        print(('[jrs_core:feed] award banners %s'):format(state and 'hidden' or 'allowed'))
    end, false)
end
