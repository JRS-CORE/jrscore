-- jrs_huntingpets: Automatic database setup
-- Creates the tables this resource needs the first time it starts, so nobody
-- has to run install/huntingpets.sql by hand. Safe to run on every
-- boot/restart: CREATE TABLE IF NOT EXISTS is a no-op once the schema
-- exists, and nothing here ever drops, alters or truncates player data.

local function EnsureTables()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `player_dogs` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(50) NOT NULL,
            `charid` INT(11) NOT NULL,
            `model` VARCHAR(255) NOT NULL,
            `preset` INT(11) NOT NULL DEFAULT '0',
            `xp` INT(11) NOT NULL DEFAULT '0',
            `price` INT(11) NOT NULL DEFAULT '0',
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `player_birds` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(50) NOT NULL,
            `charid` INT(11) NOT NULL,
            `model` VARCHAR(255) NOT NULL,
            `preset` INT(11) NOT NULL DEFAULT '0',
            `xp` INT(11) NOT NULL DEFAULT '0',
            `price` INT(11) NOT NULL DEFAULT '0',
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `player_selected_pets` (
            `identifier` VARCHAR(50) NOT NULL,
            `charid` INT(11) NOT NULL,
            `selected_dog` INT(11) DEFAULT NULL,
            `selected_bird` INT(11) DEFAULT NULL,
            UNIQUE KEY `uc_player` (`identifier`, `charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        print('^2[jrs_huntingpets]^7 Database tables verified/created.')
    end)
end

-- Runs once when the resource starts (server boot, `ensure`, or `restart`).
-- oxmysql queues queries until its connection is ready, so this is safe to
-- call immediately without waiting on MySQL.ready() first.
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    EnsureTables()
end)
