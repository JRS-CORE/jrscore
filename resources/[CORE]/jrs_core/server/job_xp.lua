-- JRS - per-script (per-job) leveling.
-- Every job/script keeps its own XP + level (1..100) in `jrs_job_levels`, using
-- the same medium Config.Levels curve the global level uses (so all jobs are
-- balanced against each other). Each positive award also feeds Config.JobXP.CoreShare
-- of the XP into the global core level, so every script contributes to the core
-- in a balanced way. Awards are race-safe via an atomic upsert.

JRSJobXP = JRSJobXP or {}

local function jobConfig() return Config.JobXP or {} end

local function isEnabled() return jobConfig().Enabled ~= false end

local function jobTable()
    local t = tostring(jobConfig().Table or 'jrs_job_levels')
    if not t:match('^[%w_]+$') then t = 'jrs_job_levels' end
    return t
end

local function normalizeJob(job)
    job = tostring(job or ''):lower():gsub('[^%w_]', '')
    if job == '' then return nil end
    return job:sub(1, 40)
end

local function defaultCoreShare()
    local s = tonumber(jobConfig().CoreShare)
    if not s or s < 0 then s = 0.25 end
    return s
end

-- Per-job override of the core share, DB-backed so jrs_admin can change it live
-- without a restart. Live overrides win over Config.JobXP.CoreShareByJob, which
-- wins over the flat default above.
local SHARES_TABLE = 'jrs_job_xp_shares'
local shareOverrides = {}

local function coreShare(job)
    local key = normalizeJob(job)
    if key and shareOverrides[key] ~= nil then return shareOverrides[key] end
    local cfgByJob = jobConfig().CoreShareByJob
    if key and type(cfgByJob) == 'table' then
        local s = tonumber(cfgByJob[key])
        if s and s >= 0 then return s end
    end
    return defaultCoreShare()
end

local function clampShare(share)
    share = tonumber(share)
    if not share or share < 0 then return nil end
    if share > 1 then share = 1 end
    return math.floor((share * 10000) + 0.5) / 10000
end

-- Sets (or, with share=nil, clears) a per-job core-share override, persisted so
-- it survives a restart. Callback receives (success, overrides).
function JRSJobXP.SetCoreShare(job, share, callback)
    callback = type(callback) == 'function' and callback or function() end
    local key = normalizeJob(job)
    if not key then callback(false, shareOverrides) return end

    if share == nil then
        shareOverrides[key] = nil
        exports.oxmysql:execute(('DELETE FROM `%s` WHERE `job` = ?'):format(SHARES_TABLE), { key }, function()
            callback(true, shareOverrides)
        end)
        return
    end

    local normalized = clampShare(share)
    if not normalized then callback(false, shareOverrides) return end
    shareOverrides[key] = normalized
    exports.oxmysql:execute(
        ('INSERT INTO `%s` (`job`, `core_share`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `core_share` = VALUES(`core_share`)'):format(SHARES_TABLE),
        { key, normalized },
        function() callback(true, shareOverrides) end
    )
end

-- Returns { [job] = share, ... } for every job with a live override. Synchronous:
-- the cache is loaded once at boot (CreateThread below) and kept in sync by SetCoreShare.
function JRSJobXP.GetCoreShareOverrides()
    local out = {}
    for job, share in pairs(shareOverrides) do out[job] = share end
    return out
end

function JRSJobXP.GetEffectiveCoreShare(job)
    return coreShare(job)
end

function JRSJobXP.GetDefaultCoreShare()
    return defaultCoreShare()
end

local function charIdOf(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then return nil end
    local user = jrsCore and jrsCore.getUser and jrsCore.getUser(playerSource)
    if user and (user.character or user.getUsedCharacter) and user.getUsedCharacter.charIdentifier then
        return tonumber(user.getUsedCharacter.charIdentifier)
    end
    if jrsCore and type(jrsCore.GetCharacter) == 'function' then
        local char = jrsCore.GetCharacter(playerSource)
        if char and char.charIdentifier then
            return tonumber(char.charIdentifier)
        end
    end
    return nil
end

local function levelDataFor(xp)
    if type(Config.GetLevelData) == 'function' then return Config.GetLevelData(xp) end
    return { level = 1, totalXp = xp or 0, currentXp = xp or 0, requiredXp = 1, progress = 0, isMaxLevel = false }
end

-- Per-job XP shares Config.Levels with the global core level (see header
-- comment), so the same curve gives the XP total for the job's own max level.
local function maxJobXp()
    local level = tonumber(jobConfig().MaxLevel) or Config.MaxLevel
    if type(Config.GetTotalXpForLevel) == 'function' then
        return math.floor(Config.GetTotalXpForLevel(level))
    end
    return math.huge
end

-- Read the stored xp for a (source, job) and hand back (xp, levelData) async.
function JRSJobXP.Get(playerSource, job, callback)
    callback = type(callback) == 'function' and callback or function() end
    local charId = charIdOf(playerSource)
    local key = normalizeJob(job)
    if not charId or not key then callback(0, levelDataFor(0)) return end
    exports.oxmysql:fetch(
        ('SELECT `xp` FROM `%s` WHERE `charidentifier` = ? AND `job` = ? LIMIT 1'):format(jobTable()),
        { charId, key },
        function(rows)
            local xp = (rows and rows[1] and math.max(0, math.floor(tonumber(rows[1].xp) or 0))) or 0
            callback(xp, levelDataFor(xp))
        end
    )
end

-- Return all job levels for a character: { {job, xp, level}, ... } async.
function JRSJobXP.GetAll(playerSource, callback)
    callback = type(callback) == 'function' and callback or function() end
    local charId = charIdOf(playerSource)
    if not charId then callback({}) return end
    exports.oxmysql:fetch(
        ('SELECT `job`, `xp` FROM `%s` WHERE `charidentifier` = ? ORDER BY `job` ASC'):format(jobTable()),
        { charId },
        function(rows)
            local out = {}
            for _, r in ipairs(rows or {}) do
                local xp = math.max(0, math.floor(tonumber(r.xp) or 0))
                out[#out + 1] = { job = tostring(r.job or ''), xp = xp, level = levelDataFor(xp).level }
            end
            callback(out)
        end
    )
end

local function afterWrite(playerSource, job, reason, previousLevel)
    JRSJobXP.Get(playerSource, job, function(xp, data)
        TriggerClientEvent('jrs_core:jobXpUpdated', playerSource, {
            job = job, xp = xp, levelData = data,
            previousLevel = tonumber(previousLevel) or data.level,
            reason = reason,
        })
    end)
end

-- Add (or subtract) job XP with an atomic upsert, then optionally feed the
-- balanced core share into the global level.
function JRSJobXP.Add(playerSource, job, amount, reason, callback)
    callback = type(callback) == 'function' and callback or function() end
    if not isEnabled() then callback(false) return false end
    local charId = charIdOf(playerSource)
    local key = normalizeJob(job)
    amount = math.floor(tonumber(amount) or 0)
    if not charId or not key or amount == 0 then callback(false) return false end

    -- Keep the unboosted award for the core-share calculation. JRSXP.Add applies
    -- the timed multiplier itself, so feeding it the already boosted job amount
    -- would apply x2/x3 twice to the global level.
    local baseAmount = amount
    if amount > 0 and JRSDoubleXP and type(JRSDoubleXP.Apply) == 'function' then
        amount = select(1, JRSDoubleXP.Apply(amount, reason))
    end

    JRSJobXP.Get(playerSource, key, function(_, oldData)
        local prevLevel = oldData.level
        local capXp = maxJobXp()
        local initial = math.min(capXp, math.max(0, amount))
        exports.oxmysql:execute(
            ('INSERT INTO `%s` (`charidentifier`, `job`, `xp`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `xp` = LEAST(%d, GREATEST(0, `xp` + ?))'):format(jobTable(), capXp),
            { charId, key, initial, amount },
            function()
                -- Balanced core contribution: a fixed share of positive job XP.
                if amount > 0 and coreShare(key) > 0 and JRSXP and type(JRSXP.Add) == 'function' then
                    local share = math.floor(baseAmount * coreShare(key))
                    if share > 0 then pcall(JRSXP.Add, playerSource, share, (reason or 'job') .. ':core-share') end
                end
                -- Server-side broadcast so systems that ride on top of job
                -- progress (battle pass, seasonal events) can react without
                -- every one of them having to wrap the export.
                if amount > 0 then
                    TriggerEvent('jrs_core:server:jobXpAdded', playerSource, key, amount, reason)
                end
                afterWrite(playerSource, key, reason, prevLevel)
                callback(true)
            end
        )
    end)
    return true
end

function JRSJobXP.Remove(playerSource, job, amount, reason, callback)
    amount = math.floor(tonumber(amount) or 0)
    return JRSJobXP.Add(playerSource, job, -math.abs(amount), reason, callback)
end

function JRSJobXP.Set(playerSource, job, amount, reason, callback)
    callback = type(callback) == 'function' and callback or function() end
    if not isEnabled() then callback(false) return false end
    local charId = charIdOf(playerSource)
    local key = normalizeJob(job)
    amount = math.min(maxJobXp(), math.max(0, math.floor(tonumber(amount) or 0)))
    if not charId or not key then callback(false) return false end
    exports.oxmysql:execute(
        ('INSERT INTO `%s` (`charidentifier`, `job`, `xp`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `xp` = VALUES(`xp`)'):format(jobTable()),
        { charId, key, amount },
        function()
            afterWrite(playerSource, key, reason, nil)
            callback(true)
        end
    )
    return true
end

-- Exports. Add/Set/Remove are fire-and-forget; the Get* variants block briefly
-- via a promise so admin tools / HUDs can read a value inline.
exports('AddJobXP', function(source, job, amount, reason) return JRSJobXP.Add(source, job, amount, reason) end)
exports('RemoveJobXP', function(source, job, amount, reason) return JRSJobXP.Remove(source, job, amount, reason) end)
exports('SetJobXP', function(source, job, amount, reason) return JRSJobXP.Set(source, job, amount, reason) end)

exports('GetJobXP', function(source, job)
    local p = promise.new()
    JRSJobXP.Get(source, job, function(xp) p:resolve(xp) end)
    return Citizen.Await(p)
end)

exports('GetJobLevel', function(source, job)
    local p = promise.new()
    JRSJobXP.Get(source, job, function(_, data) p:resolve(data and data.level or 1) end)
    return Citizen.Await(p)
end)

exports('GetJobLevelData', function(source, job)
    local p = promise.new()
    JRSJobXP.Get(source, job, function(_, data) p:resolve(data or { level = 1 }) end)
    return Citizen.Await(p)
end)

exports('GetAllJobLevels', function(source)
    local p = promise.new()
    JRSJobXP.GetAll(source, function(rows) p:resolve(rows or {}) end)
    return Citizen.Await(p)
end)

-- Per-job core-share overrides, editable live from jrs_admin (SERVER > LEVEL).
exports('SetJobCoreShare', function(job, share, callback) return JRSJobXP.SetCoreShare(job, share, callback) end)
exports('GetJobCoreShareOverrides', function() return JRSJobXP.GetCoreShareOverrides() end)
exports('GetEffectiveJobCoreShare', function(job) return JRSJobXP.GetEffectiveCoreShare(job) end)
exports('GetDefaultJobCoreShare', function() return JRSJobXP.GetDefaultCoreShare() end)

-- Ensure the per-job level table exists, and the per-job core-share override
-- table too, then load any saved overrides into memory. oxmysql buffers until
-- the DB connects.
CreateThread(function()
    Wait(500)
    exports.oxmysql:execute(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `charidentifier` INT NOT NULL,
            `job` VARCHAR(40) NOT NULL,
            `xp` INT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`charidentifier`, `job`),
            KEY `idx_jrs_job_levels_char` (`charidentifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(jobTable()), {})

    exports.oxmysql:execute(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `job` VARCHAR(40) NOT NULL,
            `core_share` DECIMAL(6,4) NOT NULL DEFAULT 0.25,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(SHARES_TABLE), {}, function()
        exports.oxmysql:fetch(('SELECT `job`, `core_share` FROM `%s`'):format(SHARES_TABLE), {}, function(rows)
            for _, row in ipairs(rows or {}) do
                local key = normalizeJob(row.job)
                local share = clampShare(row.core_share)
                if key and share then shareOverrides[key] = share end
            end
        end)
    end)
end)
