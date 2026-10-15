JRSDoubleXP = JRSDoubleXP or {}

local boostState = {
    active = false,
    multiplier = 1.0,
    startedAt = 0,
    endsAt = 0,
    startedBy = '',
}

local storageReady = false
local storageLoading = false
local pendingStorageCallbacks = {}

local function getConfig()
    return Config.DoubleXP or {}
end

local function getTableName()
    local tableName = tostring(getConfig().tableName or 'jrs_double_xp_state')
    if not tableName:match('^[%w_]+$') then
        error('[jrs_core] Config.DoubleXP.tableName contains invalid characters')
    end
    return tableName
end

local function now()
    return os.time()
end

local function normalizeMultiplier(value)
    local multiplier = tonumber(value) or 1.0
    local maximum = tonumber(getConfig().maxMultiplier) or 10.0
    if maximum < 1.0 then maximum = 10.0 end
    if multiplier < 1.0 then multiplier = 1.0 end
    if multiplier > maximum then multiplier = maximum end
    return math.floor((multiplier * 100.0) + 0.5) / 100.0
end

local function normalizeMinutes(value)
    local minutes = math.floor(tonumber(value) or 0)
    local maximum = math.floor(tonumber(getConfig().maxDurationMinutes) or 10080)
    if maximum < 1 then maximum = 10080 end
    if minutes < 0 then minutes = 0 end
    if minutes > maximum then minutes = maximum end
    return minutes
end

local function resetLocalState()
    boostState.active = false
    boostState.multiplier = 1.0
    boostState.startedAt = 0
    boostState.endsAt = 0
    boostState.startedBy = ''
end

local function remainingSeconds()
    if boostState.active ~= true then return 0 end
    return math.max(0, math.floor((tonumber(boostState.endsAt) or 0) - now()))
end

local function publicState()
    local remaining = remainingSeconds()
    if remaining <= 0 then
        return {
            active = false,
            multiplier = 1.0,
            startedAt = 0,
            endsAt = 0,
            remainingSeconds = 0,
            durationSeconds = 0,
        }
    end

    return {
        active = true,
        multiplier = normalizeMultiplier(boostState.multiplier),
        startedAt = tonumber(boostState.startedAt) or 0,
        endsAt = tonumber(boostState.endsAt) or 0,
        remainingSeconds = remaining,
        durationSeconds = math.max(0, math.floor((tonumber(boostState.endsAt) or 0) - (tonumber(boostState.startedAt) or 0))),
    }
end

local function runStorageCallbacks()
    local callbacks = pendingStorageCallbacks
    pendingStorageCallbacks = {}
    for _, callback in ipairs(callbacks) do
        local ok, err = pcall(callback, storageReady)
        if not ok then
            print(('^1[jrs_core][doublexp]^7 storage callback failed: %s'):format(tostring(err)))
        end
    end
end

local function ensureStorage(callback)
    if type(callback) == 'function' then
        pendingStorageCallbacks[#pendingStorageCallbacks + 1] = callback
    end

    if storageReady then
        runStorageCallbacks()
        return
    end
    if storageLoading then return end
    storageLoading = true

    local tableName = getTableName()
    local query = ([=[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` TINYINT UNSIGNED NOT NULL DEFAULT 1,
            `active` TINYINT(1) NOT NULL DEFAULT 0,
            `multiplier` DECIMAL(8,2) NOT NULL DEFAULT 1.00,
            `started_at` BIGINT NOT NULL DEFAULT 0,
            `ends_at` BIGINT NOT NULL DEFAULT 0,
            `started_by` VARCHAR(128) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]=]):format(tableName)

    exports.oxmysql:execute(query, {}, function()
        storageLoading = false
        storageReady = true
        runStorageCallbacks()
    end)
end

local function persistState(callback)
    ensureStorage(function(ready)
        if not ready then
            if callback then callback(false) end
            return
        end

        local tableName = getTableName()
        exports.oxmysql:execute(([[
            INSERT INTO `%s` (`id`, `active`, `multiplier`, `started_at`, `ends_at`, `started_by`)
            VALUES (1, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `active` = VALUES(`active`),
                `multiplier` = VALUES(`multiplier`),
                `started_at` = VALUES(`started_at`),
                `ends_at` = VALUES(`ends_at`),
                `started_by` = VALUES(`started_by`)
        ]]):format(tableName), {
            boostState.active and 1 or 0,
            normalizeMultiplier(boostState.multiplier),
            tonumber(boostState.startedAt) or 0,
            tonumber(boostState.endsAt) or 0,
            tostring(boostState.startedBy or ''),
        }, function()
            if callback then callback(true) end
        end)
    end)
end

local function broadcastState(target)
    TriggerClientEvent('jrs_core:doubleXpState', tonumber(target) or -1, publicState())
end

local function notifyAll(title, message, duration)
    TriggerClientEvent(
        'jrsCore:notify',
        -1,
        tostring(title or 'XP EVENT'),
        tostring(message or ''),
        'placeholder',
        tonumber(duration) or 6000
    )
end

local function formatMultiplier(multiplier)
    multiplier = normalizeMultiplier(multiplier)
    if math.floor(multiplier) == multiplier then
        return tostring(math.floor(multiplier))
    end
    return string.format('%.2f', multiplier):gsub('0+$', ''):gsub('%.$', '')
end

local function stopInternal(reason, announce)
    local wasActive = boostState.active == true
    resetLocalState()
    persistState()
    broadcastState(-1)

    if wasActive and announce == true and getConfig().announceEnd ~= false then
        notifyAll('XP EVENT', _U('core_the_xp_boost_has_ended'), 6000)
    end

    if Config.Info_print and wasActive then
        jrsCore.Debug(('Double XP stopped. Reason: %s'):format(tostring(reason or 'unknown')))
    end

    return wasActive
end

local function ensureActiveState()
    if boostState.active == true and remainingSeconds() <= 0 then
        stopInternal('expired', true)
        return false
    end
    return boostState.active == true
end

function JRSDoubleXP.GetState()
    ensureActiveState()
    return publicState()
end

function JRSDoubleXP.GetMultiplier()
    if not ensureActiveState() then return 1.0 end
    return normalizeMultiplier(boostState.multiplier)
end

-- Admin grants, bot/gift bundles, origin bonuses and pass pushes are never boosted.
local function isExemptReason(reason)
    if reason == nil then return false end
    reason = tostring(reason):lower()
    for _, prefix in ipairs(getConfig().exemptReasonPrefixes or {}) do
        if reason:sub(1, #prefix) == tostring(prefix):lower() then return true end
    end
    return false
end

function JRSDoubleXP.Apply(amount, reason)
    local baseAmount = math.floor(tonumber(amount) or 0)
    if baseAmount <= 0 then return baseAmount, 1.0 end
    if isExemptReason(reason) then return baseAmount, 1.0 end

    local multiplier = JRSDoubleXP.GetMultiplier()
    if multiplier <= 1.0 then return baseAmount, 1.0 end

    local boosted = math.floor((baseAmount * multiplier) + 0.000001)
    if boosted < baseAmount then boosted = baseAmount end
    return boosted, multiplier
end

function JRSDoubleXP.Start(multiplier, minutes, startedBy, callback)
    if getConfig().enabled == false then
        if callback then callback(false, 'disabled') end
        return false, 'disabled'
    end

    multiplier = normalizeMultiplier(multiplier)
    minutes = normalizeMinutes(minutes)

    if multiplier <= 1.0 then
        if callback then callback(false, 'invalid_multiplier') end
        return false, 'invalid_multiplier'
    end
    if minutes <= 0 then
        if callback then callback(false, 'invalid_duration') end
        return false, 'invalid_duration'
    end

    boostState.active = true
    boostState.multiplier = multiplier
    boostState.startedAt = now()
    boostState.endsAt = boostState.startedAt + (minutes * 60)
    boostState.startedBy = tostring(startedBy or ''):sub(1, 128)

    persistState(function(success)
        if not success then
            resetLocalState()
            broadcastState(-1)
            if callback then callback(false, 'database_error') end
            return
        end

        broadcastState(-1)
        if getConfig().announceStart ~= false then
            notifyAll(
                'XP EVENT',
                (_U('core_x_xp_is_active_for_minute')):format(
                    formatMultiplier(multiplier),
                    minutes,
                    minutes == 1 and '' or 's'
                ),
                7000
            )
        end

        if Config.Info_print then
            jrsCore.Debug(('Double XP started: x%s for %s minutes by %s'):format(
                formatMultiplier(multiplier),
                minutes,
                boostState.startedBy ~= '' and boostState.startedBy or 'unknown'
            ))
        end

        if callback then callback(true, nil, JRSDoubleXP.GetState()) end
    end)

    return true
end

function JRSDoubleXP.Stop(reason)
    return stopInternal(reason or 'manual', true)
end

function JRSDoubleXP.SyncPlayer(playerSource)
    local src = tonumber(playerSource)
    if not src or src <= 0 then return false end
    ensureActiveState()
    broadcastState(src)
    return true
end

exports('GetDoubleXPState', function()
    return JRSDoubleXP.GetState()
end)

exports('GetXPMultiplier', function()
    return JRSDoubleXP.GetMultiplier()
end)

-- Single entry point for resources that keep their own XP counters: returns the
-- boosted amount (base amount while no boost is active).
exports('ApplyXPBoost', function(amount, reason)
    return (JRSDoubleXP.Apply(amount, reason))
end)

exports('StartDoubleXP', function(multiplier, minutes, startedBy)
    return JRSDoubleXP.Start(multiplier, minutes, startedBy)
end)

exports('StopDoubleXP', function(reason)
    return JRSDoubleXP.Stop(reason)
end)

RegisterNetEvent('jrs_core:requestDoubleXpState', function()
    JRSDoubleXP.SyncPlayer(source)
end)

AddEventHandler('jrs_core:server:characterReady', function(playerSource)
    JRSDoubleXP.SyncPlayer(playerSource)
end)

AddEventHandler('jrs_core:server:characterUnloaded', function(playerSource)
    local src = tonumber(playerSource)
    if src and src > 0 then
        TriggerClientEvent('jrs_core:doubleXpState', src, {
            active = false,
            multiplier = 1.0,
            remainingSeconds = 0,
        })
    end
end)

local function loadPersistedState()
    ensureStorage(function(ready)
        if not ready then return end

        local tableName = getTableName()
        exports.oxmysql:fetch(("SELECT `active`, `multiplier`, `started_at`, `ends_at`, `started_by` FROM `%s` WHERE `id` = 1 LIMIT 1"):format(tableName), {}, function(rows)
            local row = rows and rows[1] or nil
            if not row then
                resetLocalState()
                persistState()
                broadcastState(-1)
                return
            end

            -- oxmysql can hand back a TINYINT(1) column as a real boolean or as 0/1
            -- depending on driver path; tonumber(true) is nil so a plain == 1 check
            -- silently drops a persisted active boost on load.
            boostState.active = row.active == true or tonumber(row.active) == 1
            boostState.multiplier = normalizeMultiplier(row.multiplier)
            boostState.startedAt = tonumber(row.started_at) or 0
            boostState.endsAt = tonumber(row.ends_at) or 0
            boostState.startedBy = tostring(row.started_by or '')

            if boostState.active and remainingSeconds() <= 0 then
                resetLocalState()
                persistState()
            end

            -- Re-sync connected players after a resource/server restart once the
            -- persisted event state has actually been loaded from the database.
            broadcastState(-1)
        end)
    end)
end

-- One random Double/Triple XP event per restart, starting 1-3h after boot.
CreateThread(function()
    local cfg = getConfig().autoEvent
    if type(cfg) ~= 'table' or cfg.enabled ~= true then return end

    -- Only on a real server boot: server-side GetGameTimer is uptime, so a
    -- later `restart jrs_core` (uptime > 10 min) must not schedule another one.
    if GetGameTimer() > 10 * 60 * 1000 then
        print('^3[jrs_core][doublexp]^7 auto event not scheduled: resource restart, not a server boot')
        return
    end

    local pool = {}
    for _, m in ipairs(cfg.multipliers or { 2, 3 }) do
        if (tonumber(m) or 0) > 1.0 then pool[#pool + 1] = tonumber(m) end
    end
    if #pool == 0 then return end

    local minMin = math.max(1, math.floor(tonumber(cfg.minDelayMinutes) or 60))
    local maxMin = math.max(minMin, math.floor(tonumber(cfg.maxDelayMinutes) or 180))
    math.randomseed(os.time() + GetGameTimer())
    math.random(); math.random()
    local delayMin = math.random(minMin, maxMin)
    local multiplier = pool[math.random(1, #pool)]
    local minDur = math.max(1, math.floor(tonumber(cfg.minDurationMinutes) or 60))
    local maxDur = math.max(minDur, math.floor(tonumber(cfg.maxDurationMinutes) or 180))
    local duration = math.random(minDur, maxDur)

    print(('^3[jrs_core][doublexp]^7 auto event scheduled: x%s for %d min, starts in %d min'):format(
        tostring(multiplier), duration, delayMin))

    Wait(delayMin * 60 * 1000)

    if ensureActiveState() then
        print('^3[jrs_core][doublexp]^7 auto event skipped: another XP boost is already active')
        return
    end
    JRSDoubleXP.Start(multiplier, duration, 'auto_schedule')
end)

CreateThread(function()
    loadPersistedState()
    while true do
        Wait(1000)
        if boostState.active == true and remainingSeconds() <= 0 then
            stopInternal('expired', true)
        end
    end
end)
