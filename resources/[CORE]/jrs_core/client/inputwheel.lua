local WHEEL_DEBUG = '^3[JRS WHEEL]^7 '
local NATIVE_DISABLE_CONTROL_ACTION = 0xFE99B66D079CF6BC
local INPUT_OPEN_WHEEL_MENU = 0xAC4BD4F1
local INPUT_QUICK_SHORTCUT_ABILITIES_MENU = 0x9CC7A1A4

local function dbg(...)
    if Config.InputWheel.Debug then
        print(WHEEL_DEBUG, ...)
    end
end

local function toHex(v)
    if type(v) ~= 'number' then
        return tostring(v)
    end
    if v < 0 then
        v = 0x100000000 + v
    end
    return string.format('0x%08X', v)
end

local function safeHash(nameOrHash)
    if type(nameOrHash) == 'number' then
        return nameOrHash
    end
    return GetHashKey(tostring(nameOrHash))
end

local function itemNameOrDefault(idx, args, fallback)
    return tostring(args[idx] or fallback)
end

local function qtyOrDefault(idx, args, fallback)
    local n = tonumber(args[idx] or fallback)
    if not n or n < 1 then
        return fallback
    end
    return math.floor(n)
end

local WheelHook = {
    enabled = true,
    isOpen = false,
    currentWheel = 0,
    selectedItem = 0,
    lastSelectedItem = 0,
    currentUsableItem = 0,
    currentUsableJrsItem = nil,
    sawHeld = false,
    lastUseAt = 0,
    useCooldownMs = (Config.InputWheel.Sync and Config.InputWheel.Sync.UseCooldownMs) or 350,
    onMountOpened = false,
    forceWeaponsOnOpen = false,
    switchedToWeapons = false,
    weaponTransitionRequested = false,
}

local WheelState = {
    desiredCounts = {},
    appliedCounts = {},
    extraEntries = {},    -- server-provided entries for auto-mirrored items (not in Config)
    signatures = {},      -- jrs key -> effect signature (H/S/D cores it restores)
    resolvedNative = {},  -- jrs key -> native item hash that is actually mirrored
    nativeHashToJrs = {},
    retries = {},         -- jrs key -> failed repair attempts since the last snapshot
}

local function getWheelEntry(jrsKey)
    local items = Config.InputWheel.WheelItems
    return (items and items[jrsKey]) or WheelState.extraEntries[jrsKey]
end

local function nativeKeyIsValid(hash)
    if not ItemdatabaseIsKeyValid then
        return true
    end
    local ok, valid = pcall(ItemdatabaseIsKeyValid, hash, 0)
    return (not ok) or valid == true or valid == 1
end

local MULTI_SLOT_TONIC_HASHES = {
    [safeHash('consumable_tonic')] = true,
    [safeHash('consumable_tonic_used')] = true,
    [safeHash('consumable_potent_tonic')] = true,
    [safeHash('consumable_special_tonic')] = true,
}

-- Chooses the native item mirrored for a jrs item. Natives the game lists on the wheel
-- (Config.InputWheel.ShownNatives) are used as-is; anything else takes the place of an unused
-- native from Config.InputWheel.Substitutes so it still gets its own wheel entry. Names the item
-- database rejects fall through to the entry's fallback list. `used` holds the hashes already
-- taken by other owned items.
local function pickNativeHash(jrsKey, used, shown)
    local entry = getWheelEntry(jrsKey)
    if not entry then
        return nil
    end
    local wanted = safeHash(entry.nativeName)
    local substitute = Config.InputWheel.SubstituteUnlisted ~= false
    -- If wanted is valid and shown (and not already taken by another item in this bag), use it directly
    if nativeKeyIsValid(wanted) and (shown[wanted] or not substitute) and not used[wanted] then
        return wanted
    end
    if substitute then
        local kind = entry.kind or ((entry.nativeName == 'consumable_coffee') and 'drink' or 'food')
        -- prefer natives whose wheel description/icons match what the item really restores
        local sig = WheelState.signatures[jrsKey]
        local pool = sig and (Config.InputWheel.SubstitutesBySignature or {})[sig]
            or (Config.InputWheel.Substitutes or {})[kind] or {}
        local firstValid = nil
        for i = 1, #pool do
            local hash = safeHash(pool[i])
            -- Never allow multi-slot miracle tonics as a substitute (prevents 3-slot duplication)
            if nativeKeyIsValid(hash) and not MULTI_SLOT_TONIC_HASHES[hash] then
                firstValid = firstValid or hash
                if not used[hash] then
                    return hash
                end
            end
        end
        if firstValid then
            return firstValid -- pool exhausted: share an entry rather than lose the item
        end
    end
    if nativeKeyIsValid(wanted) and not used[wanted] then
        return wanted
    end
    local fallbacks = Config.InputWheel.FallbackNatives or {}
    local extra = entry.fallback
    if not extra then
        extra = (entry.nativeName == 'consumable_coffee') and fallbacks.drink or fallbacks.generic
    end
    for i = 1, #(extra or {}) do
        local hash = safeHash(extra[i])
        if nativeKeyIsValid(hash) and not MULTI_SLOT_TONIC_HASHES[hash] and not used[hash] then
            return hash
        end
    end
    if nativeKeyIsValid(wanted) then
        return wanted
    end
    return nil
end

local function resolveNativeHash(jrsKey)
    return WheelState.resolvedNative[jrsKey]
end

-- Deterministic assignment (sorted keys, natives the game lists first) so the same bag always
-- produces the same wheel. Returns the previous assignment so callers can move items whose
-- native changed.
local function assignNatives()
    local previous = WheelState.resolvedNative
    local shown = {}
    for _, name in ipairs(Config.InputWheel.ShownNatives or {}) do
        shown[safeHash(name)] = true
    end

    local keys = {}
    for jrsKey, count in pairs(WheelState.desiredCounts) do
        if (tonumber(count) or 0) > 0 then keys[#keys + 1] = jrsKey end
    end
    table.sort(keys)

    local assigned, used = {}, {}
    for pass = 1, 2 do
        for i = 1, #keys do
            local jrsKey = keys[i]
            local entry = getWheelEntry(jrsKey)
            local isShown = (entry and shown[safeHash(entry.nativeName)]) and true or false
            if (pass == 1) == isShown and not assigned[jrsKey] then
                local hash = pickNativeHash(jrsKey, used, shown)
                if hash then
                    assigned[jrsKey] = hash
                    used[hash] = true
                    if entry and hash ~= safeHash(entry.nativeName) then
                        dbg(('%s (%s) takes the place of %s'):format(tostring(jrsKey), tostring(entry.nativeName), tostring(hash)))
                    end
                end
            end
        end
    end
    -- items that left the bag but still have native units to remove keep their old native
    for jrsKey, hash in pairs(previous) do
        if not assigned[jrsKey] and (WheelState.appliedCounts[jrsKey] or 0) > 0 then
            assigned[jrsKey] = hash
        end
    end
    WheelState.resolvedNative = assigned
    return previous
end

-- Reverse index (native hash -> owned jrs keys), rebuilt from what the player owns.
-- Several jrs items can share one native ("moonshine" and "consumable_moonshine"), so the
-- lookup below resolves to whichever synonym is actually in the bag.
local function buildNativeIndex()
    WheelState.nativeHashToJrs = {}
    for jrsKey, count in pairs(WheelState.desiredCounts) do
        if (tonumber(count) or 0) > 0 then
            local hash = resolveNativeHash(jrsKey)
            if hash then
                WheelState.nativeHashToJrs[hash] = WheelState.nativeHashToJrs[hash] or {}
                table.insert(WheelState.nativeHashToJrs[hash], jrsKey)
            end
        end
    end
end

local function ResolveJrsItemForNativeHash(itemHash)
    local candidates = WheelState.nativeHashToJrs[itemHash]
    if not candidates then
        return nil
    end
    for i = 1, #candidates do
        local jrsItem = candidates[i]
        if (WheelState.appliedCounts[jrsItem] or 0) > 0 then
            return jrsItem
        end
    end
    return candidates[1]
end

-- UI-side state only: safe to reset any time without touching the native items that are mirrored.
local function resetWheelUiState()
    WheelHook.isOpen = false
    WheelHook.currentWheel = 0
    WheelHook.selectedItem = 0
    WheelHook.lastSelectedItem = 0
    WheelHook.currentUsableItem = 0
    WheelHook.currentUsableJrsItem = nil
    WheelHook.sawHeld = false
    WheelHook.onMountOpened = false
    WheelHook.forceWeaponsOnOpen = false
    WheelHook.switchedToWeapons = false
    WheelHook.weaponTransitionRequested = false
end

-- Full reset: only valid right after the native items were removed (start/stop).
local function resetWheelMirrorState()
    WheelState.desiredCounts = {}
    WheelState.appliedCounts = {}
    WheelState.extraEntries = {}
    WheelState.signatures = {}
    WheelState.resolvedNative = {}
    WheelState.nativeHashToJrs = {}
    WheelState.retries = {}
    resetWheelUiState()
end

function NewGuid()
    local struct = DataView.ArrayBuffer(8 * 4)
    struct:SetInt32(0, 0)
    struct:SetInt32(8, 0)
    struct:SetInt32(16, 0)
    struct:SetInt32(24, 0)
    return struct
end

local function GuidToString(guid)
    if not guid then
        return 'nil-guid'
    end
    return string.format(
        '[%s %s %s %s]',
        toHex(guid:GetInt32(0) or 0),
        toHex(guid:GetInt32(8) or 0),
        toHex(guid:GetInt32(16) or 0),
        toHex(guid:GetInt32(24) or 0)
    )
end

function NewSlotInfo()
    local struct = DataView.ArrayBuffer(8 * 8)
    local guid = NewGuid()
    local function syncGuid()
        struct:SetInt32(0, guid:GetInt32(0))
        struct:SetInt32(8, guid:GetInt32(8))
        struct:SetInt32(16, guid:GetInt32(16))
        struct:SetInt32(24, guid:GetInt32(24))
    end
    syncGuid()
    struct:SetInt32(32, 0)
    struct:SetInt32(40, 0)
    struct:SetInt32(48, 0)
    struct:SetInt32(56, 0)
    function struct:GetGuidStruct()
        return guid
    end
    function struct:GetGuidBuffer()
        return guid:Buffer()
    end
    function struct:SetGuid(newGuid)
        guid:SetInt32(0, newGuid:GetInt32(0) or 0)
        guid:SetInt32(8, newGuid:GetInt32(8) or 0)
        guid:SetInt32(16, newGuid:GetInt32(16) or 0)
        guid:SetInt32(24, newGuid:GetInt32(24) or 0)
        syncGuid()
    end
    function struct:GetSlotId()
        return struct:GetInt32(56)
    end
    function struct:SetSlotId(slotId)
        struct:SetInt32(56, tonumber(slotId) or 0)
    end
    return struct
end

function NewItemInfo()
    local struct = DataView.ArrayBuffer(8 * 13)
    for i = 0, 96, 8 do
        struct:SetInt32(i, 0)
    end
    return struct
end

function GetPlayerInventoryItemGUID(item, guidBuffer, slotId)
    local outGuid = NewGuid()
    local result = Citizen.InvokeNative(
        0x886DFD3E185C8A89,
        1,
        guidBuffer,
        item,
        slotId,
        outGuid:Buffer(),
        Citizen.ResultAsInteger()
    )
    return outGuid, result
end

function GetPlayerInventoryGUID()
    local emptyGuid = NewGuid()
    local invGuid, result = GetPlayerInventoryItemGUID(`CHARACTER`, emptyGuid:Buffer(), `SLOTID_NONE`)
    return invGuid, result
end

function GetItemGroup(item)
    local info = NewItemInfo()
    if ItemdatabaseIsKeyValid and not ItemdatabaseIsKeyValid(item, 0) then
        return 0, info
    end
    local ok = Citizen.InvokeNative(0xFE90ABBCBFDC13B2, item, info:Buffer())
    if not ok then
        return 0, info
    end
    local group = info:GetInt32(16) or 0
    return group, info
end

function GetDefaultItemSlotInfo(item, context)
    return Citizen.InvokeNative(0x6452B1D357D81742, item, context)
end

function FitsSlot(item, slotId)
    return Citizen.InvokeNative(0x780C5B9AE2819807, item, slotId)
end

function ResolveItemSlotInfo(item)
    local slotInfo = NewSlotInfo()
    local playerInvGuid = select(1, GetPlayerInventoryGUID())
    slotInfo:SetGuid(playerInvGuid)
    slotInfo:SetSlotId(`SLOTID_SATCHEL`)
    local group = GetItemGroup(item)
    if group == `CLOTHING` then
        if FitsSlot(item, `SLOTID_WARDROBE`) then
            local wardrobeGuid = select(1, GetPlayerInventoryItemGUID(`WARDROBE`, slotInfo:GetGuidBuffer(), `SLOTID_WARDROBE`))
            slotInfo:SetGuid(wardrobeGuid)
            slotInfo:SetSlotId(GetDefaultItemSlotInfo(item, `WARDROBE`))
        else
            slotInfo:SetSlotId(GetDefaultItemSlotInfo(item, `SLOTID_WARDROBE`))
        end
    elseif group == `WEAPON` then
        if FitsSlot(item, `SLOTID_WEAPON_0`) then
            slotInfo:SetSlotId(`SLOTID_WEAPON_0`)
        elseif FitsSlot(item, `SLOTID_WEAPON_1`) then
            slotInfo:SetSlotId(`SLOTID_WEAPON_1`)
        else
            slotInfo:SetSlotId(GetDefaultItemSlotInfo(item, `CHARACTER`))
        end
    elseif group == `HORSE` then
        slotInfo:SetSlotId(`SLOTID_ACTIVE_HORSE`)
    elseif group == `UPGRADE` then
        if FitsSlot(item, `SLOTID_UPGRADE`) then
            slotInfo:SetSlotId(`SLOTID_UPGRADE`)
        else
            slotInfo:SetSlotId(GetDefaultItemSlotInfo(item, `CHARACTER`))
        end
    else
        if FitsSlot(item, `SLOTID_SATCHEL`) then
            slotInfo:SetSlotId(`SLOTID_SATCHEL`)
        elseif FitsSlot(item, `SLOTID_WARDROBE`) then
            slotInfo:SetSlotId(`SLOTID_WARDROBE`)
        else
            slotInfo:SetSlotId(GetDefaultItemSlotInfo(item, `CHARACTER`))
        end
    end
    return slotInfo, group
end

function GetExistingItemGuid(item)
    local slotInfo, group = ResolveItemSlotInfo(item)
    local existingGuid, guidResult = GetPlayerInventoryItemGUID(item, slotInfo:GetGuidBuffer(), slotInfo:GetSlotId())
    return slotInfo, existingGuid, guidResult, group
end

function AddItemWithGUID(item, newItemGuid, slotInfo, quantity, addReason)
    local inventoryGuidValid = Citizen.InvokeNative(0xB881CA836CC4B6D4, slotInfo:GetGuidBuffer())
    if not inventoryGuidValid then
        return false
    end
    return Citizen.InvokeNative(
        0xCB5D11F9508A928D,
        1,
        newItemGuid:Buffer(),
        slotInfo:GetGuidBuffer(),
        item,
        slotInfo:GetSlotId(),
        quantity,
        addReason
    )
end

function AddItemToInventory(item, quantity)
    local slotInfo = ResolveItemSlotInfo(item)
    local newItemGuid = NewGuid()
    return AddItemWithGUID(item, newItemGuid, slotInfo, quantity, `ADD_REASON_DEFAULT`)
end

function RemoveItemWithGuid(existingGuid, quantity, removeReason)
    return Citizen.InvokeNative(
        0x3E4E811480B3AE79,
        1,
        existingGuid:Buffer(),
        quantity or 1,
        removeReason or `REMOVE_REASON_DEFAULT`
    )
end

function RemoveItemByName(item, quantity)
    local _, existingGuid, guidResult = GetExistingItemGuid(item)
    if guidResult ~= 1 then
        return false
    end
    local guidValid = Citizen.InvokeNative(0xB881CA836CC4B6D4, existingGuid:Buffer())
    if not guidValid then
        return false
    end
    return RemoveItemWithGuid(existingGuid, quantity, `REMOVE_REASON_DEFAULT`)
end

-- Every native this script could have mirrored (wanted names, fallbacks, auto natives).
local function allManagedNativeHashes()
    local seen, list = {}, {}
    local function add(name)
        if name and name ~= '' then
            local hash = safeHash(name)
            if not seen[hash] then
                seen[hash] = true
                list[#list + 1] = hash
            end
        end
    end
    for _, data in pairs(Config.InputWheel.WheelItems or {}) do
        add(data.nativeName)
        for i = 1, #(data.fallback or {}) do add(data.fallback[i]) end
    end
    local fallbacks = Config.InputWheel.FallbackNatives or {}
    for _, group in pairs(fallbacks) do
        for i = 1, #group do add(group[i]) end
    end
    for _, native in pairs((Config.InputWheel.AutoNative or {}).Categories or {}) do add(native) end
    return list
end

local function clearManagedWheelItems()
    local hashes = allManagedNativeHashes()
    for i = 1, #hashes do
        local removed = 0
        while removed < 250 do
            if not RemoveItemByName(hashes[i], 1) then
                break
            end
            removed = removed + 1
        end
    end
end

-- Adds/removes `qty` units of a native item ONE AT A TIME. A single call with the full quantity
-- creates an item the game's wheel does not list, while unit-by-unit adds (the original
-- behaviour) show up correctly. Returns units done.
local function addNativeUnits(hash, qty)
    local done = 0
    for _ = 1, qty do
        local ok, res = pcall(AddItemToInventory, hash, 1)
        if not (ok and res) then
            break
        end
        done = done + 1
    end
    return done
end

local function removeNativeUnits(hash, qty)
    local done = 0
    for _ = 1, qty do
        local ok, res = pcall(RemoveItemByName, hash, 1)
        if not (ok and res) then
            break
        end
        done = done + 1
    end
    return done
end

local MAX_REPAIR_ATTEMPTS = 3

-- Brings the native inventory in line with desiredCounts. appliedCounts only ever records
-- units the game actually accepted, so a failed add is retried by the repair loop instead
-- of being remembered as done (which used to leave items missing from the wheel for good).
local function reconcileWheel()
    local keys = {}
    for jrsKey in pairs(WheelState.desiredCounts) do keys[jrsKey] = true end
    for jrsKey in pairs(WheelState.appliedCounts) do keys[jrsKey] = true end

    local pending = false
    for jrsKey in pairs(keys) do
        local desired = tonumber(WheelState.desiredCounts[jrsKey] or 0) or 0
        local applied = tonumber(WheelState.appliedCounts[jrsKey] or 0) or 0
        local diff = desired - applied
        if diff ~= 0 then
            local hash = resolveNativeHash(jrsKey)
            if hash then
                if diff > 0 then
                    applied = applied + addNativeUnits(hash, diff)
                else
                    applied = applied - removeNativeUnits(hash, -diff)
                end
            else
                -- no usable native at all: nothing to mirror, do not retry forever
                applied = desired
            end
            if applied < 0 then applied = 0 end
            WheelState.appliedCounts[jrsKey] = applied
            if applied ~= desired then
                WheelState.retries[jrsKey] = (WheelState.retries[jrsKey] or 0) + 1
                if WheelState.retries[jrsKey] < MAX_REPAIR_ATTEMPTS then
                    pending = true
                else
                    -- give up until the next snapshot (e.g. native stack cap reached)
                    WheelState.appliedCounts[jrsKey] = desired
                end
            else
                WheelState.retries[jrsKey] = nil
            end
        end
        if (WheelState.appliedCounts[jrsKey] or 0) <= 0 and desired <= 0 then
            WheelState.appliedCounts[jrsKey] = nil
        end
    end
    return pending
end

local function ApplyWheelSnapshot(counts, extra, sigs)
    WheelState.desiredCounts = type(counts) == 'table' and counts or {}
    WheelState.extraEntries = type(extra) == 'table' and extra or {}
    WheelState.signatures = type(sigs) == 'table' and sigs or {}
    WheelState.retries = {}
    local previous = assignNatives()
    -- an item whose native changed (another item took its entry) moves: drop the old native's units
    for jrsKey, oldHash in pairs(previous) do
        local newHash = WheelState.resolvedNative[jrsKey]
        local applied = tonumber(WheelState.appliedCounts[jrsKey] or 0) or 0
        if newHash and newHash ~= oldHash and applied > 0 then
            removeNativeUnits(oldHash, applied)
            WheelState.appliedCounts[jrsKey] = 0
        end
    end
    buildNativeIndex()
    reconcileWheel()
end

-- Re-adds native items the game lost (death/respawn/ped change wipe the native satchel while
-- appliedCounts still says they are there).
local function verifyWheelItems()
    local repaired = false
    for jrsKey, applied in pairs(WheelState.appliedCounts) do
        if (tonumber(applied) or 0) > 0 then
            local hash = resolveNativeHash(jrsKey)
            if hash then
                local ok, _, _, guidResult = pcall(GetExistingItemGuid, hash)
                if ok and guidResult ~= 1 then
                    WheelState.appliedCounts[jrsKey] = 0
                    WheelState.retries[jrsKey] = nil
                    repaired = true
                end
            end
        end
    end
    if repaired or next(WheelState.retries) ~= nil then
        buildNativeIndex()
        reconcileWheel()
    end
end

local function UpdateCurrentUsableWheelItem(itemHash)
    WheelHook.currentUsableItem = 0
    WheelHook.currentUsableJrsItem = nil
    if not itemHash or itemHash == 0 then
        return
    end
    local jrsItem = ResolveJrsItemForNativeHash(itemHash)
    if not jrsItem then
        return
    end
    if ItemdatabaseIsKeyValid and not ItemdatabaseIsKeyValid(itemHash, 0) then
        return
    end
    local _, _, guidResult = GetExistingItemGuid(itemHash)
    if guidResult == 1 then
        WheelHook.currentUsableItem = itemHash
        WheelHook.currentUsableJrsItem = jrsItem
    end
end

local function HandleQuickSelectMessages()
    while EventsUiIsPending(`HUD_QUICK_SELECT`) do
        local msg = DataView.ArrayBuffer(8 * 4)
        msg:SetInt32(0, 0)
        msg:SetInt32(8, 0)
        msg:SetInt32(16, 0)
        msg:SetInt32(24, 0)
        local ok = Citizen.InvokeNative(0xE24E957294241444, `hud_quick_select`, msg:Buffer())
        if ok ~= 0 then
            local f0 = msg:GetInt32(0) or 0
            local f1 = msg:GetInt32(8) or 0
            local f2 = msg:GetInt32(16) or 0
            if f0 == `ITEM_FOCUSED` then
                if f1 == 1 and f2 == 813560150 then
                    WheelHook.currentWheel = 0
                elseif f1 == 2 and f2 == -414255251 then
                    WheelHook.currentWheel = 1
                elseif f1 == 3 and f2 == -1472057397 then
                    WheelHook.currentWheel = 2
                end
            end
        end
    end
end

local function prettifyItemName(jrsItemName)
    local cfg = Config.InputWheel.WheelItems and Config.InputWheel.WheelItems[jrsItemName]
    if cfg and cfg.notifyText and cfg.notifyText ~= '' then
        return tostring(cfg.notifyText)
    end
    local text = tostring(jrsItemName or _U('item_used'))
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    text = text:gsub('_', ' ')
    text = text:upper()
    return text
end

local function showUsedItemNotification(jrsItemName, amount)
    local notifyCfg = Config.InputWheel.Notify or {}
    if notifyCfg.Enabled == false then
        return
    end
    local cfg = Config.InputWheel.WheelItems and Config.InputWheel.WheelItems[jrsItemName]
    local title = notifyCfg.Title or _U('used')
    local icon = notifyCfg.Icon or 'inventory_items'
    local color = notifyCfg.Color or 'COLOR_WHITE'
    local duration = tonumber(notifyCfg.Duration or 5000) or 5000
    local nativeNameForNotify = 'lock'
    if cfg and cfg.nativeName and cfg.nativeName ~= '' then
        nativeNameForNotify = tostring(cfg.nativeName)
    end
    local prettyName = prettifyItemName(jrsItemName)
    TriggerEvent(
        notifyCfg.Event or 'jrs_core:sendAdvancedRightNotification',
        title .. ' ' .. '~o~' .. prettyName,
        icon,
        nativeNameForNotify,
        color,
        duration
    )
end

local wheelReleaseStartedAt = 0

local function RestoreCameraAndControls()
    pcall(SetPlayerControl, PlayerId(), true, 0)
    local controls = {
        0xA987235F, -- INPUT_LOOK_LR (Mouse X)
        0xD2047988, -- INPUT_LOOK_UD (Mouse Y)
        0x8AAA0AD4, -- INPUT_SPRINT
        0xD9D0E1C0, -- INPUT_JUMP
    }
    for i = 1, #controls do
        local c = controls[i]
        pcall(EnableControlAction, 0, c, true)
        pcall(EnableControlAction, 1, c, true)
        pcall(EnableControlAction, 2, c, true)
    end
end

local function ForceUnstickWheelAndMouse()
    pcall(function()
        Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("hud_quick_select"))
        Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("ability_cards"))
        Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("hud_quick_select_abilities"))
        Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("ability_card_indicator"))
    end)
    resetWheelUiState()
    wheelReleaseStartedAt = 0
    RestoreCameraAndControls()
end

local function HandleWheelHook()
    if not WheelHook.enabled then
        return
    end

    local wheelHeld = IsControlPressed(0, INPUT_OPEN_WHEEL_MENU)
        or IsDisabledControlPressed(0, INPUT_OPEN_WHEEL_MENU)
        or IsControlPressed(2, INPUT_OPEN_WHEEL_MENU)
        or IsDisabledControlPressed(2, INPUT_OPEN_WHEEL_MENU)

    local running = IsUiappRunning("hud_quick_select")

    -- Disable ALL spacebar and ability card shortcut controls on groups 0, 1, and 2
    -- whenever TAB is held or the wheel UI is active so pressing Space can NEVER
    -- trigger ability cards, desync the wheel, or lock the mouse camera.
    if running or wheelHeld or WheelHook.isOpen then
        local blockedControls = {
            0xD9D0E1C0, -- INPUT_JUMP (Physical Spacebar key)
            0x9CC7A1A4, -- INPUT_QUICK_SHORTCUT_ABILITIES_MENU (Wheel spacebar shortcut)
            0xCEE12B50, -- INPUT_QUICK_SHORTCUT_SECONDARY
            0x6319DB71, -- INPUT_CURSOR_ACCEPT_PROMPT
        }
        for i = 1, #blockedControls do
            local ctrl = blockedControls[i]
            Citizen.InvokeNative(NATIVE_DISABLE_CONTROL_ACTION, 0, ctrl, true)
            Citizen.InvokeNative(NATIVE_DISABLE_CONTROL_ACTION, 1, ctrl, true)
            Citizen.InvokeNative(NATIVE_DISABLE_CONTROL_ACTION, 2, ctrl, true)
        end
    end

    -- Make sure the native satchel still holds the mirrored items the moment the wheel key goes down
    -- (before the game builds the wheel), not only on the periodic check.
    if wheelHeld and not WheelHook.wheelKeyWasDown and not running then
        pcall(verifyWheelItems)
    end
    WheelHook.wheelKeyWasDown = wheelHeld

    if running and wheelHeld then
        WheelHook.sawHeld = true
    end

    -- Watchdog: Detect stuck wheel if TAB was released but UI app did not close cleanly.
    -- It only arms once the key was actually seen held for this wheel: if the key state cannot be
    -- read while the wheel is open, "not held" would be a false alarm and the watchdog would kill a
    -- healthy wheel a few frames after it opened.
    if running and not wheelHeld and WheelHook.isOpen and WheelHook.sawHeld then
        if wheelReleaseStartedAt == 0 then
            wheelReleaseStartedAt = GetGameTimer()
        elseif (GetGameTimer() - wheelReleaseStartedAt) > 400 then
            pcall(function()
                Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("hud_quick_select"))
                Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("ability_cards"))
                Citizen.InvokeNative(0x2FF10C9C3F92277E, GetHashKey("hud_quick_select_abilities"))
            end)
            running = false
            wheelReleaseStartedAt = 0
        end
    else
        wheelReleaseStartedAt = 0
    end

    if running then
        if not WheelHook.isOpen then
            WheelHook.isOpen = true
            local ped = PlayerPedId()
            local onMount = (ped ~= 0 and (IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false)))
            WheelHook.onMountOpened = onMount
            -- The native wheel remembers its last tab.  After opening it on a
            -- horse, that can be the horse tab even after the player dismounts.
            -- Arm the short initial correction for every open, not just opens
            -- that start while mounted, so TAB always begins on Weapons.
            WheelHook.forceWeaponsOnOpen = Config.InputWheel.MountForceWeaponsTab ~= false
            WheelHook.switchedToWeapons = false
            WheelHook.currentWheel = -1 -- unknown until the engine reports the focused tab
            WheelHook.weaponTransitionRequested = false
        end
        HandleQuickSelectMessages()

        -- The native wheel remembers the horse/items tab after a dismount.  Do not
        -- synthesize R/RB or overwrite the player's input context: both can leave
        -- the ped trapped in the quick-select state.  Instead request the wheel's
        -- own documented WEAPON_WHEEL transition once after it reports a non-weapon
        -- tab.  This is a UI state change, not a fake key press.
        if WheelHook.forceWeaponsOnOpen and not WheelHook.switchedToWeapons then
            if WheelHook.currentWheel == 0 then
                WheelHook.switchedToWeapons = true
            elseif WheelHook.currentWheel ~= -1 and not WheelHook.weaponTransitionRequested then
                WheelHook.weaponTransitionRequested = true
                local transitioned = false
                local ok, result = pcall(function()
                    return Citizen.InvokeNative(0x7689CD255655BFD7, `hud_quick_select`, `WEAPON_WHEEL`)
                end)
                transitioned = ok and (result == true or result == 1)
                if not transitioned then
                    -- Keep native behaviour intact if this client build does
                    -- not expose the transition; never fall back to fake input.
                    WheelHook.switchedToWeapons = true
                end
            elseif WheelHook.weaponTransitionRequested then
                -- The focus event will update currentWheel to 0 on clients
                -- that support the transition.  No repeated requests needed.
                WheelHook.switchedToWeapons = true
            end
        end

        local selected = Citizen.InvokeNative(0x9C409BBC492CB5B1, Citizen.ResultAsInteger())
        if selected ~= WheelHook.lastSelectedItem then
            WheelHook.lastSelectedItem = selected or 0
            WheelHook.selectedItem = selected or 0
            if WheelHook.currentWheel == 1 or WheelHook.currentWheel == 2 then
                UpdateCurrentUsableWheelItem(selected or 0)
            end
        end
        return
    end

    if WheelHook.isOpen then
        local wheelBeforeClose = WheelHook.currentWheel
        local usableNative = WheelHook.currentUsableItem
        local usableJrs = WheelHook.currentUsableJrsItem
        local now = GetGameTimer()
        resetWheelUiState()

        -- Immediately restore player and mouse camera controls
        RestoreCameraAndControls()

        if (wheelBeforeClose == 1 or wheelBeforeClose == 2) and usableNative and usableNative ~= 0 and usableJrs then
            if now >= (WheelHook.lastUseAt + WheelHook.useCooldownMs) then
                WheelHook.lastUseAt = now
                TriggerServerEvent('jrs_core:wheel:useFromWheel', usableJrs)
            end
        end
    end
end

if Config.InputWheel.Enabled then
    CreateThread(function()
        clearManagedWheelItems()
        resetWheelMirrorState()
        Wait((Config.InputWheel.Sync and Config.InputWheel.Sync.RequestOnClientStartDelayMs) or 3000)
        TriggerServerEvent('jrs_core:wheel:requestSync')
    end)

    CreateThread(function()
        while true do
            Wait(0)
            HandleWheelHook()
            -- Emergency ESC unstick if wheel somehow flagged open without running app
            if WheelHook.isOpen and IsControlJustPressed(0, 0x4A903C11) then
                ForceUnstickWheelAndMouse()
            end
        end
    end)

    RegisterCommand('fixwheel', function()
        ForceUnstickWheelAndMouse()
        TriggerEvent('jrsCore:notify', 'WHEEL', 'Input wheel & camera controls reset.', 'placeholder', 3000)
    end, false)

    RegisterCommand('fixmouse', function()
        ForceUnstickWheelAndMouse()
        TriggerEvent('jrsCore:notify', 'MOUSE', 'Camera & mouse controls unfrozen.', 'placeholder', 3000)
    end, false)

    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName ~= GetCurrentResourceName() then
            return
        end
        -- A restart while the native wheel is open must never leave the
        -- player's camera or movement controls captured by that UI.
        ForceUnstickWheelAndMouse()
        clearManagedWheelItems()
        resetWheelMirrorState()
    end)

    RegisterNetEvent('jrs_core:wheel:applySnapshot', function(counts, extra, sigs)
        ApplyWheelSnapshot(counts, extra, sigs)
    end)

    -- Periodic repair: retries adds the game rejected and restores items the game dropped.
    CreateThread(function()
        Wait(8000)
        while true do
            Wait(6000)
            if not WheelHook.isOpen and next(WheelState.appliedCounts) ~= nil then
                local ped = PlayerPedId()
                if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
                    pcall(verifyWheelItems)
                end
            end
        end
    end)

    -- /wheeldiag: lists every owned wheel item with the native it maps to and whether the game
    -- accepted it, so a missing entry can be traced to a rejected native name.
    RegisterCommand('wheeldiag', function()
        local rows, bad = 0, 0
        print('^3[JRS WHEEL]^7 ---- diag ----')
        for jrsKey, desired in pairs(WheelState.desiredCounts) do
            local entry = getWheelEntry(jrsKey)
            local wanted = entry and entry.nativeName or '?'
            local hash = resolveNativeHash(jrsKey)
            local present = false
            if hash then
                local ok, _, _, guidResult = pcall(GetExistingItemGuid, hash)
                present = ok and guidResult == 1
            end
            rows = rows + 1
            if not present then bad = bad + 1 end
            print(('  %-34s x%-4s [%-3s] wanted=%-42s mirrored=%s applied=%s present=%s'):format(
                tostring(jrsKey), tostring(desired), tostring(WheelState.signatures[jrsKey] or '?'), tostring(wanted),
                hash and (safeHash(wanted) == hash and 'yes' or 'SUBSTITUTED') or 'NONE',
                tostring(WheelState.appliedCounts[jrsKey] or 0), tostring(present)))
        end
        print(('^3[JRS WHEEL]^7 %d wheel item(s), %d not present in the native satchel'):format(rows, bad))
        TriggerEvent('jrsCore:notify', 'WHEEL', ('%d items, %d missing - see F8 console'):format(rows, bad), 'placeholder', 4000)
    end, false)

    RegisterNetEvent('jrs_core:wheel:forceResync', function()
        TriggerServerEvent('jrs_core:wheel:requestSync')
    end)

    RegisterNetEvent('jrs_core:wheel:showUsedNotification', function(jrsItemName, amount)
        showUsedItemNotification(jrsItemName, amount)
    end)

    RegisterCommand('jrs_wheel_additem', function(_, args)
        local itemName = itemNameOrDefault(1, args, 'CONSUMABLE_PEACHES_CAN')
        local qty = qtyOrDefault(2, args, 1)
        local itemHash = safeHash(itemName)
        local added = AddItemToInventory(itemHash, qty)
        TriggerEvent(
            'jrsCore:notify',
            added and 'COMMAND SUCCESS' or 'COMMAND FAILED',
            added and ('Added %s x %s to the native item wheel.'):format(qty, itemName)
                or ('Unable to add %s to the native item wheel.'):format(itemName),
            'placeholder',
            4000
        )
    end, true)

    RegisterCommand('jrs_wheel_removeitem', function(_, args)
        local itemName = itemNameOrDefault(1, args, 'CONSUMABLE_PEACHES_CAN')
        local qty = qtyOrDefault(2, args, 1)
        local itemHash = safeHash(itemName)
        local removed = RemoveItemByName(itemHash, qty)
        TriggerEvent(
            'jrsCore:notify',
            removed and 'COMMAND SUCCESS' or 'COMMAND FAILED',
            removed and ('Removed %s x %s from the native item wheel.'):format(qty, itemName)
                or ('Unable to remove %s from the native item wheel.'):format(itemName),
            'placeholder',
            4000
        )
    end, true)
end
