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

-- See server/main.lua for why this re-resolves getCoreApi() on every access
-- instead of caching it once (jrs_core rebuilds its funcref table per call).
local jrsCoreWarned = {}
local jrsCore = setmetatable({}, {
    __index = function(_, key)
        return function(...)
            local args = { ... }
            if key == "getUser" or key == "GetUser" then
                if type(JRSInventoryGetCoreUser) == "function" then
                    return JRSInventoryGetCoreUser(tonumber(args[1]))
                end
                return nil
            end

            if key == "getCharacter" or key == "GetCharacter" then
                local okDirect, character = pcall(function()
                    return exports[(Config and Config.CoreResource) or 'jrs_core']:GetCharacter(tonumber(args[1]))
                end)
                if okDirect and character then return character end
            end

            local ok, api = pcall(function() return exports[(Config and Config.CoreResource) or 'jrs_core']:getCoreApi() end)
            if not ok or type(api) ~= "table" or not isCallable(api[key]) then
                if not jrsCoreWarned[key] then
                    jrsCoreWarned[key] = true
                    print(("^1[jrs_inventory:robbery] jrs_core API unavailable - \"%s\" was skipped.^0"):format(tostring(key)))
                end
                return nil
            end
            return api[key](...)
        end
    end,
})
local Inventory = JRSInventoryInternalAPI or exports[GetCurrentResourceName()]:jrs_inventoryApi()

local activeSearches = {}
local targetSearchers = {}
local actionLocks = {}
local lastActionAt = {}
local seenOperations = {}
local itemDefinitions = nil
local lastPoliceAlertAt = {}

local function cfg()
    return (Config and (Config.Robbery or Config.Search)) or {}
end

local function debugPrint(message)
    if cfg().Debug == true then
        print(("^3[jrs_inventory:robbery]^7 %s"):format(tostring(message)))
    end
end

local function notify(playerId, message)
    playerId = tonumber(playerId)
    if not playerId or not message then return end
    local ok = pcall(function()
        jrsCore.NotifyRightTip(playerId, tostring(message), 3000)
    end)
    if not ok then
        TriggerClientEvent('jrs_inventory:robbery:notify', playerId, tostring(message))
    end
end

local function positiveInteger(value)
    local number = tonumber(value)
    if not number or number <= 0 or number ~= math.floor(number) then return nil end
    local maxAmount = math.max(1, tonumber(cfg().MaxTransferAmount) or 100000)
    if number > maxAmount then return nil end
    return number
end

local function positiveCurrencyAmount(value)
    local number = tonumber(value)
    if not number or number <= 0 then return nil end
    local maxAmount = math.max(1, tonumber(cfg().MaxTransferAmount) or 100000)
    if number > maxAmount then return nil end
    -- Currency supports cents while item stacks stay integer-only.
    number = math.floor(number * 100 + 0.5) / 100
    if number <= 0 then return nil end
    return number
end

local function playerActive(playerId)
    playerId = tonumber(playerId)
    return playerId and playerId > 0 and GetPlayerName(playerId) ~= nil
end

local function getCharacter(playerId)
    playerId = tonumber(playerId)
    if not playerId then return nil end

    local ok, character = pcall(function()
        return jrsCore.getCharacter(playerId)
    end)
    if ok and character then return character end

    local okUser, user = pcall(function()
        return jrsCore.getUser(playerId)
    end)
    if okUser and user then
        return (user.character or user.getUsedCharacter)
    end
    return nil
end

local function restrictionCfg()
    local search = cfg()
    return (search.Restrictions or {})
end

local function protectedZoneAt(coords)
    local settings = restrictionCfg().ProtectedZones or {}
    if settings.Enabled ~= true or not coords then return nil end

    for _, zone in ipairs(settings.Zones or {}) do
        local zx, zy, zz = tonumber(zone.x), tonumber(zone.y), tonumber(zone.z)
        local radius = math.max(0.0, tonumber(zone.radius) or 0.0)
        if zx and zy and zz and radius > 0.0 then
            local dx = (coords.x or 0.0) - zx
            local dy = (coords.y or 0.0) - zy
            local dz = (coords.z or 0.0) - zz
            if (dx * dx + dy * dy + dz * dz) <= (radius * radius) then
                return tostring(zone.name or 'Protected Zone')
            end
        end
    end
    return nil
end

local function isPoliceJob(job)
    local settings = restrictionCfg().Police or {}
    local jobs = settings.Jobs or {}
    return jobs[tostring(job or ''):lower()] == true
end

local function getPolicePlayers()
    local police = {}
    for _, id in ipairs(GetPlayers()) do
        local playerId = tonumber(id)
        if playerId then
            local character = getCharacter(playerId)
            if character and isPoliceJob(character.job) then
                police[#police + 1] = playerId
            end
        end
    end
    return police
end

local function isAllowedNightHour(hour)
    local settings = restrictionCfg().NightOnly or {}
    if settings.Enabled ~= true then return true end

    hour = tonumber(hour)
    if not hour or hour < 0 or hour > 23 then return false end
    hour = math.floor(hour)

    local startHour = math.floor(tonumber(settings.StartHour) or 20) % 24
    local endHour = math.floor(tonumber(settings.EndHour) or 6) % 24

    if startHour == endHour then return true end
    if startHour < endHour then
        return hour >= startHour and hour < endHour
    end
    return hour >= startHour or hour < endHour
end

local function notifyRestriction(playerId, reason, extra)
    if reason == 'protected_zone' then
        notify(playerId, _Up(playerId, 'protected_zone_blocked') .. (extra and (' (' .. tostring(extra) .. ')') or ''))
    elseif reason == 'police_required' then
        notify(playerId, _Up(playerId, 'police_required', tonumber(extra) or 1))
    elseif reason == 'night_only' then
        local settings = restrictionCfg().NightOnly or {}
        notify(playerId, _Up(playerId, 'night_only', tonumber(settings.StartHour) or 20, tonumber(settings.EndHour) or 6))
    else
        notify(playerId, _Up(playerId, 'robbery_restricted'))
    end
end

local function getServerLocalHour()
    local ok, date = pcall(os.date, '*t')
    if not ok or type(date) ~= 'table' then return nil end
    local hour = tonumber(date.hour)
    if not hour then return nil end
    return math.floor(hour) % 24
end

local function checkRobberyRestrictions(sourcePlayer, targetPlayer)
    sourcePlayer, targetPlayer = tonumber(sourcePlayer), tonumber(targetPlayer)
    if not sourcePlayer or not targetPlayer then return false, 'restricted' end

    local restrictions = restrictionCfg()
    local zoneSettings = restrictions.ProtectedZones or {}
    if zoneSettings.Enabled == true then
        local sourcePed = GetPlayerPed(sourcePlayer)
        local targetPed = GetPlayerPed(targetPlayer)
        if sourcePed and sourcePed ~= 0 and zoneSettings.BlockSearcherInside == true then
            local zone = protectedZoneAt(GetEntityCoords(sourcePed))
            if zone then return false, 'protected_zone', zone end
        end
        if targetPed and targetPed ~= 0 and zoneSettings.BlockTargetInside == true then
            local zone = protectedZoneAt(GetEntityCoords(targetPed))
            if zone then return false, 'protected_zone', zone end
        end
    end

    local policeSettings = restrictions.Police or {}
    if policeSettings.RequirementEnabled == true then
        local minimum = math.max(0, math.floor(tonumber(policeSettings.MinimumOnline) or 1))
        if minimum > 0 then
            local onlinePolice = #getPolicePlayers()
            if onlinePolice < minimum then
                return false, 'police_required', minimum
            end
        end
    end

    local serverHour = getServerLocalHour()
    if not isAllowedNightHour(serverHour) then
        return false, 'night_only'
    end

    return true
end

local function alertPolice(sourcePlayer, targetPlayer)
    local settings = restrictionCfg().Police or {}
    if settings.NotifyOnRobbery ~= true then return end

    sourcePlayer = tonumber(sourcePlayer)
    if not sourcePlayer then return end
    local now = GetGameTimer()
    local cooldown = math.max(0, tonumber(settings.AlertCooldownMs) or 60000)
    if lastPoliceAlertAt[sourcePlayer] and now - lastPoliceAlertAt[sourcePlayer] < cooldown then return end
    lastPoliceAlertAt[sourcePlayer] = now

    -- A configured AlertMessage is used verbatim; the built-in text is resolved
    -- once per officer below, because they may not all read the same language.
    local message = tostring(settings.AlertMessage or '')
    local useDefaultMessage = message == ''

    local suffix = ''
    if settings.IncludeCoordinates == true then
        local targetPed = targetPlayer and GetPlayerPed(tonumber(targetPlayer)) or 0
        if targetPed and targetPed ~= 0 then
            local coords = GetEntityCoords(targetPed)
            suffix = (' [%.1f, %.1f]'):format(coords.x or 0.0, coords.y or 0.0)
        end
    end

    for _, policeId in ipairs(getPolicePlayers()) do
        local text = useDefaultMessage and _Up(policeId, 'police_robbery_alert') or message
        notify(policeId, text .. suffix)
    end
end

local function targetState(targetPlayer)
    local targetPed = GetPlayerPed(targetPlayer)
    if not targetPed or targetPed == 0 then return false, false end

    local dead = (tonumber(GetEntityHealth(targetPed)) or 0) <= 0
    local hogtied = false
    local ok, result = pcall(Citizen.InvokeNative, 0x3AA24CCC0D451379, targetPed)
    if ok then hogtied = result == true end
    return dead, hogtied
end

local function canSearchTarget(sourcePlayer, targetPlayer)
    sourcePlayer, targetPlayer = tonumber(sourcePlayer), tonumber(targetPlayer)
    if not playerActive(sourcePlayer) or not playerActive(targetPlayer) or sourcePlayer == targetPlayer then
        return false
    end

    local sourcePed = GetPlayerPed(sourcePlayer)
    local targetPed = GetPlayerPed(targetPlayer)
    if not sourcePed or sourcePed == 0 or not targetPed or targetPed == 0 then return false end

    local sourceCoords = GetEntityCoords(sourcePed)
    local targetCoords = GetEntityCoords(targetPed)
    local distance = #(sourceCoords - targetCoords)
    if distance > (tonumber(cfg().ServerDistance) or 2.0) then return false end

    local dead, hogtied = targetState(targetPlayer)
    return dead or hogtied
end

local function releaseSearch(sourcePlayer)
    sourcePlayer = tonumber(sourcePlayer)
    local search = sourcePlayer and activeSearches[sourcePlayer]
    if search and targetSearchers[search.target] == sourcePlayer then
        targetSearchers[search.target] = nil
    end
    if sourcePlayer then
        activeSearches[sourcePlayer] = nil
        actionLocks[sourcePlayer] = nil
    end
end

local function getActiveTarget(sourcePlayer)
    sourcePlayer = tonumber(sourcePlayer)
    local search = sourcePlayer and activeSearches[sourcePlayer]
    if not search then return nil end
    if (tonumber(search.expiresAt) or 0) < GetGameTimer() then
        releaseSearch(sourcePlayer)
        TriggerClientEvent('jrs_inventory:robbery:forceClose', sourcePlayer)
        return nil
    end
    if not canSearchTarget(sourcePlayer, search.target) then
        releaseSearch(sourcePlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'target_unavailable'))
        TriggerClientEvent('jrs_inventory:robbery:forceClose', sourcePlayer)
        return nil
    end
    search.expiresAt = GetGameTimer() + math.max(5000, tonumber(cfg().SessionTimeoutMs) or 30000)
    return tonumber(search.target)
end

local function claimOperation(sourcePlayer, operationId)
    sourcePlayer = tonumber(sourcePlayer)
    operationId = tostring(operationId or '')
    if not sourcePlayer or operationId == '' or #operationId > 96 then return false end

    seenOperations[sourcePlayer] = seenOperations[sourcePlayer] or {}
    local now = GetGameTimer()
    local bucket = seenOperations[sourcePlayer]

    for id, expiresAt in pairs(bucket) do
        if expiresAt < now then bucket[id] = nil end
    end
    if bucket[operationId] then return false end
    bucket[operationId] = now + 60000
    return true
end

local function beginAction(sourcePlayer, operationId, clientHour)
    sourcePlayer = tonumber(sourcePlayer)
    if not sourcePlayer or not AllowInventoryRequest(sourcePlayer, 'robbery_action') then return nil end
    local targetPlayer = getActiveTarget(sourcePlayer)
    if not targetPlayer then return nil end

    local allowed, reason, extra = checkRobberyRestrictions(sourcePlayer, targetPlayer)
    if not allowed then
        notifyRestriction(sourcePlayer, reason, extra)
        releaseSearch(sourcePlayer)
        TriggerClientEvent('jrs_inventory:robbery:forceClose', sourcePlayer)
        return nil
    end

    if not claimOperation(sourcePlayer, operationId) then
        notify(sourcePlayer, _Up(sourcePlayer, 'action_busy'))
        return nil
    end

    local now = GetGameTimer()
    local cooldown = math.max(0, tonumber(cfg().ActionCooldownMs) or 300)
    if lastActionAt[sourcePlayer] and now - lastActionAt[sourcePlayer] < cooldown then
        notify(sourcePlayer, _Up(sourcePlayer, 'action_busy'))
        return nil
    end
    lastActionAt[sourcePlayer] = now

    if actionLocks[sourcePlayer] or actionLocks[targetPlayer] then
        notify(sourcePlayer, _Up(sourcePlayer, 'action_busy'))
        return nil
    end

    actionLocks[sourcePlayer] = true
    actionLocks[targetPlayer] = true
    return targetPlayer
end

local function finishAction(sourcePlayer, targetPlayer)
    actionLocks[tonumber(sourcePlayer)] = nil
    actionLocks[tonumber(targetPlayer)] = nil
end

local function getInventory(playerId)
    local ok, inventory = pcall(function()
        return Inventory.getUserInventory(tonumber(playerId))
    end)
    return ok and (inventory or {}) or {}
end

local function findInventoryItem(playerId, itemId)
    itemId = tonumber(itemId)
    for _, entry in pairs(getInventory(playerId)) do
        if tonumber(entry.itemId) == itemId then return entry end
    end
    return nil
end

local function itemTotal(playerId, itemName)
    local total = 0
    for _, entry in pairs(getInventory(playerId)) do
        if tostring(entry.item) == tostring(itemName) then
            total = total + (tonumber(entry.count) or 0)
        end
    end
    return total
end

local function loadItemDefinitions()
    if itemDefinitions then return itemDefinitions end
    itemDefinitions = {}
    local ok, rows = pcall(function() return Inventory.check_itemtable() end)
    for _, row in pairs(ok and (rows or {}) or {}) do
        itemDefinitions[tostring(row.item)] = row
    end
    return itemDefinitions
end

local function itemBlocked(itemName)
    if cfg().BlockPersonalItems ~= true then return false end
    local definition = loadItemDefinitions()[tostring(itemName)]
    if not definition then return false end

    local category = tostring(definition.category or ''):lower()
    if category == 'personal' then return true end
    if definition.personal == true or tonumber(definition.personal) == 1 then return true end
    if definition.can_remove ~= nil and tonumber(definition.can_remove) == 0 then return true end
    return false
end

local function sendSearchLog(category, title, actor, target, details)
    local fields = {
        { name = 'Searched Player', value = (GetPlayerName(target) or 'Unknown') .. ' (`' .. tostring(target) .. '`)', inline = false },
    }
    for _, field in ipairs(details or {}) do fields[#fields + 1] = field end

    pcall(function()
        exports.jrs_inventory:sendInventoryLog(category, title, actor, fields, {
            description = 'Action performed through integrated jrs_inventory robbery mode.'
        })
    end)
end

local function refreshCurrency(playerId)
    TriggerEvent('jrs_inventory:get_money_sec', tonumber(playerId))
end

-- Cash budget per victim. The cap used to be "MoneyStealPercent of the current
-- balance" on every single take, so repeating the take drained 10%, then 10% of
-- the rest, and so on down to nothing. The budget is fixed from the balance
-- at the first take and lasts MoneyStealWindowMinutes, keyed by character so
-- a relog doesn't reset it.
local moneyStealBudgets = {}

local function moneyBudgetKey(Character, targetPlayer)
    return tostring(Character and Character.charIdentifier or ('src:' .. tostring(targetPlayer)))
end

local function robberyMoneyAllowance(targetPlayer, Character)
    local balance = tonumber(Character and Character.money) or 0
    local stealPct = math.max(0.01, math.min(1.0, tonumber(cfg().MoneyStealPercent) or 0.10))
    local key = moneyBudgetKey(Character, targetPlayer)
    local now = os.time()
    local budget = moneyStealBudgets[key]
    local cap, taken
    if budget and budget.resetAt > now then
        cap, taken = budget.cap, budget.taken
    else
        cap, taken = math.floor(balance * stealPct * 100 + 0.5) / 100, 0
    end
    return math.max(0, math.min(balance, cap - taken)), key, cap
end

local function recordRobberyMoneyTaken(key, cap, amount)
    local now = os.time()
    local budget = moneyStealBudgets[key]
    if not budget or budget.resetAt <= now then
        local windowMinutes = math.max(1, tonumber(cfg().MoneyStealWindowMinutes) or 30)
        budget = { cap = cap, taken = 0, resetAt = now + windowMinutes * 60 }
        moneyStealBudgets[key] = budget
    end
    budget.taken = budget.taken + amount
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10 * 60 * 1000)
        local now = os.time()
        for key, budget in pairs(moneyStealBudgets) do
            if budget.resetAt <= now then moneyStealBudgets[key] = nil end
        end
    end
end)

local function loadInventory(sourcePlayer, targetPlayer)
    sourcePlayer, targetPlayer = tonumber(sourcePlayer), tonumber(targetPlayer)
    if not sourcePlayer or not targetPlayer or getActiveTarget(sourcePlayer) ~= targetPlayer then return end

    local Character = getCharacter(targetPlayer)
    if not Character then return end

    local inv = getInventory(targetPlayer)
    local allItems = {}
    local allWeapons = {}
    local okItems, itemRows = pcall(function() return Inventory.check_itemtable() end)
    if okItems then allItems = itemRows or {} end
    local okWeapons, weaponRows = pcall(function() return Inventory.GetWeaponTable() end)
    if okWeapons then allWeapons = weaponRows or {} end

    exports.oxmysql:execute(
        'SELECT id, name, used, slot, serial_number FROM jrs_weaponloadout WHERE identifier=@identifier AND charidentifier=@charid',
        {
            ['identifier'] = Character.identifier,
            ['charid'] = Character.charIdentifier,
        },
        function(result)
            if getActiveTarget(sourcePlayer) ~= targetPlayer then return end
            TriggerClientEvent('jrs_inventory:robbery:search', sourcePlayer, {
                targetId = targetPlayer,
                targetName = GetPlayerName(targetPlayer) or ('Player ' .. tostring(targetPlayer)),
                inventory = inv,
                itemDefinitions = allItems,
                weapons = result or {},
                weaponDefinitions = allWeapons,
                money = math.floor((robberyMoneyAllowance(targetPlayer, Character)) * 100) / 100,
                gold = tonumber(Character.gold) or 0,
                dirtymoney = tonumber(Character.dirtymoney) or 0,
                allowMoney = cfg().AllowMoney == true,
                allowGold = cfg().AllowGold == true,
                allowDirtyMoney = cfg().AllowDirtyMoney == true,
                showWeaponSerial = cfg().ShowWeaponSerial == true,
            })
        end
    )
end

RegisterNetEvent('jrs_inventory:robbery:search')
AddEventHandler('jrs_inventory:robbery:search', function(targetPlayer, clientHour)
    local sourcePlayer = tonumber(source)
    targetPlayer = tonumber(targetPlayer)
    if not sourcePlayer or not AllowInventoryRequest(sourcePlayer, 'robbery_search') then return end
    if not targetPlayer or not canSearchTarget(sourcePlayer, targetPlayer) then
        notify(sourcePlayer, _Up(sourcePlayer, 'target_unavailable'))
        return
    end

    local allowed, reason, extra = checkRobberyRestrictions(sourcePlayer, targetPlayer)
    if not allowed then
        notifyRestriction(sourcePlayer, reason, extra)
        return
    end

    if cfg().LockTargetToOneSearcher == true then
        local currentSearcher = targetSearchers[targetPlayer]
        if currentSearcher and currentSearcher ~= sourcePlayer and getActiveTarget(currentSearcher) == targetPlayer then
            notify(sourcePlayer, _Up(sourcePlayer, 'search_busy'))
            return
        end
    end

    releaseSearch(sourcePlayer)
    activeSearches[sourcePlayer] = {
        target = targetPlayer,
        expiresAt = GetGameTimer() + math.max(5000, tonumber(cfg().SessionTimeoutMs) or 30000),
    }
    targetSearchers[targetPlayer] = sourcePlayer
    alertPolice(sourcePlayer, targetPlayer)
    loadInventory(sourcePlayer, targetPlayer)
end)

RegisterNetEvent('jrs_inventory:robbery:closeSearch')
AddEventHandler('jrs_inventory:robbery:closeSearch', function()
    releaseSearch(source)
end)

RegisterNetEvent('jrs_inventory:robbery:refresh')
AddEventHandler('jrs_inventory:robbery:refresh', function()
    local sourcePlayer = tonumber(source)
    if not sourcePlayer or not AllowInventoryRequest(sourcePlayer, 'robbery_refresh') then return end
    local targetPlayer = getActiveTarget(sourcePlayer)
    if targetPlayer then loadInventory(sourcePlayer, targetPlayer) end
end)

RegisterNetEvent('jrs_inventory:robbery:takeItem')
AddEventHandler('jrs_inventory:robbery:takeItem', function(itemId, count, operationId, clientHour)
    local sourcePlayer = tonumber(source)
    itemId = tonumber(itemId)
    count = positiveInteger(count)
    if not sourcePlayer or not itemId or not count or cfg().AllowItems ~= true then return end

    local targetPlayer = beginAction(sourcePlayer, operationId, clientHour)
    if not targetPlayer then
        local activeTarget = getActiveTarget(sourcePlayer)
        if activeTarget then Citizen.SetTimeout(100, function() loadInventory(sourcePlayer, activeTarget) end) end
        return
    end

    local entry = findInventoryItem(targetPlayer, itemId)
    if not entry or (tonumber(entry.count) or 0) < count then
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'target_doesnt_have'))
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    local itemName = tostring(entry.item or '')
    if itemName == '' or itemBlocked(itemName) then
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'robbery_personal_item_locked'))
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    local canCarryOk, canCarry = pcall(function()
        return Inventory.canCarryItem(sourcePlayer, itemName, count)
    end)
    if not canCarryOk or canCarry ~= true then
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'cannot_carry'))
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    -- Snapshot both sides. The inventory API updates its authoritative cache
    -- synchronously; this lets us verify each step and restore the target if
    -- the receiving step fails.
    local targetBefore = tonumber(entry.count) or 0
    local targetTotalBefore = itemTotal(targetPlayer, itemName)
    local receiverBefore = itemTotal(sourcePlayer, itemName)
    local metadata = entry.metaData or {}

    pcall(function() Inventory.subItemByID(targetPlayer, itemId, count) end)
    local targetAfterEntry = findInventoryItem(targetPlayer, itemId)
    local targetAfter = targetAfterEntry and (tonumber(targetAfterEntry.count) or 0) or 0
    if targetAfter ~= (targetBefore - count) then
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'robbery_transfer_failed'))
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    pcall(function() Inventory.addItem(sourcePlayer, itemName, count, metadata) end)
    local receiverAfter = itemTotal(sourcePlayer, itemName)
    if receiverAfter < receiverBefore + count then
        -- Roll back the exact item metadata to the searched player.
        pcall(function() Inventory.addItem(targetPlayer, itemName, count, metadata) end)
        local rollbackTotal = itemTotal(targetPlayer, itemName)
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'robbery_transfer_failed'))
        sendSearchLog('Security', rollbackTotal >= targetTotalBefore and 'Search Item Transfer Rolled Back' or 'Search Item Rollback Failed', sourcePlayer, targetPlayer, {
            { name = 'Item', value = itemName, inline = true },
            { name = 'Amount', value = tostring(count), inline = true },
            { name = 'Rollback Restored', value = rollbackTotal >= targetTotalBefore and 'yes' or 'NO', inline = true },
        })
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    finishAction(sourcePlayer, targetPlayer)
    local label = (loadItemDefinitions()[itemName] and loadItemDefinitions()[itemName].label) or itemName
    sendSearchLog('Items', 'Item Taken During Search', sourcePlayer, targetPlayer, {
        { name = 'Item', value = tostring(label) .. ' (`' .. itemName .. '`)', inline = true },
        { name = 'Item ID', value = tostring(itemId), inline = true },
        { name = 'Amount', value = tostring(count), inline = true },
    })
    loadInventory(sourcePlayer, targetPlayer)
end)

local function completeWeaponTransfer(sourcePlayer, targetPlayer, weaponId, weaponRow, operationId)
    local serial = tostring(weaponRow.serial_number or '')
    pcall(function() Inventory.giveWeapon(targetPlayer, weaponId, sourcePlayer) end)

    Citizen.SetTimeout(450, function()
        exports.oxmysql:execute(
            'SELECT identifier, charidentifier, name, serial_number FROM jrs_weaponloadout WHERE id=@id LIMIT 1',
            { ['id'] = weaponId },
            function(rows)
                local row = rows and rows[1]
                local recipientCharacter = getCharacter(sourcePlayer)
                local success = row and recipientCharacter
                    and row.identifier == recipientCharacter.identifier
                    and tonumber(row.charidentifier) == tonumber(recipientCharacter.charIdentifier)

                finishAction(sourcePlayer, targetPlayer)
                if success then
                    sendSearchLog('Weapons', 'Weapon Taken During Search', sourcePlayer, targetPlayer, {
                        { name = 'Weapon', value = tostring(row.name or weaponRow.name), inline = true },
                        { name = 'Weapon ID', value = tostring(weaponId), inline = true },
                        { name = 'Serial', value = tostring(row.serial_number or serial), inline = true },
                        { name = 'Operation', value = tostring(operationId or ''), inline = false },
                    })
                else
                    notify(sourcePlayer, _Up(sourcePlayer, 'robbery_transfer_failed'))
                end
                if getActiveTarget(sourcePlayer) == targetPlayer then
                    loadInventory(sourcePlayer, targetPlayer)
                end
            end
        )
    end)
end

RegisterNetEvent('jrs_inventory:robbery:takeWeapon')
AddEventHandler('jrs_inventory:robbery:takeWeapon', function(weaponId, operationId, clientHour)
    local sourcePlayer = tonumber(source)
    weaponId = tonumber(weaponId)
    if not sourcePlayer or not weaponId or cfg().AllowWeapons ~= true then return end

    local targetPlayer = beginAction(sourcePlayer, operationId, clientHour)
    if not targetPlayer then
        local activeTarget = getActiveTarget(sourcePlayer)
        if activeTarget then Citizen.SetTimeout(100, function() loadInventory(sourcePlayer, activeTarget) end) end
        return
    end
    local targetCharacter = getCharacter(targetPlayer)
    if not targetCharacter then
        finishAction(sourcePlayer, targetPlayer)
        return
    end

    exports.oxmysql:execute(
        'SELECT id, name, used, serial_number FROM jrs_weaponloadout WHERE id=@id AND identifier=@identifier AND charidentifier=@charid LIMIT 1',
        {
            ['id'] = weaponId,
            ['identifier'] = targetCharacter.identifier,
            ['charid'] = targetCharacter.charIdentifier,
        },
        function(rows)
            local row = rows and rows[1]
            if not row or getActiveTarget(sourcePlayer) ~= targetPlayer then
                finishAction(sourcePlayer, targetPlayer)
                notify(sourcePlayer, _Up(sourcePlayer, 'target_unavailable'))
                return
            end

            if tonumber(row.used) == 1 then
                local dead = select(1, targetState(targetPlayer))
                if not dead then
                    finishAction(sourcePlayer, targetPlayer)
                    notify(sourcePlayer, _Up(sourcePlayer, 'weapon_equipped'))
                    loadInventory(sourcePlayer, targetPlayer)
                    return
                end

                -- Dead players cannot manually put an equipped weapon away.
                -- Clear only the equipped state; ownership/serial transfer still
                -- goes through jrs_inventory's protected transfer routine.
                exports.oxmysql:execute(
                    'UPDATE jrs_weaponloadout SET used=0 WHERE id=@id AND identifier=@identifier AND charidentifier=@charid AND used=1',
                    {
                        ['id'] = weaponId,
                        ['identifier'] = targetCharacter.identifier,
                        ['charid'] = targetCharacter.charIdentifier,
                    },
                    function()
                        TriggerClientEvent('jrs_inventory:remove_wepo', targetPlayer, row.name)
                        completeWeaponTransfer(sourcePlayer, targetPlayer, weaponId, row, operationId)
                    end
                )
                return
            end

            completeWeaponTransfer(sourcePlayer, targetPlayer, weaponId, row, operationId)
        end
    )
end)

local function takeCurrency(sourcePlayer, currencyType, count, operationId, clientHour)
    count = positiveCurrencyAmount(count)
    if not count then
        notify(sourcePlayer, _Up(sourcePlayer, 'invalid_amount'))
        return
    end

    if currencyType == 0 and cfg().AllowMoney ~= true then return end
    if currencyType == 1 and cfg().AllowGold ~= true then return end
    if currencyType == 3 and cfg().AllowDirtyMoney ~= true then return end

    local targetPlayer = beginAction(sourcePlayer, operationId, clientHour)
    if not targetPlayer then
        local activeTarget = getActiveTarget(sourcePlayer)
        if activeTarget then Citizen.SetTimeout(100, function() loadInventory(sourcePlayer, activeTarget) end) end
        return
    end

    local targetCharacter = getCharacter(targetPlayer)
    local sourceCharacter = getCharacter(sourcePlayer)
    if not targetCharacter or not sourceCharacter then
        finishAction(sourcePlayer, targetPlayer)
        return
    end

    local moneyBudgetKeyUsed, moneyBudgetCap
    local balanceKey = currencyType == 0 and 'money' or (currencyType == 1 and 'gold' or 'dirtymoney')
    local targetBalance = tonumber(targetCharacter[balanceKey]) or 0
    if currencyType == 0 then
        local maxAllowed
        maxAllowed, moneyBudgetKeyUsed, moneyBudgetCap = robberyMoneyAllowance(targetPlayer, targetCharacter)
        maxAllowed = math.floor(maxAllowed * 100) / 100
        if count > maxAllowed then count = maxAllowed end
        if count <= 0 then
            finishAction(sourcePlayer, targetPlayer)
            notify(sourcePlayer, _Up(sourcePlayer, 'target_doesnt_have'))
            loadInventory(sourcePlayer, targetPlayer)
            return
        end
    end
    if targetBalance < count then
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'target_doesnt_have'))
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    local removeOk, removed = pcall(function()
        return jrsCore.removeMoney(targetPlayer, currencyType, count)
    end)
    if not removeOk or removed ~= true then
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'robbery_transfer_failed'))
        loadInventory(sourcePlayer, targetPlayer)
        return
    end

    local addOk, added = pcall(function()
        return jrsCore.addMoney(sourcePlayer, currencyType, count)
    end)
    if not addOk or added ~= true then
        local rollbackOk, rollback = pcall(function()
            return jrsCore.addMoney(targetPlayer, currencyType, count)
        end)
        finishAction(sourcePlayer, targetPlayer)
        notify(sourcePlayer, _Up(sourcePlayer, 'robbery_transfer_failed'))
        if not rollbackOk or rollback ~= true then
            sendSearchLog('Security', 'Currency Search Rollback Failed', sourcePlayer, targetPlayer, {
                { name = 'Currency Type', value = tostring(currencyType), inline = true },
                { name = 'Amount', value = tostring(count), inline = true },
            })
        end
        if getActiveTarget(sourcePlayer) == targetPlayer then loadInventory(sourcePlayer, targetPlayer) end
        return
    end

    if moneyBudgetKeyUsed then recordRobberyMoneyTaken(moneyBudgetKeyUsed, moneyBudgetCap, count) end
    refreshCurrency(targetPlayer)
    refreshCurrency(sourcePlayer)
    finishAction(sourcePlayer, targetPlayer)

    local currencyName = currencyType == 0 and 'Money' or (currencyType == 1 and 'Gold' or 'Dirty Money')
    sendSearchLog('Currency', currencyName .. ' Taken During Search', sourcePlayer, targetPlayer, {
        { name = 'Currency', value = currencyName, inline = true },
        { name = 'Amount', value = tostring(count), inline = true },
    })
    loadInventory(sourcePlayer, targetPlayer)
end

RegisterNetEvent('jrs_inventory:robbery:takeMoney')
AddEventHandler('jrs_inventory:robbery:takeMoney', function(count, operationId, clientHour)
    takeCurrency(tonumber(source), 0, count, operationId, clientHour)
end)

RegisterNetEvent('jrs_inventory:robbery:takeGold')
AddEventHandler('jrs_inventory:robbery:takeGold', function(count, operationId, clientHour)
    takeCurrency(tonumber(source), 1, count, operationId, clientHour)
end)

RegisterNetEvent('jrs_inventory:robbery:takeDirtyMoney')
AddEventHandler('jrs_inventory:robbery:takeDirtyMoney', function(count, operationId, clientHour)
    takeCurrency(tonumber(source), 3, count, operationId, clientHour)
end)

-- Close the dual inventory immediately if the searched player is no longer
-- dead/hogtied, moves too far away, disconnects, or the session expires.
Citizen.CreateThread(function()
    while true do
        if next(activeSearches) == nil then
            Citizen.Wait(5000)
        else
            Citizen.Wait(1000)
            local searchers = {}
            for sourcePlayer in pairs(activeSearches) do
                searchers[#searchers + 1] = tonumber(sourcePlayer)
            end
            for _, sourcePlayer in ipairs(searchers) do
                if sourcePlayer then getActiveTarget(sourcePlayer) end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local playerId = tonumber(source)
    releaseSearch(playerId)
    seenOperations[playerId] = nil
    lastActionAt[playerId] = nil
    lastPoliceAlertAt[playerId] = nil

    local searchingPlayer = targetSearchers[playerId]
    if searchingPlayer then
        TriggerClientEvent('jrs_inventory:robbery:forceClose', tonumber(searchingPlayer))
        releaseSearch(searchingPlayer)
    end
    targetSearchers[playerId] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    activeSearches = {}
    targetSearchers = {}
    actionLocks = {}
end)

debugPrint('Integrated secure player robbery server loaded.')
