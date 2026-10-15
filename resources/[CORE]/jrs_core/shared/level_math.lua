-- ============================================================================
-- JRS_CORE LEVEL & PERK MATHEMATICS (SHARED)
-- ============================================================================
Config = Config or {}

if Config.Levels and Config.MaxLevel then
    for rank = 100, Config.MaxLevel - 1 do
        Config.Levels[rank] = Config.Levels[rank] or (6100 + ((rank - 99) * 50))
    end
    Config.Levels[Config.MaxLevel] = 0
end

function Config.GetRoleLevelData(totalRoleXp)
    totalRoleXp = math.max(0, math.floor(tonumber(totalRoleXp) or 0))
    local roleMax = tonumber(Config.RoleMaxLevel) or 20
    local rankXp = tonumber(Config.RoleRankXP) or 2000
    local maxRoleXp = roleMax * rankXp
    if totalRoleXp >= maxRoleXp then
        return {
            totalXp = maxRoleXp,
            level = roleMax,
            currentXp = rankXp,
            requiredXp = rankXp,
            tier = "Distinguished",
            tokens = 8,
            progress = 100,
            isMaxLevel = true,
        }
    end

    local level = math.floor(totalRoleXp / rankXp) + 1
    local currentXp = totalRoleXp % rankXp
    local tierName = "Novice"
    local totalTokens = 0
    for _, t in ipairs(Config.RoleTiers or {}) do
        if level >= t.min and level <= t.max then
            tierName = t.name
        end
        if level >= t.min then
            totalTokens = totalTokens + t.tokens
        end
    end

    return {
        totalXp = totalRoleXp,
        level = level,
        currentXp = currentXp,
        requiredXp = rankXp,
        tier = tierName,
        tokens = totalTokens,
        progress = math.floor((currentXp / rankXp) * 100),
        isMaxLevel = false,
    }
end

local function normalizeTotalXp(totalXp)
    totalXp = math.floor(tonumber(totalXp) or 0)
    if totalXp < 0 then return 0 end
    return totalXp
end

function Config.GetTotalXpForLevel(level)
    local maxLevel = tonumber(Config.MaxLevel) or 100
    level = math.floor(tonumber(level) or 1)
    if level <= 1 then return 0 end
    if level > maxLevel then level = maxLevel end

    local total = 0
    for currentLevel = 1, level - 1 do
        total = total + math.max(0, tonumber(Config.Levels and Config.Levels[currentLevel]) or 0)
    end
    return total
end

function Config.GetMaximumXp()
    return Config.GetTotalXpForLevel(Config.MaxLevel or 100)
end

function Config.GetLevelData(totalXp)
    local normalizedXp = normalizeTotalXp(totalXp)
    local maximumXp = Config.GetMaximumXp()
    local maxLevel = tonumber(Config.MaxLevel) or 100

    if normalizedXp >= maximumXp then
        return {
            totalXp = maximumXp,
            level = maxLevel,
            currentXp = 0,
            requiredXp = 0,
            levelStartXp = maximumXp,
            nextLevelTotalXp = maximumXp,
            progress = 100,
            isMaxLevel = true,
        }
    end

    local remainingXp = normalizedXp
    local levelStartXp = 0

    for level = 1, maxLevel - 1 do
        local requiredXp = math.max(1, tonumber(Config.Levels and Config.Levels[level]) or 1)
        if remainingXp < requiredXp then
            return {
                totalXp = normalizedXp,
                level = level,
                currentXp = remainingXp,
                requiredXp = requiredXp,
                levelStartXp = levelStartXp,
                nextLevelTotalXp = levelStartXp + requiredXp,
                progress = math.floor((remainingXp / requiredXp) * 100),
                isMaxLevel = false,
            }
        end

        remainingXp = remainingXp - requiredXp
        levelStartXp = levelStartXp + requiredXp
    end

    return {
        totalXp = maximumXp,
        level = maxLevel,
        currentXp = 0,
        requiredXp = 0,
        levelStartXp = maximumXp,
        nextLevelTotalXp = maximumXp,
        progress = 100,
        isMaxLevel = true,
    }
end

local function clampLevel(level)
    local maxLevel = tonumber(Config.MaxLevel) or 100
    return math.max(1, math.min(maxLevel, math.floor(tonumber(level) or 1)))
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

function Config.LevelPerksNextMilestone(tbl, level)
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

function Config.LevelPerksCarryKg(level)
    local c = (Config.LevelPerks or {}).Carry or {}
    local minKg = tonumber(c.MinKg) or 50
    local maxKg = tonumber(c.MaxKg) or minKg
    local maxAt = math.max(2, tonumber(c.MaxAtLevel) or 100)
    level = clampLevel(level)
    local t = math.min(1, (level - 1) / (maxAt - 1))
    local kg = minKg + (maxKg - minKg) * t
    local step = math.max(1, tonumber(c.RoundToKg) or 1)
    kg = math.floor(kg / step) * step
    if level >= maxAt then kg = maxKg end
    return math.max(minKg, math.min(maxKg, kg))
end

function Config.ComputeLevelPerks(level)
    level = clampLevel(level)
    local p = Config.LevelPerks or {}
    local move = p.Movement or {}
    return {
        level = level,
        carryKg = Config.LevelPerksCarryKg(level),
        weaponSlots = math.floor(tonumber(milestoneValue(p.WeaponSlots, level, 4)) or 4),
        freeRun = level >= (tonumber(move.FreeRunLevel) or 40),
        shopDiscount = tonumber(milestoneValue(p.ShopDiscount, level, 0)) or 0,
        sellBonus = tonumber(milestoneValue(p.SellBonus, level, 0)) or 0,
        taxReduction = tonumber(milestoneValue(p.TaxReduction, level, 0)) or 0,
        bankFeeReduction = tonumber(milestoneValue(p.BankFeeReduction, level, 0)) or 0,
        rewardBonus = tonumber(milestoneValue(p.RewardBonus, level, 0)) or 0,
        doctorFeeReduction = tonumber(milestoneValue(p.DoctorFeeReduction, level, 0)) or 0,
        stableFeeReduction = tonumber(milestoneValue(p.StableFeeReduction, level, 0)) or 0,
        travelDiscount = tonumber(milestoneValue(p.TravelDiscount, level, 0)) or 0,
        staminaDrainReduction = tonumber(milestoneValue(p.StaminaDrainReduction, level, 0)) or 0,
    }
end

function Config.LevelPerksMoveSpeed(perks, carriedKg)
    local move = (Config.LevelPerks or {}).Movement or {}
    if type(perks) ~= 'table' or perks.freeRun then return 0.0 end
    local capacity = math.max(1, tonumber(perks.carryKg) or 50)
    local percent = (math.max(0, tonumber(carriedKg) or 0) / capacity) * 100

    local chosen, chosenPercent = nil, -1
    for _, tier in ipairs(move.Tiers or {}) do
        local tp, ts = tonumber(tier.percent), tonumber(tier.speed)
        if tp and ts and percent >= tp and tp > chosenPercent then
            chosen, chosenPercent = ts, tp
        end
    end
    if not chosen then return 0.0 end

    local freeAt = math.max(2, tonumber(move.FreeRunLevel) or 40)
    local relief = math.max(0, math.min(1, ((tonumber(perks.level) or 1) - 1) / (freeAt - 1)))
    relief = relief * math.max(0, math.min(1, tonumber(move.MaxRelief) or 0))
    local speed = chosen + (3.0 - chosen) * relief
    if speed >= 2.95 then return 0.0 end
    return math.max(1.0, math.min(3.0, speed))
end

function Config.GetRolePerks(jobName, currentLevel)
    local normalized = string.lower(tostring(jobName or ''))
    local role = Config.RolePerks and Config.RolePerks[normalized]
    if not role then return {} end
    local unlocked = {}
    for reqLvl, perk in pairs(role) do
        if type(reqLvl) == 'number' and currentLevel >= reqLvl then
            table.insert(unlocked, { level = reqLvl, name = perk.name, desc = perk.desc, tier = perk.tier })
        end
    end
    table.sort(unlocked, function(a, b) return a.level < b.level end)
    return unlocked
end

function Config.GetCharacterPerks(currentRank)
    currentRank = tonumber(currentRank) or 1
    local unlocked = {}
    for rank, perk in pairs(Config.CharacterPerks or {}) do
        if currentRank >= rank then
            table.insert(unlocked, { rank = rank, title = perk.title, desc = perk.desc, icon = perk.icon })
        end
    end
    table.sort(unlocked, function(a, b) return a.rank < b.rank end)
    return unlocked
end

