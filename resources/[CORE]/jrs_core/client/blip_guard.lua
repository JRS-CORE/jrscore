-- ============================================================================
-- JRS / JRS CORE - BLIP POOL PROTECTION GUARD (fwuiBlip Safeguard)
-- Protects RedM client from hitting the hard 920-slot fwuiBlip pool limit.
-- Features:
--   1. Central tracking of all created blips per resource.
--   2. Automatic orphaned blip cleanup when any resource stops/restarts.
--   3. Hard ceiling (850/920) preventing engine overflow crashes.
--   4. Periodic health watchdog & cleanup of stale handles.
--   5. Client inspection command: /blippool
-- ============================================================================

local BLIP_POOL_LIMIT   = 850 -- RedM engine hard limit is 920; 850 provides a safe buffer
local BLIP_POOL_WARNING = 780 -- Threshold to trigger console warnings

local activeBlips = {}         -- [blipHandle] = { res = resourceName, addedAt = gameTimer }
local resourceBlipCounts = {}  -- [resName] = count
local totalBlips = 0

-- Exported: Can a resource safely create a blip?
local function canCreateBlip(resName)
    resName = tostring(resName or 'unknown')
    if totalBlips >= BLIP_POOL_LIMIT then
        print(string.format('^1[JRS BLIP GUARD CRITICAL]^7 fwuiBlip pool nearly full (%d/920)! Blocked blip creation from resource: ^3%s^7', totalBlips, resName))
        return false
    end
    if totalBlips >= BLIP_POOL_WARNING and (totalBlips % 20 == 0) then
        print(string.format('^3[JRS BLIP GUARD WARNING]^7 High blip usage (%d/920). Blip created by: ^5%s^7', totalBlips, resName))
    end
    return true
end

-- Exported: Register a newly created blip handle
local function registerBlip(resName, handle)
    if not handle or handle == 0 then return end
    resName = tostring(resName or 'unknown')

    if not activeBlips[handle] then
        activeBlips[handle] = {
            res = resName,
            addedAt = GetGameTimer()
        }
        resourceBlipCounts[resName] = (resourceBlipCounts[resName] or 0) + 1
        totalBlips = totalBlips + 1
    end
end

-- Exported: Unregister a blip when deleted
local function unregisterBlip(handle)
    if not handle or handle == 0 then return end
    local info = activeBlips[handle]
    if info then
        local res = info.res
        if resourceBlipCounts[res] and resourceBlipCounts[res] > 0 then
            resourceBlipCounts[res] = resourceBlipCounts[res] - 1
            if resourceBlipCounts[res] <= 0 then
                resourceBlipCounts[res] = nil
            end
        end
        activeBlips[handle] = nil
        totalBlips = math.max(0, totalBlips - 1)
    end
end

-- Exported: Safe wrapper to create a coordinate blip with automatic protection
local function createSafeBlip(style, x, y, z, sprite, scale, name, color)
    local caller = GetInvokingResource() or GetCurrentResourceName()
    if not canCreateBlip(caller) then
        return nil
    end

    local blip = nil
    if type(BlipAddForCoords) == 'function' then
        blip = BlipAddForCoords(tonumber(style) or 1664425300, x + 0.0, y + 0.0, z + 0.0)
    else
        blip = Citizen.InvokeNative(0x554D9D53F696D002, tonumber(style) or 1664425300, x + 0.0, y + 0.0, z + 0.0)
    end

    if not blip or blip == 0 then
        return nil
    end

    registerBlip(caller, blip)

    if sprite then
        local spriteHash = type(sprite) == 'number' and sprite or joaat(tostring(sprite))
        if type(SetBlipSprite) == 'function' then
            pcall(SetBlipSprite, blip, spriteHash, true)
        end
    end

    if scale and type(SetBlipScale) == 'function' then
        pcall(SetBlipScale, blip, tonumber(scale) or 0.2)
    end

    if name and tostring(name) ~= '' then
        local safeName = type(JrsLang) == 'table' and type(JrsLang.SanitizeNativeText) == 'function' and JrsLang.SanitizeNativeText(tostring(name), 'Location') or tostring(name)
        pcall(Citizen.InvokeNative, 0x9CB1A1623062F402, blip, CreateVarString(10, 'LITERAL_STRING', safeName))
    end

    if color then
        local colorHash = type(color) == 'number' and color or joaat(tostring(color))
        pcall(Citizen.InvokeNative, 0x662D364ABF16DE2F, blip, colorHash)
    end

    return blip
end

-- Exports
exports('CanCreateBlip', canCreateBlip)
exports('RegisterBlip', registerBlip)
exports('UnregisterBlip', unregisterBlip)
exports('CreateSafeBlip', createSafeBlip)
exports('GetBlipPoolStats', function()
    return {
        total = totalBlips,
        maxSafe = BLIP_POOL_LIMIT,
        engineLimit = 920,
        resources = resourceBlipCounts
    }
end)

-- Automatic Sentinel: Clean up any blips created by stopped/restarted resources
AddEventHandler('onResourceStop', function(stoppedRes)
    if not stoppedRes or stoppedRes == '' then return end

    local cleaned = 0
    local toRemove = {}
    for handle, info in pairs(activeBlips) do
        if info.res == stoppedRes then
            toRemove[#toRemove + 1] = handle
        end
    end

    for _, handle in ipairs(toRemove) do
        if DoesBlipExist(handle) then
            pcall(RemoveBlip, handle)
            cleaned = cleaned + 1
        end
        activeBlips[handle] = nil
    end

    if resourceBlipCounts[stoppedRes] then
        totalBlips = math.max(0, totalBlips - resourceBlipCounts[stoppedRes])
        resourceBlipCounts[stoppedRes] = nil
    end

    if cleaned > 0 then
        print(string.format('^2[JRS BLIP GUARD]^7 Auto-cleaned %d orphaned blip(s) from stopped resource: ^3%s^7', cleaned, stoppedRes))
    end
end)

-- Background Watchdog: Runs every 10 seconds to purge stale handles and reconcile counts
CreateThread(function()
    while true do
        Wait(10000)
        local purged = 0
        for handle, info in pairs(activeBlips) do
            if not DoesBlipExist(handle) then
                local res = info.res
                if resourceBlipCounts[res] and resourceBlipCounts[res] > 0 then
                    resourceBlipCounts[res] = resourceBlipCounts[res] - 1
                    if resourceBlipCounts[res] <= 0 then
                        resourceBlipCounts[res] = nil
                    end
                end
                activeBlips[handle] = nil
                purged = purged + 1
            end
        end

        local actualCount = 0
        for _ in pairs(activeBlips) do
            actualCount = actualCount + 1
        end
        totalBlips = actualCount

        -- If pool is excessively high, log top consumers to help server admins
        if totalBlips >= BLIP_POOL_WARNING then
            print(string.format('^3[JRS BLIP GUARD WATCHDOG]^7 High blip count: ^1%d^7/920 slots active.', totalBlips))
            local sorted = {}
            for res, count in pairs(resourceBlipCounts) do
                sorted[#sorted + 1] = { res = res, count = count }
            end
            table.sort(sorted, function(a, b) return a.count > b.count end)
            for i = 1, math.min(5, #sorted) do
                print(string.format('   ^3- Top consumer:^7 %-25s (%d blips)', sorted[i].res, sorted[i].count))
            end
        end
    end
end)

-- Client Command: /blippool to view live usage
RegisterCommand('blippool', function()
    print('^2==================== JRS BLIP POOL STATUS ====================^7')
    print(string.format('Active Tracked Blips: ^3%d^7 / ^2920^7 (Safe Limit: ^5%d^7)', totalBlips, BLIP_POOL_LIMIT))
    print('Breakdown by Resource:')
    local sorted = {}
    for res, count in pairs(resourceBlipCounts) do
        sorted[#sorted + 1] = { res = res, count = count }
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    for _, item in ipairs(sorted) do
        print(string.format('  - %-30s : %d blips', item.res, item.count))
    end
    print('^2=============================================================^7')
end, false)
