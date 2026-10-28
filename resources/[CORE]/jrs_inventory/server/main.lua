-- ===========================================================================
-- Core setup & shared state
-- ===========================================================================

-- jrs_core's own getCoreApi() rebuilds a fresh table of cross-resource funcrefs
-- on every call (server/api.lua: exports('getCoreApi', buildUnifiedServerAPI)).
-- Caching the result once here meant a jrs_core restart while jrs_inventory
-- kept running left every jrsCore.xxx(...) call site pointing at funcrefs bound
-- to the dead pre-restart instance, breaking inventory load/save server-wide
-- until jrs_inventory itself was also restarted. Re-resolve on each access
-- instead, same pattern as jrs_metabolism's JRSinv proxy for jrs_inventory.
local function isCallable(fn)
    if fn == nil then return false end
    local t = type(fn)
    if t == 'function' or t == 'userdata' then return true end
    if t == 'table' then
        local mt = getmetatable(fn)
        if mt and mt.__call then return true end
        if rawget(fn, '__cfx_functionReference') ~= nil then return true end
    end
    return false
end

local function GetPlayerCharacter(source)
    local src = tonumber(source)
    if not src or src <= 0 then return nil end
    local char = exports[Config.CoreResource or 'jrs_core']:GetCharacter(src) or (jrsCore and jrsCore.GetCharacter and jrsCore.GetCharacter(src))
    if char then return char end
    local user = jrsCore and jrsCore.getUser and jrsCore.getUser(src)
    return user and (user.character or user.getUsedCharacter) or nil
end

local jrsCoreWarnedAt = {}
local JRS_CORE_WARN_THROTTLE_MS = 30000
jrsCore = setmetatable({}, {
    __index = function(_, key)
        return function(...)
            -- getUser is inventory-critical. Resolve it through the
            -- compatibility layer loaded by server/jrsInventoryAPI.lua.
            -- IMPORTANT: nil can legitimately mean "character not ready";
            -- never fall through and report that as "no such API method".
            if key == "GetCharacter" or key == "getCharacter" then
                local args = { ... }
                local src = tonumber(args[1])
                if not src or src <= 0 then return nil end
                local ok, char = pcall(function() return exports[Config.CoreResource or 'jrs_core']:GetCharacter(src) end)
                if ok and char then return char end
                if type(JRSInventoryGetCoreUser) == "function" then
                    local u = JRSInventoryGetCoreUser(src)
                    return u and u.getUsedCharacter or nil
                end
                return nil
            end

            if key == "getUser" or key == "GetUser" then
                local args = { ... }
                if type(JRSInventoryGetCoreUser) == "function" then
                    return JRSInventoryGetCoreUser(tonumber(args[1]))
                end
                return nil
            end

            -- Debug messages should only be processed when Config.Debug is active.
            -- When debug is disabled, return quietly without warning.
            if key == "Debug" or key == "debug" then
                if not Config.Debug then return end
                local args = { ... }
                local msg = tostring(args[1] or "")
                local ok, api = pcall(function() return exports[Config.CoreResource]:getCoreApi() end)
                if ok and type(api) == "table" and isCallable(api.Debug) then
                    local okDebug = pcall(api.Debug, msg)
                    if okDebug then return end
                end
                print(("^2[jrs_inventory] %s^0"):format(msg))
                return
            end

            local ok, api = pcall(function() return exports[Config.CoreResource]:getCoreApi() end)
            if not ok or type(api) ~= "table" or not isCallable(api[key]) then
                local now = GetGameTimer()
                if not jrsCoreWarnedAt[key] or (now - jrsCoreWarnedAt[key]) > JRS_CORE_WARN_THROTTLE_MS then
                    jrsCoreWarnedAt[key] = now
                    -- Logging the actual pcall failure reason (previously discarded)
                    -- turns this from a dead-end warning into something actionable
                    -- if jrs_core's getCoreApi() is genuinely erroring, not just slow
                    -- to associate this connection with its loaded character yet.
                    print(("^1[jrs_inventory] jrs_core API unavailable - \"%s\" was skipped. ok=%s reason=%s^0")
                        :format(tostring(key), tostring(ok), tostring(not ok and api or (type(api) ~= "table" and "getCoreApi() did not return a table" or "no such API method"))))
                end
                return nil
            end
            return api[key](...)
        end
    end,
})

Inventory = exports.jrs_inventory:jrs_inventoryApi()

itemTableForData = {}
itemTableForDataLower = {}
weaponTableForData = {}
weaponNameLookup = {}

-- itemTableForData is keyed by the exact casing of the `items` DB table's
-- `item` column. A player's saved inventory (characters.inventory JSON) can
-- carry a different casing for the same item (e.g. renamed/re-cased over
-- time, or granted through a code path with different casing), which made
-- the direct itemTableForData[b.item] lookup return nil and silently drop
-- that item from the payload sent to the NUI - it never reached the client,
-- with no error logged. Fall back to a case-insensitive lookup so a casing
-- mismatch degrades to "resolved via lowercase" instead of "item vanishes".
function ResolveItemDef(name)
    if name == nil then return nil end
    local def = itemTableForData and itemTableForData[name]
    if not def and itemTableForDataLower and type(name) == "string" then
        def = itemTableForDataLower[name:lower()]
    end
    if def then
        -- One blocking DB read per definition, not per call: this runs on every
        -- item resolve (render, use, weight) and used to stall the thread each time.
        if not def._limitChecked and tonumber(def.limit) and tonumber(def.limit) >= 10 then
            def._limitChecked = true
            pcall(function()
                local row = nil
                if MySQL and MySQL.single and MySQL.single.await then
                    row = MySQL.single.await('SELECT `limit` FROM jrs_items WHERE item = ? LIMIT 1', { def.item or name })
                end
                if row and row.limit and tonumber(row.limit) < tonumber(def.limit) then
                    def.limit = tonumber(row.limit)
                end
            end)
        end
        return def
    end

    if type(name) == "string" and name ~= "" then
        local row = nil
        pcall(function()
            if MySQL and MySQL.single and MySQL.single.await then
                row = MySQL.single.await('SELECT * FROM jrs_items WHERE item = ? LIMIT 1', { name })
            elseif exports and Config and Config.MysqlResource and exports[Config.MysqlResource] and exports[Config.MysqlResource].executeSync then
                local res = exports[Config.MysqlResource]:executeSync('SELECT * FROM jrs_items WHERE item = @item LIMIT 1', { ['@item'] = name })
                row = res and res[1] or nil
            end
        end)
        if row and type(row) == "table" and row.item then
            local isUsable = (row.usable == 1 or row.usable == true)
            if not isUsable and usableItemsFunctions and (usableItemsFunctions[row.item] or (type(row.item) == 'string' and usableItemsFunctions[row.item:lower()])) then
                isUsable = true
            end
            local newDef = {
                item = row.item,
                label = row.label or row.item,
                label_ar = row.label_ar or row.label,
                limit = tonumber(row.limit) or 0.1,
                can_remove = row.can_remove,
                type = row.type or "item_standard",
                usable = isUsable and 1 or 0,
                descriptions = row.descriptions,
                descriptions_ar = row.descriptions_ar,
                metadata = row.metadata,
                category = row.category
            }
            if itemTableForData then itemTableForData[row.item] = newDef end
            if itemTableForDataLower then itemTableForDataLower[row.item:lower()] = newDef end
            if type(table_item) == "table" then
                table.insert(table_item, row)
            end
            return newDef
        end

        if JrsItemTranslations and JrsItemTranslations[name] then
            local trans = JrsItemTranslations[name]
            local newDef = {
                item = name,
                label = trans.label or name,
                label_ar = trans.label or name,
                limit = 0.1,
                can_remove = 1,
                type = "item_standard",
                usable = 0,
                descriptions = trans.descriptions or "",
                descriptions_ar = trans.descriptions or "",
                metadata = "0",
                category = "general"
            }
            if itemTableForData then itemTableForData[name] = newDef end
            if itemTableForDataLower then itemTableForDataLower[name:lower()] = newDef end
            return newDef
        end
    end
    return nil
end

function ResolveInventoryWeaponName(name)
    if name == nil then return nil end
    local key = string.upper(tostring(name))
    if weaponTableForData[key] ~= nil or weaponNameLookup[key] ~= nil then
        return key
    end
    return nil
end
table_item = {}
weapons_table = {}
inv_table = {}
usableItemsFunctions = {}
in_inventory_weapons = {}
new_table = {}

function GetMaxWeight(source)
    local src = tonumber(source)
    if src then
        local state = Player(src).state
        local perks = state and state.jrsPerks
        if perks and tonumber(perks.carryKg) then
            return tonumber(perks.carryKg)
        end
        if GetResourceState('jrs_core') == 'started' then
            local ok, cap = pcall(function() return exports.jrs_core:GetCarryCapacity(src) end)
            if ok and tonumber(cap) then
                return tonumber(cap)
            end
        end
    end
    local fallback = tonumber(Config and Config.Max_Items) or 50
    return fallback
end

exports('GetMaxWeight', GetMaxWeight)

function getMaxWeapons(source)
    local job = "default"
    local Character = GetPlayerCharacter(source)
    if Character then
        local rawJob = Character.job
        if type(rawJob) == "table" then
            rawJob = rawJob.name or rawJob.job or rawJob.id
        end
        if rawJob ~= nil and tostring(rawJob) ~= "" then
            job = string.lower(tostring(rawJob))
        end
    end

    local configured = Config.WeaponLimitByJob and Config.WeaponLimitByJob[job]
    if configured == nil and job ~= "default" and Config.WeaponLimitByJobPrefix then
        for prefix, limit in pairs(Config.WeaponLimitByJobPrefix) do
            if job:sub(1, #prefix) == string.lower(prefix) then
                configured = math.max(tonumber(configured) or 0, tonumber(limit) or 0)
            end
        end
    end
    local hasJobOverride = configured ~= nil and job ~= "default"
    if configured == nil and Config.WeaponLimitByJob then
        configured = Config.WeaponLimitByJob.default
    end
    local jobLimit = math.max(0, math.floor(tonumber(configured) or tonumber(Config.Max_Weapons) or 4))

    local perkSlots = math.max(0, math.floor(tonumber(Config.Max_Weapons) or 4))
    local src = tonumber(source)
    if src then
        local state = Player(src).state
        local perks = state and state.jrsPerks
        if perks and tonumber(perks.weaponSlots) then
            perkSlots = tonumber(perks.weaponSlots)
        elseif GetResourceState('jrs_core') == 'started' then
            local ok, slots = pcall(function() return exports.jrs_core:GetWeaponSlots(src) end)
            if ok and tonumber(slots) then perkSlots = tonumber(slots) end
        end
    end

    if hasJobOverride and jobLimit > perkSlots then
        return jobLimit
    end
    return perkSlots
end

exports('GetMaxWeapons', getMaxWeapons)

AddEventHandler('jrs_core:server:levelPerksUpdated', function(src, perks)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end
    if inventory_table_sended and inventory_table_sended[src] then
        TriggerClientEvent("jrs_inventory:send_list_inventory", src, inventory_table_sended[src], weapon_table and weapon_table[src] or {}, false, false, hotbarByPlayer and hotbarByPlayer[src], getMaxWeapons(src))
    end
end)

local UTILITY_WEAPONS = {
    ['WEAPON_LASSO'] = true,
    ['WEAPON_LASSO_REINFORCED'] = true,
    ['WEAPON_FISHINGROD'] = true,
    ['WEAPON_KIT_BINOCULARS'] = true,
    ['WEAPON_KIT_BINOCULARS_IMPROVED'] = true,
    ['WEAPON_KIT_CAMERA'] = true,
    ['WEAPON_KIT_CAMERA_ADVANCED'] = true,
    ['WEAPON_KIT_METAL_DETECTOR'] = true,
    ['WEAPON_MELEE_LANTERN'] = true,
    ['WEAPON_MELEE_DAVY_LANTERN'] = true,
    ['WEAPON_MELEE_LANTERN_HALLOWEEN'] = true,
    ['WEAPON_THROWN_BOLAS'] = true,
    ['WEAPON_THROWN_BOLAS_HAWKMOTH'] = true,
    ['WEAPON_THROWN_BOLAS_INTERTWINED'] = true,
    ['WEAPON_THROWN_BOLAS_IRONSPIKED'] = true,
    ['WEAPON_THROWN_THROWING_KNIVES'] = true,
    ['WEAPON_THROWN_TOMAHAWK'] = true,
    ['WEAPON_THROWN_TOMAHAWK_ANCIENT'] = true,
    ['WEAPON_THROWN_TOMAHAWK_HOMING'] = true,
    ['WEAPON_THROWN_DYNAMITE'] = true,
    ['WEAPON_THROWN_MOLOTOV'] = true,
}

function IsUtilityWeapon(weaponName)
    if weaponName == nil then return false end
    local upper = string.upper(tostring(weaponName))
    if UTILITY_WEAPONS[upper] or upper:find('^WEAPON_THROWN_') or upper:find('BOLAS') then return true end
    local resolved = ResolveInventoryWeaponName(weaponName)
    return resolved ~= nil and (UTILITY_WEAPONS[resolved] == true or resolved:find('^WEAPON_THROWN_') ~= nil or resolved:find('BOLAS') ~= nil)
end

function ShouldCountWeaponTowardLimit(weaponName)
    if IsUtilityWeapon(weaponName) then return false end
    if Config.CountUnknownWeaponsTowardLimit == true then return true end
    if next(weaponTableForData or {}) == nil then return true end
    return ResolveInventoryWeaponName(weaponName) ~= nil
end

searched = {}
inventory_table_sended = {}
in_inventory = {}
weapon_table = {}
hotbarByPlayer = {}
clientDefinitionsSent = {}
in_inventory_count = {}
count_calc = {}
openstorages = {}
canSaveInventory = {}
-- Cache safety: only data loaded from characters.inventory for the SAME active
-- character is allowed to be written back. This blocks empty/stale caches after
-- txAdmin restarts, source-id reuse and character switches.
inventoryLoaded = {}
inventoryLoadedIdentity = {}
lastActionAt = {}
inventoryTransferLocks = {}
inventoryResourceLocks = {}
inventoryOperationClaims = {}
inventorySecurityViolations = {}
inventoryRequestBuckets = {}
local INVENTORY_LOCK_TIMEOUT_MS = tonumber(Config.AntiDupe and Config.AntiDupe.LockTimeoutMs) or 30000

local function securityConfig()
    return type(Config.Security) == "table" and Config.Security or {}
end

function InventoryPayloadSize(value)
    local ok, encoded = pcall(json.encode, value)
    if not ok or type(encoded) ~= "string" then return math.huge end
    return #encoded
end

function AllowInventoryRequest(playerId, action, customLimit, customWindowMs)
    playerId = tonumber(playerId)
    action = tostring(action or "unknown")
    if not playerId or playerId <= 0 then return false end

    local settings = securityConfig()
    local limits = type(settings.RequestLimits) == "table" and settings.RequestLimits or {}
    local limit = math.max(1, math.floor(tonumber(customLimit or limits[action]) or 10))
    local windowMs = math.max(500, math.floor(tonumber(customWindowMs or settings.RequestWindowMs) or 5000))
    local now = GetGameTimer()

    inventoryRequestBuckets[playerId] = inventoryRequestBuckets[playerId] or {}
    local bucket = inventoryRequestBuckets[playerId][action]
    if type(bucket) ~= "table" or now >= (tonumber(bucket.resetAt) or 0) then
        inventoryRequestBuckets[playerId][action] = { count = 1, resetAt = now + windowMs, blockedLogged = false }
        return true
    end

    bucket.count = (tonumber(bucket.count) or 0) + 1
    if bucket.count <= limit then return true end

    if bucket.blockedLogged ~= true then
        bucket.blockedLogged = true
        RecordInventorySecurityViolation(playerId, "request_rate_limit", action .. ":" .. tostring(bucket.count))
    end
    return false
end

-- ===========================================================================
-- Player-to-player transfer safety
-- ===========================================================================

local function inventoryLockKey(playerId)
	playerId = tonumber(playerId)
	if not playerId then return nil end
	return "player:" .. tostring(playerId)
end

local function inventoryLockIsActive(key)
	if not key then return false end
	local expiresAt = tonumber(inventoryTransferLocks[key])
	if not expiresAt then return false end
	if expiresAt <= GetGameTimer() then
		inventoryTransferLocks[key] = nil
		return false
	end
	return true
end

function TryLockInventoryPlayer(playerId)
	local key = inventoryLockKey(playerId)
	if not key or inventoryLockIsActive(key) then return false end
	inventoryTransferLocks[key] = GetGameTimer() + INVENTORY_LOCK_TIMEOUT_MS
	return true
end

function UnlockInventoryPlayer(playerId)
	local key = inventoryLockKey(playerId)
	if key then inventoryTransferLocks[key] = nil end
end

function TryLockInventoryPlayers(firstPlayer, secondPlayer)
	firstPlayer = tonumber(firstPlayer)
	secondPlayer = tonumber(secondPlayer)
	if not firstPlayer or not secondPlayer or firstPlayer == secondPlayer then return false end

	local firstKey = inventoryLockKey(firstPlayer)
	local secondKey = inventoryLockKey(secondPlayer)
	if inventoryLockIsActive(firstKey) or inventoryLockIsActive(secondKey) then
		return false
	end

	local expiresAt = GetGameTimer() + INVENTORY_LOCK_TIMEOUT_MS
	inventoryTransferLocks[firstKey] = expiresAt
	inventoryTransferLocks[secondKey] = expiresAt
	return true
end

function UnlockInventoryPlayers(firstPlayer, secondPlayer)
	UnlockInventoryPlayer(firstPlayer)
	UnlockInventoryPlayer(secondPlayer)
end

local function inventoryResourceLockKey(resourceType, resourceId)
    resourceType = tostring(resourceType or "resource")
    resourceId = tostring(resourceId or "")
    if resourceId == "" then return nil end
    return resourceType .. ":" .. resourceId
end

local function getInventoryResourceLock(key)
    if not key then return nil end
    local lock = inventoryResourceLocks[key]
    if lock == nil then return nil end

    -- Backward-compatible with an older numeric lock value during a live restart.
    if type(lock) ~= "table" then
        lock = { expiresAt = tonumber(lock), owner = nil }
        inventoryResourceLocks[key] = lock
    end

    local expiresAt = tonumber(lock.expiresAt)
    if not expiresAt or expiresAt <= GetGameTimer() then
        inventoryResourceLocks[key] = nil
        return nil
    end
    return lock
end

local function resourceLockIsActive(key)
    return getInventoryResourceLock(key) ~= nil
end

function TryLockInventoryResource(resourceType, resourceId, ownerPlayerId)
    local key = inventoryResourceLockKey(resourceType, resourceId)
    if not key or resourceLockIsActive(key) then return false end
    inventoryResourceLocks[key] = {
        expiresAt = GetGameTimer() + INVENTORY_LOCK_TIMEOUT_MS,
        owner = tonumber(ownerPlayerId)
    }
    return true
end

function UnlockInventoryResource(resourceType, resourceId, ownerPlayerId)
    local key = inventoryResourceLockKey(resourceType, resourceId)
    if not key then return false end

    local lock = getInventoryResourceLock(key)
    if not lock then return true end

    local requestedOwner = tonumber(ownerPlayerId)
    local lockOwner = tonumber(lock.owner)
    if requestedOwner and lockOwner and requestedOwner ~= lockOwner then
        return false
    end

    inventoryResourceLocks[key] = nil
    return true
end

function TryLockInventoryPlayerAndResource(playerId, resourceType, resourceId)
    playerId = tonumber(playerId)
    local playerKey = inventoryLockKey(playerId)
    local resourceKey = inventoryResourceLockKey(resourceType, resourceId)
    if not playerKey or not resourceKey then return false end
    if inventoryLockIsActive(playerKey) or resourceLockIsActive(resourceKey) then return false end

    local expiresAt = GetGameTimer() + INVENTORY_LOCK_TIMEOUT_MS
    inventoryTransferLocks[playerKey] = expiresAt
    inventoryResourceLocks[resourceKey] = { expiresAt = expiresAt, owner = playerId }
    return true
end

function UnlockInventoryPlayerAndResource(playerId, resourceType, resourceId)
    UnlockInventoryPlayer(playerId)
    UnlockInventoryResource(resourceType, resourceId, playerId)
end

function ReleaseInventoryResourcesOwnedBy(playerId)
    playerId = tonumber(playerId)
    if not playerId then return end
    for key, lock in pairs(inventoryResourceLocks) do
        if type(lock) == "table" and tonumber(lock.owner) == playerId then
            inventoryResourceLocks[key] = nil
        end
    end
end

local function cleanOperationId(value)
    if value == nil then return nil end
    local operationId = tostring(value)
    if operationId == "" or #operationId > 96 then return nil end
    if not operationId:match("^[%w%-%_:%./]+$") then return nil end
    return operationId
end

function RecordInventorySecurityViolation(playerId, reason, details)
    playerId = tonumber(playerId)
    if not playerId then return end
    inventorySecurityViolations[playerId] = (inventorySecurityViolations[playerId] or 0) + 1

    if not Config.AntiDupe or Config.AntiDupe.LogBlockedActions ~= false then
        local strikes = inventorySecurityViolations[playerId]
        if strikes <= 3 or strikes % 10 == 0 then
            print(("[jrs_inventory][ANTI-DUPE] blocked source=%s reason=%s details=%s strikes=%s")
                :format(tostring(playerId), tostring(reason), tostring(details or "none"), tostring(strikes)))
        end
    end

    if type(JRSInventorySecurityLog) == "function" then
        JRSInventorySecurityLog(playerId, reason, details, inventorySecurityViolations[playerId])
    end

    local maxViolations = tonumber(Config.AntiDupe and Config.AntiDupe.MaxViolationsBeforeDrop) or 0
    if maxViolations > 0 and inventorySecurityViolations[playerId] >= maxViolations then
        DropPlayer(playerId, "Inventory security: repeated invalid transfer requests.")
    end
end

-- Claims a client-generated operation id. Replayed packets keep the same id and
-- are rejected even if they arrive after the first database callback completed.
-- Older callers without an id use a short fingerprint window for compatibility.
function ClaimInventoryOperation(playerId, operationId, fingerprint)
    if not Config.AntiDupe or Config.AntiDupe.Enabled == false then return true end
    playerId = tonumber(playerId)
    if not playerId then return false end

    if not AllowInventoryRequest(playerId, "inventory_operation") then
        return false
    end

    local now = GetGameTimer()
    local cleanId = cleanOperationId(operationId)
    local ttl
    local claimKey
    if cleanId then
        ttl = tonumber(Config.AntiDupe.OperationReplayWindowMs) or 120000
        claimKey = ("player:%s:operation:%s"):format(playerId, cleanId)
    else
        ttl = tonumber(Config.AntiDupe.LegacyReplayWindowMs) or 1500
        claimKey = ("player:%s:legacy:%s"):format(playerId, tostring(fingerprint or "unknown"))
    end

    local expiresAt = tonumber(inventoryOperationClaims[claimKey])
    if expiresAt and expiresAt > now then
        RecordInventorySecurityViolation(playerId, "replayed_operation", fingerprint or cleanId)
        return false
    end

    inventoryOperationClaims[claimKey] = now + ttl
    return true
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        local now = GetGameTimer()
        for key, expiresAt in pairs(inventoryOperationClaims) do
            if tonumber(expiresAt) and tonumber(expiresAt) <= now then
                inventoryOperationClaims[key] = nil
            end
        end
    end
end)

function ArePlayersWithinTransferDistance(firstPlayer, secondPlayer)
	firstPlayer = tonumber(firstPlayer)
	secondPlayer = tonumber(secondPlayer)
	if not firstPlayer or not secondPlayer or firstPlayer == secondPlayer then return false end
	if not playerIsActive(firstPlayer) or not playerIsActive(secondPlayer) then return false end

	local firstPed = GetPlayerPed(firstPlayer)
	local secondPed = GetPlayerPed(secondPlayer)
	if not firstPed or firstPed == 0 or not secondPed or secondPed == 0 then
		return false
	end

	local firstCoords = GetEntityCoords(firstPed)
	local secondCoords = GetEntityCoords(secondPed)
	if not firstCoords or not secondCoords then return false end

	local dx = tonumber(firstCoords.x) - tonumber(secondCoords.x)
	local dy = tonumber(firstCoords.y) - tonumber(secondCoords.y)
	local dz = tonumber(firstCoords.z) - tonumber(secondCoords.z)
	local baseDistance = tonumber(Config.PlayerTransferDistance or Config.InteractionDistance) or 4.5
	local maxDistance = math.max(5.0, baseDistance + 0.75)
	return (dx * dx + dy * dy + dz * dz) <= (maxDistance * maxDistance)
end

-- ===========================================================================
-- Shared validation helpers
-- ===========================================================================

function isOnCooldown(src)
	local now = GetGameTimer()
	if lastActionAt[src] ~= nil and (now - lastActionAt[src]) < Config.ActionCooldownMs then
		return true
	end
	lastActionAt[src] = now
	return false
end

function isValidCount(count)
	local n = tonumber(count)
	-- n < 1e7 also rejects infinity (floor(inf) == inf) - 2026-10-02
	return n ~= nil and n == math.floor(n) and n > 0 and n < 1e7
end

function isValidTarget(id)
	local n = tonumber(id)
	if n == nil then return false end
	return playerIsActive(n)
end

-- Called for every other open storage on each transfer; GetPlayerName is a
-- direct lookup instead of building and scanning the whole player list.
function playerIsActive(playerId)
	local id = tonumber(playerId)
	if not id or id <= 0 then return false end
	return GetPlayerName(tostring(id)) ~= nil
end

-- Runs all related writes in one database transaction. This is used for
-- transfers where committing only one side could duplicate or lose inventory.
function RunInventoryTransaction(queries, callback)
    callback = type(callback) == "function" and callback or function() end
    if type(queries) ~= "table" or #queries == 0 then
        callback(false)
        return
    end

    if MySQL and type(MySQL.transaction) == "function" then
        MySQL.transaction(queries, function(success)
            callback(success == true)
        end)
        return
    end

    -- Compatibility fallback for installations that expose only the oxmysql
    -- export. The fxmanifest loads @oxmysql/lib/MySQL.lua, so this path should
    -- normally not be needed.
    local ok = pcall(function()
        exports[Config.MysqlResource]:transaction(queries, function(success)
            callback(success == true)
        end)
    end)
    if not ok then callback(false) end
end

-- ===========================================================================
-- Inventory cache identity / persistence guard
-- ===========================================================================

local function InventoryCharacterIdentity(Character)
    if not Character then return nil end
    if Character.identifier == nil or Character.charIdentifier == nil then return nil end
    return tostring(Character.identifier) .. ":" .. tostring(Character.charIdentifier)
end

function MarkInventoryLoaded(source, Character)
    local src = tonumber(source)
    local identity = InventoryCharacterIdentity(Character)
    if not src or not identity or type(inv_table[src]) ~= "table" then return false end
    inventoryLoaded[src] = true
    inventoryLoadedIdentity[src] = identity
    return true
end

function IsInventoryLoadedForPlayer(source, Character)
    local src = tonumber(source)
    if not src or inventoryLoaded[src] ~= true or type(inv_table[src]) ~= "table" then
        return false
    end

    if not Character then
        Character = GetPlayerCharacter(src)
    end

    local identity = InventoryCharacterIdentity(Character)
    return identity ~= nil and inventoryLoadedIdentity[src] == identity
end

function InvalidateInventoryCache(source, clearData)
    local src = tonumber(source)
    if not src then return end
    inventoryLoaded[src] = nil
    inventoryLoadedIdentity[src] = nil
    canSaveInventory[src] = false
    if clearData == true then
        inv_table[src] = nil
        inventory_table_sended[src] = nil
    end
end

-- ===========================================================================
-- Inventory save
-- ===========================================================================

function SaveInventoryNow(source)
    local src = tonumber(source)
    if not src or type(inv_table[src]) ~= "table" then
        return false
    end

    local Character = GetPlayerCharacter(src)
    if not Character then
        return false
    end

    -- Empty inventories are valid only when that empty table was actually
    -- loaded from the database for this exact character.
    if not IsInventoryLoadedForPlayer(src, Character) then
        if Config.Debug then
            print(("[jrs_inventory] BLOCKED unsafe inventory save for source %s (cache not loaded or character changed)"):format(src))
        end
        return false
    end

    local encodedOk, inventoryJson = pcall(json.encode, inv_table[src])
    if not encodedOk or type(inventoryJson) ~= "string" then
        return false
    end

    exports[Config.MysqlResource]:execute(
        "UPDATE jrs_characters SET inventory=@inventory WHERE identifier=@identifier AND charidentifier=@charidentifier",
        {
            ["@inventory"] = inventoryJson,
            ["@identifier"] = Character.identifier,
            ["@charidentifier"] = Character.charIdentifier
        }
    )
    return true
end
-- Flush the active character before jrs_character changes (User.character or User.getUsedCharacter).
-- This prevents the old in-memory inventory from ever being saved under the new character.
local function PrepareCharacterSwitch(src)
    src = tonumber(src)
    if not src then return false end

    SaveInventoryNow(src)
    -- The character is about to change. Do not leave the old cache writable.
    InvalidateInventoryCache(src, true)
    return true
end

RegisterNetEvent("jrs_inventory:prepare_character_switch")
AddEventHandler("jrs_inventory:prepare_character_switch", function()
    local src = tonumber(source)
    if not src or not AllowInventoryRequest(src, 'character_switch', 3, 10000) then return end
    PrepareCharacterSwitch(src)
end)

-- Server-only ordered switch hook used by jrs_character. It runs before the
-- authoritative character is detached, so inventory always keeps the old id.
AddEventHandler("jrs_inventory:server:prepareCharacterSwitch", function(src)
    PrepareCharacterSwitch(src)
end)

-- ===========================================================================
-- Slot / item / weapon queries
-- ===========================================================================

function GetFreeSlot(source)
    local src = tonumber(source)
    local usedSlots = {}

    if inv_table[src] then
        for _, v in pairs(inv_table[src]) do
            if v.slot then
                usedSlots[tonumber(v.slot)] = true
            end
        end
    end

    if weapon_table[src] then
        for _, v in pairs(weapon_table[src]) do
            if v.slot then
                usedSlots[tonumber(v.slot)] = true
            end
        end
    end

    local slot = 1
    while usedSlots[slot] do
        slot = slot + 1
    end
    return slot
end

function GetInventoryWeight(source)
    local weight = 0
    if not inv_table[source] then
        return 0
    end

    for _, item in pairs(inv_table[source]) do
        local data = ResolveItemDef(item.item)
        if data then
            local count = math.max(0, tonumber(item.count) or 0)
            local unitWeight = math.max(0, tonumber(data.limit) or 0)
            weight = weight + (count * unitWeight)
        end
    end
    return weight
end

function CanCarry(source, itemName, count)
    local data = ResolveItemDef(itemName)
    if not data then
        return false
    end

    local currentWeight = GetInventoryWeight(source)
    local unitWeight = math.max(0.01, tonumber(data.limit) or 0.1)
    local newWeight = (tonumber(count) or 1) * unitWeight
    local maxWeight = GetMaxWeight(source)
    local result = (currentWeight + newWeight) <= (maxWeight + 0.01)
    return result
end

function getWeight(source)
    return GetInventoryWeight(tonumber(source) or source)
end

function ensureOutfitItemDefinition()
    local outfitDefinition = {
        item = "jrs_outfit",
        label = "Outfit",
        limit = 0.2,
        can_remove = 1,
        type = "item",
        usable = true,
        descriptions = "A wearable outfit that can be traded to another player.",
        metadata = "outfit",
        category = "valuable"
    }

    local found = false
    for _, itemData in pairs(table_item) do
        if itemData.item == outfitDefinition.item then
            found = true
            break
        end
    end
    if not found then
        table.insert(table_item, outfitDefinition)
    end

    itemTableForData[outfitDefinition.item] = outfitDefinition
    itemTableForDataLower[outfitDefinition.item:lower()] = outfitDefinition
end
-- ===========================================================================
-- Preload & update helpers
-- ===========================================================================

function loadPreTable()
	table_item = Inventory.preload_itemtable()
	weapons_table = Inventory.preload_weapontable()
	itemTableForData = {}
	itemTableForDataLower = {}
	weaponTableForData = {}
	weaponNameLookup = {}
	for a,b in pairs(table_item) do
		-- label_ar / descriptions_ar ride along so ItemLabelFor() can resolve a
		-- player's language without a second query. A NULL falls back to English.
		local def = {item=b.item, label=b.label, label_ar=b.label_ar, limit=b.limit, can_remove=b.can_remove, type=b.type, usable=b.usable, descriptions=b.descriptions, descriptions_ar=b.descriptions_ar, metadata=b.metadata, category=b.category}
		itemTableForData[b.item] = def
		if type(b.item) == "string" then
			itemTableForDataLower[b.item:lower()] = def
		end
	end
	if usableItemsFunctions then
		for k in pairs(usableItemsFunctions) do
			if itemTableForData and itemTableForData[k] then itemTableForData[k].usable = 1 end
			if itemTableForDataLower and type(k) == 'string' and itemTableForDataLower[k:lower()] then itemTableForDataLower[k:lower()].usable = 1 end
		end
	end
	for a,b in pairs(weapons_table) do
		if b.item then
			local weaponName = string.upper(tostring(b.item))
			weaponTableForData[weaponName] = {item=weaponName, label=b.label, category="weapon"}
			weaponNameLookup[weaponName] = weaponName
		end
	end
end

exports('reloadItemDefinitions', function()
	loadPreTable()
	ensureOutfitItemDefinition()
	return true
end)

RegisterCommand('reloaditems', function(source)
	if source == 0 or (jrsCore and jrsCore.getUser(source) and jrsCore.getUser(source).getGroup == 'admin') then
		loadPreTable()
		ensureOutfitItemDefinition()
		print('^2[jrs_inventory] Item definitions reloaded from database successfully.^0')
	end
end, true)

function updateItemsInventory(_source)
	_source = tonumber(_source)
	if not _source then return end
	local User = jrsCore and jrsCore.getUser(_source)
	local Character = User and (User.character or User.getUsedCharacter)
	if not Character then return end
	local identifier = Character.identifier
	local CharIdentifier = Character.charIdentifier

	if not IsInventoryLoadedForPlayer(_source, Character) then
		if Config.Debug then
			print(("[jrs_inventory] BLOCKED updateItemsInventory for source %s before authoritative load"):format(_source))
		end
		return false
	end
	inventory_table_sended[_source] = {}
	for a,b in pairs(inv_table[_source]) do
	local def = ResolveItemDef(b.item)
	if def ~= nil then
    if type(JRSInventoryNormalizeMetadata) == "function" then
        b.metaData = JRSInventoryNormalizeMetadata(b.metaData, b.item, true)
    elseif type(b.metaData) ~= "table" then
        b.metaData = {}
    end
    -- The name and description the player reads, in their own language. An
    -- item with no translation yet falls back to the English column.
    local displayLabel = ItemLabelFromDefinition(_source, def, b.item)
    if b.item == "jrs_outfit" and type(b.metaData) == "table" and b.metaData.outfitName then
        -- A player-named outfit is the player's own text; never translated.
        displayLabel = tostring(b.metaData.outfitName)
    end
    table.insert(inventory_table_sended[tonumber(_source)], {
    item=def.item,
    label=displayLabel,
    label_ar=def.label_ar,
    count=math.floor(tonumber(b.count) or 0),
    description=ItemDescriptionFromDefinition(_source, def, b.item),
    description_ar=def.descriptions_ar,
    usable=def.usable,
    limit=def.limit,
    metaData=b.metaData,
    itemId=tonumber(b.itemId),
    category=def.category,
    slot=b.slot
     })
	end
	end
	-- Item/weapon definition tables are static for a running resource and can be
	-- very large. Send them only once per player instead of with every inventory mutation.
	local sendDefinitions = clientDefinitionsSent[_source] ~= true
	TriggerClientEvent(
		"jrs_inventory:send_list_inventory",
		_source,
		inventory_table_sended[_source],
		weapon_table[_source],
		sendDefinitions and table_item or false,
		sendDefinitions and weapons_table or false,
		hotbarByPlayer[_source],
		getMaxWeapons(_source)
	)
	clientDefinitionsSent[_source] = true
	canSaveInventory[_source] = true
	return true
end

-- ===========================================================================
-- Background auto-save
-- ===========================================================================

Citizen.CreateThread(function()
	Citizen.Wait(2000)
	loadPreTable()
	ensureOutfitItemDefinition()
	while true do
		for _, playerId in ipairs(GetPlayers()) do
			local _source = tonumber(playerId)
			if _source and canSaveInventory[_source] == true then
				local User = jrsCore.getUser(_source)
				local Character = User and (User.character or User.getUsedCharacter)
				if Character and IsInventoryLoadedForPlayer(_source, Character) then
					if SaveInventoryNow(_source) then
						jrsCore.Debug("[Inventory] CharIdentifier : "..tostring(Character.charIdentifier).." inventory has been saved!")
					end
				elseif Config.Debug then
					print(("[jrs_inventory] BLOCKED unsafe autosave for source %s"):format(_source))
				end
				canSaveInventory[_source] = false
				Citizen.Wait(Config.SaveThrottleMs)
			end
		end
		Citizen.Wait(Config.AutoSaveIntervalMs)
	end
end)

-- txAdmin/resource restarts do not disconnect players, so playerDropped never
-- gets a chance to persist the in-memory item cache. Flush every loaded
-- character in one awaited transaction before this resource finishes stopping.
AddEventHandler('onResourceStop', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then return end

	local queries = {}
	local savedPlayers = 0
	for playerId, inventory in pairs(inv_table or {}) do
		local src = tonumber(playerId)
		if src and type(inventory) == 'table' then
			local User = jrsCore and jrsCore.getUser(src)
			local Character = User and (User.character or User.getUsedCharacter)
			local encodedOk, inventoryJson = pcall(json.encode, inventory)
			if Character and IsInventoryLoadedForPlayer(src, Character) and encodedOk and type(inventoryJson) == 'string' then
				queries[#queries + 1] = {
					query = 'UPDATE jrs_characters SET inventory = ? WHERE identifier = ? AND charidentifier = ?',
					values = { inventoryJson, Character.identifier, Character.charIdentifier },
				}
				savedPlayers = savedPlayers + 1
			end
		end
	end

	if #queries == 0 then return end

	local ok, success = pcall(function()
		if MySQL and MySQL.transaction and MySQL.transaction.await then
			return MySQL.transaction.await(queries)
		end
		error('oxmysql transaction.await is unavailable')
	end)

	if Config.Debug then
		if ok and success == true then
			print(('[jrs_inventory] Saved %s inventories before resource stop.'):format(savedPlayers))
		else
			print(('[jrs_inventory] WARNING: resource-stop inventory save failed: %s'):format(tostring(success)))
		end
	end
end)

-- ===========================================================================
-- Player dropped
-- ===========================================================================

AddEventHandler('playerDropped', function (reason)
	local _source = source
	-- Keep the player lock until its safety timeout so an unfinished callback
	-- cannot overlap a reconnect or a quickly reused source id.
	ReleaseInventoryResourcesOwnedBy(_source)
	hotbarByPlayer[tonumber(_source)] = nil
	clientDefinitionsSent[tonumber(_source)] = nil
	openstorages[tonumber(_source)] = nil
	openstorages[_source] = nil
	inventorySecurityViolations[tonumber(_source)] = nil
	inventoryRequestBuckets[tonumber(_source)] = nil
	local src = tonumber(_source)
	if canSaveInventory[src] == true and SaveInventoryNow(src) then
		jrsCore.Debug("[Inventory] Player drop inventory has been saved for source : "..tostring(src))
	end
	-- FXServer can reuse source ids. Never retain a departed player's cache.
	InvalidateInventoryCache(src, true)
	weapon_table[src] = nil
end)

-- ===========================================================================
-- Inventory load / send to client
-- ===========================================================================

-- jrs_core may not have associated this connection with its loaded character
-- yet at the exact instant a client asks for its items (a brief window right
-- after connecting, or right after jrs_inventory itself is restarted while
-- players are already online). Previously a nil User here just silently
-- dropped the request forever - the client's inventory stayed on "Loading..."
-- with nothing telling it to ask again. Retry a few times before giving up.
local GET_ITEMS_MAX_ATTEMPTS = 6
local GET_ITEMS_RETRY_DELAY_MS = 800

local function AttemptGetItems(_source, attempt)
	if type(JRSInventoryAmmoRevisions) == 'table' then
		JRSInventoryAmmoRevisions[tonumber(_source)] = {}
	end
	local User = jrsCore.getUser(_source)
	if User ~= nil and (User.character or User.getUsedCharacter) ~= nil then
		openstorages[_source] = {}
		local Character = (User.character or User.getUsedCharacter)
		local identifier = Character.identifier
		local charid = Character.charIdentifier
		exports[Config.MysqlResource]:execute('SELECT inventory, hotbar FROM jrs_characters WHERE identifier=@identifier and charidentifier=@charidentifier', {["identifier"]=identifier,["charidentifier"]=charid}, function(resultInventory)
			if resultInventory[1] ~= nil then
                local decodedInventory = {}
                if resultInventory[1].inventory and resultInventory[1].inventory ~= "" then
                    local ok, decoded = pcall(json.decode, resultInventory[1].inventory)
                    if ok and type(decoded) == "table" then decodedInventory = decoded end
                end
				inv_table[tonumber(_source)] = decodedInventory
				MarkInventoryLoaded(tonumber(_source), Character)
                local metadataMigrated = false
				local hotbar = {}

				if resultInventory[1].hotbar and resultInventory[1].hotbar ~= "" then
					local decodedHotbar = json.decode(resultInventory[1].hotbar)
					if type(decodedHotbar) == "table" then
						hotbar = decodedHotbar
					end
				end

				hotbarByPlayer[tonumber(_source)] = hotbar

				for k,v in pairs(inv_table[tonumber(_source)]) do
					if v.slot == nil then
						v.slot = k
					end
				end

                if type(JRSInventoryNormalizeLoadedInventory) == "function" then
                    metadataMigrated = JRSInventoryNormalizeLoadedInventory(tonumber(_source)) == true
                end

				table.sort(inv_table[tonumber(_source)], function(a,b)
					return (a.slot or 9999) < (b.slot or 9999)
				end)

				inventory_table_sended[tonumber(_source)] = {}
				for a,b in pairs(inv_table[tonumber(_source)]) do
					local def = ResolveItemDef(b.item)
					if def ~= nil then
                        if type(JRSInventoryNormalizeMetadata) == "function" then
                            b.metaData = JRSInventoryNormalizeMetadata(b.metaData, b.item, true)
                        elseif type(b.metaData) ~= "table" then
                            b.metaData = {}
                        end
                        local displayLabel = ItemLabelFromDefinition(_source, def, b.item)
                        if b.item == "jrs_outfit" and type(b.metaData) == "table" and b.metaData.outfitName then
                            displayLabel = tostring(b.metaData.outfitName)
                        end
						table.insert(inventory_table_sended[tonumber(_source)], {
							item=def.item,
							label=displayLabel,
							label_ar=def.label_ar,
							count=math.floor(tonumber(b.count) or 0),
							description=ItemDescriptionFromDefinition(_source, def, b.item),
							description_ar=def.descriptions_ar,
							usable=def.usable,
							limit=def.limit,
							metaData=b.metaData,
							itemId=tonumber(b.itemId),
							category=def.category,
							slot = b.slot
						})
					end
				end
                if metadataMigrated and type(SaveInventoryNow) == "function" then
                    SaveInventoryNow(tonumber(_source))
                end

				exports[Config.MysqlResource]:execute('SELECT * FROM jrs_weaponloadout WHERE charidentifier = @charidentifier AND identifier = @identifier' , {['charidentifier'] = charid, ['identifier'] = identifier}, function(result)
					if result ~= nil then
						weapon_table[tonumber(_source)]  = {}
						for a,b in pairs(result) do
							local resolvedName = ResolveInventoryWeaponName(b.name)
							if resolvedName and weaponTableForData[resolvedName] ~= nil then
								if tostring(b.name) ~= tostring(resolvedName) then
									exports[Config.MysqlResource]:execute("UPDATE jrs_weaponloadout SET name=@name WHERE id=@id", {['@name']=resolvedName, ['@id']=b.id})
								end
								table.insert(weapon_table[tonumber(_source)], {
									id=b.id,
									name=resolvedName,
									label=(b.custom_name and tostring(b.custom_name) ~= "") and tostring(b.custom_name) or weaponTableForData[resolvedName].label,
									custom_name=b.custom_name,
									ammo=b.ammo,
									used=b.used,
									slot=b.slot,
									comps=b.comps,
									dirtlevel=b.dirtlevel,
									conditionlevel=b.conditionlevel,
									serial_number=b.serial_number,
									package_name=b.package_name,
									stolen=(b.stolen==true or tonumber(b.stolen)==1),
									no_break=(b.no_break==true or tonumber(b.no_break)==1),
									category=weaponTableForData[resolvedName].category
								})
							end
						end
						local usedSlots = {}
						if inv_table[tonumber(_source)] then
							for _, v in pairs(inv_table[tonumber(_source)]) do
								if v.slot then usedSlots[v.slot] = true end
							end
						end
						local repairedWeaponSlots = {}
						for _, w in pairs(weapon_table[tonumber(_source)]) do
							if usedSlots[w.slot] then
								local nextSlot = 1
								while usedSlots[nextSlot] do
									nextSlot = nextSlot + 1
								end
								w.slot = nextSlot
								repairedWeaponSlots[#repairedWeaponSlots + 1] = w
							end
							usedSlots[w.slot] = true
						end
						for _, w in ipairs(repairedWeaponSlots) do
							exports[Config.MysqlResource]:execute("UPDATE jrs_weaponloadout SET slot = @slot WHERE id = @id", {['@slot'] = w.slot, ['@id'] = w.id})
						end
						in_inventory_weapons[tonumber(_source)] = #weapon_table[tonumber(_source)]

						TriggerClientEvent("jrs_inventory:send_list_inventory", tonumber(_source), inventory_table_sended[tonumber(_source)], weapon_table[tonumber(_source)], (clientDefinitionsSent[tonumber(_source)] ~= true) and table_item or false, (clientDefinitionsSent[tonumber(_source)] ~= true) and weapons_table or false, hotbar, getMaxWeapons(tonumber(_source)))
						clientDefinitionsSent[tonumber(_source)] = true
					else
						weapon_table[tonumber(_source)] = {}
						in_inventory_weapons[tonumber(_source)] = 0

						TriggerClientEvent("jrs_inventory:send_list_inventory", tonumber(_source), inventory_table_sended[tonumber(_source)], weapon_table[tonumber(_source)], (clientDefinitionsSent[tonumber(_source)] ~= true) and table_item or false, (clientDefinitionsSent[tonumber(_source)] ~= true) and weapons_table or false, hotbar, getMaxWeapons(tonumber(_source)))
						clientDefinitionsSent[tonumber(_source)] = true
					end
				end)
			else
				InvalidateInventoryCache(tonumber(_source), true)
				hotbarByPlayer[tonumber(_source)] = {}
				TriggerClientEvent("jrs_inventory:send_list_inventory", tonumber(_source), {}, {}, (clientDefinitionsSent[tonumber(_source)] ~= true) and table_item or false, (clientDefinitionsSent[tonumber(_source)] ~= true) and weapons_table or false, hotbarByPlayer[tonumber(_source)], getMaxWeapons(tonumber(_source)))
				clientDefinitionsSent[tonumber(_source)] = true
			end
		end)
	elseif attempt < GET_ITEMS_MAX_ATTEMPTS and GetPlayerName(_source) then
		if Config.Debug then
			print(("[jrs_inventory] get_items: no User yet for source %s, retry %d/%d"):format(_source, attempt, GET_ITEMS_MAX_ATTEMPTS))
		end
		SetTimeout(GET_ITEMS_RETRY_DELAY_MS, function()
			AttemptGetItems(_source, attempt + 1)
		end)
	end
end

-- A target id is only honoured from server code. From a client it let anyone
-- force-close any other player's inventory (mid-trade, mid-transfer).
local function closeInventoryTarget(targetSource)
	if GetInvokingResource() ~= nil then return tonumber(targetSource) end
	return tonumber(source)
end

RegisterServerEvent('jrs_inventory:CloseInv')
AddEventHandler('jrs_inventory:CloseInv', function(targetSource)
	local src = closeInventoryTarget(targetSource)
	if src then
		TriggerClientEvent('jrs_inventory:CloseInv', src)
	end
end)

RegisterServerEvent('jrs_inventory:closeInventory')
AddEventHandler('jrs_inventory:closeInventory', function(targetSource)
	local src = closeInventoryTarget(targetSource)
	if src then
		TriggerClientEvent('jrs_inventory:CloseInv', src)
	end
end)

RegisterServerEvent('jrs_inventory:get_items')
AddEventHandler('jrs_inventory:get_items', function(requestedSource)
	local invokedLocally = GetInvokingResource() ~= nil
	local _source = invokedLocally and tonumber(requestedSource) or tonumber(source)
	if not _source then return end
	if not invokedLocally and not AllowInventoryRequest(_source, 'get_items') then return end
	AttemptGetItems(_source, 1)
end)

RegisterServerEvent('jrs_inventory:get_money')
AddEventHandler('jrs_inventory:get_money', function(requestedSource)
    local invokedLocally = GetInvokingResource() ~= nil
	local _source = invokedLocally and tonumber(requestedSource) or tonumber(source)
    if not _source then return end
    if not invokedLocally and not AllowInventoryRequest(_source, 'get_money') then return end
	local User = jrsCore.getUser(tonumber(_source))
	if User ~= nil and (User.character or User.getUsedCharacter) ~= nil then
		local Character = (User.character or User.getUsedCharacter)
		local user_money = Character.money
		local user_gold = Character.gold
		local user_dirtymoney = Character.dirtymoney
		TriggerClientEvent("jrs_inventory:send_list_money", tonumber(_source), user_money, user_gold, user_dirtymoney)
	end
end)

RegisterServerEvent('jrs_inventory:get_money_sec')
AddEventHandler('jrs_inventory:get_money_sec', function(requestedSource)
    local invokedLocally = GetInvokingResource() ~= nil
	local _source = invokedLocally and tonumber(requestedSource) or tonumber(source)
    if not _source then return end
    if not invokedLocally and not AllowInventoryRequest(_source, 'refresh_money') then return end
	local User = jrsCore.getUser(tonumber(_source))
	if User == nil or (User.character or User.getUsedCharacter) == nil then return end
	local Character = (User.character or User.getUsedCharacter)
	local user_money = Character.money
	local user_gold = Character.gold
	local user_dirtymoney = Character.dirtymoney
	TriggerClientEvent("jrs_inventory:send_list_money", tonumber(_source), user_money, user_gold, user_dirtymoney)
end)

RegisterServerEvent('jrs_inventory:get_items_sec')
AddEventHandler('jrs_inventory:get_items_sec', function(requestedSource)
    local invokedLocally = GetInvokingResource() ~= nil
	local _source = invokedLocally and tonumber(requestedSource) or tonumber(source)
    if not _source then return end
    if not invokedLocally and not AllowInventoryRequest(_source, 'refresh_items') then return end
	local User = jrsCore.getUser(tonumber(_source))
	if User == nil or (User.character or User.getUsedCharacter) == nil then return end
	local Character = (User.character or User.getUsedCharacter)
	local identifier = Character.identifier
	local charid = Character.charIdentifier

	-- Secondary refreshes can arrive immediately after a txAdmin restart. They
	-- must never create/save an empty item cache before the primary DB load.
	if not IsInventoryLoadedForPlayer(_source, Character) then
		if Config.Debug then
			print(("[jrs_inventory] get_items_sec redirected to full load for source %s"):format(_source))
		end
		TriggerClientEvent('jrs_inventory:forceInventoryReload', _source)
		return
	end

	exports[Config.MysqlResource]:execute('SELECT * FROM jrs_weaponloadout WHERE charidentifier=@charidentifier AND identifier=@identifier' , {['charidentifier'] = charid, ['identifier'] = identifier}, function(result2)
		if result2[1] ~= nil then
			in_inventory_weapons[tonumber(_source)] = 0
			weapon_table[tonumber(_source)]  = {}
			inventory_table_sended[tonumber(_source)] = {}
			for a,b in pairs(result2) do
				local resolvedName = ResolveInventoryWeaponName(b.name)
							if resolvedName and weaponTableForData[resolvedName] ~= nil then
								if tostring(b.name) ~= tostring(resolvedName) then
									exports[Config.MysqlResource]:execute("UPDATE jrs_weaponloadout SET name=@name WHERE id=@id", {['@name']=resolvedName, ['@id']=b.id})
								end
					table.insert(weapon_table[tonumber(_source)],{
					id=b.id,
					name=resolvedName,
					label=(b.custom_name and tostring(b.custom_name) ~= "") and tostring(b.custom_name) or weaponTableForData[resolvedName].label,
					custom_name=b.custom_name,
					ammo=b.ammo,
					used=b.used,
					comps=b.comps,
					dirtlevel=b.dirtlevel,
					conditionlevel=b.conditionlevel,
					serial_number=b.serial_number,
					package_name=b.package_name,
					stolen=(b.stolen==true or tonumber(b.stolen)==1),
					no_break=(b.no_break==true or tonumber(b.no_break)==1),
					slot=b.slot
				})
				end
			end
			local usedSlots = {}
			if inv_table[tonumber(_source)] then
				for _, v in pairs(inv_table[tonumber(_source)]) do
					if v.slot then usedSlots[v.slot] = true end
				end
			end
			local repairedWeaponSlots = {}
			for _, w in pairs(weapon_table[tonumber(_source)]) do
				if usedSlots[w.slot] then
					local nextSlot = 1
					while usedSlots[nextSlot] do
						nextSlot = nextSlot + 1
					end
					w.slot = nextSlot
					repairedWeaponSlots[#repairedWeaponSlots + 1] = w
				end
				usedSlots[w.slot] = true
			end
			for _, w in ipairs(repairedWeaponSlots) do
				exports[Config.MysqlResource]:execute("UPDATE jrs_weaponloadout SET slot = @slot WHERE id = @id", {['@slot'] = w.slot, ['@id'] = w.id})
			end
			in_inventory_weapons[tonumber(_source)] = #weapon_table[tonumber(_source)]
			updateItemsInventory(tonumber(_source))
			SaveInventoryNow(_source)
		else
			weapon_table[tonumber(_source)] = {}
			inventory_table_sended[tonumber(_source)] = {}
			updateItemsInventory(tonumber(_source))
			SaveInventoryNow(_source)
		end
	end)
end)

-- ===========================================================================
-- Hotbar save
-- ===========================================================================

local function sanitizeHotbarForPlayer(src, hotbarData)
    local cleaned = {}
    local seenEntries = {}
    hotbarData = type(hotbarData) == "table" and hotbarData or {}

    for index = 1, 5 do
        local key = "slot" .. index
        local entry = hotbarData[key]
        cleaned[key] = {}

        if type(entry) == "table" and entry.item ~= nil and tostring(entry.item) ~= "" then
            local itemName = tostring(entry.item)
            local isWeapon = entry.weapon == true or tonumber(entry.weapon) == 1 or tostring(entry.weapon) == "true"
            local candidate = nil

            if isWeapon then
                local weaponId = tonumber(entry.id)
                local itemUpper = string.upper(itemName)
                for _, weapon in pairs(weapon_table[tonumber(src)] or {}) do
                    if weaponId and tonumber(weapon.id) == weaponId and string.upper(tostring(weapon.name)) == itemUpper then
                        candidate = { item = tostring(weapon.name), id = weaponId, weapon = true }
                        break
                    end
                end
            else
                local requestedId = tonumber(entry.id)
                local fallbackItem = nil
                for _, item in pairs(inv_table[tonumber(src)] or {}) do
                    if tostring(item.item) == itemName and tonumber(item.count or 0) > 0 then
                        fallbackItem = fallbackItem or item
                        if requestedId and tonumber(item.itemId) == requestedId then
                            candidate = { item = itemName, id = tonumber(item.itemId), weapon = false }
                            break
                        end
                    end
                end

                -- Stack IDs may change after a legitimate merge. If the exact old
                -- stack disappeared but the player still owns the same item, repair
                -- the shortcut to the current owned stack instead of silently losing it.
                if not candidate and fallbackItem then
                    candidate = { item = itemName, id = tonumber(fallbackItem.itemId), weapon = false }
                end
            end

            if candidate then
                local identity = (candidate.weapon and "w:" or "i:") .. tostring(candidate.id) .. ":" .. tostring(candidate.item)
                if not seenEntries[identity] then
                    cleaned[key] = candidate
                    seenEntries[identity] = true
                end
            end
        end
    end

    return cleaned
end

RegisterServerEvent("jrs_inventory:saveHotbar")
AddEventHandler("jrs_inventory:saveHotbar", function(hotbarData)
    local src = tonumber(source)
    if not src or not AllowInventoryRequest(src, 'save_hotbar') then return end
    if type(hotbarData) ~= 'table' or InventoryPayloadSize(hotbarData) > (tonumber(securityConfig().MaxHotbarPayloadBytes) or 4096) then
        RecordInventorySecurityViolation(src, 'invalid_hotbar_payload', tostring(InventoryPayloadSize(hotbarData)))
        return
    end
    local User = jrsCore.getUser(src)
    if not User then return end
    local Character = (User.character or User.getUsedCharacter)
    if not Character then return end

    local cleanedHotbar = sanitizeHotbarForPlayer(src, hotbarData)
    hotbarByPlayer[src] = cleanedHotbar

    -- Immediately mirror the authoritative result back to the client/NUI. If a
    -- malicious or stale shortcut was rejected, it cannot remain usable locally.
    TriggerClientEvent("jrs_inventory:hotbarSync", src, cleanedHotbar)

    exports[Config.MysqlResource]:execute(
        "UPDATE jrs_characters SET hotbar=@hotbar WHERE identifier=@identifier AND charidentifier=@charid",
        {
            ["@hotbar"] = json.encode(cleanedHotbar),
            ["@identifier"] = Character.identifier,
            ["@charid"] = Character.charIdentifier
        }
    )

    if DiscordLogConfig and DiscordLogConfig.LogLayoutChanges == true then
        JRSInventoryLogAction("Layout", "Hotbar Updated", src, {
            slots = cleanedHotbar,
        })
    end
end)

-- ===========================================================================
-- Save slots
-- ===========================================================================

RegisterServerEvent("jrs_inventory:saveSlots")
AddEventHandler("jrs_inventory:saveSlots", function(items, weapons)
    local src = tonumber(source)
    if not src or not AllowInventoryRequest(src, 'save_slots') then return end
    if not inv_table[src] then return end
    if not weapon_table[src] then weapon_table[src] = {} end

    local settings = securityConfig()
    local maxEntries = math.max(16, math.floor(tonumber(settings.MaxLayoutEntries) or 256))
    local maxSlot = math.max(32, math.floor(tonumber(settings.MaxLayoutSlot) or 512))
    local payloadSize = InventoryPayloadSize({ items = items, weapons = weapons })
    if type(items) ~= 'table' or type(weapons) ~= 'table'
        or payloadSize > (tonumber(settings.MaxLayoutPayloadBytes) or 65536) then
        RecordInventorySecurityViolation(src, 'invalid_layout_payload', tostring(payloadSize))
        return
    end

    local ownedItems = {}
    local ownedWeapons = {}
    local ownedCount = 0
    for _, entry in pairs(inv_table[src]) do
        local id = tonumber(entry.itemId)
        if id then
            ownedItems[id] = entry
            ownedCount = ownedCount + 1
        end
    end
    for _, entry in pairs(weapon_table[src]) do
        local id = tonumber(entry.id)
        if id then
            ownedWeapons[id] = entry
            ownedCount = ownedCount + 1
        end
    end

    local requestedItems = {}
    local requestedWeapons = {}
    local requestedIds = {}
    local requestedSlots = {}
    local payloadEntries = 0

    local function readEntries(payload, kind, ownedMap, destination)
        for _, entry in pairs(payload) do
            payloadEntries = payloadEntries + 1
            if payloadEntries > maxEntries or payloadEntries > ownedCount then
                return false, 'layout_too_large'
            end
            if type(entry) ~= 'table' then
                return false, 'invalid_layout_entry'
            end

            local id = tonumber(kind == 'item' and entry.itemId or entry.id)
            local slot = tonumber(entry.slot)
            if not id or not slot or slot ~= math.floor(slot) or slot < 1 or slot > maxSlot then
                return false, 'invalid_layout_entry'
            end
            if not ownedMap[id] then
                return false, 'layout_unowned_entry'
            end

            local composite = kind .. ':' .. tostring(id)
            if requestedIds[composite] or requestedSlots[slot] then
                return false, 'duplicate_layout_entry'
            end

            requestedIds[composite] = true
            requestedSlots[slot] = composite
            destination[id] = slot
        end
        return true
    end

    local ok, reason = readEntries(items, 'item', ownedItems, requestedItems)
    if ok then ok, reason = readEntries(weapons, 'weapon', ownedWeapons, requestedWeapons) end
    if not ok then
        RecordInventorySecurityViolation(src, reason, 'entries=' .. tostring(payloadEntries))
        return
    end

    -- Validate the final combined layout, including owned entries omitted by a
    -- partial client update. This prevents hidden slot collisions.
    local finalSlots = {}
    local function claimFinalSlot(kind, id, entry, requestedMap)
        local slot = tonumber(requestedMap[id] or entry.slot)
        if not slot or slot ~= math.floor(slot) or slot < 1 or slot > maxSlot then
            return false, 'invalid_existing_slot'
        end
        local existing = finalSlots[slot]
        if existing then
            return false, 'final_slot_collision:' .. tostring(slot)
        end
        finalSlots[slot] = kind .. ':' .. tostring(id)
        return true
    end

    for id, entry in pairs(ownedItems) do
        ok, reason = claimFinalSlot('item', id, entry, requestedItems)
        if not ok then break end
    end
    if ok then
        for id, entry in pairs(ownedWeapons) do
            ok, reason = claimFinalSlot('weapon', id, entry, requestedWeapons)
            if not ok then break end
        end
    end
    if not ok then
        RecordInventorySecurityViolation(src, 'invalid_final_layout', reason)
        return
    end

    local User = jrsCore and jrsCore.getUser(src)
    local Character = User and (User.character or User.getUsedCharacter)
    if not Character then return end

    for id, slot in pairs(requestedItems) do
        ownedItems[id].slot = slot
    end

    local changedWeapons = {}
    for id, slot in pairs(requestedWeapons) do
        local entry = ownedWeapons[id]
        if tonumber(entry.slot) ~= slot then
            entry.slot = slot
            changedWeapons[#changedWeapons + 1] = { id = id, slot = slot }
        end
    end

    for _, weapon in ipairs(changedWeapons) do
        exports[Config.MysqlResource]:execute(
            "UPDATE jrs_weaponloadout SET slot=@slot WHERE id=@id AND identifier=@identifier AND charidentifier=@charid",
            {
                ["@slot"] = weapon.slot,
                ["@id"] = weapon.id,
                ["@identifier"] = Character.identifier,
                ["@charid"] = Character.charIdentifier,
            }
        )
    end

    SaveInventoryNow(src)
    canSaveInventory[src] = false

    if DiscordLogConfig and DiscordLogConfig.LogLayoutChanges == true then
        JRSInventoryLogAction("Layout", "Inventory Slots Updated", src, {
            itemCount = payloadEntries,
            weaponChanges = #changedWeapons,
        })
    end
end)

-- ===========================================================================
-- jrsCore API bridges (query / use / clear)
-- ===========================================================================

AddEventHandler('jrsCore:registerUsableItem', function(name, cb)
	usableItemsFunctions[name] = cb
	if type(name) == 'string' then
		usableItemsFunctions[name:lower()] = cb
		if itemTableForData and itemTableForData[name] then itemTableForData[name].usable = 1 end
		if itemTableForDataLower and itemTableForDataLower[name:lower()] then itemTableForDataLower[name:lower()].usable = 1 end
	end
end)

-- Trusted server-local reset used only by JRS server resources. It is not a
-- network event, so a modified client cannot erase or replace inventory state.
AddEventHandler('jrs_inventory:server:clearInventoryCache', function(target)
	local _source = tonumber(target)
    if not _source then return end
    local invokingResource = GetInvokingResource()
    if invokingResource == nil then return end

    local previousItems = #(inv_table[_source] or {})
    local previousWeapons = #(weapon_table[_source] or {})
	in_inventory[_source] = 0
	in_inventory_count[_source] = 0
	-- Invalidate instead of manufacturing a writable empty inventory.
	InvalidateInventoryCache(_source, true)
	inventory_table_sended[_source] = {}
	new_table[_source] = {}
    weapon_table[_source] = {}
    hotbarByPlayer[_source] = {}
    clientDefinitionsSent[_source] = nil

    JRSInventoryLogAction("Items", "Inventory Cache Cleared", _source, {
        previousItemStacks = previousItems,
        previousWeapons = previousWeapons,
        sourceResource = invokingResource,
    })
end)

-- Returns the TOTAL owned across every stack of `item`, in a single callback.
--
-- This used to fire `cb` once per matching row and never fire it at all when
-- the player owned none, which was wrong twice over. Any item carrying
-- metadata is stored as one row PER distinct metadata variant (durability is a
-- unique key), so a character holding five separate `pickaxe` rows of count 1
-- reported "1" - whichever row the iteration happened to visit last - instead
-- of 5. Every caller of this event treats the value as the amount owned and
-- gates on it (`< 1`, `>= amount`, read-back checks after add/remove), so the
-- under-count made items look like they were never granted or never consumed.
-- Firing exactly once also means a caller can rely on the callback running for
-- a player who owns none of the item, which the old loop skipped entirely.
AddEventHandler('jrsCore:getItemCount', function(source, item, cb)
	local _source = tonumber(source)
	local total = 0
	local itemKey = type(item) == 'string' and item:lower() or nil

	for _, v in pairs((_source and inv_table[_source]) or {}) do
		if type(v) == "table" and (v.item == item
			or (itemKey and type(v.item) == 'string' and v.item:lower() == itemKey)) then
			total = total + (tonumber(v.count) or 0)
		end
	end

	-- cb arrives through TriggerEvent as a Cfx funcref table, never type "function".
	if cb ~= nil then cb(total) end
end)

AddEventHandler('jrsCore:getUserInventory', function(source, cb)
	local _source = source
	cb(inv_table[tonumber(_source)])
end)

AddEventHandler('jrsCore:canCarryItem', function(source, name, count, cb)
    local _source = tonumber(source)
    if CanCarry(_source, name, tonumber(count)) then
        cb(true)
    else
        cb(false)
    end
end)

AddEventHandler('jrsCore:getCarryInfo', function(source, name, count, cb)
    local _source = tonumber(source)
    local countNum = tonumber(count) or 1
    if not _source or _source <= 0 then
        cb({ canCarry = false, reason = 'invalid_source', currentWeight = 0, addedWeight = 0, maxWeight = 0 })
        return
    end

    local data = ResolveItemDef(name)
    if not data then
        cb({ canCarry = false, reason = 'item_not_found', currentWeight = 0, addedWeight = 0, maxWeight = 0 })
        return
    end

    local currentWeight = GetInventoryWeight(_source)
    local addedWeight = countNum * tonumber(data.limit or 0)
    local maxWeight = GetMaxWeight(_source)

    if (currentWeight + addedWeight) > maxWeight then
        cb({
            canCarry = false,
            reason = 'overweight',
            currentWeight = currentWeight,
            addedWeight = addedWeight,
            maxWeight = maxWeight
        })
        return
    end

    local limit = type(Config.MaxOwnedItems) == "table" and tonumber(Config.MaxOwnedItems[tostring(name)]) or nil
    if limit then
        local owned = 0
        for _, entry in pairs(inv_table[_source] or {}) do
            if entry.item == name then
                owned = owned + (tonumber(entry.count) or 0)
            end
        end
        if (owned + countNum) > limit then
            cb({
                canCarry = false,
                reason = 'item_limit_reached',
                currentWeight = currentWeight,
                addedWeight = addedWeight,
                maxWeight = maxWeight
            })
            return
        end
    end

    cb({
        canCarry = true,
        reason = 'ok',
        currentWeight = currentWeight,
        addedWeight = addedWeight,
        maxWeight = maxWeight
    })
end)

AddEventHandler('jrsCore:canAcquireItem', function(source, name, count, cb)
    local _source = tonumber(source)
    local limit = type(Config.MaxOwnedItems) == "table" and tonumber(Config.MaxOwnedItems[tostring(name)]) or nil
    if not limit then
        cb(true)
        return
    end
    local owned = 0
    for _, entry in pairs(inv_table[_source] or {}) do
        if entry.item == name then
            owned = owned + (tonumber(entry.count) or 0)
        end
    end
    cb(owned + (tonumber(count) or 0) <= limit)
end)

AddEventHandler('jrsCore:canCarryItems', function(source, itemName, count, cb)
    local _source = tonumber(source)
    local currentWeight = 0

    if not inv_table[_source] then
        cb(false)
        return
    end

    for _, item in pairs(inv_table[_source]) do
        local itemData = ResolveItemDef(item.item)
        if itemData then
            currentWeight = currentWeight + (item.count * itemData.limit)
        end
    end

    local newWeight = 0
    local newItemData = ResolveItemDef(itemName)
    if newItemData then
        newWeight = count * newItemData.limit
    end

    local _source = tonumber(source)
    cb((currentWeight + newWeight) <= GetMaxWeight(_source))
end)

AddEventHandler('jrsCore:canCarryWeapons', function(source, count, cb)
    local _source = tonumber(source)
    local requested = math.max(1, math.floor(tonumber(count) or 1))
    local User = jrsCore and jrsCore.getUser(_source)
    local Character = User and (User.character or User.getUsedCharacter)
    if not _source or not Character then
        cb(false)
        return
    end

    local maxWeapons = getMaxWeapons(_source)
    exports[Config.MysqlResource]:execute(
        'SELECT name FROM jrs_weaponloadout WHERE charidentifier=@charidentifier AND identifier=@identifier',
        {
            ['charidentifier'] = Character.charIdentifier,
            ['identifier'] = Character.identifier
        },
        function(rows)
            local current = 0
            for _, row in pairs(rows or {}) do
                if ShouldCountWeaponTowardLimit(row.name) then current = current + 1 end
            end
            in_inventory_weapons[_source] = current
            cb((current + requested) <= maxWeapons)
        end
    )
end)

RegisterServerEvent('jrs:use')
AddEventHandler('jrs:use', function(name, id, args)
    local source = tonumber(source)
    if not source or not AllowInventoryRequest(source, 'use_item') then return end
    if Player(source).state.jrsArena == true then return end -- jrs_fightarena: no item use while fighting
    name = tostring(name or '')
    if name == '' or #name > 96 then
        RecordInventorySecurityViolation(source, 'invalid_use_item_name', name)
        return
    end
    if args ~= nil and InventoryPayloadSize(args) > (tonumber(securityConfig().MaxUseArgsBytes) or 4096) then
        RecordInventorySecurityViolation(source, 'oversized_use_args', tostring(InventoryPayloadSize(args)))
        return
    end
    if args ~= nil and type(args) ~= 'table' then args = {} end
    UseInventoryItem(source, name, id, args)
end)

-- Shared use path for the inventory NUI ('jrs:use') and the native item wheel
-- (UseItemFromWheel export below). Returns true only when a registered usable
-- callback actually ran, so callers never consume an item that did nothing.
function UseInventoryItem(source, name, id, args)
    local itemId = tonumber(id)
    local inventoryItem = nil

    -- `name` is what the NUI echoed back, which is the resolved definition's
    -- canonical item id (ResolveItemDef / updateItemsInventory's `def.item`) -
    -- not necessarily the exact casing stored in this player's inv_table (a
    -- saved inventory can carry a different casing for the same item, see
    -- ResolveItemDef's own comment). An exact-only match here silently
    -- dropped every use attempt on such an item: e.g. a "Water" (capital)
    -- inventory row is displayed and reported as "water" everywhere else,
    -- but never matched entry.item == "water", so inventoryItem stayed nil
    -- and the handler returned with no animation, no effect, and no error.
    if inv_table[source] then
        for _, entry in pairs(inv_table[source]) do
            local isMatch = entry.item == name
                or (type(entry.item) == 'string' and type(name) == 'string' and entry.item:lower() == name:lower())
            if isMatch and (itemId == nil or tonumber(entry.itemId) == itemId) then
                inventoryItem = entry
                break
            end
        end
    end
    if not inventoryItem then return end

    local itemDefinition = ResolveItemDef(name)
    local isUsable = itemDefinition and (itemDefinition.usable == true or tonumber(itemDefinition.usable) == 1)
    if not isUsable and usableItemsFunctions and (usableItemsFunctions[name] or (type(name) == 'string' and usableItemsFunctions[name:lower()])) then
        isUsable = true
        if itemDefinition then itemDefinition.usable = 1 end
    end

    if not isUsable then
        TriggerClientEvent("jrsCore:notify", source, _Up(source, 'inventory'), _Up(source, 'item_not_usable'), 'bag', 2500)
        return
    end

    -- Server-authoritative durability protection. Even if a client calls the
    -- use event directly, an item at 0% durability cannot execute its usable callback.
    if type(JRSInventoryIsItemBroken) == "function" then
        local broken, durability = JRSInventoryIsItemBroken(name, inventoryItem.metaData or {})
        if broken then
            TriggerClientEvent("jrsCore:notify", source, _Up(source, 'inventory'), _Up(source, 'item_broken_cannot_use'), 'bag', 2500)
            if type(JRSInventoryLogAction) == "function" and Config.Metadata and Config.Metadata.LogBrokenUseAttempts == true then
                JRSInventoryLogAction("Usage", "Broken Item Use Blocked", source, {
                    item = (itemDefinition.label or itemDefinition.item) .. " (`" .. tostring(itemDefinition.item) .. "`)",
                    itemId = inventoryItem.itemId,
                    durability = durability,
                    metadata = inventoryItem.metaData or {},
                })
            end
            return
        end
    end

    local usableCallback = usableItemsFunctions[name] or (type(name) == 'string' and usableItemsFunctions[name:lower()])
    if usableCallback then
        usableCallback({
            source = source,
            item = itemDefinition.item,
            label = itemDefinition.label,
            limit = itemDefinition.limit,
            itemId = inventoryItem.itemId,
            metaData = inventoryItem.metaData or {},
            args = args
        })
        JRSInventoryLogAction("Usage", "Item Used", source, {
            item = (itemDefinition.label or itemDefinition.item) .. " (`" .. tostring(itemDefinition.item) .. "`)",
            itemId = inventoryItem.itemId,
            metadata = inventoryItem.metaData or {},
        })
        return true
    else
        jrsCore.Error("" .. itemDefinition.item .. " : item is usable and without any function")
    end
    return false
end

-- Native item wheel (jrs_core/server/wheel.lua) helpers.
-- WheelItemInfo: nil when the item is unknown, else { item, category, hasCallback }
-- where `item` is the canonical casing from the items table.
exports('WheelItemInfo', function(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local def = ResolveItemDef(name)
    if not def then return nil end
    local hasCallback = (usableItemsFunctions[def.item] or usableItemsFunctions[tostring(def.item):lower()]) ~= nil
    return {
        item = def.item,
        category = def.category,
        usable = (def.usable == true or tonumber(def.usable) == 1),
        hasCallback = hasCallback,
    }
end)

exports('UseItemFromWheel', function(source, name)
    source = tonumber(source)
    if not source or type(name) ~= 'string' or name == '' or #name > 96 then return false end
    return UseInventoryItem(source, name, nil, {}) == true
end)
-- ===========================================================================
-- Metadata
-- ===========================================================================

AddEventHandler('jrsCore:getMetadataValue', function(source, item, data, cb)
    local playerId = tonumber(source)
    local itemId = tonumber(item)
    local value = nil
    if playerId and itemId and type(JRSInventoryGetMetadata) == "function" then
        local metadata = JRSInventoryGetMetadata(playerId, itemId)
        if type(metadata) == "table" then value = metadata[tostring(data or "")] end
    else
        for _, entry in pairs(inv_table[playerId] or {}) do
            if itemId == tonumber(entry.itemId) then
                local metadata = type(entry.metaData) == "table" and entry.metaData or {}
                value = metadata[tostring(data or "")]
                break
            end
        end
    end
    -- cb arrives through TriggerEvent as a Cfx funcref table, never type "function".
    if cb ~= nil then cb(value) end
end)

-- ===========================================================================
-- Turn ped
-- ===========================================================================

RegisterNetEvent('jrs_inventory:turn_ped')
AddEventHandler('jrs_inventory:turn_ped', function(target)
	local playerId = tonumber(source)
    if not playerId or not AllowInventoryRequest(playerId, 'turn_ped') then return end
	target = tonumber(target)
	if not playerId or not target or playerId == target then return end
	if not isValidTarget(target) or not ArePlayersWithinTransferDistance(playerId, target) then return end
	TriggerClientEvent("jrs_inventory:turn_client", playerId, target, 1)
	TriggerClientEvent("jrs_inventory:turn_client", target, playerId, 0)
end)

-- ===========================================================================
-- Resource restart recovery
-- ===========================================================================

AddEventHandler('onResourceStart', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then return end
	Citizen.CreateThread(function()
		-- Wait until item/weapon definitions have been preloaded by the startup
		-- thread, then re-sync only players who were already online/selected.
		Citizen.Wait(tonumber(Config.ResourceRestartSyncDelayMs) or 3500)
		for _, playerId in ipairs(GetPlayers()) do
			local src = tonumber(playerId)
			local User = src and jrsCore and jrsCore.getUser and jrsCore.getUser(src)
			local Character = User and (User.character or User.getUsedCharacter)
			if src and Character then
				TriggerClientEvent('jrs_inventory:restartSyncReady', src)
			end
		end
	end)
end)

-- ===========================================================================
-- Dev Mode
-- ===========================================================================

local devReinitActive = {}

RegisterServerEvent('jrs_inventory:devReinitRequest')
AddEventHandler('jrs_inventory:devReinitRequest', function()
	local _source = tonumber(source)
	if not Config.DevMode then return end
	if not _source or devReinitActive[_source] then return end

	local User = jrsCore.getUser(_source)
	if User == nil or User.group ~= Config.DevPermission then
		TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), _Up(_source, 'no_permission'), 'bag', 2500)
		return
	end

	if isOnCooldown(tonumber(_source)) then
		TriggerClientEvent("jrsCore:notify", tonumber(_source), _Up(tonumber(_source), 'inventory'), _Up(_source, 'too_fast'), 'bag', 2500)
		return
	end

	if Config.Debug then
		jrsCore.Debug("[Inventory][DevMode] Reinit requested by source "..tostring(_source))
	end

	local Character = (User.character or User.getUsedCharacter)
	local currentInventory = inv_table[_source]
	if not Character or type(currentInventory) ~= 'table' or not IsInventoryLoadedForPlayer(_source, Character) then
		TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), 'Reinitialization cancelled: inventory is not loaded.', 'bag', 4000)
		return
	end

	local encodedOk, inventoryJson = pcall(json.encode, currentInventory)
	if not encodedOk or type(inventoryJson) ~= 'string' then
		TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), 'Reinitialization cancelled: inventory could not be saved.', 'bag', 4000)
		return
	end

	devReinitActive[_source] = true
	TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), _Up(_source, 'reinitializing'), 'bag', 2500)

	-- Persist the authoritative in-memory inventory first. Items live in the
	-- characters JSON column, unlike weapons, so reloading before this callback
	-- can replace unsaved items with an old or empty database value.
	exports[Config.MysqlResource]:execute(
		'UPDATE jrs_characters SET inventory=@inventory WHERE identifier=@identifier AND charidentifier=@charidentifier',
		{
			['@inventory'] = inventoryJson,
			['@identifier'] = Character.identifier,
			['@charidentifier'] = Character.charIdentifier,
		},
		function(saveResult)
			if saveResult == nil then
				devReinitActive[_source] = nil
				TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), 'Reinitialization cancelled: database save failed.', 'bag', 4500)
				return
			end

			-- Reload item definitions safely. A transient empty items query must not
			-- make every owned item disappear from the client payload.
			local previousTableItem = table_item
			local previousWeaponsTable = weapons_table
			local previousItemDefinitions = itemTableForData
			local previousItemDefinitionsLower = itemTableForDataLower
			local previousWeaponDefinitions = weaponTableForData
			local previousWeaponLookup = weaponNameLookup
			local preloadOk = pcall(loadPreTable)
			if not preloadOk or type(table_item) ~= 'table' or next(table_item) == nil then
				table_item = previousTableItem
				weapons_table = previousWeaponsTable
				itemTableForData = previousItemDefinitions
				itemTableForDataLower = previousItemDefinitionsLower
				weaponTableForData = previousWeaponDefinitions
				weaponNameLookup = previousWeaponLookup
				devReinitActive[_source] = nil
				TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), 'Reinitialization cancelled: item definitions failed to reload.', 'bag', 4500)
				return
			end

			if openstorages[_source] ~= nil then openstorages[_source] = {} end
			in_inventory[_source] = nil
			in_inventory_count[_source] = nil
			count_calc[_source] = nil
			clientDefinitionsSent[_source] = nil
			canSaveInventory[_source] = false

			TriggerClientEvent("jrs_inventory:devReinitReset", _source)
			TriggerEvent("jrs_inventory:get_items", _source)
			devReinitActive[_source] = nil

			if Config.Debug then
				jrsCore.Debug("[Inventory][DevMode] Safely saved and reloaded source "..tostring(_source))
			end
			TriggerClientEvent("jrsCore:notify", _source, _Up(_source, 'inventory'), _Up(_source, 'system_reinitialized'), 'bag', 2500)
		end
	)
end)

RegisterServerEvent("jrs_inventory:refreshInventoryLanguage")
AddEventHandler("jrs_inventory:refreshInventoryLanguage", function()
	local _source = tonumber(source)
	if not _source or _source <= 0 or not AllowInventoryRequest(_source, 'refresh_language', 4, 10000) then return end
	updateItemsInventory(_source)
end)
