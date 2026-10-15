JRSClothingDatabaseReady = false

local schemaStatements = {
    [[
        CREATE TABLE IF NOT EXISTS `jrs_clothing_current` (
            `charid` INT NOT NULL,
            `clothes` LONGTEXT NOT NULL,
            `outfit_id` VARCHAR(50) DEFAULT NULL,
            `hidden_categories` LONGTEXT NULL,
            PRIMARY KEY (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `jrs_clothing_outfits` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `charid` INT NOT NULL,
            `outfit_id` VARCHAR(50) NOT NULL,
            `price` DECIMAL(10,2) NOT NULL DEFAULT 0,
            `name` VARCHAR(255) NOT NULL DEFAULT '',
            `clothes` LONGTEXT NOT NULL,
            `singleitems` LONGTEXT NOT NULL,
            `gender` VARCHAR(32) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            UNIQUE KEY `jrs_clothing_outfit_unique` (`outfit_id`),
            KEY `jrs_clothing_outfit_charid_idx` (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `jrs_clothing_wearables` (
            `charid` INT NOT NULL,
            `outfit_id` VARCHAR(50) NOT NULL,
            `skin` LONGTEXT NOT NULL,
            PRIMARY KEY (`charid`, `outfit_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
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
    ]]
}

local function columnExists(tableName, columnName)
    return (tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })) or 0) > 0
end

local function indexExists(tableName, indexName)
    return (tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tableName, indexName })) or 0) > 0
end

local function ensureColumn(tableName, columnName, definition)
    if not columnExists(tableName, columnName) then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

local function repairClothingSchema()
    ensureColumn('jrs_clothing_current', 'charid', 'INT NOT NULL')
    ensureColumn('jrs_clothing_current', 'clothes', "LONGTEXT NOT NULL")
    ensureColumn('jrs_clothing_current', 'outfit_id', 'VARCHAR(50) DEFAULT NULL')
    ensureColumn('jrs_clothing_current', 'hidden_categories', 'LONGTEXT NULL')

    ensureColumn('jrs_clothing_outfits', 'charid', 'INT NOT NULL')
    ensureColumn('jrs_clothing_outfits', 'outfit_id', 'VARCHAR(50) NOT NULL')
    ensureColumn('jrs_clothing_outfits', 'price', 'DECIMAL(10,2) NOT NULL DEFAULT 0')
    ensureColumn('jrs_clothing_outfits', 'name', "VARCHAR(255) NOT NULL DEFAULT ''")
    ensureColumn('jrs_clothing_outfits', 'clothes', 'LONGTEXT NOT NULL')
    ensureColumn('jrs_clothing_outfits', 'singleitems', 'LONGTEXT NULL')
    ensureColumn('jrs_clothing_outfits', 'gender', "VARCHAR(32) NOT NULL DEFAULT ''")

    ensureColumn('jrs_clothing_wearables', 'charid', 'INT NOT NULL')
    ensureColumn('jrs_clothing_wearables', 'outfit_id', 'VARCHAR(50) NOT NULL')
    ensureColumn('jrs_clothing_wearables', 'skin', 'LONGTEXT NOT NULL')

    -- Legacy versions used numeric outfit ids. Keep everything string-safe.
    MySQL.query.await('ALTER TABLE `jrs_clothing_current` MODIFY `outfit_id` VARCHAR(50) NULL')
    MySQL.query.await('ALTER TABLE `jrs_clothing_outfits` MODIFY `outfit_id` VARCHAR(50) NULL')
    MySQL.query.await('ALTER TABLE `jrs_clothing_wearables` MODIFY `outfit_id` VARCHAR(50) NULL')

    MySQL.update.await("UPDATE `jrs_clothing_outfits` SET `gender` = 'male' WHERE `gender` IN ('true', '1')")
    MySQL.update.await("UPDATE `jrs_clothing_outfits` SET `gender` = 'female' WHERE `gender` IN ('false', '0')")
    MySQL.update.await("UPDATE `jrs_clothing_outfits` SET `singleitems` = '[]' WHERE `singleitems` IS NULL OR `singleitems` = ''")
    MySQL.query.await('ALTER TABLE `jrs_clothing_outfits` MODIFY `singleitems` LONGTEXT NOT NULL')

    if not indexExists('jrs_clothing_outfits', 'jrs_clothing_outfit_unique') then
        pcall(function()
            MySQL.query.await('ALTER TABLE `jrs_clothing_outfits` ADD UNIQUE KEY `jrs_clothing_outfit_unique` (`outfit_id`)')
        end)
    end
    if not indexExists('jrs_clothing_outfits', 'jrs_clothing_outfit_charid_idx') then
        pcall(function()
            MySQL.query.await('ALTER TABLE `jrs_clothing_outfits` ADD KEY `jrs_clothing_outfit_charid_idx` (`charid`)')
        end)
    end
end

local function ensureOrdinaryOutfitItem()
    if not ClothingConfig.OutfitItem or tostring(ClothingConfig.OutfitItem) == '' then return true end

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

    local fieldOrder = { 'item', 'label', 'limit', 'can_remove', 'type', 'usable', 'descriptions', 'metadata', 'category' }
    local function ensureItem(itemName, label, description)
        itemName = tostring(itemName or '')
        if itemName == '' then return end
        local exists = MySQL.scalar.await('SELECT 1 FROM `jrs_items` WHERE `item` = ? LIMIT 1', { itemName })
        if exists then
            if available.usable then
                MySQL.update.await('UPDATE `jrs_items` SET `usable` = 1 WHERE `item` = ?', { itemName })
            end
            return
        end

        local wanted = {
            item = itemName,
            label = tostring(label or itemName),
            limit = 0.2,
            can_remove = 1,
            type = 'item',
            usable = 1,
            descriptions = tostring(description or 'Wearable clothing item'),
            -- This items table uses a compact flag/default column; per-instance
            -- clothing metadata is stored in characters.inventory by jrs_inventory.
            metadata = 0,
            category = 'clothing',
        }
        local fields, placeholders, params = {}, {}, {}
        for _, field in ipairs(fieldOrder) do
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
    end

    ensureItem(ClothingConfig.OutfitItem, 'Outfit', 'Saved clothing outfit')
    for itemName in pairs(ClothingConfig.SingleItemCategory or {}) do
        local label = tostring(itemName):gsub('_', ' '):gsub('(%a)([%w]*)', function(first, rest)
            return first:upper() .. rest
        end)
        ensureItem(itemName, label, 'Wearable clothing item')
    end
    -- Refresh the inventory definition cache after inserting the normal item.
    if GetResourceState('jrs_inventory') == 'started' then
        pcall(function() exports.jrs_inventory:reloadItemTable() end)
    end
    return true
end

JRSClothingEnsureOutfitItem = ensureOrdinaryOutfitItem

CreateThread(function()
    -- Core table creation is authoritative. Optional legacy repairs are isolated
    -- so one stale ALTER cannot disable every clothing callback.
    local createOk = true
    for _, statement in ipairs(schemaStatements) do
        local ok, err = pcall(function() MySQL.query.await(statement) end)
        if not ok then
            createOk = false
            print(('[jrs_clothing] Required schema statement failed: %s'):format(tostring(err)))
        end
    end

    if not createOk then
        JRSClothingDatabaseReady = false
        return
    end

    local repairOk, repairErr = pcall(repairClothingSchema)
    if not repairOk then
        -- Existing servers can have legacy keys/column definitions. As long as
        -- the required tables/columns exist, saving must stay available.
        print(('[jrs_clothing] Legacy schema repair warning: %s'):format(tostring(repairErr)))
    end

    local function requiredColumn(tableName, columnName)
        local ok, count = pcall(MySQL.scalar.await, [[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ]], { tableName, columnName })
        return ok and (tonumber(count) or 0) > 0
    end

    local required = {
        {'jrs_clothing_current', 'charid'},
        {'jrs_clothing_current', 'clothes'},
        {'jrs_clothing_current', 'outfit_id'},
        {'jrs_clothing_outfits', 'charid'},
        {'jrs_clothing_outfits', 'outfit_id'},
        {'jrs_clothing_outfits', 'name'},
        {'jrs_clothing_outfits', 'clothes'},
        {'jrs_clothing_outfits', 'singleitems'},
        {'jrs_clothing_outfits', 'gender'},
    }
    for _, pair in ipairs(required) do
        if not requiredColumn(pair[1], pair[2]) then
            print(('[jrs_clothing] Missing required SQL column: %s.%s'):format(pair[1], pair[2]))
            JRSClothingDatabaseReady = false
            return
        end
    end

    JRSClothingDatabaseReady = true

    -- The outfit is a normal inventory item. Keep item initialization separate
    -- from clothing SQL readiness and refresh jrs_inventory's item cache.
    local itemOk, itemResult = pcall(ensureOrdinaryOutfitItem)
    if not itemOk or itemResult ~= true then
        print(('[jrs_clothing] Outfit item initialization failed: %s'):format(tostring(itemResult)))
    end
end)

-- Shape check for clothing / wearable tables a client sends straight into the
-- DB (jrs_clothes:updateclothes, jrs_clothing:SaveWearable). Keeps the normal
-- { category = { model = n, texture = n | { palette, tint0.. } } } layout and
-- drops anything else: huge tables, odd keys, NaN/inf, nested junk. Stops a
-- modified client from bloating its row or storing data that later breaks
-- every client that reads it back. Returns nil when nothing usable is left.
local function cleanScalar(value)
    local t = type(value)
    if t == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        if value > 4294967295 or value < -4294967296 then return nil end
        return value
    elseif t == 'boolean' then
        return value
    elseif t == 'string' then
        if #value > 64 then return nil end
        return value
    end
    return nil
end

function JRSClothingSanitizePayload(payload)
    if type(payload) ~= 'table' then return nil end
    local clean, count = {}, 0
    for category, entry in pairs(payload) do
        local key = tostring(category or '')
        -- ~155 real categories exist; a lower cap dropped random pieces.
        if count >= 256 then break end
        if #key > 0 and #key <= 64 and key:match('^[%w_%-]+$') and type(entry) == 'table' then
            local out = {}
            for field, value in pairs(entry) do
                local fname = tostring(field or '')
                if #fname <= 32 and fname:match('^[%w_]+$') then
                    if fname == 'texture' and type(value) == 'table' then
                        local tex = {}
                        for tk, tv in pairs(value) do
                            local tname = tostring(tk or '')
                            if #tname <= 32 and tname:match('^[%w_]+$') then
                                tex[tname] = cleanScalar(tv)
                            end
                        end
                        out.texture = tex
                    else
                        out[fname] = cleanScalar(value)
                    end
                end
            end
            if out.model ~= nil and type(out.model) ~= 'number' then out.model = tonumber(out.model) or 0 end
            clean[key] = out
            count = count + 1
        end
    end
    return clean
end
