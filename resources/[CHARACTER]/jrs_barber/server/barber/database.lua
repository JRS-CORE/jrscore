JRSBarberDatabaseReady = false

local schemaStatements = {
    [[
        CREATE TABLE IF NOT EXISTS `jrs_appearance_legacy_backup` (
            `charid` INT NOT NULL,
            `compPlayer` LONGTEXT NOT NULL,
            `skinPlayer` LONGTEXT NOT NULL,
            `migrated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `jrs_appearance_onboarding` (
            `charid` INT NOT NULL,
            `stage` VARCHAR(32) NOT NULL DEFAULT 'clothing',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `jrs_barber` (
            `charid` INT NOT NULL,
            `hairstyle` LONGTEXT NOT NULL,
            `overlays` LONGTEXT NOT NULL,
            `permanentoverlay` LONGTEXT NOT NULL,
            `outfit_id` VARCHAR(50) DEFAULT NULL,
            PRIMARY KEY (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `jrs_barber_preset` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `charid` INT NOT NULL,
            `outfit_id` VARCHAR(50) NOT NULL,
            `price` DECIMAL(10,2) NOT NULL DEFAULT 0,
            `name` VARCHAR(255) NOT NULL DEFAULT '',
            `hairstyle` LONGTEXT NOT NULL,
            `overlays` LONGTEXT NOT NULL,
            `gender` VARCHAR(32) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            UNIQUE KEY `jrs_barber_preset_outfit_unique` (`outfit_id`),
            KEY `jrs_barber_preset_charid_idx` (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]
}

local function ensureColumn(tableName, columnName, definition)
    local exists = tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })) or 0
    if exists == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

-- BarberConfig.OverlayItem was registered as a usable item that did not exist
-- in the items table, so the makeup-kit item could never be given or used.
-- jrs_clothing already self-heals its outfit item the same way.
local function ensureOverlayItem()
    local itemName = tostring(BarberConfig.OverlayItem or '')
    if itemName == '' then return true end

    local tableExists = (tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jrs_items'
    ]])) or 0) > 0
    if not tableExists then return false end

    local columns = MySQL.query.await([[
        SELECT COLUMN_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jrs_items'
    ]]) or {}
    local available = {}
    for _, row in ipairs(columns) do
        available[tostring(row.COLUMN_NAME or row.column_name or '')] = true
    end
    if not available.item then return false end

    local exists = MySQL.scalar.await('SELECT 1 FROM `jrs_items` WHERE `item` = ? LIMIT 1', { itemName })
    if exists then
        if available.usable then
            MySQL.update.await('UPDATE `jrs_items` SET `usable` = 1 WHERE `item` = ?', { itemName })
        end
        return true
    end

    local wanted = {
        item = itemName,
        label = 'Makeup Kit',
        limit = 0.2,
        can_remove = 1,
        type = 'item',
        usable = 1,
        descriptions = 'Applies a saved barber preset',
        metadata = 0,
        category = 'clothing',
    }
    local fields, placeholders, params = {}, {}, {}
    for _, field in ipairs({ 'item', 'label', 'limit', 'can_remove', 'type', 'usable', 'descriptions', 'metadata', 'category' }) do
        if available[field] then
            fields[#fields + 1] = ('`%s`'):format(field)
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = wanted[field]
        end
    end
    MySQL.insert.await(
        ('INSERT INTO `jrs_items` (%s) VALUES (%s)'):format(table.concat(fields, ', '), table.concat(placeholders, ', ')),
        params
    )

    if GetResourceState('jrs_inventory') == 'started' then
        pcall(function() exports.jrs_inventory:reloadItemTable() end)
    end
    return true
end

CreateThread(function()
    local ok, err = pcall(function()
        for _, statement in ipairs(schemaStatements) do
            MySQL.query.await(statement)
        end

        -- Safe upgrades for databases created by older releases.
        ensureColumn('jrs_barber', 'permanentoverlay', 'LONGTEXT NULL')
        MySQL.update.await("UPDATE jrs_barber SET permanentoverlay = '[]' WHERE permanentoverlay IS NULL OR permanentoverlay = ''")
        MySQL.query.await('ALTER TABLE jrs_barber MODIFY permanentoverlay LONGTEXT NOT NULL')
        ensureColumn('jrs_barber', 'outfit_id', 'VARCHAR(50) NULL')
        ensureColumn('jrs_barber_preset', 'gender', "VARCHAR(32) NOT NULL DEFAULT ''")
        MySQL.query.await('ALTER TABLE jrs_barber MODIFY outfit_id VARCHAR(50) NULL')
    end)

    JRSBarberDatabaseReady = ok
    if not ok then
        print(('[jrs_barber] Database initialization failed: %s'):format(tostring(err)))
        return
    end

    local itemOk, itemErr = pcall(ensureOverlayItem)
    if not itemOk then
        print(('[jrs_barber] Makeup item initialization failed: %s'):format(tostring(itemErr)))
    end
end)
