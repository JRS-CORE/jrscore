-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | server: tables and the helpers the dog and bird files share
-- The tables are created on start (IF NOT EXISTS, nothing is ever dropped or changed), so no SQL file has to
-- be run by hand.

local COLUMNS <const> = [[
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(50) NOT NULL,
    `charid` INT(11) NOT NULL,
    `model` VARCHAR(255) NOT NULL,
    `preset` INT(11) NOT NULL DEFAULT '0',
    `xp` INT(11) NOT NULL DEFAULT '0',
    `price` INT(11) NOT NULL DEFAULT '0',
    PRIMARY KEY (`id`)]]

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, table_ in ipairs({ 'player_dogs', 'player_birds' }) do
        MySQL.query(('CREATE TABLE IF NOT EXISTS `%s` (%s) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;'):format(table_, COLUMNS))
    end

    MySQL.query([[CREATE TABLE IF NOT EXISTS `player_selected_pets` (
        `identifier` VARCHAR(50) NOT NULL,
        `charid` INT(11) NOT NULL,
        `selected_dog` INT(11) DEFAULT NULL,
        `selected_bird` INT(11) DEFAULT NULL,
        UNIQUE KEY `uc_player` (`identifier`, `charid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {}, function()
        print('^2[jrs_huntingpets]^7 Database tables verified/created.')
    end)
end)

-- ------------------------------------------------------------------ helpers (global, used by the server files)

Pets = {}

-- the character behind a source: { player, cid (account), charid }
function Pets.who(src)
    local player = JRS.Player(src)
    if not player then return nil end
    return { player = player, cid = player.PlayerData.citizenid, charid = player.PlayerData.id, job = player.PlayerData.job and player.PlayerData.job.name }
end

function Pets.say(src, title, text, kind)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = title, description = text, duration = 5000, type = kind or 'inform' })
end

function Pets.sayKey(src, key, kind, ...)
    Pets.say(src, L('notif_title_pets'), L(key, ...), kind)
end

-- the row of one pet owned by this character, or nil
function Pets.owned(tableName, id, me)
    local rows = MySQL.query.await(('SELECT * FROM %s WHERE id = ? AND identifier = ? AND charid = ?'):format(tableName), { id, me.cid, me.charid })
    return rows and rows[1] or nil
end

function Pets.selection(me)
    local rows = MySQL.query.await('SELECT selected_dog, selected_bird FROM player_selected_pets WHERE identifier = ? AND charid = ?', { me.cid, me.charid })
    return rows and rows[1] or {}
end

function Pets.select(column, id, me)
    MySQL.execute(('INSERT INTO player_selected_pets (identifier, charid, %s) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE %s = ?'):format(column, column),
        { me.cid, me.charid, id, id })
end

function Pets.clearSelection(column, me)
    MySQL.execute(('UPDATE player_selected_pets SET %s = NULL WHERE identifier = ? AND charid = ?'):format(column), { me.cid, me.charid })
end

-- pays half the price back and removes the row; false when it was already gone
function Pets.sellBack(tableName, row, me)
    local gone = MySQL.update.await(('DELETE FROM %s WHERE id = ? AND identifier = ? AND charid = ?'):format(tableName), { row.id, me.cid, me.charid })
    if not gone or gone < 1 then return false end
    local refund = math.floor(row.price * 0.5)
    me.player.Functions.AddMoney('cash', refund)
    return refund
end
