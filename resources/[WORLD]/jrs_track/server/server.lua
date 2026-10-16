-- jrs_track | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_track | server
-- One race at a time. The server keeps the route, who rides, the laps and the results. Riders only report
-- that they crossed the finish; time and position are checked here before anything is paid.

local MIN_SECONDS_PER_LAP <const> = 8       -- a faster finish than this is not real
local MIN_RIDERS_FOR_REWARD <const> = 2     -- a solo race pays nothing, no farming
local REWARD <const> = 100
local ADMIN_ONLY = true                     -- start/reset/laps/tracks need the JRS admin group

local race = {
    riders = {},                -- source -> { name, laps, passedEndPoint }
    started = false, startedAt = 0, riderCount = 0,
    points = {}, name = nil,
    laps = 1, maxMarkers = 15,
    finishers = {}, results = {}, saved = {},
}

local function admin(src) return not ADMIN_ONLY or JRS.IsAdmin(src) end

local function tell(src, key, kind, ...)
    TriggerClientEvent('jrs_track:toast', src, { title = Locale('title'), description = Locale(key, ...), type = kind or 'error' })
end

local function validPoint(p)
    return type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number'
end

local function displayName(player, src)
    if player then
        local full = (('%s %s'):format(player.firstname or '', player.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if full ~= '' then return full end
    end
    local account = GetPlayerName(src)
    if type(account) == 'string' and account ~= '' then return account end
    return Locale('ui_rider_num', src)
end

local function riderList()
    local list = {}
    for src, data in pairs(race.riders) do
        local id = tonumber(src)
        if id and type(data) == 'table' then
            list[#list + 1] = {
                source = id,
                name = type(data.name) == 'string' and data.name or Locale('ui_rider_num', id),
                laps = tonumber(data.laps) or 0,
                passedEndPoint = data.passedEndPoint == true,
            }
        end
    end
    table.sort(list, function(a, b) return a.source < b.source end)
    return list
end

local function broadcastRiders()
    TriggerClientEvent('jrs_track:updatePlayers', -1, riderList(), race.started)
end

local function riderCount()
    local n = 0
    for _ in pairs(race.riders) do n = n + 1 end
    return n
end

local function sendSetup(target)
    TriggerClientEvent('jrs_track:syncTracks', target, race.saved)
    TriggerClientEvent('jrs_track:syncMaxMarkers', target, race.maxMarkers)
    if #race.points >= 2 then TriggerClientEvent('jrs_track:syncTrack', target, race.points, true) end
end

-- ------------------------------------------------------------------ saved tracks

local function loadSaved()
    race.saved = {}
    for _, row in ipairs(MySQL.query.await('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC') or {}) do
        local points = json.decode(row.points)
        if points then race.saved[#race.saved + 1] = { track_id = row.track_id, name = row.name, points = points } end
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local ok, err = pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS horse_race_tracks (
        track_id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50) NOT NULL, points JSON NOT NULL, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)]])
    if not ok then
        print(('[jrs_track] Failed to create horse_race_tracks table: %s'):format(tostring(err)))
        return SendTrackWebhook('dbError', 'Database Error', 'Failed to create `horse_race_tracks` table on resource start.', {
            { name = 'Error', value = ('```%s```'):format(tostring(err)), inline = false },
        })
    end

    loadSaved()
    TriggerClientEvent('jrs_track:syncTracks', -1, race.saved)
    TriggerClientEvent('jrs_track:syncMaxMarkers', -1, race.maxMarkers)
end)

AddEventHandler('playerConnecting', function() sendSetup(source) end)
RegisterServerEvent('jrs_track:requestTracks', function() sendSetup(source) end)

RegisterServerEvent('horse_race:trackCreated', function(points, trackName)
    local src = source
    local player = JRS.Char(src)
    if not player then return end

    if type(points) ~= 'table' or #points < 2 or #points > race.maxMarkers then
        return tell(src, 'notify_invalid_points', nil, race.maxMarkers)
    end
    for i = 1, #points do
        if not validPoint(points[i]) then return tell(src, 'notify_invalid_points', nil, race.maxMarkers) end
    end

    -- the name column holds 50 characters
    local name = type(trackName) == 'string' and trackName:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 50) or ''
    if name == '' then name = 'Track ' .. (#race.saved + 1) end

    local ok, err = pcall(MySQL.insert.await, 'INSERT INTO horse_race_tracks (name, points) VALUES (?, ?)', { name, json.encode(points) })
    if not ok then
        print(('[jrs_track] Failed to save track: %s'):format(tostring(err)))
        SendTrackWebhook('dbError', 'Database Error', 'Failed to save a new track.', {
            WebhookPlayerField(displayName(player, src), src, player.charIdentifier),
            { name = 'Track Name', value = name, inline = true },
            { name = 'Error', value = ('```%s```'):format(tostring(err)), inline = false },
        })
        return tell(src, 'notify_save_failed')
    end

    loadSaved()
    race.points, race.name = points, name
    TriggerClientEvent('jrs_track:syncTrack', -1, points, true)
    TriggerClientEvent('jrs_track:syncTracks', -1, race.saved)

    SendTrackWebhook('trackCreated', 'Track Created', nil, {
        WebhookPlayerField(displayName(player, src), src, player.charIdentifier),
        { name = 'Track', value = name, inline = true },
        { name = 'Track ID', value = race.saved[1] and tostring(race.saved[1].track_id) or '?', inline = true },
        { name = 'Points', value = tostring(#points), inline = true },
    })
end)

RegisterServerEvent('jrs_track:loadTrack', function(trackId)
    local src = source
    if not JRS.Char(src) or not admin(src) then return end
    if race.started then return tell(src, 'notify_cannot_load_during_race') end

    for _, t in ipairs(race.saved) do
        if t.track_id == trackId then
            race.points, race.name = t.points, t.name
            return TriggerClientEvent('jrs_track:syncTrack', -1, t.points, true)
        end
    end
    tell(src, 'notify_track_not_found')
end)

RegisterServerEvent('jrs_track:deleteTrack', function(trackId)
    local src = source
    local player = JRS.Char(src)
    if not player or not admin(src) then return end

    local name
    for _, t in ipairs(race.saved) do
        if t.track_id == trackId then name = t.name break end
    end

    local removed = MySQL.update.await('DELETE FROM horse_race_tracks WHERE track_id = ?', { trackId })
    if not removed or removed < 1 then return tell(src, 'notify_track_delete_fail') end

    SendTrackWebhook('trackDeleted', 'Track Deleted', nil, {
        WebhookPlayerField(displayName(player, src), src, player.charIdentifier),
        { name = 'Track', value = name or ('#' .. tostring(trackId)), inline = true },
        { name = 'Track ID', value = tostring(trackId), inline = true },
    })

    loadSaved()
    TriggerClientEvent('jrs_track:syncTracks', -1, race.saved)
    tell(src, 'notify_track_deleted', 'success')

    -- the deleted track is gone from the list, so it cannot stay in use either
    if #race.points > 0 then
        local stillThere = false
        for _, t in ipairs(race.saved) do
            if t.name == race.name then stillThere = true end
        end
        if not stillThere then
            race.points = {}
            TriggerClientEvent('jrs_track:syncTrack', -1, {}, false)
        end
    end
end)

-- ------------------------------------------------------------------ settings

local function setting(event, default, title, low, high, current, apply)
    RegisterServerEvent(event, function(value)
        local src = source
        local player = JRS.Char(src)
        if not player or not admin(src) or race.started then return end

        local old = current()
        local new = math.max(low, math.min(high, tonumber(value) or default))
        apply(new)
        if new ~= old then
            SendTrackWebhook('settingsChanged', title, nil, {
                WebhookPlayerField(displayName(player, src), src, player.charIdentifier),
                { name = 'Old Value', value = tostring(old), inline = true },
                { name = 'New Value', value = tostring(new), inline = true },
            })
        end
    end)
end

setting('jrs_track:setMaxMarkers', 15, 'Max Markers Changed', 2, 30, function() return race.maxMarkers end, function(v)
    race.maxMarkers = v
    TriggerClientEvent('jrs_track:syncMaxMarkers', -1, v)
end)

setting('jrs_track:setLaps', 1, 'Lap Count Changed', 1, 5, function() return race.laps end, function(v)
    race.laps = v
    TriggerClientEvent('jrs_track:syncLaps', -1, v)
end)

-- ------------------------------------------------------------------ joining and starting

RegisterServerEvent('jrs_track:joinRace', function()
    local src = source
    local player = JRS.Char(src)
    if not player then return end
    if #race.points < 2 then return tell(src, 'notify_no_track_yet') end
    if race.started then return tell(src, 'notify_race_already_started') end
    if race.riders[src] then return tell(src, 'notify_already_in_race') end

    race.riders[src] = { name = displayName(player, src), laps = 0, passedEndPoint = false }
    TriggerClientEvent('jrs_track:joinedRace', src)
    broadcastRiders()
end)

RegisterServerEvent('jrs_track:leaveRace', function()
    local src = source
    if race.riders[src] then
        race.riders[src] = nil
        TriggerClientEvent('jrs_track:leftRace', src)
        broadcastRiders()
    end
end)

-- somebody who disconnects (crash, alt-F4) would otherwise stay in the race forever
AddEventHandler('playerDropped', function()
    local src = source
    if race.riders[src] then
        race.riders[src] = nil
        broadcastRiders()
    end
end)

RegisterServerEvent('jrs_track:startRace', function()
    local src = source
    local player = JRS.Char(src)
    if not player then return tell(src, 'notify_player_data_not_found') end
    if #race.points < 2 then return tell(src, 'notify_no_track') end

    local count = riderCount()
    if count < 1 then return tell(src, 'notify_min_players') end
    if race.started then return tell(src, 'notify_race_in_progress') end

    race.started, race.startedAt, race.riderCount = true, GetGameTimer(), count
    broadcastRiders()
    TriggerClientEvent('jrs_track:startRace', -1)

    SendTrackWebhook('raceStarted', 'Race Started', nil, {
        WebhookPlayerField(displayName(player, src), src, player.charIdentifier),
        { name = 'Riders', value = tostring(count), inline = true },
        { name = 'Laps', value = tostring(race.laps), inline = true },
        { name = 'Checkpoints', value = tostring(#race.points), inline = true },
    })
end)

RegisterServerEvent('horse_race:countdownFinished', function()
    if race.started and race.riders[source] then TriggerClientEvent('jrs_track:raceStarted', -1) end
end)

-- ------------------------------------------------------------------ finishing

-- everything back to "no race"
local function clearRace()
    race.started, race.points, race.name, race.riders, race.finishers, race.laps = false, {}, nil, {}, {}, 1
end

RegisterServerEvent('horse_race:finishRace', function()
    local src = source
    local player = JRS.Char(src)
    if not player then return end

    -- the client only says "I crossed the finish"; whether a race runs, how long it took and where the rider is, is checked here
    if not race.started or not race.riders[src] then return tell(src, 'notify_not_in_race') end

    local seconds = (GetGameTimer() - race.startedAt) / 1000
    if seconds < race.laps * MIN_SECONDS_PER_LAP then return tell(src, 'notify_incomplete_laps') end

    local finish = race.points[#race.points]
    if not finish or #(GetEntityCoords(GetPlayerPed(src)) - vector3(finish.x, finish.y, finish.z)) > 40.0 then return end

    local name = displayName(player, src)
    local place = #race.finishers + 1
    race.finishers[place] = { name = name, position = place, laps = race.laps }
    TriggerClientEvent('jrs_track:showFinisherNotification', -1, name, place)

    if place == 1 and race.riderCount >= MIN_RIDERS_FOR_REWARD then
        JRS.GiveMoney(src, REWARD)
        TriggerClientEvent('jrs_track:rewardReceived', src, REWARD)
    end

    race.riders[src] = nil
    TriggerClientEvent('jrs_track:syncResults', -1, race.finishers)

    -- the first to finish ends the visuals for everybody; riders who missed a checkpoint get 12 s, then the race ends
    if place == 1 then
        TriggerClientEvent('jrs_track:finishRace', -1)
        SetTimeout(12000, function()
            if not race.started then return end
            for rider in pairs(race.riders) do tell(rider, 'notify_ended_missed_checkpoint', 'inform') end
            TriggerClientEvent('jrs_track:finishRace', -1)
            TriggerClientEvent('jrs_track:resetRace', -1, false)
            clearRace()
            broadcastRiders()
            TriggerClientEvent('jrs_track:syncResults', -1, {})
        end)
    end

    if riderCount() > 0 then return end

    -- the last rider is in
    race.results[#race.results + 1] = { finishers = race.finishers, raceId = #race.results + 1 }
    if #race.results > 5 then table.remove(race.results, 1) end

    local standings = {}
    for _, f in ipairs(race.finishers) do standings[#standings + 1] = ('%d. %s'):format(f.position, f.name) end
    SendTrackWebhook('raceFinished', 'Race Finished', race.name, {
        { name = 'Standings', value = #standings > 0 and table.concat(standings, '\n') or 'No finishers', inline = false },
        { name = 'Reward (1st Place)', value = tostring(REWARD), inline = true },
        { name = 'Laps', value = tostring(race.laps), inline = true },
    })

    TriggerClientEvent('jrs_track:syncRaceResults', -1, race.results)
    TriggerClientEvent('jrs_track:finishRace', -1)
    clearRace()
    TriggerClientEvent('jrs_track:resetRace', -1, false)
    broadcastRiders()
    TriggerClientEvent('jrs_track:syncResults', -1, {})
end)

RegisterServerEvent('jrs_track:resetRace', function()
    local src = source
    local player = JRS.Char(src)
    if not player or not admin(src) then return end

    clearRace()
    race.results = {}
    TriggerClientEvent('jrs_track:syncRaceResults', -1, race.results)
    TriggerClientEvent('jrs_track:resetRace', -1, true)

    SendTrackWebhook('raceReset', 'Race Manually Reset', nil, { WebhookPlayerField(displayName(player, src), src, player.charIdentifier) })
end)
