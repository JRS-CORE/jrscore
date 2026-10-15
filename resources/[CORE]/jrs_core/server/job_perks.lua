-- JRS Job Perks - Server Authority
-- ---------------------------------------------------------------------------
-- Computes and serves perks for each job based on its 1..100 level.
-- ---------------------------------------------------------------------------

JRSJobPerks = JRSJobPerks or {}

local function clampLevel(level)
    local maxLevel = tonumber(Config.MaxLevel) or 100
    return math.max(1, math.min(maxLevel, math.floor(tonumber(level) or 1)))
end

local function normalizeJob(job)
    job = tostring(job or ''):lower():gsub('[^%w_]', '')
    if job == '' then return nil end
    return job:sub(1, 40)
end

local function milestoneValue(tbl, level, default)
    local bestLevel, bestValue = -1, default
    for lvl, value in pairs(tbl or {}) do
        local levelNum = tonumber(lvl)
        if levelNum and levelNum <= level and levelNum > bestLevel then
            bestLevel, bestValue = levelNum, value
        end
    end
    return bestValue
end

local function nextMilestone(tbl, level)
    level = clampLevel(level)
    local nextLevel, nextValue
    for lvl, value in pairs(tbl or {}) do
        local levelNum = tonumber(lvl)
        if levelNum and levelNum > level and (not nextLevel or levelNum < nextLevel) then
            nextLevel, nextValue = levelNum, value
        end
    end
    return nextLevel, nextValue
end

--- Returns a table with active calculated perk values for (jobKey, level).
function JRSJobPerks.Get(jobKey, level)
    jobKey = normalizeJob(jobKey)
    if not jobKey then return {} end
    level = clampLevel(level)

    local cfg = (Config.JobPerks and Config.JobPerks.Jobs and Config.JobPerks.Jobs[jobKey]) or nil
    if not cfg or type(cfg.perks) ~= 'table' then return {} end

    local out = { job = jobKey, level = level }
    for _, perk in ipairs(cfg.perks) do
        out[perk.key] = milestoneValue(perk.milestones, level, 0)
    end
    return out
end

--- Builds structured rows for NUI (pause menu LEVELS tab).
--- Row: key, name, name_ar, kind, value, fromLevel, nextLevel, nextValue
function JRSJobPerks.Overview(jobKey, level)
    jobKey = normalizeJob(jobKey)
    if not jobKey then return nil end
    level = clampLevel(level)

    local cfg = (Config.JobPerks and Config.JobPerks.Jobs and Config.JobPerks.Jobs[jobKey]) or nil
    if not cfg or type(cfg.perks) ~= 'table' then return nil end

    local rows = {}
    for _, perk in ipairs(cfg.perks) do
        local fromLevel = 1
        for l in pairs(perk.milestones or {}) do
            local lNum = tonumber(l)
            if lNum and lNum <= level and lNum > fromLevel then fromLevel = lNum end
        end
        local nextLevel, nextValue = nextMilestone(perk.milestones, level)
        local val = milestoneValue(perk.milestones, level, 0)
        rows[#rows + 1] = {
            key = perk.key,
            name = perk.name,
            name_ar = perk.name_ar,
            kind = perk.kind or 'percent',
            value = val,
            fromLevel = fromLevel,
            nextLevel = nextLevel,
            nextValue = nextValue,
        }
    end

    return { job = jobKey, level = level, rows = rows }
end

-- Key for the payout perk of each job
local PAY_PERK_KEYS = {
    beekeeping = 'royal_jelly_payout',
    boats = 'voyage_pay',
    bounty = 'bounty_pay',
    business = 'order_revenue',
    chimneysweep = 'sweep_pay',
    surfacecleaner = 'sweep_pay',
    delivery = 'tip_bonus',
    doctor = 'healing_pay',
    farming = 'market_produce',
    fight = 'purse_bonus',
    fishing = 'fish_sell',
    herbs = 'apothecary_bonus',
    hunting = 'butcher_bonus',
    lumberjack = 'sawmill_bonus',
    metal_detector = 'artifact_value',
    mining = 'gold_nugget_payout',
    moonshiner = 'batch_payout',
    organizations = 'turf_income',
    police = 'patrol_salary',
    randomquests = 'quest_payout',
    stable = 'horse_sale',
    train = 'rail_pay',
    trash = 'trash_pay',
}

--- Applies job payout perk to reward amounts.
function JRSJobPerks.ApplyJobPayBonus(playerSource, jobKey, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return amount end
    jobKey = normalizeJob(jobKey)
    if not jobKey then return amount end

    local perkKey = PAY_PERK_KEYS[jobKey]
    if not perkKey then return amount end

    -- Read the live, server-authoritative job level via the synchronous export.
    local jobLevel = 1
    local ok, level = pcall(function() return exports.jrs_core:GetJobLevel(playerSource, jobKey) end)
    if ok and tonumber(level) then jobLevel = tonumber(level) end

    local cfg = Config.JobPerks and Config.JobPerks.Jobs and Config.JobPerks.Jobs[jobKey]
    if not cfg or type(cfg.perks) ~= 'table' then return amount end

    local rate = 0
    for _, perk in ipairs(cfg.perks) do
        if perk.key == perkKey then
            rate = milestoneValue(perk.milestones, jobLevel, 0)
            break
        end
    end

    if rate <= 0 then return amount end
    return math.max(amount, math.floor(amount * (1 + rate)))
end

-- Exports
exports('GetJobPerksOverview', function(jobKey, level) return JRSJobPerks.Overview(jobKey, level) end)
exports('GetJobPerks', function(jobKey, level) return JRSJobPerks.Get(jobKey, level) end)
exports('ApplyJobPayBonus', function(playerSource, jobKey, amount) return JRSJobPayBonus and JRSJobPayBonus(playerSource, jobKey, amount) or JRSJobPerks.ApplyJobPayBonus(playerSource, jobKey, amount) end)
