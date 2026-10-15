JRSRestartManager = JRSRestartManager or {}

local config = Config.RestartManagement or {}
local lastAnnouncementKey = nil
local lastKickKey = nil

local function parseClock(value)
    if type(value) ~= 'string' then return nil end
    local h, m = value:match('^(%d%d?):(%d%d?)$')
    h, m = tonumber(h), tonumber(m)
    if not h or not m or h < 0 or h > 23 or m < 0 or m > 59 then return nil end
    return h * 60 + m
end

local function currentClock()
    local t = os.date('*t')
    local clock = ('%02d:%02d'):format(t.hour, t.min)
    local dateKey = ('%04d-%02d-%02d %s'):format(t.year, t.month, t.day, clock)
    return t.hour * 60 + t.min, clock, dateKey
end

local function inWindow(nowMinutes, window)
    if type(window) ~= 'table' then return false end
    local from = parseClock(window.From or window.from)
    local to = parseClock(window.To or window.to)
    if not from or not to then return false end

    if from <= to then
        return nowMinutes >= from and nowMinutes <= to
    end

    -- Window crosses midnight, e.g. 23:55 -> 00:05.
    return nowMinutes >= from or nowMinutes <= to
end

function JRSRestartManager.IsJoinBlocked()
    if config.Enabled ~= true then return false end
    local nowMinutes = currentClock()

    for _, window in ipairs(config.BlockJoinWindows or {}) do
        if inWindow(nowMinutes, window) then
            return true
        end
    end

    return false
end

function JRSRestartManager.CanJoin()
    return not JRSRestartManager.IsJoinBlocked()
end

function JRSRestartManager.GetStatus()
    local _, clock = currentClock()
    return {
        enabled = config.Enabled == true,
        blocked = JRSRestartManager.IsJoinBlocked(),
        clock = clock,
    }
end

local function announce(message, durationMs)
    if not message or message == '' then return end
    TriggerClientEvent('jrs_core:sendTipNotification', -1, tostring(message), tonumber(durationMs) or 10000)
end

local function kickPlayers()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then
            DropPlayer(src, tostring(config.KickMessage or 'The server is restarting. Please reconnect in a few minutes.'))
        end
    end
end

CreateThread(function()
    while true do
        if config.Enabled ~= true then
            Wait(5000)
        else
            local _, clock, dateKey = currentClock()

            if config.Debug then
                print(('[jrs_core][restart] time=%s blocked=%s'):format(clock, tostring(JRSRestartManager.IsJoinBlocked())))
            end

            local announcement = config.Announcements and config.Announcements[clock]
            if announcement and lastAnnouncementKey ~= dateKey then
                announce(announcement.Text or announcement.text, announcement.DurationMs or announcement.duration)
                lastAnnouncementKey = dateKey
            end

            local shouldKick = false
            for _, kickTime in ipairs(config.KickTimes or {}) do
                local minutes = parseClock(kickTime)
                local currentMinutes = parseClock(clock)
                if minutes and minutes == currentMinutes then
                    shouldKick = true
                    break
                end
            end

            if shouldKick and lastKickKey ~= dateKey then
                lastKickKey = dateKey
                kickPlayers()
            end

            Wait(5000)
        end
    end
end)

exports('GetRestartStatus', function()
    return JRSRestartManager.GetStatus()
end)
