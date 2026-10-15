-- jrs_banking | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local JRScore = exports.jrs_core:GetCore()


-- All amounts are checked on the server (positive, finite, max 2 decimals) and every balance change is a
-- single conditional UPDATE, so negative amounts / double clicks can't create money.

local MAX_AMOUNT = 10000000

local function cleanAmount(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value <= 0 or value > MAX_AMOUNT then return nil end
    value = math.floor(value * 100 + 0.0000001) / 100
    return value > 0 and value or nil
end

local function bank(name)
    return type(name) == "string" and Config.banks[name] or nil
end

local function getChar(src)
    local user = JRScore.getUser(src)
    local char = user and user.getUsedCharacter or nil
    -- no character selected yet: treat as no character at all
    if not char or not char.charIdentifier or not char.identifier then return nil end
    return char
end

local busy = {}
local function guard(src)
    local now = os.clock()
    if busy[src] and now - busy[src] < 1.0 then return false end
    busy[src] = now
    return true
end

-- one shared storage per character and bank, created the first time it is needed
local function ensureVault(bankKey, vaultId, slots)
    if exports.jrs_inventory:isCustomInventoryRegistered(vaultId) then return end
    exports.jrs_inventory:registerInventory({
        id = vaultId,
        name = bankKey,
        limit = slots,
        acceptWeapons = Config.banks[bankKey].canStoreWeapons,
        shared = true,
        ignoreItemStackLimit = true,
        webhook = Config.CustomInventoryWebhook,
    })
    Wait(200)
end
local registerStorage = ensureVault

-- the player is at the counter (a little slack for lag)
local function IsNearBank(src, bankKey)
    local cfg = bank(bankKey)
    if not cfg then return false end
    local at = cfg.BankLocation
    return #(GetEntityCoords(GetPlayerPed(src)) - vector3(at.x, at.y, at.z)) <= cfg.distOpen + 10.0
end

JRScore.Callback.Register('jrs_bank:getinfo', function(source, cb, bankName)
    local Character = getChar(source)
    if not Character or not bank(bankName) then return cb(false) end
    local charidentifier = Character.charIdentifier
    -- no character loaded yet (selection / creation screen): nothing to open
    if not charidentifier or not Character.identifier then return cb(false) end

    local row = MySQL.single.await("SELECT * FROM bank_users WHERE charidentifier = ? AND name = ? LIMIT 1", { charidentifier, bankName })
    if not row then
        MySQL.insert.await("INSERT INTO bank_users (`name`,`identifier`,`charidentifier`,`money`,`gold`,`invspace`) VALUES (?, ?, ?, 0, 0, 10)",
            { bankName, Character.identifier, charidentifier })
        row = { money = 0, gold = 0, invspace = 10 }
    end
    local allBanks = MySQL.query.await("SELECT * FROM bank_users WHERE charidentifier = ?", { charidentifier }) or {}
    return cb({ { money = row.money, gold = row.gold, invspace = row.invspace, name = bankName }, allBanks })
end)

RegisterServerEvent('jrs_bank:UpgradeSafeBox', function(slotsToBuy, _, bankName)
    local _source = source
    local T = BankTranslation.For(_source)
    local Character = getChar(_source)
    local cfg = bank(bankName)
    slotsToBuy = math.floor(tonumber(slotsToBuy) or 0)
    if not Character or not cfg or slotsToBuy < 1 or not guard(_source) then return end

    if not IsNearBank(_source, bankName) then
        return JRScore.NotifyRightTip(_source, T.notnear, 4000)
    end

    local charidentifier = Character.charIdentifier
    local currentspace = MySQL.scalar.await("SELECT invspace FROM bank_users WHERE charidentifier = ? AND name = ? LIMIT 1",
        { charidentifier, bankName })
    if not currentspace then return end

    local amountToPay = cfg.costslot * slotsToBuy
    local FinalSlots = currentspace + slotsToBuy
    if FinalSlots > cfg.maxslots then
        return JRScore.NotifyRightTip(_source, T.maxslots .. " | " .. slotsToBuy .. " / " .. cfg.maxslots, 4000)
    end
    if Character.money < amountToPay then
        return JRScore.NotifyRightTip(_source, T.nomoney, 4000)
    end

    Character.removeCurrency(0, amountToPay)
    MySQL.update.await("UPDATE bank_users SET invspace = ? WHERE charidentifier = ? AND name = ?", { FinalSlots, charidentifier, bankName })
    local bankId = "jrs_banking_" .. bankName .. "_" .. charidentifier
    registerStorage(bankName, bankId, currentspace)
    exports.jrs_inventory:updateCustomInventorySlots(bankId, FinalSlots)
    JRScore.NotifyRightTip(_source, T.success .. amountToPay .. " | " .. FinalSlots .. " / " .. cfg.maxslots, 4000)
end)

-- one Discord log per kind of transaction: which webhook, and which text of the language file
local LOGS = {
    withdraw = { 'WithdrawLogWebhook', 'WithdrawLogDescription' },
    deposit  = { 'DepositLogWebhook',  'DepositLogDescription' },
    transfer = { 'TransferLogWebhook', 'TransferLogDescription' },
    take     = { 'TakeLogWebhook',     'TakeLogDescription' },
    move     = { 'MoveLogWebhook',     'MoveLogDescription' },
}

function DiscordLogs(amount, bankKey, who, kind, targetBank, currency, itemName, src)
    local entry = LOGS[kind]
    if not entry then return end
    local words = BankTranslation.For(src).Webhooks
    local unit = currency == 'gold' and 'G' or '$'

    local line
    if kind == 'transfer' then
        line = words[entry[2]]:format(who, amount .. unit, bankKey, targetBank)
    elseif kind == 'take' or kind == 'move' then
        line = words[entry[2]]:format(who, amount, itemName, bankKey)
    else
        line = words[entry[2]]:format(who, amount .. unit, bankKey)
    end
    JRScore.AddWebhook(words.LogTitle, Config[entry[1]], line)
end

-- move money between two of your own accounts (fee from Config.feeamount)
RegisterServerEvent('jrs_bank:transfer', function(amount, fromBank, toBank)
    local _source = source
    local T = BankTranslation.For(_source)
    local Character = getChar(_source)
    amount = cleanAmount(amount)
    if not Character or not amount or not bank(fromBank) or not bank(toBank) or fromBank == toBank or not guard(_source) then return end

    if not IsNearBank(_source, toBank) then
        return JRScore.NotifyRightTip(_source, T.notnear, 4000)
    end

    local characterId = Character.charIdentifier
    local hasTarget = MySQL.scalar.await("SELECT 1 FROM bank_users WHERE charidentifier = ? AND name = ? LIMIT 1", { characterId, toBank })
    if not hasTarget then return JRScore.NotifyRightTip(_source, T.noaccmoney, 4000) end

    local taken = MySQL.update.await("UPDATE bank_users SET money = money - ? WHERE charidentifier = ? AND name = ? AND money >= ?",
        { amount, characterId, fromBank, amount })
    if not taken or taken < 1 then
        return JRScore.NotifyRightTip(_source, T.noaccmoney, 4000)
    end

    local received = math.floor(amount * (tonumber(Config.feeamount) or 1) * 100) / 100
    MySQL.update.await("UPDATE bank_users SET money = money + ? WHERE charidentifier = ? AND name = ?", { received, characterId, toBank })

    local shown = string.format("%.2f", received)
    DiscordLogs(shown, fromBank, Character.firstname .. ' ' .. Character.lastname, "transfer", toBank, "cash", nil, _source)
    JRScore.NotifyRightTip(_source, string.format(T.transfer .. "%s $" .. T.to .. "%s" .. T.transferred, shown, toBank), 4000)
end)

local function deposit(src, amount, bankName, currency)
    local T = BankTranslation.For(src)
    local Character = getChar(src)
    amount = cleanAmount(amount)
    if currency == 1 and amount then amount = math.floor(amount) end
    if not Character or not amount or amount <= 0 or not bank(bankName) or not guard(src) then
        return JRScore.NotifyRightTip(src, T.invalid, 4000)
    end
    if not IsNearBank(src, bankName) then
        return JRScore.NotifyRightTip(src, T.notnear, 4000)
    end

    local balance = currency == 1 and Character.gold or Character.money
    if balance < amount then
        return JRScore.NotifyRightTip(src, T.invalid, 4000)
    end

    local column = currency == 1 and "gold" or "money"
    local exists = MySQL.scalar.await("SELECT 1 FROM bank_users WHERE charidentifier = ? AND name = ? LIMIT 1", { Character.charIdentifier, bankName })
    if not exists then return end

    Character.removeCurrency(currency, amount)
    MySQL.update.await(("UPDATE bank_users SET %s = %s + ? WHERE charidentifier = ? AND name = ?"):format(column, column),
        { amount, Character.charIdentifier, bankName })
    DiscordLogs(amount, bankName, Character.firstname .. ' ' .. Character.lastname, "deposit", nil, currency == 1 and "gold" or "cash", nil, src)
    JRScore.NotifyRightTip(src, (currency == 1 and T.youdepog or T.youdepo) .. amount, 4000)
end

local function withdraw(src, amount, bankName, currency)
    local T = BankTranslation.For(src)
    local Character = getChar(src)
    amount = cleanAmount(amount)
    if currency == 1 and amount then amount = math.floor(amount) end
    if not Character or not amount or amount <= 0 or not bank(bankName) or not guard(src) then
        return JRScore.NotifyRightTip(src, T.invalid, 4000)
    end
    if not IsNearBank(src, bankName) then
        return JRScore.NotifyRightTip(src, T.notnear, 4000)
    end

    local column = currency == 1 and "gold" or "money"
    local taken = MySQL.update.await(("UPDATE bank_users SET %s = %s - ? WHERE charidentifier = ? AND name = ? AND %s >= ?"):format(column, column, column),
        { amount, Character.charIdentifier, bankName, amount })
    if not taken or taken < 1 then
        return JRScore.NotifyRightTip(src, T.invalid .. amount, 4000)
    end

    Character.addCurrency(currency, amount)
    DiscordLogs(amount, bankName, Character.firstname .. ' ' .. Character.lastname, "withdraw", nil, currency == 1 and "gold" or "cash", nil, src)
    JRScore.NotifyRightTip(src, (currency == 1 and T.withdrewg or T.withdrew) .. amount, 4000)
end

RegisterServerEvent('jrs_bank:depositcash', function(amount, bankName) deposit(source, amount, bankName, 0) end)
RegisterServerEvent('jrs_bank:depositgold', function(amount, bankName) deposit(source, amount, bankName, 1) end)
RegisterServerEvent('jrs_bank:withcash', function(amount, bankName) withdraw(source, amount, bankName, 0) end)
RegisterServerEvent('jrs_bank:withgold', function(amount, bankName) withdraw(source, amount, bankName, 1) end)

RegisterServerEvent("jrs_banking:server:OpenBankInventory", function(bankName)
    local _source = source
    local T = BankTranslation.For(_source)
    local Character = getChar(_source)
    if not Character or not bank(bankName) then return end

    local characterId = Character.charIdentifier
    local bankId = "jrs_banking_" .. bankName .. "_" .. characterId

    if not IsNearBank(_source, bankName) then
        return JRScore.NotifyRightTip(_source, T.notnear, 4000)
    end

    local invSpace = MySQL.scalar.await('SELECT `invspace` FROM `bank_users` WHERE `charidentifier` = ? AND `name` = ? LIMIT 1', { characterId, bankName })
    if invSpace then
        registerStorage(bankName, bankId, invSpace)
        exports.jrs_inventory:openInventory(_source, bankId)
    else
        JRScore.NotifyRightTip(_source, T.invOpenFail, 4000)
    end
end)

AddEventHandler("playerDropped", function()
    busy[source] = nil
end)
