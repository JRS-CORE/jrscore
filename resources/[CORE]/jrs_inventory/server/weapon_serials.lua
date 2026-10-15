-- ===========================================================================
-- Weapon Serial Numbers
-- Adds one permanent, unique serial number to every weaponloadout row.
-- The serial never changes when the weapon is given, dropped, or stored.
-- ===========================================================================

WeaponSerialSystemReady = false
WeaponSerialSystemAvailable = false

local readyCallbacks = {}
local migrationRunning = false
local serialCounter = 0

local function serialConfig()
    return Config.WeaponSerials or {}
end

local function cleanPrefix(value)
    value = tostring(value or "JRS"):upper():gsub("[^A-Z0-9]", "")
    if value == "" then value = "JRS" end
    return value:sub(1, 10)
end

local function randomSerialPart(length)
    local alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local output = {}
    length = math.max(4, math.min(20, tonumber(length) or 8))
    for index = 1, length do
        local position = math.random(1, #alphabet)
        output[index] = alphabet:sub(position, position)
    end
    return table.concat(output)
end

function GenerateWeaponSerial()
    serialCounter = serialCounter + 1
    local cfg = serialConfig()
    local prefix = cleanPrefix(cfg.Prefix)
    local datePart = os.date("!%Y%m%d")
    local timerPart = string.format("%08X", math.floor((GetGameTimer() + serialCounter) % 0xFFFFFFFF))
    return string.format("%s-%s-%s-%s", prefix, datePart, timerPart, randomSerialPart(cfg.RandomLength))
end

-- Black Market weapons never get a legitimate-looking serial. This format is
-- deliberately obvious/fake (STOLEN-XXXX-XXXX) so it reads at a glance as a
-- filed/forged number, while still satisfying NormalizeWeaponSerial.
function GenerateStolenWeaponSerial()
    serialCounter = serialCounter + 1
    return string.format("STOLEN-%s-%s", randomSerialPart(4), randomSerialPart(4))
end

function NormalizeWeaponSerial(value)
    if value == nil then return nil end
    local serial = tostring(value):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if serial == "" or #serial > 64 then return nil end
    if not serial:match("^[A-Z0-9%-]+$") then return nil end
    return serial
end

function WhenWeaponSerialSystemReady(callback)
    if type(callback) ~= "function" then return end
    if WeaponSerialSystemReady then
        callback(WeaponSerialSystemAvailable == true)
        return
    end
    table.insert(readyCallbacks, callback)
end

local function finishSerialMigration(success, reason)
    WeaponSerialSystemReady = true
    WeaponSerialSystemAvailable = success == true
    migrationRunning = false

    if success then
        Citizen.SetTimeout(250, function()
            for _, playerId in ipairs(GetPlayers()) do
                TriggerEvent("jrs_inventory:get_items_sec", tonumber(playerId))
            end
        end)
    else
        print("[jrs_inventory] Weapon serial system failed: " .. tostring(reason or "unknown"))
    end

    local callbacks = readyCallbacks
    readyCallbacks = {}
    for _, callback in ipairs(callbacks) do
        pcall(callback, success == true)
    end
end

local function execute(query, params, callback)
    exports[Config.MysqlResource]:execute(query, params or {}, callback or function() end)
end

local function ensureUniqueIndex(callback)
    execute("SHOW INDEX FROM jrs_weaponloadout WHERE Key_name='uniq_weapon_serial'", {}, function(rows)
        if rows and rows[1] then
            callback(true)
            return
        end

        execute("ALTER TABLE jrs_weaponloadout ADD UNIQUE KEY uniq_weapon_serial (serial_number)", {}, function(result)
            if result == nil or result == false then
                callback(false, "unique_index_failed")
                return
            end
            callback(true)
        end)
    end)
end

-- Black Market weapons are flagged with a `stolen` column so the rest of the
-- system (inventory badge, jrs_weapons customization, police search) can tell
-- them apart from legitimately-bought weapons. Migrated alongside the serial
-- column so weapon creation waits for both before it ever writes a row.
local function ensureStolenColumn(callback)
    execute("SHOW COLUMNS FROM jrs_weaponloadout LIKE 'stolen'", {}, function(rows)
        if rows and rows[1] then
            callback(true)
            return
        end

        execute("ALTER TABLE jrs_weaponloadout ADD COLUMN stolen TINYINT(1) NOT NULL DEFAULT 0", {}, function(result)
            if result == nil or result == false then
                callback(false, "stolen_column_migration_failed")
                return
            end
            callback(true)
        end)
    end)
end

-- Weapons delivered from a jrs_weapons package remember that package's name so
-- the inventory info panel can show it. NULL for every other weapon.
local function ensurePackageColumn(callback)
    execute("SHOW COLUMNS FROM jrs_weaponloadout LIKE 'package_name'", {}, function(rows)
        if rows and rows[1] then
            callback(true)
            return
        end

        execute("ALTER TABLE jrs_weaponloadout ADD COLUMN package_name VARCHAR(64) NULL DEFAULT NULL AFTER stolen", {}, function(result)
            if result == nil or result == false then
                callback(false, "package_column_migration_failed")
                return
            end
            callback(true)
        end)
    end)
end

local function ensureCustomNameColumn(callback)
    execute("SHOW COLUMNS FROM jrs_weaponloadout LIKE 'custom_name'", {}, function(rows)
        if rows and rows[1] then
            callback(true)
            return
        end

        execute("ALTER TABLE jrs_weaponloadout ADD COLUMN custom_name VARCHAR(100) NULL DEFAULT NULL AFTER package_name", {}, function(result)
            if result == nil or result == false then
                callback(false, "custom_name_column_migration_failed")
                return
            end
            callback(true)
        end)
    end)
end

local function backfillWeaponSerials(callback)
    execute("SELECT id, serial_number FROM jrs_weaponloadout ORDER BY id ASC", {}, function(rows)
        rows = rows or {}
        local seen = {}
        local updates = {}

        for _, row in ipairs(rows) do
            local weaponId = tonumber(row.id)
            local current = NormalizeWeaponSerial(row.serial_number)
            if not current or seen[current] then
                local replacement
                repeat
                    replacement = GenerateWeaponSerial()
                until not seen[replacement]
                table.insert(updates, { id = weaponId, serial = replacement })
                seen[replacement] = true
            else
                seen[current] = true
            end
        end

        if #updates == 0 then
            callback(true)
            return
        end

        local remaining = #updates
        local failed = false
        for _, update in ipairs(updates) do
            execute(
                "UPDATE jrs_weaponloadout SET serial_number=@serial WHERE id=@id",
                { ['serial'] = update.serial, ['id'] = update.id },
                function(result)
                    if result == nil or result == false then failed = true end
                    remaining = remaining - 1
                    if remaining == 0 then callback(not failed, failed and "backfill_failed" or nil) end
                end
            )
        end
    end)
end

local function runSerialMigration()
    if migrationRunning or WeaponSerialSystemReady then return end
    migrationRunning = true

    execute("SHOW COLUMNS FROM jrs_weaponloadout LIKE 'serial_number'", {}, function(rows)
        local function continueMigration()
            ensureStolenColumn(function(stolenOk, stolenReason)
                if not stolenOk then
                    finishSerialMigration(false, stolenReason)
                    return
                end
                ensurePackageColumn(function(packageOk, packageReason)
                if not packageOk then
                    finishSerialMigration(false, packageReason)
                    return
                end
                ensureCustomNameColumn(function(customNameOk, customNameReason)
                if not customNameOk then
                    finishSerialMigration(false, customNameReason)
                    return
                end
                backfillWeaponSerials(function(backfillOk, backfillReason)
                    if not backfillOk then
                        finishSerialMigration(false, backfillReason)
                        return
                    end
                    ensureUniqueIndex(function(indexOk, indexReason)
                        finishSerialMigration(indexOk, indexReason)
                    end)
                end)
                end)
                end)
            end)
        end

        if rows and rows[1] then
            continueMigration()
            return
        end

        if serialConfig().AutoMigrate == false then
            finishSerialMigration(false, "serial_number column missing and AutoMigrate is disabled")
            return
        end

        execute("ALTER TABLE jrs_weaponloadout ADD COLUMN serial_number VARCHAR(64) NULL AFTER id", {}, function(result)
            if result == nil or result == false then
                finishSerialMigration(false, "column_migration_failed")
                return
            end
            continueMigration()
        end)
    end)
end

-- Assign a serial to weapons inserted by older external resources that still
-- write directly to weaponloadout without the serial_number column.
local function scanForMissingSerials()
    if not WeaponSerialSystemAvailable then return end
    backfillWeaponSerials(function(ok, reason)
        if not ok and Config.Debug then
            print("[jrs_inventory] Weapon serial maintenance failed: " .. tostring(reason))
        end
    end)
end

Citizen.CreateThread(function()
    math.randomseed(os.time() + GetGameTimer())
    Citizen.Wait(250)
    runSerialMigration()

    while true do
        Citizen.Wait(math.max(30000, tonumber(serialConfig().MaintenanceIntervalMs) or 60000))
        scanForMissingSerials()
    end
end)
