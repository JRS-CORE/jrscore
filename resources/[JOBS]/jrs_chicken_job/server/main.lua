local Active = {}
local Starting = {}

local function nowMs()
    return os.time() * 1000
end

-- v3.3.0 security: every reward event is checked against the mission's own
-- progress counters, the player's real server-side position and a minimum
-- time between steps. Before, any client could fire grantProducts/complete
-- straight after starting and collect items and money for work never done.
local Guard = {
    npcRadius = 25.0,        -- start: near the hub NPC
    catchRadius = 120.0,     -- load chicken: near the catch zone / its parking
    butcherRadius = 75.0,    -- slaughter: near the butcher site / wagon station
    cutRadius = 20.0,        -- cut products: near the cutting table
    deliveryRadius = 70.0,   -- complete: near the delivery point
    loadGapMs = 1000,        -- between two chickens loaded on the wagon
    killGapMs = 1500,        -- between two slaughters
    minMissionSec = 15,      -- whole mission can't be faster than this
}

local function gameMs()
    return GetGameTimer()
end

local function playerPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if not c or (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then return nil end
    return c
end

-- Position not readable (no OneSync entity yet) -> don't block the player.
local function isNear(src, targets, radius)
    local pos = playerPos(src)
    if not pos then return true end
    for _, t in ipairs(targets) do
        if t and #(vector3(pos.x, pos.y, pos.z) - vector3(t.x, t.y, t.z)) <= radius then
            return true
        end
    end
    return false
end

local function getButcherSite(id)
    for _, s in ipairs(Config.ButcherSites or {}) do
        if s.id == id then return s end
    end
    return nil
end

local function flag(src, m, what)
    m.flags = (m.flags or 0) + 1
    print(('[jrs_chicken_job] ^3blocked^7 %s from player %s (%s) flags=%d'):format(what, src, GetPlayerName(src) or '?', m.flags))
    if m.flags == 3 then
        JRSBridge.Discord('Chicken Job Suspicious', ('Player: %s\nLast blocked: %s'):format(GetPlayerName(src) or src, what))
    end
end

MySQL.ready(function()
    pcall(function()
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `jrs_chicken_cooldowns` (
                `identifier` varchar(100) NOT NULL,
                `last_mission` bigint NOT NULL DEFAULT 0,
                PRIMARY KEY (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)
    pcall(function()
        MySQL.query([[
            INSERT INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
            ('chicken_thigh', 'Chicken Thigh', 'فخذ دجاج', 0.25, 1, 'item_standard', 1, 'Raw chicken thigh', 'فخذ دجاج نيء طازج', '0', 'food'),
            ('chicken_wing', 'Chicken Wing', 'جناح دجاج', 0.25, 1, 'item_standard', 1, 'Raw chicken wing', 'جناح دجاج نيء طازج', '0', 'food'),
            ('chicken_breast', 'Chicken Breast', 'صدر دجاج', 0.25, 1, 'item_standard', 1, 'Raw chicken breast', 'صدر دجاج نيء طازج', '0', 'food'),
            ('chicken_drumstick', 'Chicken Drumstick', 'ساق دجاج', 0.25, 1, 'item_standard', 1, 'Raw chicken drumstick', 'ساق دجاج نيء طازج', '0', 'food'),
            ('Feather', 'Feather', 'ريش دجاج', 0.25, 1, 'item_standard', 1, 'Raw chicken feather', 'ريش دجاج طازج', '0', 'materials')
            ON DUPLICATE KEY UPDATE `limit` = VALUES(`limit`), `label` = VALUES(`label`), `label_ar` = VALUES(`label_ar`);
        ]])
    end)
    -- Clear any existing cooldowns so players can work immediately
    pcall(function()
        MySQL.query('TRUNCATE TABLE `jrs_chicken_cooldowns`;')
    end)
end)

local function getCooldown(identifier)
    if not Config.MissionCooldown or not Config.MissionCooldown.enabled then return 0 end
    local cooldownMins = tonumber(Config.MissionCooldown.minutes) or 0
    if cooldownMins <= 0 then return 0 end
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT last_mission FROM jrs_chicken_cooldowns WHERE identifier = ?', { identifier })
    end)
    if not ok or not row then return 0 end
    local last = tonumber(row.last_mission) or 0
    local cooldown = cooldownMins * 60 * 1000
    return math.max(0, (last + cooldown) - nowMs())
end

local function saveCooldown(identifier)
    if not Config.MissionCooldown or not Config.MissionCooldown.enabled then return end
    local cooldownMins = tonumber(Config.MissionCooldown.minutes) or 0
    if cooldownMins <= 0 then return end
    pcall(function()
        MySQL.update.await([[
            INSERT INTO jrs_chicken_cooldowns (identifier, last_mission)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE last_mission = VALUES(last_mission)
        ]], { identifier, nowMs() })
    end)
end

-- Do NOT impose cooldown on cancel / fail / premature end
local function endMission(src, m)
    Active[src] = nil
end

-- Shared "is this still a valid mission" check. Returns the mission or nil.
local function getMission(src)
    local m = Active[src]
    if not m then return nil end
    if not JRSBridge.HasRequiredJob(src) then
        endMission(src, m)
        TriggerClientEvent('jrs_chicken_job:client:startDenied', src, 'job')
        return nil
    end
    return m
end

RegisterNetEvent('jrs_chicken_job:server:requestStart', function(hubId)
    local src = source
    if type(hubId) ~= 'string' then return end
    local hub = Config.GetJobHub(hubId)
    if not hub then return end

    if Active[src] or Starting[src] then
        TriggerClientEvent('jrs_chicken_job:client:startDenied', src, 'active')
        return
    end
    if hub.npc and hub.npc.coords and not isNear(src, { hub.npc.coords }, Guard.npcRadius) then return end

    -- Lock across the DB await so two quick requests can't both start.
    Starting[src] = true

    local hasJob, reason, currentVal, requiredVal = JRSBridge.HasRequiredJob(src)
    if not hasJob then
        Starting[src] = nil
        TriggerClientEvent('jrs_chicken_job:client:startDenied', src, reason or 'job', currentVal, requiredVal)
        return
    end

    local identifier = JRSBridge.GetIdentifier(src)
    local remaining = getCooldown(identifier)
    if remaining > 0 then
        Starting[src] = nil
        TriggerClientEvent('jrs_chicken_job:client:startDenied', src, 'cooldown', remaining)
        return
    end
    if not GetPlayerName(src) then Starting[src] = nil return end

    local catchIndex = math.random(1, #hub.catchZones)
    local deliveryIndex = math.random(1, #hub.deliveryPoints)

    Active[src] = {
        identifier = identifier,
        hubId = hubId,
        catchIndex = catchIndex,
        deliveryIndex = deliveryIndex,
        catches = 0,
        killed = 0,
        processed = 0,
        catchDone = false,
        chestLoaded = false,
        started = os.time(),
        lastLoad = 0,
        lastKill = 0,
        flags = 0,
    }
    Starting[src] = nil

    TriggerClientEvent('jrs_chicken_job:client:startApproved', src, hubId, catchIndex, deliveryIndex)
    JRSBridge.Discord('Chicken Job Started', ('Player: %s\nHub: %s'):format(GetPlayerName(src) or src, hubId))
end)

RegisterNetEvent('jrs_chicken_job:server:chickenLoaded', function()
    local src = source
    local m = getMission(src)
    if not m then return end
    if m.catches >= Config.ChickensRequired then return flag(src, m, 'chickenLoaded over cap') end
    if gameMs() - m.lastLoad < Guard.loadGapMs then return flag(src, m, 'chickenLoaded too fast') end

    local hub = Config.GetJobHub(m.hubId)
    local zone = hub and hub.catchZones[m.catchIndex]
    local parking = hub and hub.catchParking and hub.catchParking[m.catchIndex]
    if zone and not isNear(src, { zone, parking }, Guard.catchRadius) then
        return flag(src, m, 'chickenLoaded away from catch zone')
    end

    m.lastLoad = gameMs()
    m.catches = m.catches + 1
    JRSBridge.AddXP(src, 'loadChicken')
end)

RegisterNetEvent('jrs_chicken_job:server:catchComplete', function()
    local src = source
    local m = getMission(src)
    if not m then return end
    -- Before: no cap at all -> unlimited catchComplete XP.
    if m.catchDone then return end
    if m.catches < Config.ChickensRequired then return flag(src, m, 'catchComplete early') end
    m.catchDone = true
    JRSBridge.AddXP(src, 'catchComplete')
end)

RegisterNetEvent('jrs_chicken_job:server:chickenKilled', function()
    local src = source
    local m = getMission(src)
    if not m then return end
    -- One chicken at a time: it must have been loaded, and the previous one cut.
    if m.killed >= m.catches or m.killed > m.processed then return flag(src, m, 'chickenKilled out of order') end
    if gameMs() - m.lastKill < Guard.killGapMs then return flag(src, m, 'chickenKilled too fast') end

    local hub = Config.GetJobHub(m.hubId)
    local site = hub and getButcherSite(hub.butcherSiteId)
    if site and not isNear(src, { site.coords, site.wagonStation }, Guard.butcherRadius) then
        return flag(src, m, 'chickenKilled away from butcher')
    end

    m.lastKill = gameMs()
    m.killed = m.killed + 1
    JRSBridge.AddXP(src, 'killChicken')
end)

RegisterNetEvent('jrs_chicken_job:server:grantProducts', function()
    local src = source
    local m = getMission(src)
    if not m then return end

    -- Nothing new to cut: answer with the current count so a client retry
    -- (lost reply) resyncs without granting anything twice.
    if m.processed >= Config.ChickensRequired or m.processed >= m.killed then
        TriggerClientEvent('jrs_chicken_job:client:productsGranted', src, m.processed, true)
        return
    end

    local cutStep = ((Config.ProcessStation or {}).steps or {}).cut or {}
    local minCutMs = math.floor((tonumber(cutStep.time) or 7000) * 0.9)
    if gameMs() - m.lastKill < minCutMs then return flag(src, m, 'grantProducts too fast') end

    local hub = Config.GetJobHub(m.hubId)
    local station = hub and Config.GetCutStation(hub.cutSiteId or hub.butcherSiteId)
    if station and station.table and station.table.coords
        and not isNear(src, { station.table.coords }, Guard.cutRadius) then
        return flag(src, m, 'grantProducts away from cut table')
    end

    -- Count first, then pay out, so a re-entrant call can't double up.
    m.processed = m.processed + 1

    local allOk = true
    for _, p in ipairs(cutStep.products or {}) do
        local min = tonumber(p.amount and p.amount.min) or 1
        local max = tonumber(p.amount and p.amount.max) or min
        local amount = math.random(min, max)
        if not JRSBridge.AddItem(src, p.item, amount) then
            allOk = false
        end
    end

    JRSBridge.AddXP(src, 'cutChicken')
    TriggerClientEvent('jrs_chicken_job:client:productsGranted', src, m.processed, allOk)
end)

RegisterNetEvent('jrs_chicken_job:server:chestOnWagon', function()
    local src = source
    local m = getMission(src)
    if not m then return end
    if m.chestLoaded then return end
    if m.processed < Config.ChickensRequired then return flag(src, m, 'chestOnWagon early') end
    m.chestLoaded = true
    JRSBridge.AddXP(src, 'chestOnWagon')
end)

RegisterNetEvent('jrs_chicken_job:server:complete', function()
    local src = source
    local m = getMission(src)
    if not m then return end

    local deny
    if m.processed < Config.ChickensRequired then
        deny = 'complete before all chickens were cut'
    elseif os.time() - (m.started or 0) < Guard.minMissionSec then
        deny = 'complete too fast'
    else
        local hub = Config.GetJobHub(m.hubId)
        local point = hub and hub.deliveryPoints[m.deliveryIndex]
        if point and not isNear(src, { point }, Guard.deliveryRadius) then
            deny = 'complete away from delivery point'
        end
    end
    if deny then
        flag(src, m, deny)
        TriggerClientEvent('jrs_core:sendRightTipNotification', src, 'يرجى الاقتراب أكثر من نقطة التسليم لإكمال المهمة', 5000)
        return
    end

    -- Close the mission before paying so a duplicate event finds nothing.
    Active[src] = nil

    local min = tonumber(Config.Delivery.payment.min) or 12.0
    local max = tonumber(Config.Delivery.payment.max) or min
    local payment
    if min == max then
        payment = min
    elseif math.floor(min) == min and math.floor(max) == max then
        payment = math.random(math.floor(min), math.floor(max))
    else
        payment = math.random(math.floor(min * 100), math.floor(max * 100)) / 100.0
    end

    JRSBridge.AddMoney(src, payment)
    JRSBridge.AddXP(src, 'missionComplete')
    saveCooldown(m.identifier)

    JRSBridge.Discord('Chicken Job Completed', ('Player: %s\nHub: %s\nPayment: $%.2f'):format(GetPlayerName(src) or src, tostring(m.hubId), payment))
    TriggerClientEvent('jrs_chicken_job:client:completed', src, payment)
end)

RegisterNetEvent('jrs_chicken_job:server:fail', function(reason)
    local src = source
    local m = Active[src]
    if not m then return end
    endMission(src, m)
    reason = tostring(reason or 'unknown'):sub(1, 48):gsub('[^%w_%-]', '')
    JRSBridge.Discord('Chicken Job Failed', ('Player: %s\nReason: %s'):format(GetPlayerName(src) or src, reason))
end)

RegisterNetEvent('jrs_chicken_job:server:cancel', function()
    local src = source
    local m = Active[src]
    if not m then return end
    endMission(src, m)
    JRSBridge.Discord('Chicken Job Cancelled', ('Player: %s\nHub: %s'):format(GetPlayerName(src) or src, m.hubId or 'unknown'))
end)

AddEventHandler('playerDropped', function()
    local src = source
    Starting[src] = nil
    local m = Active[src]
    if m then endMission(src, m) end
end)

RegisterNetEvent('jrs_chicken_job:server:requestJob', function()
    local src = source
    local job = JRSBridge.GetJob(src)
    TriggerClientEvent('jrs_chicken_job:client:setJob', src, job)
end)

local function handleServerJobChange(src, newJob)
    src = tonumber(src)
    if not src then return end
    local currentJob = JRSBridge.GetJob(src)
    TriggerClientEvent('jrs_chicken_job:client:setJob', src, currentJob)

    if Active[src] then
        local req = string.lower(Config.JobCheck.job or 'chicken')
        if currentJob ~= req then
            endMission(src, Active[src])
            TriggerClientEvent('jrs_chicken_job:client:startDenied', src, 'job')
            TriggerClientEvent('jrs_chicken_job:client:cancelMission', src)
            JRSBridge.Discord('Chicken Job Cancelled (Job Changed)', ('Player: %s\nNew Job: %s'):format(GetPlayerName(src) or src, currentJob))
        end
    end
end

AddEventHandler('jrs_core:server:jobChanged', function(src, job, grade)
    handleServerJobChange(src, job)
end)

AddEventHandler('jrs:setJob', function(src, job, grade)
    handleServerJobChange(src, job)
end)

RegisterCommand('chicken_reset_cooldown', function(source, args, raw)
    local src = source
    if src > 0 then
        local identifier = JRSBridge.GetIdentifier(src)
        pcall(function()
            MySQL.query.await('DELETE FROM jrs_chicken_cooldowns WHERE identifier = ?', { identifier })
        end)
        TriggerClientEvent('jrs_core:sendRightTipNotification', src, 'تم تصفير وقت الانتظار لمهمة الدجاج', 5000)
    else
        pcall(function()
            MySQL.query.await('TRUNCATE TABLE jrs_chicken_cooldowns;')
        end)
        print('[jrs_chicken_job] All chicken cooldowns cleared.')
    end
end, false)

