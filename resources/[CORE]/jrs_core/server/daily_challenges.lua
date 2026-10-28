-- JRS / Red Dead Online Daily Challenges Server Module
JRSDaily = JRSDaily or {}

local playerStreaks = {}       -- [charidentifier] = { streakDays = n, lastDate = "YYYY-MM-DD" }
local playerDailyProgress = {}  -- [charidentifier] = { [challengeId] = progress, completed = { [challengeId] = true }, allBonusClaimed = bool }

local function getTodayDate()
    return os.date('%Y-%m-%d')
end

local function getYesterdayDate()
    local yesterdayTime = os.time() - 86400
    return os.date('%Y-%m-%d', yesterdayTime)
end

-- Deterministically select today's challenges based on the day of the year
function JRSDaily.GetTodayChallenges()
    local cfg = Config.DailyChallenges
    if not cfg or not cfg.Enabled then return {} end

    local pool = cfg.ChallengePool or {}
    local count = math.min(#pool, cfg.SlotsCount or 7)
    if count <= 0 then return {} end

    local dayOfYear = tonumber(os.date('%j')) or 1
    local year = tonumber(os.date('%Y')) or 1899
    local seed = (year * 1000) + dayOfYear

    -- Pseudo-random shuffle based on date
    local selected = {}
    local available = {}
    for i, v in ipairs(pool) do available[i] = v end

    local pseudoRandom = function(max)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed % max) + 1
    end

    while #selected < count and #available > 0 do
        local idx = pseudoRandom(#available)
        selected[#selected + 1] = available[idx]
        table.remove(available, idx)
    end

    return selected
end

local function getCharId(playerSource)
    local user = jrsCore and jrsCore.getUser and jrsCore.getUser(playerSource)
    local character = user and (user.character or user.getUsedCharacter)
    return character and character.charIdentifier or nil
end

local function getStreakMultiplier(streakDays)
    local tiers = (Config.DailyChallenges and Config.DailyChallenges.Streak and Config.DailyChallenges.Streak.Tiers) or {}
    for _, tier in ipairs(tiers) do
        if streakDays >= tier.minDays then
            return tier.multiplier
        end
    end
    return 1.0
end

local function ensurePlayerLoaded(playerSource, callback)
    local charId = getCharId(playerSource)
    if not charId then
        if callback then callback(nil) end
        return
    end

    local today = getTodayDate()
    if playerDailyProgress[charId] and playerDailyProgress[charId].date == today then
        if callback then callback(playerDailyProgress[charId]) end
        return
    end

    -- Reset or initialize for today
    playerDailyProgress[charId] = {
        date = today,
        progress = {},
        completed = {},
        allBonusClaimed = false
    }

    if not playerStreaks[charId] then
        playerStreaks[charId] = { streakDays = 0, lastDate = "" }
    end

    local streak = playerStreaks[charId]
    local yesterday = getYesterdayDate()
    if streak.lastDate ~= today and streak.lastDate ~= yesterday and streak.lastDate ~= "" then
        -- Streak broken
        streak.streakDays = 0
    end

    if callback then callback(playerDailyProgress[charId]) end
end

-- Add progress to a challenge type
function JRSDaily.Progress(playerSource, jobKey, count)
    playerSource = tonumber(playerSource)
    count = math.max(1, tonumber(count) or 1)
    if not playerSource or playerSource <= 0 then return end

    local charId = getCharId(playerSource)
    if not charId then return end

    ensurePlayerLoaded(playerSource, function(data)
        if not data then return end
        local todayChallenges = JRSDaily.GetTodayChallenges()

        for _, challenge in ipairs(todayChallenges) do
            if challenge.job == jobKey and not data.completed[challenge.id] then
                local current = (data.progress[challenge.id] or 0) + count
                data.progress[challenge.id] = current

                if current >= challenge.target then
                    -- Mark completed
                    data.completed[challenge.id] = true

                    -- Update streak if first challenge of today
                    local streak = playerStreaks[charId]
                    local today = getTodayDate()
                    if streak.lastDate ~= today then
                        streak.streakDays = streak.streakDays + 1
                        streak.lastDate = today
                        local maxDays = Config.DailyChallenges.Streak.ResetDays or 28
                        if streak.streakDays > maxDays then streak.streakDays = 1 end
                    end

                    -- Calculate rewards with streak multiplier
                    local mult = getStreakMultiplier(streak.streakDays)
                    local baseGold = Config.DailyChallenges.BaseGold or 0.20
                    local baseCash = Config.DailyChallenges.BaseCash or 15.00
                    local baseXp = Config.DailyChallenges.BaseXp or 200

                    local finalGold = math.floor((baseGold * mult) * 100 + 0.5) / 100
                    local finalCash = math.floor((baseCash * mult) * 100 + 0.5) / 100

                    -- Award Gold & Cash & XP
                    pcall(function()
                        if exports.jrs_core and exports.jrs_core.AddGold then
                            exports.jrs_core:AddGold(playerSource, finalGold)
                        end
                        if exports.jrs_core and exports.jrs_core.AddMoney then
                            exports.jrs_core:AddMoney(playerSource, finalCash)
                        end
                        if JRSXP and type(JRSXP.Add) == 'function' then
                            JRSXP.Add(playerSource, baseXp, 'daily-challenge')
                        end
                    end)

                    TriggerClientEvent('jrs_core:sendRightTipNotification', playerSource,
                        string.format("⭐ Challenge Complete: %s! (+%.2f 𝕲 | +$%.2f) [Streak: %d Days (%.1fx)]",
                            challenge.title, finalGold, finalCash, streak.streakDays, mult), 8000)

                    -- Check if all completed for bonus
                    local allDone = true
                    for _, c in ipairs(todayChallenges) do
                        if not data.completed[c.id] then
                            allDone = false
                            break
                        end
                    end

                    if allDone and not data.allBonusClaimed then
                        data.allBonusClaimed = true
                        local bonusGold = Config.DailyChallenges.AllCompletedBonusGold or 0.60
                        local bonusCash = Config.DailyChallenges.AllCompletedBonusCash or 50.00
                        pcall(function()
                            if exports.jrs_core and exports.jrs_core.AddGold then
                                exports.jrs_core:AddGold(playerSource, bonusGold)
                            end
                            if exports.jrs_core and exports.jrs_core.AddMoney then
                                exports.jrs_core:AddMoney(playerSource, bonusCash)
                            end
                        end)

                        TriggerClientEvent('jrs_core:sendRightTipNotification', playerSource,
                            string.format("🏆 ALL 7 DAILY CHALLENGES COMPLETED! (+%.2f 𝕲 | +$%.2f Bonus)",
                                bonusGold, bonusCash), 10000)
                    end
                end
            end
        end
    end)
end

-- Hook into job XP additions (event bus)
AddEventHandler('jrs_core:server:jobXpAdded', function(playerSource, jobKey, amount, reason)
    JRSDaily.Progress(playerSource, jobKey, 1)
end)

-- Generic activity action event
RegisterNetEvent('jrs_core:server:dailyActivity', function(actionKey, count)
    local src = source
    JRSDaily.Progress(src, actionKey, count or 1)
end)

-- Command to view daily challenges
RegisterCommand('challenges', function(source)
    local src = tonumber(source)
    if not src or src <= 0 then return end

    local charId = getCharId(src)
    if not charId then return end

    ensurePlayerLoaded(src, function(data)
        local todayChallenges = JRSDaily.GetTodayChallenges()
        local streak = playerStreaks[charId] or { streakDays = 0 }
        local mult = getStreakMultiplier(streak.streakDays)

        TriggerClientEvent('jrs_core:sendRightTipNotification', src,
            string.format("📅 Daily Challenges (Streak: %d days | %.1fx Gold Multiplier):", streak.streakDays, mult), 7000)

        for i, c in ipairs(todayChallenges) do
            local current = (data and data.progress and data.progress[c.id]) or 0
            local done = data and data.completed and data.completed[c.id]
            local status = done and "✅ COMPLETE" or string.format("(%d/%d)", math.min(c.target, current), c.target)
            TriggerClientEvent('chat:addMessage', src, {
                args = { "Daily Challenge", string.format("%d. %s: %s", i, c.title, status) }
            })
        end
    end)
end, false)

RegisterCommand('daily', function(source)
    ExecuteCommand('challenges')
end, false)

exports('ProgressDailyChallenge', function(playerSource, jobKey, count)
    return JRSDaily.Progress(playerSource, jobKey, count)
end)

exports('GetDailyChallenges', function()
    return JRSDaily.GetTodayChallenges()
end)
