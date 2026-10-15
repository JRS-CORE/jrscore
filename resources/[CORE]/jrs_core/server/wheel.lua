local lastWheelSignature = {}
local pendingSync = {}
local lastUseAt = {}
local CoreAPI = exports.jrs_core:getCoreApi()

local function dbg(...)
    if Config.InputWheel.Debug then
        print('^3[JRS WHEEL SERVER]^7', ...)
    end
end

-- ---------------------------------------------------------------------------
-- Which bag items reach the native item wheel
--
-- 1. Items listed in Config.InputWheel.WheelItems (exact key, then a
--    case-insensitive key match: the bag can hold "Bread" while the table has
--    "bread", and the old exact-only lookup silently dropped those rows).
-- 2. Any other food / drink item that the inventory can actually use
--    (usable = 1 AND a usable callback registered) - it is mirrored with a
--    generic native from Config.InputWheel.AutoNative so it still shows up.
--
-- Items with no working use callback never reach the wheel, so a wheel entry
-- always does something when released on.
-- ---------------------------------------------------------------------------
local wheelKeyByLower = {}
for key in pairs(Config.InputWheel.WheelItems or {}) do
    local lower = tostring(key):lower()
    if wheelKeyByLower[lower] == nil then
        wheelKeyByLower[lower] = key
    end
end

-- ---------------------------------------------------------------------------
-- Effect signature: which cores an item really restores (H = health, S = stamina, D = dead eye),
-- read from the jrs_metabolism usable-item config (the values applied when the item is used).
-- The client uses it to choose a substitute native whose wheel description/icons match.
-- ---------------------------------------------------------------------------
local effectSignatures = nil -- lowercase item -> "HS" / "HSD" / ... / "-"

local function loadEffectSignatures()
    local map = {}
    local ok = pcall(function()
        local chunk = LoadResourceFile('jrs_metabolism', 'config/usables.cfg.lua')
        if not chunk then error('usables.cfg.lua not readable') end
        local env = setmetatable({}, { __index = _G })
        local fn = assert(load(chunk, '@usables.cfg.lua', 't', env))
        fn()
        local usable = env.Items and env.Items.RegisteredUsableItems or {}
        for name, data in pairs(usable) do
            local m = data.Metabolism or {}
            local function total(...)
                local sum = 0
                for _, field in ipairs({ ... }) do sum = sum + (tonumber(m[field]) or 0) end
                return sum
            end
            local sig = ''
            if total('InnerCoreHealth', 'InnerCoreHealthGold', 'OuterCoreHealthGold') > 0 then sig = sig .. 'H' end
            if total('InnerCoreStamina', 'InnerCoreStaminaGold', 'OuterCoreStaminaGold') > 0 then sig = sig .. 'S' end
            if total('InnerCoreDeadEye', 'InnerCoreDeadEyeGold', 'OuterCoreDeadEyeGold') > 0 then sig = sig .. 'D' end
            map[tostring(name):lower()] = (sig ~= '') and sig or '-'
        end
    end)
    return ok and map or nil
end

local function getEffectSignature(itemName)
    if effectSignatures == nil then
        effectSignatures = loadEffectSignatures() or false
    end
    if not effectSignatures then
        return nil
    end
    return effectSignatures[tostring(itemName):lower()]
end

local infoCache = {}
local INFO_TTL_MS = 15000

-- returns info table, or false when the inventory export could not be reached,
-- or nil when the item is unknown to the inventory.
local function getItemInfo(itemName)
    local lower = tostring(itemName):lower()
    local now = GetGameTimer()
    local cached = infoCache[lower]
    if cached and (now - cached.at) < INFO_TTL_MS then
        return cached.info
    end
    local ok, info = pcall(function()
        return exports.jrs_inventory:WheelItemInfo(itemName)
    end)
    if not ok then
        info = false
    end
    infoCache[lower] = { at = now, info = info }
    return info
end

local function autoEntryFor(info)
    local auto = Config.InputWheel.AutoNative or {}
    if not info or not info.usable or not info.hasCallback then
        return nil
    end
    local category = tostring(info.category or ''):lower()
    local native = auto.Categories and auto.Categories[category]
    if not native then
        return nil
    end
    local lowerItem = tostring(info.item):lower()
    for _, pattern in ipairs(auto.ExcludePatterns or {}) do
        if lowerItem:find(pattern) then
            return nil
        end
    end
    return { nativeName = native, useAmount = 1, notifyText = info.label, auto = true }
end

-- returns key, entry (entry.nativeName is what the client mirrors) or nil
local function resolveWheelEntry(itemName)
    if type(itemName) ~= 'string' or itemName == '' then
        return nil
    end
    local items = Config.InputWheel.WheelItems or {}
    local key = nil
    if items[itemName] then
        key = itemName
    elseif wheelKeyByLower[itemName:lower()] then
        key = wheelKeyByLower[itemName:lower()]
    end

    local info = getItemInfo(itemName)
    if key then
        -- Mapped item: hide it only when the inventory positively says it cannot be used.
        if info and not (info.usable and info.hasCallback) then
            return nil
        end
        return key, items[key]
    end
    local entry = autoEntryFor(info)
    if entry then
        return info.item, entry
    end
    return nil
end

local function buildWheelStateFromInventory(inventory)
    local counts, extra, sigs = {}, {}, {}
    local items = Config.InputWheel.WheelItems or {}
    for _, invItem in pairs(inventory or {}) do
        local itemName = invItem.item or invItem.name
        local count = tonumber(invItem.count or 0) or 0
        if count > 0 then
            local key, entry = resolveWheelEntry(itemName)
            if key then
                counts[key] = (counts[key] or 0) + count
                if not items[key] then
                    extra[key] = { nativeName = entry.nativeName, notifyText = entry.notifyText }
                end
                sigs[key] = sigs[key] or getEffectSignature(itemName) or getEffectSignature(key)
            end
        end
    end
    return counts, extra, sigs
end

local function buildSnapshotSignature(counts, extra, sigs)
    local keys = {}
    for itemName in pairs(counts) do
        keys[#keys + 1] = itemName
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local itemName = keys[i]
        local native = extra[itemName] and extra[itemName].nativeName or ''
        parts[#parts + 1] = itemName .. ':' .. tostring(counts[itemName]) .. ':' .. native .. ':' .. tostring(sigs[itemName] or '')
    end
    return table.concat(parts, '|')
end

local function readInventory(source, Character)
    local ok, inv = pcall(function()
        return exports.jrs_inventory:getUserInventory(source)
    end)
    if ok and type(inv) == 'table' then
        return inv
    end
    return json.decode(Character.inventory) or {}
end

local function syncPlayerWheel(source, force)
    if not source then
        return
    end
    local User = CoreAPI.GetUser(source)
    if not User then
        return
    end
    local Character = User.getUsedCharacter
    if not Character then
        return
    end

    local counts, extra, sigs = buildWheelStateFromInventory(readInventory(source, Character))
    local signature = buildSnapshotSignature(counts, extra, sigs)
    if force or lastWheelSignature[source] ~= signature then
        lastWheelSignature[source] = signature
        TriggerClientEvent('jrs_core:wheel:applySnapshot', source, counts, extra, sigs)
    end
end

local function queueSync(source)
    if not source then
        return
    end
    pendingSync[source] = true
end

if Config.InputWheel.Enabled then
    RegisterNetEvent('jrs_core:wheel:requestSync', function()
        local source = source
        syncPlayerWheel(source, true)
    end)

    RegisterNetEvent('jrs_core:wheel:useFromWheel', function(jrsItemName)
        local source = source
        local now = GetGameTimer()
        if lastUseAt[source] and (now - lastUseAt[source]) < 400 then
            return
        end
        lastUseAt[source] = now

        local key = resolveWheelEntry(jrsItemName)
        if not key then
            syncPlayerWheel(source, true)
            return
        end

        -- Same path as using the item from the bag: the registered usable callback
        -- plays the animation/props, applies the metabolism effects, removes the
        -- item (or deducts durability) and sends its own notification.
        local ok, used = pcall(function()
            return exports.jrs_inventory:UseItemFromWheel(source, key)
        end)
        dbg(('use %s -> ok=%s used=%s'):format(tostring(key), tostring(ok), tostring(used)))

        SetTimeout(300, function()
            if GetPlayerName(source) then
                syncPlayerWheel(source, true)
            end
        end)
        SetTimeout(1800, function()
            if GetPlayerName(source) then
                syncPlayerWheel(source, true)
            end
        end)
    end)

    CreateThread(function()
        local syncCfg = Config.InputWheel.Sync or {}
        local pollMs = tonumber(syncCfg.ServerPollMs) or 2000
        while true do
            Wait(pollMs)
            for _, source in ipairs(GetPlayers()) do
                local src = tonumber(source)
                if src then
                    if pendingSync[src] then
                        pendingSync[src] = nil
                        syncPlayerWheel(src, true)
                    else
                        syncPlayerWheel(src, false)
                    end
                end
            end
        end
    end)

    AddEventHandler('playerDropped', function()
        local source = source
        lastWheelSignature[source] = nil
        pendingSync[source] = nil
        lastUseAt[source] = nil
    end)
end
