-- =====================================================================
-- JRS - PER-JOB XP (client)
-- =====================================================================
-- server/job_xp.lua fires 'jrs_core:jobXpUpdated' after every per-job XP
-- write, but nothing was listening: players earned job levels with no
-- feedback at all, which made the whole 1..100 per-job system invisible.
--
-- This is the receiving end. It only speaks up on an actual level change,
-- so ordinary XP gains stay silent and the chat/toast is not spammed.
-- =====================================================================

local lastLevel = {}   -- job -> last level we told the player about
local lastXp = {}      -- job -> last XP value seen, used to compute the delta

-- Localized job labels
local JOB_NAMES = {
    lumberjack     = { en = 'Lumberjack',     ar = 'الحطاب' },
    woodcutter     = { en = 'Woodcutter',     ar = 'الحطاب' },
    mining         = { en = 'Mining',         ar = 'التعدين' },
    miner          = { en = 'Miner',          ar = 'عامل المناجم' },
    fishing        = { en = 'Fishing',        ar = 'صيد الأسماك' },
    fisherman      = { en = 'Fisherman',      ar = 'صياد السمك' },
    hunting        = { en = 'Hunting',        ar = 'الصيد والسلخ' },
    hunter         = { en = 'Hunter',         ar = 'الصياد' },
    herbs          = { en = 'Herbalism',      ar = 'الأعشاب والطبابة' },
    herbalism      = { en = 'Herbalism',      ar = 'الأعشاب والطبابة' },
    farming        = { en = 'Farming',        ar = 'الزراعة والحصاد' },
    farmer         = { en = 'Farmer',         ar = 'المزارع' },
    chicken        = { en = 'Poultry Butcher',ar = 'عامل الدواجن' },
    delivery       = { en = 'Delivery',       ar = 'ساعي التوصيل' },
    courier        = { en = 'Courier',        ar = 'ساعي التوصيل' },
    surfacecleaner = { en = 'Surface Cleaner',ar = 'عامل تنظيف الأسطح' },
    chimneysweep   = { en = 'Chimney Sweep',  ar = 'تنظيف الأسطح والمداخن' },
    metal_detector = { en = 'Metal Detector', ar = 'كاشف المعادن' },
    business       = { en = 'Business',       ar = 'الأعمال والتجارة' },
    crafting       = { en = 'Crafting',       ar = 'الحِرفة والتصنيع' },
    fight          = { en = 'Fight Club',     ar = 'نادي القتال' },
    moonshiner     = { en = 'Moonshiner',     ar = 'صانع المونشاين' },
    organizations  = { en = 'Organizations',  ar = 'المنظمات' },
    stable         = { en = 'Stable Hand',    ar = 'مربي الخيول' },
    trash          = { en = 'Trash Collector',ar = 'جامع النفايات' },
    beekeeping     = { en = 'Beekeeping',     ar = 'تربية النحل' },
    beekeeper      = { en = 'Beekeeper',      ar = 'نحال' },
    bounty         = { en = 'Bounty Hunter',  ar = 'صائد الجوائز' },
    bountyhunter   = { en = 'Bounty Hunter',  ar = 'صائد الجوائز' },
    police         = { en = 'Police',         ar = 'الشرطة' },
    sheriff        = { en = 'Sheriff',        ar = 'الشرطة' },
    doctor         = { en = 'Doctor',         ar = 'الطبيب' },
    medic          = { en = 'Medic',          ar = 'الطبيب' },
    train          = { en = 'Train',          ar = 'القطار' },
    truck          = { en = 'Truck',          ar = 'الشاحنات' },
    boat           = { en = 'Boats',          ar = 'القوارب' },
    boats          = { en = 'Boats',          ar = 'القوارب' },
    newspaper      = { en = 'Newspaper',      ar = 'الصحافة' },
    battlepass     = { en = 'Battle Pass',    ar = 'تذكرة المعركة' },
    blacksmith     = { en = 'Blacksmith',     ar = 'الحداد' },
}

local function prettyJob(job)
    job = tostring(job or '')
    if job == '' then return 'Job' end
    local key = job:lower():gsub('^jrs_', ''):gsub('^jrs%-', '')
    local isAr = (type(JrsLang) == 'table' and type(JrsLang.Current) == 'function' and JrsLang.Current() == 'ar')
        or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.jrsLanguage == 'ar')

    if isAr then
        if JOB_NAMES[key] and JOB_NAMES[key].ar then return JOB_NAMES[key].ar end
        if Config.JobPerks and Config.JobPerks.Jobs and Config.JobPerks.Jobs[key] and Config.JobPerks.Jobs[key].label_ar then
            return Config.JobPerks.Jobs[key].label_ar
        end
    else
        if JOB_NAMES[key] and JOB_NAMES[key].en then return JOB_NAMES[key].en end
        if Config.JobPerks and Config.JobPerks.Jobs and Config.JobPerks.Jobs[key] and Config.JobPerks.Jobs[key].label then
            return Config.JobPerks.Jobs[key].label
        end
    end

    local name = job:gsub('[_%-]+', ' ')
    return (name:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

local function notify(text, title)
    if type(CoreNotifications) ~= 'table' then return end
    if type(CoreNotifications.NotifyLeft) == 'function' then
        -- Title travels through CoreNotifications.Label, so this picks up the
        -- server branding automatically.
        CoreNotifications.NotifyLeft(title, text, 'menu_textures', 'menu_icon_level_up', 5000, 'COLOR_WHITE')
        return
    end
    if type(CoreNotifications.NotifyRightTip) == 'function' then
        CoreNotifications.NotifyRightTip(text, 5000)
    end
end

-- XP gain uses the same left notification + level-up icon as level-ups, so the
-- two read as the same family (falls back to a right-tip if unused).
local function notifyXpGain(job, amount)
    if type(CoreNotifications) ~= 'table' then return end
    local amt = math.floor(amount)
    local jobName = prettyJob(job)
    local text = nil
    if type(_U) == 'function' then
        local formatted = _U('core_job_xp_gain', amt, jobName)
        if formatted and formatted ~= 'core_job_xp_gain' then
            text = formatted
        end
    end
    if not text then
        text = ('+%d %s XP'):format(amt, jobName)
    end
    if type(CoreNotifications.NotifyLeft) == 'function' then
        CoreNotifications.NotifyLeft(_U('core_xp_gained'), text, 'menu_textures', 'menu_icon_level_up', 5000, 'COLOR_WHITE')
        return
    end
    if type(CoreNotifications.NotifyRightTip) == 'function' then
        CoreNotifications.NotifyRightTip(text, 5000)
    end
end

RegisterNetEvent('jrs_core:jobXpUpdated', function(payload)
    if type(payload) ~= 'table' then return end

    local job = tostring(payload.job or '')
    if job == '' then return end

    local data = type(payload.levelData) == 'table' and payload.levelData or {}
    local level = tonumber(data.level)
    if level == nil then return end

    local previous = tonumber(payload.previousLevel) or level
    local totalXp = math.max(0, math.floor(tonumber(payload.xp) or 0))

    -- XP gain feedback: report the delta once we have a baseline for this job.
    if lastXp[job] ~= nil then
        local change = totalXp - lastXp[job]
        if change > 0 then notifyXpGain(job, change) end
    elseif totalXp > 0 then
        notifyXpGain(job, totalXp)
    end
    lastXp[job] = totalXp

    -- First message for this job in the session just records where we are; only
    -- a genuine change after that is worth interrupting the player for.
    if lastLevel[job] == nil then
        lastLevel[job] = level
        if level <= previous then return end
    end

    if level > previous and level > (lastLevel[job] or 0) then
        lastLevel[job] = level
        if data.isMaxLevel == true then
            notify((_U('core_job_level_max_reached')):format(prettyJob(job)), _U('core_level_up'))
        else
            notify((_U('core_reached_level')):format(prettyJob(job), level, ''), _U('core_level_up'))
        end
    elseif level < previous then
        -- XP was removed (admin correction), so keep our record honest without
        -- telling the player they levelled.
        lastLevel[job] = level
    end
end)

-- Exposed so a HUD or menu can read the last level it saw without another
-- round trip to the server.
exports('GetLastKnownJobLevel', function(job)
    return lastLevel[tostring(job or '')]
end)
