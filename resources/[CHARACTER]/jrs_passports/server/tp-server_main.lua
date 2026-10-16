-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | server
-- Registering, retrieving a lost passport item and renewing an expired passport. Prices come from the
-- config; the passport itself is a row in `passports` plus an inventory item that points to it.

local function say(src, key, kind) SendNotification(src, Locales[key], kind or 'error') end

local function expiryFromNow() return os.time() + Config.PassportExpirationDays * 86400 end

local function giveItem(player, row)
    player.addItem(Config.PassportItem, 1, { durability = -1, description = row.firstname .. ' ' .. row.lastname, identityId = row.identityId })
end

-- a photo has to be a plain http(s) link
local function validPhoto(url)
    return type(url) == 'string' and #url <= 512 and url:match('^https?://[%w%-%._~:/%?#@!%$&%+,;=%%]+$') ~= nil
end

RegisterServerEvent('jrs_passports:server:register', function(targetId, photo)
    local src = source

    -- registering somebody else is for staff only
    local target = src
    if targetId ~= nil and tonumber(targetId) ~= 0 then
        if not JRS.IsAdmin(src) then return say(src, 'PLAYER_INVALID') end
        target = tonumber(targetId)
    end
    local forOther = target ~= src

    photo = type(photo) == 'string' and photo:match('^%s*(.-)%s*$') or nil
    if not validPhoto(photo) then return say(src, 'PLAYER_INVALID') end

    local player = GetPlayerName(target) and JRS.MethodPlayer(target)
    if not player or not player.loaded() then return say(src, 'PLAYER_INVALID') end

    local char = player.getCharacterIdentifier()
    if PassportOf(char) then return say(src, forOther and 'ALREADY_REGISTERED_TARGET' or 'ALREADY_REGISTERED') end

    local price = Config.PassportCosts.Registration
    if player.getAccount(0) < price then
        if forOther then
            say(target, 'NOT_ENOUGH_MONEY_REGISTER')
            say(src, 'TARGET_DOES_NOT_HAVE_ENOUGH_MONEY')
        else
            say(src, 'NOT_ENOUGH_MONEY_REGISTER')
        end
        return
    end
    player.removeAccount(0, price)

    local row = {
        identityId = player.getIdentityId(),
        identifier = player.getIdentifier(),
        charidentifier = char,
        steamname = GetPlayerName(target),
        firstname = player.getFirstName(),
        lastname = player.getLastName(),
        dob = player.getDob(),
        sex = player.getGender(),
        registration_date = os.date('%d') .. '/' .. os.date('%m') .. '/' .. Config.Year .. ' ' .. os.date('%X'),
        expiration_date = expiryFromNow(),
        avatar_url = photo,
    }
    MySQL.insert.await(
        'INSERT INTO `passports` (`identityId`, `identifier`, `charidentifier`, `steamname`, `firstname`, `lastname`, `dob`, `sex`, `registration_date`, `expiration_date`, `avatar_url`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { row.identityId, row.identifier, row.charidentifier, row.steamname, row.firstname, row.lastname, row.dob, row.sex, row.registration_date, row.expiration_date, row.avatar_url })

    giveItem(player, row)
    say(target, 'PASSPORT_CREATE_SELF_SUCCESS', 'success')
    if forOther then say(src, 'TARGET_PASSPORT_CREATE_SUCCESS', 'success') end
end)

-- a new item for an existing passport
RegisterServerEvent('jrs_passports:server:retrieve', function()
    local src = source
    local player = JRS.MethodPlayer(src)
    if not player then return end

    local price = Config.PassportCosts.Retrieve
    if player.getAccount(0) < price then return say(src, 'NOT_ENOUGH_MONEY_RETRIEVE') end

    local row = PassportOf(player.getCharacterIdentifier())
    if not row then return end

    player.removeAccount(0, price)
    giveItem(player, row)
    say(src, 'PASSPORT_RETRIEVED', 'success')
end)

-- a passport can only be renewed once it has run out
RegisterServerEvent('jrs_passports:server:renew', function()
    local src = source
    local player = JRS.MethodPlayer(src)
    if not player then return end

    local price = Config.PassportCosts.Renewal
    if player.getAccount(0) < price then return say(src, 'NOT_ENOUGH_MONEY_RENEW') end

    local char = player.getCharacterIdentifier()
    local row = PassportOf(char)
    if not row then return end
    if os.time() <= row.expiration_date then return say(src, 'PASSPORT_NOT_EXPIRED') end

    player.removeAccount(0, price)
    MySQL.update.await('UPDATE `passports` SET `expiration_date` = ? WHERE `charidentifier` = ?', { expiryFromNow(), char })
    say(src, 'PASSPORT_RENEWED', 'success')
end)
