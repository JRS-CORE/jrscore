-- JRS level perks - server authority.
-- ---------------------------------------------------------------------------
-- Numbers live in config/level_perks.lua. This file:
--   * keeps one perks table per player, computed from the cached core level
--   * publishes it on the replicated player state bag `jrsPerks` so other
--     resources (and their clients) read it without an export round-trip
--   * exposes Apply* helpers so every consumer rounds and clamps the same way
--   * tells the player which perks improved on level up, and /perks lists them
--
-- Refresh points (see server/xp.lua):
--   JRSXP.Get finish       -> JRSPerks.Sync   (login hydration, HUD polls)
--   JRSXP.ProcessQueue ok  -> JRSPerks.Refresh (any XP/level change, admin too)
-- ---------------------------------------------------------------------------

JRSPerks = JRSPerks or {}

local STATE_KEY = 'jrsPerks'
local perksBySrc = {}

local function perksEnabled()
    return type(Config.LevelPerks) == 'table'
        and Config.LevelPerks.Enabled ~= false
        and type(Config.ComputeLevelPerks) == 'function'
end

local function round2(n)
    return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100
end

local function percentText(value)
    return ('%d%%'):format(math.floor((tonumber(value) or 0) * 100 + 0.5))
end

local function usedCharacter(src)
    if not jrsCore or type(jrsCore.getUser) ~= 'function' then return nil end
    local ok, user = pcall(jrsCore.getUser, src)
    if not ok or not user then return nil end
    return user.getUsedCharacter
end

local function setStateBag(src, perks)
    pcall(function()
        Player(src).state:set(STATE_KEY, perks, true)
    end)
end

local function improvedLines(src, old, new)
    local lines = {}
    local function add(key, ...) lines[#lines + 1] = _Up(src, key, ...) end
    if new.carryKg > old.carryKg then add('perks_line_carry', new.carryKg) end
    if new.weaponSlots > old.weaponSlots then add('perks_line_weapons', new.weaponSlots) end
    if new.freeRun and not old.freeRun then add('perks_line_freerun') end
    if new.shopDiscount > old.shopDiscount then add('perks_line_shop', percentText(new.shopDiscount)) end
    if new.sellBonus > old.sellBonus then add('perks_line_sell', percentText(new.sellBonus)) end
    if new.taxReduction > old.taxReduction then add('perks_line_tax', percentText(new.taxReduction)) end
    if new.bankFeeReduction > old.bankFeeReduction then add('perks_line_bank', percentText(new.bankFeeReduction)) end
    if new.rewardBonus > old.rewardBonus then add('perks_line_reward', percentText(new.rewardBonus)) end
    if (new.doctorFeeReduction or 0) > (old.doctorFeeReduction or 0) then add('perks_line_doctor', percentText(new.doctorFeeReduction)) end
    if (new.stableFeeReduction or 0) > (old.stableFeeReduction or 0) then add('perks_line_stable', percentText(new.stableFeeReduction)) end
    if (new.travelDiscount or 0) > (old.travelDiscount or 0) then add('perks_line_travel', percentText(new.travelDiscount)) end
    if (new.staminaDrainReduction or 0) > (old.staminaDrainReduction or 0) then add('perks_line_stamina', percentText(new.staminaDrainReduction)) end
    return lines
end

--- jrs_servertag: add the Discord Server Tag perks (state bag `jrsTag`) on top of the
--- level perks, so every Apply* helper and the replicated `jrsPerks` bag include them.
local TAG_FIELDS = {
    { 'shopDiscount', 'shop' }, { 'sellBonus', 'sell' }, { 'taxReduction', 'tax' }, { 'rewardBonus', 'reward' },
    { 'doctorFeeReduction', 'doctor' }, { 'stableFeeReduction', 'stable' }, { 'travelDiscount', 'travel' },
}
local function mergeTagPerks(src, perks)
    -- Security (2026-10-02): server-side perks from jrs_servertag. The `jrsTag`
    -- state bag is client-writable (fake shop discount / sell bonus / carry kg).
    local okState, tag = pcall(function()
        if GetResourceState('jrs_servertag') ~= 'started' then return nil end
        return exports.jrs_servertag:GetTagPerks(src)
    end)
    if not okState or type(tag) ~= 'table' or tag.active ~= true then return perks end
    for _, pair in ipairs(TAG_FIELDS) do
        perks[pair[1]] = (tonumber(perks[pair[1]]) or 0) + (tonumber(tag[pair[2]]) or 0)
    end
    perks.carryKg = (tonumber(perks.carryKg) or 0) + (tonumber(tag.carryKg) or 0)
    perks.tagTier = tag.tier
    return perks
end

--- Recompute and publish. previousLevel (optional) enables the level-up notice.
function JRSPerks.Refresh(src, level, previousLevel)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    if not perksEnabled() then
        if perksBySrc[src] then
            perksBySrc[src] = nil
            setStateBag(src, nil)
        end
        return nil
    end

    local perks = mergeTagPerks(src, Config.ComputeLevelPerks(level))
    perksBySrc[src] = perks
    setStateBag(src, perks)
    TriggerEvent('jrs_core:server:levelPerksUpdated', src, perks)

    previousLevel = tonumber(previousLevel)
    if Config.LevelPerks.NotifyOnLevelUp ~= false and previousLevel and perks.level > previousLevel then
        local lines = improvedLines(src, Config.ComputeLevelPerks(previousLevel), Config.ComputeLevelPerks(perks.level))
        if #lines > 0 then
            TriggerClientEvent('jrs_core:sendRightTipNotification', src,
                _Up(src, 'perks_levelup_title', perks.level) .. ' ' .. table.concat(lines, ' - '), 9000)
        end

        if perks.level >= 10 and (perks.level % 5 == 0) then
            TriggerEvent('jrs_core:server:treasureMilestoneAwarded', src, perks.level)
            TriggerClientEvent('jrs_core:sendRightTipNotification', src,
                string.format("🗺️ Treasure Map Awarded (Rank %d Milestone)!", perks.level), 9000)
        end
    end
    return perks
end

--- Refresh only when the level actually differs from what is published.
function JRSPerks.Sync(src, level)
    src = tonumber(src)
    if not src then return nil end
    local current = perksBySrc[src]
    local lvl = math.max(1, math.floor(tonumber(level) or 1))
    if current and current.level == lvl then return current end
    return JRSPerks.Refresh(src, lvl, nil)
end

function JRSPerks.Get(src)
    src = tonumber(src)
    if not src or not perksEnabled() then return nil end
    local perks = perksBySrc[src]
    if perks then return perks end
    local character = usedCharacter(src)
    local level = character and tonumber(character.level)
    if not level then return nil end
    return JRSPerks.Refresh(src, level, nil)
end

local function perkValue(src, field)
    local perks = JRSPerks.Get(src)
    return math.max(0, math.min(0.95, tonumber(perks and perks[field]) or 0))
end

function JRSPerks.GetTaxReduction(src) return perkValue(src, 'taxReduction') end

--- Buy price after the store discount: finalAmount, savedAmount, rate
function JRSPerks.ApplyShopDiscount(src, amount)
    amount = tonumber(amount) or 0
    local rate = perkValue(src, 'shopDiscount')
    if amount <= 0 or rate <= 0 then return amount, 0, 0 end
    local final = math.max(0.01, math.min(amount, round2(amount * (1 - rate))))
    return final, round2(amount - final), rate
end

--- Sell payout after the sell bonus: finalAmount, bonusAmount, rate
function JRSPerks.ApplySellBonus(src, amount)
    amount = tonumber(amount) or 0
    local rate = perkValue(src, 'sellBonus')
    if amount <= 0 or rate <= 0 then return amount, 0, 0 end
    local final = math.max(amount, round2(amount * (1 + rate)))
    return final, round2(final - amount), rate
end

--- Tax after the reduction: taxAmount, removedAmount, rate
function JRSPerks.ApplyTaxReduction(src, tax)
    tax = tonumber(tax) or 0
    local rate = perkValue(src, 'taxReduction')
    if tax <= 0 or rate <= 0 then return tax, 0, 0 end
    local final = math.max(0, round2(tax * (1 - rate)))
    return final, round2(tax - final), rate
end

--- A bank fee rate after the player's reduction.
function JRSPerks.ApplyBankFeeRate(src, feeRate)
    feeRate = tonumber(feeRate) or 0
    local rate = perkValue(src, 'bankFeeReduction')
    if feeRate <= 0 or rate <= 0 then return feeRate end
    return math.max(0, feeRate * (1 - rate))
end

--- Whole-number reward after the job pay bonus.
function JRSPerks.ApplyRewardBonus(src, amount)
    amount = tonumber(amount) or 0
    local rate = perkValue(src, 'rewardBonus')
    if amount <= 0 or rate <= 0 then return amount end
    return math.max(amount, math.floor(amount * (1 + rate)))
end

--- Doctor fee after the player's reduction.
function JRSPerks.ApplyDoctorFeeRate(src, feeRate)
    feeRate = tonumber(feeRate) or 0
    local rate = perkValue(src, 'doctorFeeReduction')
    if feeRate <= 0 or rate <= 0 then return feeRate end
    local final = math.max(0, round2(feeRate * (1 - rate)))
    return final, round2(feeRate - final), rate
end

--- Stable care and stall fee after the player's reduction.
function JRSPerks.ApplyStableFeeRate(src, feeRate)
    feeRate = tonumber(feeRate) or 0
    local rate = perkValue(src, 'stableFeeReduction')
    if feeRate <= 0 or rate <= 0 then return feeRate end
    local final = math.max(0, round2(feeRate * (1 - rate)))
    return final, round2(feeRate - final), rate
end

--- Train ticket and fast travel fare after discount.
function JRSPerks.ApplyTravelDiscount(src, amount)
    amount = tonumber(amount) or 0
    local rate = perkValue(src, 'travelDiscount')
    if amount <= 0 or rate <= 0 then return amount, 0, 0 end
    local final = math.max(0.01, math.min(amount, round2(amount * (1 - rate))))
    return final, round2(amount - final), rate
end

--- Returns the stamina depletion reduction fraction (0.0 to 0.50).
function JRSPerks.GetStaminaDrainReduction(src)
    return perkValue(src, 'staminaDrainReduction')
end

function JRSPerks.NotifySaving(src, kind, amount, currency)
    src = tonumber(src)
    amount = round2(amount)
    if not src or amount <= 0 or not perksEnabled() or Config.LevelPerks.NotifySavings == false then return end
    local formatted = ('%.2f'):format(amount)
    local isGold = tostring(currency) == 'gold' or tonumber(currency) == 1
    local money = isGold and _Up(src, 'perks_amount_gold', formatted) or _Up(src, 'perks_amount_money', formatted)
    local key = kind == 'sell' and 'perks_saved_sell' or 'perks_saved_shop'
    TriggerClientEvent('jrs_core:sendRightTipNotification', src, _Up(src, key, money), 4000)
end

-- ---------------------------------------------------------------------------
-- /perks
-- ---------------------------------------------------------------------------
local function nextText(src, tbl, level, formatter)
    local nextLevel, nextValue = Config.LevelPerksNextMilestone(tbl, level)
    if not nextLevel then return '' end
    return ' ' .. _Up(src, 'perks_next', nextLevel, formatter(nextValue))
end

RegisterCommand(tostring((Config.LevelPerks and Config.LevelPerks.Command) or 'perks'), function(source)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    local perks = JRSPerks.Get(src)
    if not perks then
        TriggerClientEvent('jrs_core:sendRightTipNotification', src, _Up(src, 'perks_unavailable'), 4000)
        return
    end

    local cfg = Config.LevelPerks
    local lvl = perks.level
    local carry = cfg.Carry or {}
    local freeAt = tonumber((cfg.Movement or {}).FreeRunLevel) or 40

    local carryLine = _Up(src, 'perks_line_carry', perks.carryKg)
    if perks.carryKg < (tonumber(carry.MaxKg) or perks.carryKg) then
        carryLine = carryLine .. ' ' .. _Up(src, 'perks_max_at', carry.MaxKg, carry.MaxAtLevel or 100)
    end

    local lines = {
        carryLine,
        _Up(src, 'perks_line_weapons', perks.weaponSlots) .. nextText(src, cfg.WeaponSlots, lvl, tostring),
        perks.freeRun and _Up(src, 'perks_line_freerun') or _Up(src, 'perks_line_run_heavy', freeAt),
        _Up(src, 'perks_line_shop', percentText(perks.shopDiscount)) .. nextText(src, cfg.ShopDiscount, lvl, percentText),
        _Up(src, 'perks_line_sell', percentText(perks.sellBonus)) .. nextText(src, cfg.SellBonus, lvl, percentText),
        _Up(src, 'perks_line_tax', percentText(perks.taxReduction)) .. nextText(src, cfg.TaxReduction, lvl, percentText),
        _Up(src, 'perks_line_bank', percentText(perks.bankFeeReduction)) .. nextText(src, cfg.BankFeeReduction, lvl, percentText),
        _Up(src, 'perks_line_reward', percentText(perks.rewardBonus)) .. nextText(src, cfg.RewardBonus, lvl, percentText),
    }

    local title = _Up(src, 'perks_cmd_title', lvl)
    for _, line in ipairs(lines) do
        TriggerClientEvent('chat:addMessage', src, { args = { title, line } })
    end
end, false)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetTimeout(3000, function()
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local character = src and usedCharacter(src)
            if character then
                if tonumber(character.level) then
                    JRSPerks.Refresh(src, character.level, nil)
                elseif JRSXP and JRSXP.Get then
                    JRSXP.Get(src)
                end
            end
        end
    end)
end)

AddEventHandler('playerDropped', function()
    perksBySrc[tonumber(source)] = nil
end)

--- Everything the base menu's LEVELS tree needs to draw the perks card
--- (jrs_pausemenu server/basemenu.lua levelsSection). Pure table, no yield.
--- Row: key, kind ('kg'|'count'|'percent'|'flag'), value, fromLevel,
---      nextLevel/nextValue (nil when maxed), barTo (optional bar target level).
function JRSPerks.Overview(src)
    local perks = JRSPerks.Get(src)
    if not perks then return nil end
    local cfg = Config.LevelPerks or {}
    local lvl = perks.level
    local rows = {}

    local function milestoneRow(key, kind, tbl, value)
        local fromLevel = 1
        for l in pairs(tbl or {}) do
            local lNum = tonumber(l)
            if lNum and lNum <= lvl and lNum > fromLevel then fromLevel = lNum end
        end
        local nextLevel, nextValue = Config.LevelPerksNextMilestone(tbl, lvl)
        rows[#rows + 1] = { key = key, kind = kind, value = value, fromLevel = fromLevel, nextLevel = nextLevel, nextValue = nextValue }
    end

    -- Carry grows every couple of levels: "next" is the next level where the kg
    -- actually changes, while the bar tracks the whole climb to MaxAtLevel.
    local carry = cfg.Carry or {}
    local maxAt = math.floor(tonumber(carry.MaxAtLevel) or 100)
    local carryNextLevel, carryNextValue
    for l = lvl + 1, maxAt do
        local kg = Config.LevelPerksCarryKg(l)
        if kg > perks.carryKg then
            carryNextLevel, carryNextValue = l, kg
            break
        end
    end
    rows[#rows + 1] = { key = 'carry', kind = 'kg', value = perks.carryKg, fromLevel = 1, nextLevel = carryNextLevel, nextValue = carryNextValue, barTo = maxAt }

    milestoneRow('weapons', 'count', cfg.WeaponSlots, perks.weaponSlots)

    local freeAt = math.floor(tonumber((cfg.Movement or {}).FreeRunLevel) or 40)
    rows[#rows + 1] = { key = 'run', kind = 'flag', value = perks.freeRun == true, fromLevel = 1, nextLevel = (not perks.freeRun) and freeAt or nil }

    milestoneRow('shop', 'percent', cfg.ShopDiscount, perks.shopDiscount)
    milestoneRow('sell', 'percent', cfg.SellBonus, perks.sellBonus)
    milestoneRow('tax', 'percent', cfg.TaxReduction, perks.taxReduction)
    milestoneRow('bank', 'percent', cfg.BankFeeReduction, perks.bankFeeReduction)
    milestoneRow('reward', 'percent', cfg.RewardBonus, perks.rewardBonus)
    milestoneRow('doctor', 'percent', cfg.DoctorFeeReduction, perks.doctorFeeReduction)
    milestoneRow('stable', 'percent', cfg.StableFeeReduction, perks.stableFeeReduction)
    milestoneRow('travel', 'percent', cfg.TravelDiscount, perks.travelDiscount)
    milestoneRow('stamina', 'percent', cfg.StaminaDrainReduction, perks.staminaDrainReduction)

    return { level = lvl, rows = rows }
end

exports('GetLevelPerks', function(src) return JRSPerks.Get(src) end)
exports('GetLevelPerksOverview', function(src) return JRSPerks.Overview(src) end)
exports('RefreshLevelPerks', function(src)
    local character = usedCharacter(tonumber(src))
    return character and JRSPerks.Refresh(src, character.level, nil) or nil
end)
exports('GetCarryCapacity', function(src)
    local perks = JRSPerks.Get(src)
    return perks and perks.carryKg or nil
end)
exports('GetWeaponSlots', function(src)
    local perks = JRSPerks.Get(src)
    return perks and perks.weaponSlots or nil
end)
exports('ApplyShopDiscount', function(src, amount) return JRSPerks.ApplyShopDiscount(src, amount) end)
exports('ApplySellBonus', function(src, amount) return JRSPerks.ApplySellBonus(src, amount) end)
exports('ApplyTaxReduction', function(src, tax) return JRSPerks.ApplyTaxReduction(src, tax) end)
exports('ApplyBankFeeRate', function(src, rate) return JRSPerks.ApplyBankFeeRate(src, rate) end)
exports('ApplyRewardBonus', function(src, amount) return JRSPerks.ApplyRewardBonus(src, amount) end)
exports('ApplyDoctorFeeRate', function(src, rate) return JRSPerks.ApplyDoctorFeeRate(src, rate) end)
exports('ApplyStableFeeRate', function(src, rate) return JRSPerks.ApplyStableFeeRate(src, rate) end)
exports('ApplyTravelDiscount', function(src, amount) return JRSPerks.ApplyTravelDiscount(src, amount) end)
exports('GetStaminaDrainReduction', function(src) return JRSPerks.GetStaminaDrainReduction(src) end)
exports('NotifyPerkSaving', function(src, kind, amount, currency) return JRSPerks.NotifySaving(src, kind, amount, currency) end)

-- jrs_servertag changed the player's tag perks: rebuild the published perks now.
AddEventHandler('jrs_servertag:changed', function(src)
    src = tonumber(src)
    if not src then return end
    local current = perksBySrc[src]
    local character = usedCharacter(src)
    local level = (current and current.level) or (character and tonumber(character.level))
    if level then JRSPerks.Refresh(src, level, nil) end
end)
