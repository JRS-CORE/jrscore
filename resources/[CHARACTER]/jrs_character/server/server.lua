-- JRS Character server runtime
-- Consolidated character lifecycle, database, callback, creator, barber, and aging logic.
-- Each former module is isolated in a do/end block so local variables keep their original scope.

-- Lightweight server-side abuse protection. NUI/client state is never trusted as
-- an authorization boundary; sensitive character operations are revalidated here.
local jrsSecurityBuckets = {}
local jrsCreatorEditSessions = {}
local jrsAdminSelectorSessions = {}
local jrsAdminSelectorCounter = 0

local function JRSCreateAdminSelectorSession(playerSource, durationMs)
    local src = tonumber(playerSource)
    if not src or not GetPlayerName(src) then return nil end

    jrsAdminSelectorCounter = (jrsAdminSelectorCounter + 1) % 2147483647
    local token = ('jrs:%s:%s:%s:%08x:%08x:%08x'):format(
        tostring(src),
        tostring(GetGameTimer()),
        tostring(jrsAdminSelectorCounter),
        math.random(0, 0x7fffffff),
        math.random(0, 0x7fffffff),
        math.random(0, 0x7fffffff)
    )
    local lifetime = math.max(5000, math.min(60000, math.floor(tonumber(durationMs) or 30000)))
    jrsAdminSelectorSessions[src] = { token = token, expires = GetGameTimer() + lifetime }
    return token
end

local function JRSConsumeAdminSelectorSession(playerSource, token)
    local src = tonumber(playerSource)
    local session = src and jrsAdminSelectorSessions[src] or nil
    if not session then return false end
    if GetGameTimer() > tonumber(session.expires or 0) then
        jrsAdminSelectorSessions[src] = nil
        return false
    end
    if type(token) ~= 'string' or token ~= session.token then return false end
    jrsAdminSelectorSessions[src] = nil
    return true
end

local function JRSOpenCreatorEditSession(playerSource, durationMs)
    local src = tonumber(playerSource)
    if not src or not GetPlayerName(src) then return false end
    jrsCreatorEditSessions[src] = GetGameTimer() + math.max(30000, math.floor(tonumber(durationMs) or 600000))
    return true
end

local function JRSHasCreatorEditSession(playerSource)
    local src = tonumber(playerSource)
    local expires = src and jrsCreatorEditSessions[src] or nil
    if not expires then return false end
    if GetGameTimer() > expires then
        jrsCreatorEditSessions[src] = nil
        return false
    end
    return true
end

local function JRSCloseCreatorEditSession(playerSource)
    jrsCreatorEditSessions[tonumber(playerSource)] = nil
end

local function JRSAllowRequest(playerSource, key, limit, windowMs)
    local src = tonumber(playerSource)
    if not src or not GetPlayerName(src) then return false end

    key = tostring(key or 'default')
    limit = math.max(1, math.floor(tonumber(limit) or 10))
    windowMs = math.max(250, math.floor(tonumber(windowMs) or 5000))

    local now = GetGameTimer()
    local playerBuckets = jrsSecurityBuckets[src]
    if not playerBuckets then
        playerBuckets = {}
        jrsSecurityBuckets[src] = playerBuckets
    end

    local bucket = playerBuckets[key]
    if not bucket or now - bucket.started >= windowMs then
        playerBuckets[key] = { started = now, count = 1 }
        return true
    end

    if bucket.count >= limit then
        return false
    end

    bucket.count = bucket.count + 1
    return true
end

local function JRSStripInvalidUtf8(textValue)
    local parts, pos = {}, 1
    while pos <= #textValue do
        local _, badPos = utf8.len(textValue, pos)
        if not badPos then
            parts[#parts + 1] = textValue:sub(pos)
            break
        end
        parts[#parts + 1] = textValue:sub(pos, badPos - 1)
        pos = badPos + 1
    end
    return table.concat(parts)
end

local function JRSCleanText(value, maxLength)
    local textValue = tostring(value or '')
    textValue = textValue:gsub('%c', '')
    textValue = textValue:gsub('^%s+', ''):gsub('%s+$', '')
    -- Limit by characters, not bytes: a byte cut splits Arabic letters into
    -- invalid UTF-8, which a strict utf8mb4 column rejects and aborts the save.
    textValue = JRSStripInvalidUtf8(textValue)
    local limit = math.max(1, math.floor(tonumber(maxLength) or 128))
    if (utf8.len(textValue) or 0) > limit then
        textValue = textValue:sub(1, utf8.offset(textValue, limit + 1) - 1)
    end
    return textValue
end

local function JRSJsonWithinLimit(value, maxBytes)
    if type(value) ~= 'table' then return false end
    local ok, encoded = pcall(json.encode, value)
    if not ok or type(encoded) ~= 'string' then return false end
    return #encoded <= math.max(1024, math.floor(tonumber(maxBytes) or 262144))
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    jrsSecurityBuckets[src] = nil
    jrsCreatorEditSessions[src] = nil
    jrsAdminSelectorSessions[src] = nil
end)

-- ============================================================================
-- Module: callbacks
-- ============================================================================
do
local currentRequestId = 0
local responseCallback = {}
local responseSource = {}
local registeredCallback = {}

local server = IsDuplicityVersion()

Callback = {}

local function executeCallback(name, ...)
  if not registeredCallback[name] then return printconsole(('No callback for: %s'):format(name)) end
  return registeredCallback[name].cb(...)
end

local function executeResponse(requestId, fromRessource, ...)
  local callback = responseCallback[requestId]
  if not callback then return end
  if server and tonumber(source) ~= responseSource[requestId] then return end
  responseCallback[requestId] = nil
  responseSource[requestId] = nil
  callback(...)
end


---@param name string the name of the event
---@param cb function
function Callback.register(name, cb)
  if registeredCallback[name] then return printconsole('Callback already registered:', name) end
  registeredCallback[name] = {
    cb = cb,
    resource = GetInvokingResource()
  }
end



if server then

  ---@param name string Name of the callback event
  ---@param cb function return of the event
  ---@param ...? any
  function Callback.triggerClient(name, source, cb, ...)
    if not GetPlayerIdentifier(source) then
      return printconsole('Callback Module: Player is not connected - source: ' .. source)
    end
    if type(cb) ~= 'function' then return end
    responseCallback[currentRequestId] = cb
    responseSource[currentRequestId] = tonumber(source)
    local ticket, pending = currentRequestId, cb
    SetTimeout(30000, function()
      if responseCallback[ticket] == pending then
        responseCallback[ticket] = nil
        responseSource[ticket] = nil
      end
    end)

    TriggerClientEvent('jrs_character_creator:triggerCallback', source, name, currentRequestId, GetInvokingResource() or "unknown", ...)

    currentRequestId = currentRequestId < 65535 and currentRequestId + 1 or 0
  end

  function Callback.triggerServer(name, cb, ...)
    if not registeredCallback[name] then return printconsole('No server callback for:', name) end

    if cb then
      cb(executeCallback(name, ...))
    else
      return executeCallback(name, ...)
    end
  end

  RegisterServerEvent('jrs_character_creator:responseCallback', executeResponse)
  AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    for ticket, target in pairs(responseSource) do
      if target == src then
        responseCallback[ticket] = nil
        responseSource[ticket] = nil
      end
    end
  end)

  local clientCallableCallbacks = {
    ['jrs_character_creator:GetCurrentClothes'] = true,
    ['jrs_character_creator:SaveCreatorClothes'] = true,
    ['jrs_character_creator:GetPedData'] = true,
    ['jrs_character_creator:GetCurrentHairs'] = true,
    ['jrs_character_creator:GetCurrentHairsOnCharacter'] = true,
    ['jrs_character_creator:CreateNewCharacter'] = true,
    ['jrs_character_creator:SavePreset'] = true,
    ['jrs_character_creator:UpdatePedData'] = true,
    ['jrs_character_creator:SaveAppearance'] = true,
    ['jrs_character_creator:GetCurrentOverlays'] = true,
    ['jrs_barber:GetCurrentOverlays'] = true,
    ['jrs_character_creator:GetCharSkinTone'] = true,
  }

  RegisterServerEvent('jrs_character_creator:triggerCallback', function(name, requestId, fromRessource, ...)
    local src = tonumber(source)
    name = tostring(name or '')
    requestId = math.floor(tonumber(requestId) or -1)

    if not src or requestId < 0 or requestId > 65535 then return end
    -- Always answer a well-formed request: a silent drop left the client's
    -- callback pending forever (creator/selector waiting on nothing).
    local function reject(reason)
      TriggerClientEvent('jrs_character_creator:responseCallback', src, requestId,
        tostring(fromRessource or 'unknown'):sub(1, 64), false, reason)
    end
    if clientCallableCallbacks[name] ~= true or not registeredCallback[name] then return reject('unknown_callback') end
    if not JRSAllowRequest(src, 'callback:' .. name, 40, 10000) then return reject('rate_limited') end

    local result = table.pack(pcall(executeCallback, name, src, ...))
    if not result[1] then
      printconsole('Character callback failed:', name, tostring(result[2]))
      TriggerClientEvent('jrs_character_creator:responseCallback', src, requestId,
        tostring(fromRessource or 'unknown'):sub(1, 64), false, 'server_error')
      return
    end
    TriggerClientEvent('jrs_character_creator:responseCallback', src, requestId,
      tostring(fromRessource or 'unknown'):sub(1, 64), table.unpack(result, 2, result.n))
  end)

else

  function Callback.clearPending()
    responseCallback = {}
    currentRequestId = 0
  end

  RegisterNetEvent('jrs_character_creator:clearPendingCallbacks', Callback.clearPending)

  -- Do not clear pending server callbacks when NUI focus changes.
  -- Character creation intentionally removes NUI focus before the server
  -- finishes creating/selecting the character. Clearing callbacks here caused
  -- the response to be lost and left the player on a permanent black screen.
  -- Pending callbacks are still cleared explicitly when the resource stops or
  -- when a new selector lifecycle starts.

  ---@param name string Name of the callback event
  ---@param cb function return of the event
  ---@param ...? any
  function Callback.triggerServer(name, cb, ...)
    responseCallback[currentRequestId] = cb

    TriggerServerEvent('jrs_character_creator:triggerCallback', name, currentRequestId, GetInvokingResource() or 'unknown', ...)

    currentRequestId = currentRequestId < 65535 and currentRequestId + 1 or 0
  end


  function Callback.triggerClient(name, cb, ...)
    if not registeredCallback[name] then return printconsole('No client callback for:', name) end
    if cb then
      cb(executeCallback(name, ...))
    else
      return executeCallback(name, ...)
    end
  end

  RegisterNetEvent('jrs_character_creator:responseCallback', executeResponse)

  RegisterNetEvent('jrs_character_creator:triggerCallback', function(name, requestId, fromRessource, ...)
    TriggerServerEvent('jrs_character_creator:responseCallback', requestId, fromRessource, executeCallback(name, ...))
  end)


end

function printconsole(...)
  -- A vararg in the middle of an argument list is truncated to its first
  -- value, so `print(a, ..., "^0")` silently dropped every real error message
  -- ("CreateNewCharacter error:" logged with nothing after it).
  local args = table.pack(...)
  args.n = args.n + 1
  args[args.n] = "^0"
  if IsDuplicityVersion() then
    return print("^1" .. GetCurrentResourceName() .. ":", table.unpack(args, 1, args.n))
  end
  return print("^1", table.unpack(args, 1, args.n))
end

AddEventHandler('onResourceStop', function(resource)
  for name, callback in pairs(registeredCallback) do
    if callback.resource == resource then
      registeredCallback[name] = nil
    end
  end
end)
end

-- ============================================================================
-- Module: runtime.lua
-- ============================================================================
do
-- JRS character gameplay runtime.
-- Character listing, creation, selection and deletion are handled by the consolidated JRS integration module below.

jrsCore = exports.jrs_core:getCoreApi()

-- Resolved lazily: calling the export at load time threw "No such export
-- jrs_inventoryApi" whenever jrs_inventory was still starting/restarting,
-- and that error aborted the rest of this module (dead_state and every
-- handler below it never registered).
local function resolveInventoryApi()
    if GetResourceState('jrs_inventory') ~= 'started' then return nil end
    local ok, api = pcall(function() return exports.jrs_inventory:jrs_inventoryApi() end)
    if ok and type(api) == 'table' then return api end
    return nil
end
Inventory = resolveInventoryApi()


local function getReadyCharacter(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource then return nil end

    if type(jrsCore.isCharacterReady) == 'function' and not jrsCore.isCharacterReady(playerSource) then
        return nil
    end

    if type(jrsCore.getCharacter) == 'function' then
        return jrsCore.getCharacter(playerSource)
    end

    local user = type(jrsCore.getUser) == 'function' and jrsCore.getUser(playerSource) or nil
    return user and user.getUsedCharacter or nil
end

RegisterNetEvent('jrs_character:closeLoadingScreen', function()
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'close_loading', 4, 5000) then return end
    if type(jrsCore.isCharacterReady) == 'function' and not jrsCore.isCharacterReady(src) then return end
    TriggerClientEvent('jrs_character:closeLoadingScreen', src)
end)

-- Compatibility aliases now route to the new selector only.
RegisterNetEvent('jrs_character:check_character', function()
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'check_character', 5, 5000) then return end
    if type(jrsCore.isCharacterReady) == 'function' and jrsCore.isCharacterReady(src) then return end
    TriggerClientEvent('jrs_character_creator:OpenCharSelect', src)
end)

RegisterNetEvent('jrs_character:check_character2', function()
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'check_character', 5, 5000) then return end
    if type(jrsCore.isCharacterReady) == 'function' and jrsCore.isCharacterReady(src) then return end
    TriggerClientEvent('jrs_character_creator:OpenCharSelect', src)
end)

RegisterNetEvent('jrs_character:unload_character', function(reason, coords, adminToken)
    local src = tonumber(source)
    if not src or type(jrsCore.ClearCharacter) ~= 'function' then return end
    if not JRSAllowRequest(src, 'unload_character', 3, 10000) then return end

    -- Active-character unloads are admin authorized only.
    if tostring(reason or '') ~= 'admin_character_switch' or not JRSConsumeAdminSelectorSession(src, adminToken) then
        return
    end

    pcall(function() exports.jrs_core:SaveCharacter(src) end)
    TriggerEvent('jrs_inventory:server:prepareCharacterSwitch', src)
    TriggerEvent('jrs_character:agingStopSession', src)

    if type(coords) == 'table' and type(jrsCore.SaveCharacterCoords) == 'function' then
        local x = tonumber(coords.x or coords[1])
        local y = tonumber(coords.y or coords[2])
        local z = tonumber(coords.z or coords[3])
        local h = tonumber(coords.heading or coords.h or coords.w or coords[4]) or 0.0
        if x and y and z and math.abs(x) <= 20000 and math.abs(y) <= 20000 and math.abs(z) <= 5000 then
            jrsCore.SaveCharacterCoords(src, { x = x, y = y, z = z, heading = h })
        end
    end

    if jrsCore.ClearCharacter(src, 'admin_character_switch') == true then
        TriggerClientEvent('jrs_character:adminSelectorAuthorized', src)
    end
end)

local function registerHairPomade()
    Inventory = resolveInventoryApi() or Inventory
    if not Inventory or type(Inventory.RegisterUsableItem) ~= 'function' then return false end
    local ok = pcall(Inventory.RegisterUsableItem, 'Hair_Pomade', function(data)
        Inventory.subItem(data.source, 'Hair_Pomade', 1)
        Inventory.CloseInv(data.source)
        TriggerClientEvent('jrs_character:hairPomade', data.source)
    end)
    return ok
end

CreateThread(function()
    local deadline = GetGameTimer() + 120000
    while not registerHairPomade() and GetGameTimer() < deadline do
        Wait(1000)
    end
end)

-- A jrs_inventory restart drops every usable-item registration.
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= 'jrs_inventory' then return end
    CreateThread(function()
        for _ = 1, 30 do
            Wait(1000)
            if registerHairPomade() then return end
        end
    end)
end)


RegisterNetEvent('jrs_character:dead_state', function(state)
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'dead_state', 10, 5000) then return end
    local character = getReadyCharacter(src)
    if not character then return end

    local wantsDead = state == true or tonumber(state) == 1
    if not wantsDead then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityHealth(ped) <= 0 then
            return
        end
    end

    exports.oxmysql:execute(
        'UPDATE jrs_characters SET isdead = @isdead WHERE identifier = @identifier AND charidentifier = @charidentifier',
        {
            identifier = character.identifier,
            charidentifier = character.charIdentifier,
            isdead = wantsDead and 1 or 0
        }
    )
end)

local function JRSApplySavedCharacterScale(src)
    src = tonumber(src)
    if not src then return false end

    local character = getReadyCharacter(src)
    if not character then return false end

    if GetResourceState('jrs_admin') == 'started' then
        local ok, managed = pcall(function()
            return exports.jrs_admin:ApplySavedPlayerScale(src)
        end)
        if ok and managed == true then return true end
    end

    for _, entry in ipairs(Config.SteamIds or {}) do
        if entry.OwnerID == character.identifier and entry.OwnerCharId == character.charIdentifier then
            TriggerClientEvent('jrs_character:open_manage', src, entry.height)
            return true
        end
    end

    TriggerClientEvent('jrs_character:open_managestop', src)
    return true
end

RegisterNetEvent('jrs_character:AdminCheck', function()
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'admin_check', 10, 5000) then return end
    JRSApplySavedCharacterScale(src)
end)

-- Dedicated refresh used after ped recreation/revive. It has its own limiter so the
-- older periodic AdminCheck loop cannot prevent an authoritative height refresh.
RegisterNetEvent('jrs_character:RequestSavedScale', function()
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'saved_scale_refresh', 10, 5000) then return end
    JRSApplySavedCharacterScale(src)
end)
end

-- ============================================================================
-- Module: database/runtime.lua
-- ============================================================================
do
-- JRS character creator routing bucket and database bootstrap.

local function normalizeBarberOutfitId(value)
    local numeric = tonumber(value)
    if not numeric or numeric <= 0 then return nil end
    numeric = math.floor(numeric)
    if numeric <= 0 then return nil end
    return numeric
end

function GenerateJRSBarberOutfitId()
    for _ = 1, 100 do
        local candidate = math.random(10000, 99999999)
        local exists = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM jrs_barber_preset WHERE outfit_id = ?',
            { tostring(candidate) }
        )) or 0
        if exists == 0 then
            return candidate
        end
    end

    -- Extremely unlikely fallback. Keep it numeric because jrs_barber converts
    -- outfit IDs with tonumber() before using them in later queries.
    local fallback = tonumber(os.time()) or 1
    while (tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM jrs_barber_preset WHERE outfit_id = ?',
        { tostring(fallback) }
    )) or 0) > 0 do
        fallback = fallback + 1
    end
    return fallback
end

function ResolveJRSBarberOutfitId(charid, requestedOutfitId, presetName)
    local requested = normalizeBarberOutfitId(requestedOutfitId)
    if requested and tonumber(charid) then
        local owner = MySQL.scalar.await('SELECT charid FROM jrs_barber_preset WHERE outfit_id = ? LIMIT 1', { tostring(requested) })
        if tonumber(owner) == tonumber(charid) then return requested end
    end

    charid = tonumber(charid)
    if charid then
        local existing = MySQL.single.await([[
            SELECT outfit_id
            FROM jrs_barber_preset
            WHERE charid = ? AND name = ?
            ORDER BY id ASC
            LIMIT 1
        ]], { charid, tostring(presetName or 'Base') })
        local existingId = existing and normalizeBarberOutfitId(existing.outfit_id) or nil
        if existingId then return existingId end
    end

    return GenerateJRSBarberOutfitId()
end

local function repairLegacyBarberOutfitIds()
    local ok, rows = pcall(function()
        return {
            presets = MySQL.query.await('SELECT id, charid, outfit_id FROM jrs_barber_preset') or {},
            current = MySQL.query.await('SELECT charid, outfit_id FROM jrs_barber') or {}
        }
    end)
    if not ok or type(rows) ~= 'table' then
        return
    end

    local presets = rows.presets or {}
    local currentRows = rows.current or {}
    local currentByChar = {}
    for _, row in ipairs(currentRows) do
        currentByChar[tonumber(row.charid)] = row.outfit_id
    end

    local repaired = 0
    local repairedCurrent = {}
    for _, row in ipairs(presets) do
        local oldOutfitId = row.outfit_id
        if not normalizeBarberOutfitId(oldOutfitId) then
            local newOutfitId = GenerateJRSBarberOutfitId()
            MySQL.update.await(
                'UPDATE jrs_barber_preset SET outfit_id = ? WHERE id = ?',
                { tostring(newOutfitId), tonumber(row.id) }
            )

            local charid = tonumber(row.charid)
            local currentOutfitId = charid and currentByChar[charid] or nil
            if charid and not repairedCurrent[charid]
                and tostring(currentOutfitId or '') == tostring(oldOutfitId or '') then
                MySQL.update.await(
                    'UPDATE jrs_barber SET outfit_id = ? WHERE charid = ?',
                    { tostring(newOutfitId), charid }
                )
                currentByChar[charid] = tostring(newOutfitId)
                repairedCurrent[charid] = true
            end

            repaired = repaired + 1
        end
    end

    if repaired > 0 then
-- REMOVED-PRINT:         print(('[jrs_character] Repaired %s legacy barber outfit ID(s).'):format(repaired))
    end
end


CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `jrs_character_creator` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `charid` INT NOT NULL,
            `peddata` LONGTEXT NOT NULL,
            `informations` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `jrs_character_creator_charid_unique` (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Older development builds created the table without a unique key. Keep the
    -- newest row per character and add the key so all saves can use UPSERT safely.
    local uniqueIndex = tonumber(MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.statistics
        WHERE table_schema = DATABASE()
          AND table_name = 'jrs_character_creator'
          AND index_name = 'jrs_character_creator_charid_unique'
    ]])) or 0

    if uniqueIndex == 0 then
        MySQL.query.await([[
            DELETE old_row
            FROM jrs_character_creator old_row
            INNER JOIN jrs_character_creator newest_row
                ON newest_row.charid = old_row.charid
               AND newest_row.id > old_row.id
        ]])

        local ok, err = pcall(function()
            MySQL.query.await([[
                ALTER TABLE `jrs_character_creator`
                ADD UNIQUE KEY `jrs_character_creator_charid_unique` (`charid`)
            ]])
        end)
        if not ok then
            print(('[jrs_character] Failed to add creator character key: %s'):format(tostring(err)))
        end
    end

    repairLegacyBarberOutfitIds()
    CreatorDebug('[jrs_character] Creator database table verified.')
end)

function PutPlayerinInstance(playerSource)
    playerSource = tonumber(playerSource)
    if playerSource then
        SetPlayerRoutingBucket(playerSource, 60000 + playerSource)
    end
end

function RemovePlayerFromInstance(playerSource)
    playerSource = tonumber(playerSource)
    if playerSource then
        SetPlayerRoutingBucket(playerSource, 0)
    end
end

RegisterNetEvent('jrs_character_creator:RemovePlayerFromInstance', function()
    local src = tonumber(source)
    if not JRSAllowRequest(src, 'remove_instance', 4, 5000) then return end
    -- Only leave the creator's own bucket. This client event has no caller in
    -- the current creator and forced bucket 0 unconditionally, so a client
    -- could use it to break out of any instance another resource set.
    if tonumber(GetPlayerRoutingBucket(src)) ~= 60000 + src then return end
    RemovePlayerFromInstance(src)
end)
end

-- ============================================================================
-- Module: runtime/callbacks.lua
-- ============================================================================
do
-- JRS character creator server callbacks.
local function decodeJson(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return fallback or {}
end

local function getHairData(charid)
    local row = MySQL.single.await([[
        SELECT hairstyle, outfit_id, overlays, permanentoverlay
        FROM jrs_barber
        WHERE charid = ?
        LIMIT 1
    ]], { tonumber(charid) })

    if not row then return {}, '0', {}, {} end
    return decodeJson(row.hairstyle, {}), tostring(row.outfit_id or '0'),
        decodeJson(row.overlays, {}), decodeJson(row.permanentoverlay, {})
end


local function getClothingData(charid)
    local row = MySQL.single.await([[
        SELECT clothes, outfit_id
        FROM jrs_clothing_current
        WHERE charid = ?
        LIMIT 1
    ]], { tonumber(charid) })
    if not row then return {}, nil end
    return decodeJson(row.clothes, {}), row.outfit_id
end

local function ownsCharacter(source, charid)
    source = tonumber(source)
    charid = tonumber(charid)
    if not source or not charid then return false end
    local activeCharId = tonumber(GetCharIdentifier(source))
    if activeCharId and activeCharId == charid then return true end
    local identifier = GetPlayerIdentifierByType(source, 'steam') or GetPlayerIdentifier(source)
    if not identifier then return false end
    return MySQL.scalar.await(
        'SELECT 1 FROM jrs_characters WHERE identifier = ? AND charidentifier = ? LIMIT 1',
        { identifier, charid }
    ) ~= nil
end

Callback.register('jrs_character_creator:GetCurrentClothes', function(source)
    local charid = GetCharIdentifier(source)
    if not charid then return {}, nil end
    return getClothingData(charid)
end)

Callback.register('jrs_character_creator:SaveCreatorClothes', function(source, clothes)
    local charid = GetCharIdentifier(source)
    if not JRSHasCreatorEditSession(source) then return false end
    if not charid or type(clothes) ~= 'table' or not JRSJsonWithinLimit(clothes, 262144) then return false end

    local clothingJson = json.encode(clothes)
    local outfitId = 'creator_default_' .. tostring(charid)
    local character = jrsCore and type(jrsCore.getCharacter) == 'function' and jrsCore.getCharacter(tonumber(source)) or nil
    local skin = character and decodeJson(character.skin, {}) or {}
    local gender = skin.sex == 'mp_female' and 'female' or 'male'

    MySQL.query.await([[
        INSERT INTO jrs_clothing_current (charid, clothes, outfit_id)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            clothes = VALUES(clothes),
            outfit_id = VALUES(outfit_id)
    ]], { charid, clothingJson, outfitId })

    MySQL.query.await([[
        INSERT INTO jrs_clothing_outfits
            (charid, outfit_id, price, name, clothes, singleitems, gender)
        VALUES (?, ?, 0, 'Default', ?, '{}', ?)
        ON DUPLICATE KEY UPDATE
            charid = VALUES(charid),
            price = 0,
            name = 'Default',
            clothes = VALUES(clothes),
            singleitems = '{}',
            gender = VALUES(gender)
    ]], { charid, outfitId, clothingJson, gender })

    MySQL.update.await('UPDATE jrs_characters SET compPlayer = ? WHERE charidentifier = ?', { clothingJson, charid })
    if character then
        character.comp = clothingJson
        character.components = clothingJson
    end
    pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end)
    JRSCloseCreatorEditSession(source)
    return true
end)

Callback.register('jrs_character_creator:GetPedData', function(source)
    local charid = GetCharIdentifier(source)
    if not charid then return {} end

    local row = MySQL.single.await([[
        SELECT cc.peddata, c.skinPlayer
        FROM jrs_characters c
        LEFT JOIN jrs_character_creator cc ON cc.charid = c.charidentifier
        WHERE c.charidentifier = ?
        LIMIT 1
    ]], { charid })
    if not row then return {} end

    local creatorData = decodeJson(row.peddata, {})
    if next(creatorData) ~= nil then return creatorData end

    local legacySkin = decodeJson(row.skinPlayer, {})
    if next(legacySkin) ~= nil and type(BuildCreatorPedDataFromLegacy) == 'function' then
        return BuildCreatorPedDataFromLegacy(legacySkin)
    end

    return {}
end)

Callback.register('jrs_character_creator:GetCurrentHairs', function(source)
    local charid = GetCharIdentifier(source)
    if not charid then return {}, '0', {}, {} end
    return getHairData(charid)
end)

Callback.register('jrs_character_creator:GetCurrentHairsOnCharacter', function(source, charid)
    charid = tonumber(charid)
    if not charid or not ownsCharacter(source, charid) then return {}, '0', {}, {} end
    return getHairData(charid)
end)

Callback.register('jrs_character_creator:CreateNewCharacter', function(source, data, cachePedData)
    if type(data) ~= 'table' then return false end
    data._pedData = type(cachePedData) == 'table' and cachePedData or data
    return CreateNewCharacter(source, data)
end)

Callback.register('jrs_character_creator:SavePreset', function(source, hairstyleCache, overlayLayers, presetName, outfitId, isMale)
    local charid = GetCharIdentifier(source)
    if not JRSHasCreatorEditSession(source) then return false, '0' end
    if not charid then return false, '0' end
    if not JRSJsonWithinLimit(hairstyleCache, 262144) or not JRSJsonWithinLimit(overlayLayers, 262144) then return false, '0' end

    local name = JRSCleanText(presetName or 'Base', 80)
    local presetOutfitId = ResolveJRSBarberOutfitId(charid, outfitId, name)
    local activeOutfitId = presetOutfitId
    local gender = isMale and 'male' or 'female'
    local hairstyleJson = json.encode(type(hairstyleCache) == 'table' and hairstyleCache or {})
    local overlaysJson = json.encode(type(overlayLayers) == 'table' and overlayLayers or {})

    MySQL.query.await('DELETE FROM jrs_barber_preset WHERE charid = ? AND name = ?', { charid, name })
    MySQL.query.await([[
        INSERT INTO jrs_barber_preset
            (charid, outfit_id, price, name, hairstyle, overlays, gender)
        VALUES (?, ?, 0, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            charid = VALUES(charid),
            price = VALUES(price),
            name = VALUES(name),
            hairstyle = VALUES(hairstyle),
            overlays = VALUES(overlays),
            gender = VALUES(gender)
    ]], { charid, presetOutfitId, name, hairstyleJson, overlaysJson, gender })

    MySQL.query.await([[
        INSERT INTO jrs_barber
            (charid, hairstyle, overlays, permanentoverlay, outfit_id)
        VALUES (?, ?, ?, '[]', ?)
        ON DUPLICATE KEY UPDATE
            hairstyle = VALUES(hairstyle),
            overlays = VALUES(overlays),
            outfit_id = VALUES(outfit_id)
    ]], { charid, hairstyleJson, overlaysJson, activeOutfitId })

    return true, activeOutfitId
end)

Callback.register('jrs_character_creator:UpdatePedData', function(source, cachePedData, overlayLayers)
    local charid = GetCharIdentifier(source)
    if not JRSHasCreatorEditSession(source) then return false end
    if not charid or type(cachePedData) ~= 'table' or not JRSJsonWithinLimit(cachePedData, 262144) then return false end

    local pedDataJson = json.encode(cachePedData)
    MySQL.query.await([[
        INSERT INTO jrs_character_creator (charid, peddata, informations)
        VALUES (?, ?, '{}')
        ON DUPLICATE KEY UPDATE
            peddata = VALUES(peddata)
    ]], { charid, pedDataJson })

    -- Keep the legacy base skin used by jrs_character in sync after Second Chance edits.
    if type(BuildJRSBaseSkin) == 'function' then
        local baseSkin = BuildJRSBaseSkin(cachePedData, overlayLayers)
        local skinJson = json.encode(baseSkin)
        MySQL.update.await('UPDATE jrs_characters SET skinPlayer = ? WHERE charidentifier = ?', { skinJson, charid })

        local character = jrsCore and type(jrsCore.getCharacter) == 'function' and jrsCore.getCharacter(tonumber(source)) or nil
        if character and tonumber(character.charIdentifier) == tonumber(charid) then
            character.skin = skinJson
        end
    end

    pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end)
    TriggerEvent('jrs_pedmenu:server:creatorRefresh', tonumber(source), false)
    return true
end)

-- Commit the editor's complete appearance together. A failed clothing/barber
-- write must not leave a saved face paired with the old outfit.
local appearanceSaves = {}
Callback.register('jrs_character_creator:SaveAppearance', function(source, pedData, overlays, hairstyle, clothes)
    local charid = GetCharIdentifier(source)
    if not charid or not JRSHasCreatorEditSession(source) then return false, 'session_expired' end
    if appearanceSaves[source] then return false, 'busy' end
    if not JRSJsonWithinLimit(pedData, 262144)
        or not JRSJsonWithinLimit(overlays, 262144)
        or not JRSJsonWithinLimit(hairstyle, 262144)
        or not JRSJsonWithinLimit(clothes, 262144) then return false, 'invalid_data' end

    local session = jrsCreatorEditSessions[tonumber(source)]
    appearanceSaves[source] = true
    local ok, saved = pcall(function()
        local skinJson = json.encode(BuildJRSBaseSkin(pedData, overlays))
        local pedJson, clothesJson = json.encode(pedData), json.encode(clothes)
        local hairJson, overlaysJson = json.encode(hairstyle), json.encode(overlays)
        local gender = pedData.gender == 'Female' and 'female' or 'male'
        local outfitId = 'creator_default_' .. tostring(charid)
        local barberId = ResolveJRSBarberOutfitId(charid, nil, 'Base')
        if GetCharIdentifier(source) ~= charid or not JRSHasCreatorEditSession(source)
            or jrsCreatorEditSessions[tonumber(source)] ~= session then return false end
        local committed = MySQL.transaction.await({
            { query = [[INSERT INTO jrs_character_creator (charid, peddata, informations)
                VALUES (?, ?, '{}') ON DUPLICATE KEY UPDATE peddata = VALUES(peddata)]],
                values = { charid, pedJson } },
            { query = 'UPDATE jrs_characters SET skinPlayer = ?, compPlayer = ? WHERE charidentifier = ?',
                values = { skinJson, clothesJson, charid } },
            { query = 'DELETE FROM jrs_barber_preset WHERE charid = ? AND name = ?', values = { charid, 'Base' } },
            { query = [[INSERT INTO jrs_barber_preset (charid, outfit_id, price, name, hairstyle, overlays, gender)
                VALUES (?, ?, 0, 'Base', ?, ?, ?)]], values = { charid, barberId, hairJson, overlaysJson, gender } },
            { query = [[INSERT INTO jrs_barber (charid, hairstyle, overlays, permanentoverlay, outfit_id)
                VALUES (?, ?, ?, '[]', ?) ON DUPLICATE KEY UPDATE hairstyle = VALUES(hairstyle),
                overlays = VALUES(overlays), outfit_id = VALUES(outfit_id)]],
                values = { charid, hairJson, overlaysJson, barberId } },
            { query = [[INSERT INTO jrs_clothing_current (charid, clothes, outfit_id) VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE clothes = VALUES(clothes), outfit_id = VALUES(outfit_id)]],
                values = { charid, clothesJson, outfitId } },
            { query = [[INSERT INTO jrs_clothing_outfits (charid, outfit_id, price, name, clothes, singleitems, gender)
                VALUES (?, ?, 0, 'Default', ?, '{}', ?) ON DUPLICATE KEY UPDATE
                price = 0, name = 'Default', clothes = VALUES(clothes), singleitems = '{}', gender = VALUES(gender)]],
                values = { charid, outfitId, clothesJson, gender } },
        })
        if committed ~= true then return false end
        local character = jrsCore and type(jrsCore.getCharacter) == 'function' and jrsCore.getCharacter(tonumber(source)) or nil
        if character and tonumber(character.charIdentifier) == tonumber(charid) then
            character.skin, character.comp, character.components = skinJson, clothesJson, clothesJson
        end
        if jrsCreatorEditSessions[tonumber(source)] == session then JRSCloseCreatorEditSession(source) end
        pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end)
        if GetCharIdentifier(source) == charid then
            TriggerEvent('jrs_pedmenu:server:creatorRefresh', tonumber(source), false)
        end
        return true
    end)
    appearanceSaves[source] = nil
    if not ok then printconsole('SaveAppearance failed:', tostring(saved)) end
    if ok and saved == true then return true end
    return false, ok and 'save_failed' or 'server_error'
end)

Callback.register('jrs_character_creator:GetCurrentOverlays', function(source)
    local charid = GetCharIdentifier(source)
    if not charid then return {}, {} end
    local _, _, makeup, permanent = getHairData(charid)
    return makeup, permanent
end)

Callback.register('jrs_barber:GetCurrentOverlays', function(source, charid)
    local targetCharId = tonumber(charid) or GetCharIdentifier(source)
    if not targetCharId or not ownsCharacter(source, targetCharId) then return {}, {} end
    local _, _, makeup, permanent = getHairData(targetCharId)
    return makeup, permanent
end)
end

-- ============================================================================
-- Module: integration/jrs_server.lua
-- ============================================================================
do
if CreatorConfig.framework == 'jrs_core' then
    local creatingCharacters = {}
    local activeAgingSessions = {}
    local agingColumnsReady = false
    local agingColumnsChecked = false
    local core = jrsCore

    CreateThread(function()
        while type(core) ~= 'table' or type(core.getUser) ~= 'function' do
            core = exports.jrs_core:getCoreApi()
            Wait(250)
        end
    end)

    local function notify(source, message, duration)
        local player = tonumber(source)
        local state = player and Player(player) and Player(player).state or nil
        if state and state.jrsCharacterGate == true then
            return
        end
        TriggerClientEvent('jrs_core:sendRightTipNotification', player, tostring(message), tonumber(duration) or 4000)
    end

    local function getIdentifier(source)
        return GetPlayerIdentifierByType(tonumber(source), 'steam') or GetPlayerIdentifier(tonumber(source))
    end

    local function getUser(source)
        return core and core.getUser and core.getUser(tonumber(source)) or nil
    end

    local function selectCoreCharacter(source, charid, characterRow)
        source = tonumber(source)
        charid = tonumber(charid)
        if not source or not charid or type(characterRow) ~= 'table' then
            return false
        end

        local lastReason = 'unknown'
        for attempt = 1, 12 do
            if GetResourceState('jrs_core') ~= 'started' then
                lastReason = 'jrs_core_not_started'
            else
                -- Primary path: a real cross-resource server export. Do not
                -- depend on function fields inside the getCoreApi event table.
                local ok, selected, reason = pcall(function()
                    return exports['jrs_core']:SelectCharacterFromRow(source, characterRow)
                end)

                if ok and selected == true then
                    return true
                end

                if ok then
                    lastReason = tostring(reason or 'selection_rejected')
                else
                    lastReason = 'core_export_error:' .. tostring(selected)
                end

                -- Compatibility fallback for installations where the core
                -- table is available in the same runtime/API implementation.
                core = exports.jrs_core:getCoreApi()

                if core and type(core.SelectCharacterFromRow) == 'function' then
                    local fallbackOk, fallbackSelected, fallbackReason = pcall(
                        core.SelectCharacterFromRow,
                        source,
                        characterRow
                    )
                    if fallbackOk and fallbackSelected == true then
                        return true
                    end
                    lastReason = fallbackOk
                        and tostring(fallbackReason or lastReason)
                        or ('core_table_error:' .. tostring(fallbackSelected))
                end
            end

            Wait(attempt < 4 and 250 or 500)
        end

        print(('^1[jrs_character] Failed to select character %s for source %s. Reason: %s^7')
            :format(tostring(charid), tostring(source), tostring(lastReason)))
        return false
    end

    local function getActiveCharacter(source)
        if core and type(core.getCharacter) == 'function' then
            return core.getCharacter(tonumber(source))
        end
        local user = getUser(source)
        return user and user.getUsedCharacter or nil
    end

    function GetCharIdentifier(targetID)
        local character = getActiveCharacter(targetID)
        return character and tonumber(character.charIdentifier) or nil
    end

    function GetCharFirstname(targetID)
        local character = getActiveCharacter(targetID)
        return character and character.firstname or nil
    end

    function GetCharLastname(targetID)
        local character = getActiveCharacter(targetID)
        return character and character.lastname or nil
    end

    function GetCharGroup(targetID)
        local user = getUser(targetID)
        return user and user.group or 'user'
    end

    local function getSlotLimit(source)
        local identifier = getIdentifier(source)
        local group = GetCharGroup(source)
        local user = getUser(source)
        local slots = tonumber(CreatorConfig.Slots.default) or 1

        -- 1. Check jrs_core live user object
        if CreatorConfig.Slots.useCoreLimit ~= false and user and tonumber(user.chars) then
            slots = tonumber(user.chars)
        end

        -- 2. Check database directly if user is missing or default
        if CreatorConfig.Slots.useCoreLimit ~= false and identifier then
            local row = MySQL.single.await('SELECT chars_override, chars FROM jrs_users WHERE identifier = ? LIMIT 1', { identifier })
            if row then
                local dbSlots = tonumber(row.chars_override) or tonumber(row.chars)
                if dbSlots and dbSlots > 0 then
                    slots = dbSlots
                end
            end
        end

        -- 3. Optional creator overrides are applied only when explicitly configured.
        if CreatorConfig.Slots.role and CreatorConfig.Slots.role[group] ~= nil then
            slots = tonumber(CreatorConfig.Slots.role[group]) or slots
        end
        if identifier and CreatorConfig.Slots.identifier and CreatorConfig.Slots.identifier[identifier] ~= nil then
            slots = tonumber(CreatorConfig.Slots.identifier[identifier]) or slots
        end

        -- Maximum safety limit: saloon has 6 pedslots, never allow infinity or out-of-bounds
        local maxPedSlots = (CreatorConfig.CharSelect and type(CreatorConfig.CharSelect.pedslots) == 'table') and #CreatorConfig.CharSelect.pedslots or 6
        if maxPedSlots <= 0 then maxPedSlots = 6 end
        return math.max(1, math.min(maxPedSlots, slots))
    end

    local function getPedPermission(source)
        local identifier = getIdentifier(source)
        local group = GetCharGroup(source)
        local allowed = CreatorConfig.PedPermission.default == true
        if CreatorConfig.PedPermission.role[group] ~= nil then
            allowed = CreatorConfig.PedPermission.role[group] == true
        end
        if identifier and CreatorConfig.PedPermission.identifier[identifier] ~= nil then
            allowed = CreatorConfig.PedPermission.identifier[identifier] == true
        end
        return allowed
    end

    local function decode(value, fallback)
        if type(value) == 'table' then return value end
        if type(value) ~= 'string' or value == '' then return fallback or {} end
        local ok, result = pcall(json.decode, value)
        return ok and type(result) == 'table' and result or (fallback or {})
    end

    local profileColumnsReady = false

    local function ensureCharacterProfileColumns()
        local statements = {
            [[ALTER TABLE `jrs_characters`
                ADD COLUMN IF NOT EXISTS `dateofbirth` DATE NULL]],
            [[ALTER TABLE `jrs_characters`
                ADD COLUMN IF NOT EXISTS `nickname` VARCHAR(50)
                CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '']],
            [[ALTER TABLE `jrs_characters`
                ADD COLUMN IF NOT EXISTS `occupation` VARCHAR(80)
                CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '']]
        }

        local allSucceeded = true
        for _, statement in ipairs(statements) do
            local ok, err = pcall(function()
                MySQL.query.await(statement)
            end)
            if not ok then
                allSucceeded = false
                print(('^3[jrs_character] Character profile migration warning: %s^7'):format(tostring(err)))
            end
        end

        -- Older databases create `characters` as latin1 and jrs_core adds
        -- character_desc without a charset, so it inherited latin1. Any Arabic
        -- lore then made the creator's profile UPDATE throw halfway through
        -- creation, leaving a character with no clothes, hair or birth date.
        local descOk, descColumn = pcall(function()
            return MySQL.single.await([[
                SELECT CHARACTER_SET_NAME AS charset
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'jrs_characters'
                  AND COLUMN_NAME = 'character_desc'
                LIMIT 1
            ]])
        end)
        if descOk and descColumn and tostring(descColumn.charset or ''):lower() ~= 'utf8mb4' then
            local ok, err = pcall(function()
                MySQL.query.await([[ALTER TABLE `jrs_characters`
                    MODIFY COLUMN `character_desc` VARCHAR(512)
                    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '']])
            end)
            if not ok then
                allSucceeded = false
                print(('^3[jrs_character] character_desc utf8mb4 migration warning: %s^7'):format(tostring(err)))
            end
        end

        if allSucceeded then
            local dateColumn = MySQL.single.await("SHOW COLUMNS FROM `jrs_characters` LIKE 'dateofbirth'")
            local nicknameColumn = MySQL.single.await("SHOW COLUMNS FROM `jrs_characters` LIKE 'nickname'")
            local occupationColumn = MySQL.single.await("SHOW COLUMNS FROM `jrs_characters` LIKE 'occupation'")
            profileColumnsReady = dateColumn ~= nil and nicknameColumn ~= nil and occupationColumn ~= nil
        end

        return profileColumnsReady
    end

    local function normalizeBirthDate(value)
        value = tostring(value or '')
        -- oxmysql returns a DATE column as a JS Date unless the connection
        -- string sets dateStrings, which serializes across the export bridge
        -- as an ISO datetime ("1881-01-17T00:00:00.000Z"). Match the leading
        -- date only so that trailing time/zone text never breaks this.
        local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
        year, month, day = tonumber(year), tonumber(month), tonumber(day)
        if not year or not month or not day or year < 1 or month < 1 or month > 12 then
            return nil, '', '', ''
        end

        local daysInMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
        local leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
        if leap then daysInMonth[2] = 29 end
        if day < 1 or day > daysInMonth[month] then
            return nil, '', '', ''
        end

        return ('%04d-%02d-%02d'):format(year, month, day),
            tostring(day), tostring(month), tostring(year)
    end

    local function isPlaytimeAgingEnabled()
        return tostring(Config and Config.AgingMode or ''):lower() == 'playtime'
    end

    local function secondsPerAgeYear()
        local hours = tonumber(Config and Config.HoursPerYear) or 100
        return math.max(1, math.floor(hours * 3600))
    end

    -- The world's "today". Red Dead is set in 1899, so ages are measured from
    -- Config.WorldDate rather than from the real-world clock - measuring against
    -- os.date() is what forced players to enter modern birth years (the live
    -- data still holds 2008 and 1990) just to clear the minimum-age check.
    local function worldToday()
        local world = type(Config) == 'table' and type(Config.WorldDate) == 'table' and Config.WorldDate or nil
        return {
            year  = math.floor(tonumber(world and world.year) or 1899),
            month = math.max(1, math.min(12, math.floor(tonumber(world and world.month) or 1))),
            day   = math.max(1, math.min(31, math.floor(tonumber(world and world.day) or 1))),
        }
    end
    JRSCharacterWorldToday = worldToday

    local function calculateBaseAge(birthdate)
        local normalized = normalizeBirthDate(birthdate)
        if not normalized then return 0 end

        local year, month, day = normalized:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
        year, month, day = tonumber(year), tonumber(month), tonumber(day)
        local now = worldToday()
        local age = now.year - year
        if now.month < month or (now.month == month and now.day < day) then
            age = age - 1
        end
        return math.max(0, math.min(250, age))
    end

    local function calculatePlaytimeAge(baseAge, playtimeSeconds)
        local minAge = math.max(1, math.floor(tonumber(Config and Config.MinimumAge) or 18))
        baseAge = math.max(minAge, tonumber(baseAge) or minAge)
        playtimeSeconds = math.max(0, tonumber(playtimeSeconds) or 0)
        return math.floor(baseAge + (playtimeSeconds / secondsPerAgeYear()))
    end

    local function ensureCharacterAgingColumns()
        if not isPlaytimeAgingEnabled() then return false end
        if agingColumnsChecked then return agingColumnsReady end
        agingColumnsChecked = true

        local statements = {
            [[ALTER TABLE `jrs_characters`
                ADD COLUMN IF NOT EXISTS `playtime_seconds` BIGINT UNSIGNED NOT NULL DEFAULT 0]],
            [[ALTER TABLE `jrs_characters`
                ADD COLUMN IF NOT EXISTS `base_age` SMALLINT UNSIGNED NULL DEFAULT NULL]],
            [[ALTER TABLE `jrs_characters`
                ADD COLUMN IF NOT EXISTS `age_years` SMALLINT UNSIGNED NULL DEFAULT NULL]]
        }

        local allSucceeded = true
        for _, statement in ipairs(statements) do
            local ok, err = pcall(function()
                MySQL.query.await(statement)
            end)
            if not ok then
                allSucceeded = false
                print(('^3[jrs_character] Character aging migration warning: %s^7'):format(tostring(err)))
            end
        end

        if allSucceeded then
            local playtimeColumn = MySQL.single.await("SHOW COLUMNS FROM `jrs_characters` LIKE 'playtime_seconds'")
            local baseAgeColumn = MySQL.single.await("SHOW COLUMNS FROM `jrs_characters` LIKE 'base_age'")
            local ageColumn = MySQL.single.await("SHOW COLUMNS FROM `jrs_characters` LIKE 'age_years'")
            agingColumnsReady = playtimeColumn ~= nil and baseAgeColumn ~= nil and ageColumn ~= nil
        end

        if not agingColumnsReady then
-- REMOVED-PRINT:             print('^3[jrs_character] Playtime aging columns are unavailable. Import sql/install.sql.^7')
        end
        return agingColumnsReady
    end

    local function ensureCharacterAgingState(identifier, charid, birthdate, row)
        -- Characters created before the world date moved to 1899 hold modern
        -- birth years, which now compute to 0. Never let an existing character
        -- read back as younger than the minimum; their stored base_age still
        -- wins in the playtime branch below.
        local fallbackMinAge = math.max(1, math.floor(tonumber(Config and Config.MinimumAge) or 18))
        local fallbackBaseAge = math.max(fallbackMinAge, calculateBaseAge(birthdate))
        if not isPlaytimeAgingEnabled() then
            return {
                baseAge = fallbackBaseAge,
                playtimeSeconds = 0,
                ageYears = fallbackBaseAge,
                yearsFromPlaytime = 0,
                secondsToNextYear = 0,
            }
        end

        if not ensureCharacterAgingColumns() then
            return {
                baseAge = fallbackBaseAge,
                playtimeSeconds = 0,
                ageYears = fallbackBaseAge,
                yearsFromPlaytime = 0,
                secondsToNextYear = secondsPerAgeYear(),
            }
        end

        local data = row
        if type(data) ~= 'table' or data.playtime_seconds == nil then
            data = MySQL.single.await([[
                SELECT DATE_FORMAT(dateofbirth, '%Y-%m-%d') AS dateofbirth, playtime_seconds, base_age, age_years
                FROM jrs_characters
                WHERE identifier = ? AND charidentifier = ?
                LIMIT 1
            ]], { identifier, charid }) or {}
        end

        local minAge = math.max(1, math.floor(tonumber(Config and Config.MinimumAge) or 18))
        local storedBirthDate = data.dateofbirth or birthdate
        local baseAge = tonumber(data.base_age)
        if baseAge == nil or baseAge < minAge then
            baseAge = calculateBaseAge(storedBirthDate)
        end
        baseAge = math.max(minAge, math.floor(baseAge))

        local playtimeSeconds = math.max(0, math.floor(tonumber(data.playtime_seconds) or 0))
        local ageYears = calculatePlaytimeAge(baseAge, playtimeSeconds)
        local secondsInCurrentYear = playtimeSeconds % secondsPerAgeYear()
        local secondsToNextYear = secondsPerAgeYear() - secondsInCurrentYear

        if tonumber(data.base_age) ~= baseAge or tonumber(data.age_years) ~= ageYears then
            MySQL.update.await([[
                UPDATE jrs_characters
                SET base_age = ?, age_years = ?, playtime_seconds = COALESCE(playtime_seconds, 0)
                WHERE identifier = ? AND charidentifier = ?
            ]], { baseAge, ageYears, identifier, charid })
        end

        return {
            baseAge = baseAge,
            playtimeSeconds = playtimeSeconds,
            ageYears = ageYears,
            yearsFromPlaytime = math.floor(playtimeSeconds / secondsPerAgeYear()),
            secondsToNextYear = secondsToNextYear,
        }
    end

    local function persistAgingSession(source, keepActive)
        source = tonumber(source)
        local session = source and activeAgingSessions[source] or nil
        if not session then return nil end

        local now = os.time()
        local elapsed = math.max(0, now - (tonumber(session.startedAt) or now))
        -- Move the timestamp before yielding to oxmysql so a second event cannot
        -- save the same elapsed seconds twice.
        session.startedAt = now

        local snapshot
        if elapsed > 0 and isPlaytimeAgingEnabled() and ensureCharacterAgingColumns() then
            MySQL.update.await([[
                UPDATE jrs_characters
                SET playtime_seconds = COALESCE(playtime_seconds, 0) + ?
                WHERE identifier = ? AND charidentifier = ?
            ]], { elapsed, session.identifier, session.charid })
        end

        snapshot = ensureCharacterAgingState(
            session.identifier,
            session.charid,
            session.birthdate,
            nil
        )
        local previousAge = session.ageYears
        session.ageYears = snapshot.ageYears
        session.playtimeSeconds = snapshot.playtimeSeconds

        if GetPlayerName(source) then
            local ageChanged = (previousAge ~= nil and tonumber(previousAge) ~= tonumber(snapshot.ageYears))
            TriggerClientEvent('jrs_character:ageUpdated', source, {
                age = snapshot.ageYears,
                playtimeSeconds = snapshot.playtimeSeconds,
                hoursPerYear = tonumber(Config and Config.HoursPerYear) or 100,
                secondsToNextYear = snapshot.secondsToNextYear,
                ageChanged = ageChanged,
            })
        end

        if keepActive ~= true then
            activeAgingSessions[source] = nil
        end
        return snapshot
    end

    local function startAgingSession(source, charid, identifier, birthdate, row)
        source = tonumber(source)
        charid = tonumber(charid)
        identifier = tostring(identifier or '')
        if not source or not charid or identifier == '' or not isPlaytimeAgingEnabled() then return nil end

        local current = activeAgingSessions[source]
        if current and tonumber(current.charid) == charid then
            return ensureCharacterAgingState(identifier, charid, birthdate, row)
        end
        if current then persistAgingSession(source, false) end

        local snapshot = ensureCharacterAgingState(identifier, charid, birthdate, row)
        activeAgingSessions[source] = {
            charid = charid,
            identifier = identifier,
            birthdate = birthdate,
            startedAt = os.time(),
            ageYears = snapshot.ageYears,
            playtimeSeconds = snapshot.playtimeSeconds,
        }
        return snapshot
    end

    local function getLiveAgingSnapshot(source, charid, identifier, birthdate, row)
        source = tonumber(source)
        charid = tonumber(charid)
        local session = source and activeAgingSessions[source] or nil
        if session and tonumber(session.charid) == charid then
            local liveSeconds = math.max(0, tonumber(session.playtimeSeconds) or 0)
                + math.max(0, os.time() - (tonumber(session.startedAt) or os.time()))
            local minAge = math.max(1, math.floor(tonumber(Config and Config.MinimumAge) or 18))
            local baseAge = tonumber(row and row.base_age)
            if not baseAge or baseAge < minAge then
                baseAge = calculateBaseAge(birthdate)
            end
            baseAge = math.max(minAge, math.floor(baseAge))
            return {
                baseAge = baseAge,
                playtimeSeconds = liveSeconds,
                ageYears = calculatePlaytimeAge(baseAge, liveSeconds),
                yearsFromPlaytime = math.floor(liveSeconds / secondsPerAgeYear()),
                secondsToNextYear = secondsPerAgeYear() - (liveSeconds % secondsPerAgeYear()),
            }
        end
        return ensureCharacterAgingState(identifier, charid, birthdate, row)
    end

    CreateThread(function()
        Wait(750)
        ensureCharacterProfileColumns()
        ensureCharacterAgingColumns()
    end)

    local function toCoords(value)
        local valueType = type(value)

        -- Cfx vector userdata supports named fields, but numeric indexing such as
        -- value[4] raises "attempt to index a vector value". Handle each type
        -- separately before normalising it into a plain JSON-safe Lua table.
        if valueType == 'vector3' then
            return {
                x = tonumber(value.x) or 0.0,
                y = tonumber(value.y) or 0.0,
                z = tonumber(value.z) or 0.0,
                heading = 0.0,
            }
        end

        if valueType == 'vector4' then
            return {
                x = tonumber(value.x) or 0.0,
                y = tonumber(value.y) or 0.0,
                z = tonumber(value.z) or 0.0,
                heading = tonumber(value.w) or 0.0,
            }
        end

        if valueType ~= 'table' then return {} end

        return {
            x = tonumber(value.x or value[1]) or 0.0,
            y = tonumber(value.y or value[2]) or 0.0,
            z = tonumber(value.z or value[3]) or 0.0,
            heading = tonumber(value.heading or value.h or value.w or value[4]) or 0.0,
        }
    end

    local function roundNumber(value, decimals)
        value = tonumber(value) or 0.0
        local factor = 10 ^ (tonumber(decimals) or 0)
        if value >= 0 then
            return math.floor((value * factor) + 0.5) / factor
        end
        return math.ceil((value * factor) - 0.5) / factor
    end

    -- characters.coords was VARCHAR(75) in older JRS databases. Full Cfx
    -- floating-point values plus heading can exceed that limit. Keep the JSON
    -- compact even when the database migration cannot be applied immediately.
    local function encodeCoordsForDatabase(value)
        local coords = toCoords(value)
        return json.encode({
            x = roundNumber(coords.x, 3),
            y = roundNumber(coords.y, 3),
            z = roundNumber(coords.z, 3),
            heading = roundNumber(coords.heading, 1),
        })
    end

    local coordsColumnChecked = false

    local function ensureCoordsColumnCapacity()
        if coordsColumnChecked then return true end
        coordsColumnChecked = true

        local ok, column = pcall(function()
            return MySQL.single.await([[
                SELECT DATA_TYPE AS dataType, CHARACTER_MAXIMUM_LENGTH AS maxLength
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'jrs_characters'
                  AND COLUMN_NAME = 'coords'
                LIMIT 1
            ]])
        end)

        if not ok or not column then
-- REMOVED-PRINT:             print('^3[jrs_character] Could not inspect characters.coords; compact coordinate storage will be used.^7')
            return false
        end

        local dataType = tostring(column.dataType or ''):lower()
        local maxLength = tonumber(column.maxLength) or 0
        if dataType == 'longtext' or dataType == 'text' or dataType == 'mediumtext' or maxLength >= 255 then
            return true
        end

        local altered, alterError = pcall(function()
            MySQL.query.await([[
                ALTER TABLE `jrs_characters`
                MODIFY COLUMN `coords` LONGTEXT
                CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci
                DEFAULT '{}'
            ]])
        end)

        if altered then
-- REMOVED-PRINT:             print('^2[jrs_character] Updated characters.coords to LONGTEXT.^7')
            return true
        end

        return false
    end

    CreateThread(function()
        while not MySQL or not MySQL.single or not MySQL.query do Wait(250) end
        ensureCoordsColumnCapacity()
    end)

    local function deepCopy(value)
        if type(value) ~= 'table' then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = deepCopy(item) end
        return result
    end

    PlayerSkin = {
        ShouldersS                           = 0.0,
        ShouldersT                           = 0.0,
        ShouldersM                           = 0.0,
        ArmsS                                = 0.0,
        LegsS                                = 0.0,
        CalvesS                              = 0.0,
        ChestS                               = 0.0,
        WaistW                               = 0.0,
        HipsS                                = 0.0,
        FaceW                                = 0.0,
        FaceD                                = 0.0,
        FaceS                                = 0.0,
        NeckW                                = 0.0,
        NeckD                                = 0.0,
        MouthCLW                             = 0.0,
        MouthCRW                             = 0.0,
        MouthCLD                             = 0.0,
        MouthCRD                             = 0.0,
        MouthCLH                             = 0.0,
        MouthCRH                             = 0.0,
        MouthCLLD                            = 0.0,
        MouthCRLD                            = 0.0,
        EyeLidL                              = 0.0,
        EyeLidR                              = 0.0,
        sex                                  = "mp_male",
        albedo                               = 0,
        HeadType                             = 0,
        BodyType                             = 0,
        LegsType                             = 0,
        Torso                                = 0,
        HeadSize                             = 0.0,
        EyeBrowH                             = 0.0,
        EyeBrowW                             = 0.0,
        EyeBrowD                             = 0.0,
        EarsH                                = 0.0,
        EarsW                                = 0.0,
        EarsD                                = 0.0,
        EarsA                                = 0.0,
        EyeLidH                              = 0.0,
        EyeLidW                              = 0.0,
        EyeD                                 = 0.0,
        EyeAng                               = 0.0,
        EyeDis                               = 0.0,
        EyeH                                 = 0.0,
        NoseW                                = 0.0,
        NoseS                                = 0.0,
        NoseH                                = 0.0,
        NoseAng                              = 0.0,
        NoseC                                = 0.0,
        NoseDis                              = 0.0,
        CheekBonesH                          = 0.0,
        CheekBonesW                          = 0.0,
        CheekBonesD                          = 0.0,
        MouthW                               = 0.0,
        MouthD                               = 0.0,
        MouthX                               = 0.0,
        MouthY                               = 0.0,
        ULiphH                               = 0.0,
        ULiphW                               = 0.0,
        ULiphD                               = 0.0,
        LLiphH                               = 0.0,
        LLiphW                               = 0.0,
        LLiphD                               = 0.0,
        JawH                                 = 0.0,
        JawW                                 = 0.0,
        JawD                                 = 0.0,
        ChinH                                = 0.0,
        ChinW                                = 0.0,
        ChinD                                = 0.0,
        Beard                                = 0,
        Hair                                 = 0,
        Body                                 = 0,
        Waist                                = 0,
        Eyes                                 = 0,
        Scale                                = 0.0,
        eyebrows_visibility                  = 0,
        eyebrows_tx_id                       = 0,
        eyebrows_opacity                     = 0.0,
        eyebrows_color                       = 0,
        scars_visibility                     = 0,
        scars_tx_id                          = 0,
        scars_opacity                        = 0,
        spots_visibility                     = 0,
        spots_tx_id                          = 0,
        spots_opacity                        = 0,
        disc_visibility                      = 0,
        disc_tx_id                           = 0,
        disc_opacity                         = 0,
        complex_visibility                   = 0,
        complex_tx_id                        = 0,
        complex_opacity                      = 0,
        acne_visibility                      = 0,
        acne_tx_id                           = 0,
        acne_opacity                         = 0,
        ageing_visibility                    = 0,
        ageing_tx_id                         = 0,
        ageing_opacity                       = 0,
        freckles_visibility                  = 0,
        freckles_tx_id                       = 0,
        freckles_opacity                     = 0,
        moles_visibility                     = 0,
        moles_tx_id                          = 0,
        moles_opacity                        = 0,
        grime_visibility                     = 0,
        grime_tx_id                          = 0,
        grime_opacity                        = 0,
        lipsticks_visibility                 = 0,
        lipsticks_tx_id                      = 0,
        lipsticks_palette_id                 = 0,
        lipsticks_palette_color_primary      = 0,
        lipsticks_palette_color_secondary    = 0,
        lipsticks_palette_color_tertiary     = 0,
        lipsticks_opacity                    = 0,
        shadows_visibility                   = 0,
        shadows_tx_id                        = 0,
        shadows_palette_id                   = 0,
        shadows_palette_color_primary        = 0,
        shadows_palette_color_secondary      = 0,
        shadows_palette_color_tertiary       = 0,
        shadows_opacity                      = 0,
        beardstabble_tx_id                   = 0,
        beardstabble_visibility              = 0,
        beardstabble_color_primary           = 0,
        beardstabble_opacity                 = 0,
        eyeliner_tx_id                       = 0,
        eyeliner_visibility                  = 0,
        eyeliner_color_primary               = 0,
        eyeliner_opacity                     = 0,
        eyeliner_palette_id                  = 0,
        blush_visibility                     = 0,
        blush_tx_id                          = 0,
        blush_palette_id                     = 0,
        blush_palette_color_primary          = 0,
        blush_opacity                        = 0,
        hair_tx_id                           = 0,
        hair_visibility                      = 0,
        hair_color_primary                   = 0,
        hair_opacity                         = 0,
        foundation_tx_id                     = 0,
        foundation_visibility                = 0,
        foundation_palette_id                = 0,
        foundation_palette_color_primary     = 0,
        foundation_palette_color_secondary   = 0,
        foundation_palette_color_tertiary    = 0,
        foundation_opacity                   = 0,
        paintedmasks_tx_id                   = 0,
        paintedmasks_visibility              = 0,
        paintedmasks_palette_id              = 0,
        paintedmasks_palette_color_primary   = 0,
        paintedmasks_palette_color_secondary = 0,
        paintedmasks_palette_color_tertiary  = 0,
        paintedmasks_opacity                 = 0,

    }

    PlayerClothing = {
        Poncho      = { comp = -1 },
        Glove       = { comp = -1 },
        RingRh      = { comp = -1 },
        Gauntlets   = { comp = -1 },
        Spats       = { comp = -1 },
        GunbeltAccs = { comp = -1 },
        NeckTies    = { comp = -1 },
        bow         = { comp = -1 },
        RingLh      = { comp = -1 },
        Loadouts    = { comp = -1 },
        Boots       = { comp = -1 },
        Suspender   = { comp = -1 },
        NeckWear    = { comp = -1 },
        Holster     = { comp = -1 },
        CoatClosed  = { comp = -1 },
        EyeWear     = { comp = -1 },
        Shirt       = { comp = -1 },
        Gunbelt     = { comp = -1 },
        Hat         = { comp = -1 },
        Spurs       = { comp = -1 },
        Cloak       = { comp = -1 },
        Vest        = { comp = -1 },
        Belt        = { comp = -1 },
        Pant        = { comp = -1 },
        Skirt       = { comp = -1 },
        Coat        = { comp = -1 },
        Mask        = { comp = -1 },
        Accessories = { comp = -1 },
        Buckle      = { comp = -1 },
        Bracelet    = { comp = -1 },
        Satchels    = { comp = -1 },
        Dress       = { comp = -1 },
        Badge       = { comp = -1 },
        Armor       = { comp = -1 },
        Teeth       = { comp = -1 },
        Chap        = { comp = -1 },
    }

    local function getLegacyComponents(gender)
        local components = {}
        for key, value in pairs(PlayerClothing) do components[key] = tonumber(value.comp) or -1 end
        if gender == 'Male' then
            components.Gunbelt = 795591403
        else
            components.Gunbelt = 1511461630
        end
        return components
    end

    local function resolveCreatorScale(value)
        local height = tonumber(value) or 1.0
        if height <= 0.0 then height = 1.0 end

        -- Current creator data stores the final ped scale (normally 0.95-1.05).
        -- Keep compatibility with early builds that stored a 0-100 slider value.
        if height > 2.0 then
            height = 0.95 + (math.max(0.0, math.min(100.0, height)) / 100.0) * 0.10
        end

        return math.max(0.7, math.min(1.3, height))
    end

    local legacyExpressionMap

    function BuildJRSBaseSkin(data, overlayLayers)
        data = type(data) == 'table' and data or {}
        local pedData = type(data._pedData) == 'table' and data._pedData or data
        local genderValue = data.gender or pedData.gender
        local gender = genderValue == 'Female' and 'Female' or 'Male'
        local skinTone = math.max(1, tonumber(data.skintone or pedData.skintone) or 1)
        local defaults = DefaultChar[gender] and DefaultChar[gender][skinTone] or nil
        if not defaults then
            skinTone = 1
            defaults = DefaultChar[gender][1]
        end

        local upperIndex = math.max(1, tonumber(pedData.upperbody) or 1)
        local lowerIndex = math.max(1, tonumber(pedData.lowerbody) or 1)
        local defaultBody = defaults.Body[upperIndex] or defaults.Body[1]
        local defaultLegs = defaults.Legs[lowerIndex] or defaults.Legs[1]

        local skin = deepCopy(PlayerSkin)
        skin.sex = gender == 'Male' and 'mp_male' or 'mp_female'
        skin.albedo = GetHashKey(defaults.HeadTexture[1])
        skin.HeadType = tonumber(data.headType) or tonumber('0x' .. tostring(defaults.Heads[tonumber(pedData.head) or 1] or defaults.Heads[1])) or 0
        skin.BodyType = tonumber(data.body) or tonumber('0x' .. tostring(defaultBody)) or 0
        skin.LegsType = tonumber(data.legs) or tonumber('0x' .. tostring(defaultLegs)) or 0
        skin.Torso = skin.BodyType
        skin.Eyes = tonumber((Eyes[gender] or {})[math.max(1, tonumber(pedData.eyes) or 1)]) or (gender == 'Male' and 612262189 or 928002221)
        skin.Body = tonumber(Body[math.max(1, tonumber(pedData.body) or 1)]) or tonumber(Body[1]) or 0
        skin.Waist = tonumber(Waist[math.max(1, tonumber(pedData.waist) or 1)]) or tonumber(Waist[1]) or 0
        local teethEntry = (Teeth[gender] or {})[math.max(1, tonumber(pedData.teeth) or 1)]
        skin.Teeth = teethEntry and tonumber(teethEntry.hash or teethEntry.hash_dec_signed) or -1
        skin.Scale = resolveCreatorScale(pedData.height)
        skin.Hair = -1
        skin.Beard = -1

        for expressionName, legacyField in pairs(legacyExpressionMap or {}) do
            local value = type(pedData.expressions) == 'table' and tonumber(pedData.expressions[expressionName]) or nil
            if value ~= nil then skin[legacyField] = value end
        end

        local overlays = overlayLayers or (data._barber and data._barber.overlays) or data.overlays or pedData.overlays
        if type(overlays) == 'table' then
            for _, layer in pairs(overlays) do
                if type(layer) == 'table' and layer.name then
                    local name = layer.name
                    local vis = tonumber(layer.visibility) or 0
                    skin[name .. '_visibility'] = vis
                    if vis > 0 then
                        skin[name .. '_tx_id'] = tonumber(layer.tx_id_index) or tonumber(layer.tx_id) or 1
                        skin[name .. '_opacity'] = tonumber(layer.opacity) or tonumber(layer.tx_opacity) or 1.0
                        if layer.palette_id ~= nil then
                            skin[name .. '_palette_id'] = tonumber(layer.palette_id) or 0
                        end
                        if layer.palette_color_primary ~= nil then
                            skin[name .. '_palette_color_primary'] = tonumber(layer.palette_color_primary) or 0
                        end
                        if layer.palette_color_secondary ~= nil then
                            skin[name .. '_palette_color_secondary'] = tonumber(layer.palette_color_secondary) or 0
                        end
                        if layer.palette_color_tertiary ~= nil then
                            skin[name .. '_palette_color_tertiary'] = tonumber(layer.palette_color_tertiary) or 0
                        end
                    end
                end
            end
        end

        return skin
    end

    legacyExpressionMap = {
        Head_Width = 'HeadSize',
        Forehead_Size = 'FaceS',
        Face_Width = 'FaceW',
        Neck_Width = 'NeckW',
        Neck_Depth = 'NeckD',
        Brows_Height = 'EyeBrowH',
        Brows_Width = 'EyeBrowW',
        Brows_Depth = 'EyeBrowD',
        Eyes_Depth = 'EyeD',
        Eyes_Angle = 'EyeAng',
        Eyes_Distance = 'EyeDis',
        Eyes_Height = 'EyeH',
        Eyelid_Height = 'EyeLidH',
        Eyelid_Width = 'EyeLidW',
        Eyelid_Left_Opening = 'EyeLidL',
        Eyelid_Right_Opening = 'EyeLidR',
        Ears_Width = 'EarsW',
        Ears_Angle = 'EarsA',
        Ears_Height = 'EarsH',
        Ears_Depth = 'EarsD',
        CheekBone_Height = 'CheekBonesH',
        CheekBone_Width = 'CheekBonesW',
        CheekBone_Depth = 'CheekBonesD',
        Jaw_Height = 'JawH',
        Jaw_Width = 'JawW',
        Jaw_Depth = 'JawD',
        Chin_Height = 'ChinH',
        Chin_Width = 'ChinW',
        Chin_Depth = 'ChinD',
        Nose_Width = 'NoseW',
        Nose_Size = 'NoseS',
        Nose_Height = 'NoseH',
        Nose_Angle = 'NoseAng',
        Nose_Curvature = 'NoseC',
        Nose_Distance = 'NoseDis',
        Mouth_Width = 'MouthW',
        Mouth_Depth = 'MouthD',
        Mouth_DistanceX = 'MouthX',
        Mouth_DistanceY = 'MouthY',
        Lip_Upper_Height = 'ULiphH',
        Lip_Upper_Width = 'ULiphW',
        Lip_Upper_Depth = 'ULiphD',
        Lip_Lower_Height = 'LLiphH',
        Lip_Lower_Width = 'LLiphW',
        Lip_Lower_Depth = 'LLiphD',
        Mouth_Corner_Left_Withd = 'MouthCLW',
        Mouth_Corner_Right_Withd = 'MouthCRW',
        Mouth_Corner_Left_Depth = 'MouthCLD',
        Mouth_Corner_Right_Depth = 'MouthCRD',
        Mouth_Corner_Left_Height = 'MouthCLH',
        Mouth_Corner_Right_Height = 'MouthCRH',
        Mouth_Corner_Left_Lips_Distance = 'MouthCLLD',
        Mouth_Corner_Right_Lips_Distance = 'MouthCRLD',
        Arms_Size = 'ArmsS',
        Upper_Shoulders_Size = 'ShouldersS',
        Back_Shoulders_Thickness = 'ShouldersT',
        Back_Muscles = 'ShouldersM',
        Chest_Size = 'ChestS',
        Tights_Size = 'LegsS',
        Calves_Size = 'CalvesS',
        Waist_Width = 'WaistW',
        Hips_Size = 'HipsS',
    }

    local function hashesMatch(left, right)
        left = tonumber(left)
        right = tonumber(right)
        if not left or not right then return false end
        if left == right then return true end
        if left < 0 then left = left + 4294967296 end
        if right < 0 then right = right + 4294967296 end
        return left == right
    end

    local function hexHash(value)
        if value == nil then return nil end
        return tonumber('0x' .. tostring(value))
    end

    local function findHashIndex(values, target, valuesAreHex)
        if type(values) ~= 'table' then return 1 end
        for index, value in ipairs(values) do
            local candidate = value
            if type(value) == 'table' then
                candidate = value.hash or value.hash_dec_signed
            elseif valuesAreHex then
                candidate = hexHash(value)
            end
            if hashesMatch(candidate, target) then return index end
        end
        return 1
    end

    function BuildCreatorPedDataFromLegacy(skin)
        skin = type(skin) == 'table' and skin or {}
        local sex = tostring(skin.sex or 'mp_male')
        local gender = sex == 'mp_female' and 'Female' or 'Male'
        local pedData = {
            expressions = {},
            gender = gender,
            pedmodel = { model = sex ~= '' and sex or (gender == 'Male' and 'mp_male' or 'mp_female'), outfit = 0 },
            skintone = 1,
            head = 1,
            teeth = 1,
            eyes = 1,
            body = 1,
            waist = 1,
            upperbody = 1,
            lowerbody = 1,
            height = resolveCreatorScale(skin.Scale),
        }

        for index, colorSet in ipairs(DefaultChar[gender] or {}) do
            if colorSet.HeadTexture and hashesMatch(GetHashKey(colorSet.HeadTexture[1]), skin.albedo) then
                pedData.skintone = index
                break
            end
        end

        local defaults = DefaultChar[gender] and (DefaultChar[gender][pedData.skintone] or DefaultChar[gender][1]) or nil
        if defaults then
            pedData.head = findHashIndex(defaults.Heads, skin.HeadType, true)
            pedData.upperbody = findHashIndex(defaults.Body, skin.BodyType or skin.Torso, true)
            pedData.lowerbody = findHashIndex(defaults.Legs, skin.LegsType, true)
        end

        pedData.body = findHashIndex(Body, skin.Body, false)
        pedData.waist = findHashIndex(Waist, skin.Waist, false)
        pedData.eyes = findHashIndex(Eyes[gender], skin.Eyes, false)

        for expressionName, legacyField in pairs(legacyExpressionMap) do
            local value = tonumber(skin[legacyField])
            if value ~= nil then pedData.expressions[expressionName] = value end
        end

        return pedData
    end

    -- A character with no jrs_character_creator row (left behind by a creation
    -- that threw mid-save) used to reach the client with empty peddata. The
    -- client then fell back to the legacy ReloadCloth path, which drops
    -- bodies_lower and spawns the player with no legs. Rebuild it from
    -- skinPlayer instead, the same way GetPedData already does.
    function ResolveCreatorPedData(rawPedData, legacySkin)
        local pedData = decode(rawPedData, {})
        if next(pedData) ~= nil then return pedData end

        legacySkin = decode(legacySkin, {})
        if next(legacySkin) ~= nil then
            return BuildCreatorPedDataFromLegacy(legacySkin)
        end
        return {}
    end

    local LAST_LOCATION_POINTS = {
        { name = 'Valentine',          x = -281.2,  y = 806.0 },
        { name = 'Saint Denis',        x = 2512.0,  y = -1305.0 },
        { name = 'Blackwater',         x = -875.0,  y = -1325.0 },
        { name = 'Rhodes',             x = 1232.0,  y = -1291.0 },
        { name = 'Strawberry',         x = -1777.0, y = -428.0 },
        { name = 'Armadillo',          x = -3664.0, y = -2612.0 },
        { name = 'Tumbleweed',         x = -5514.0, y = -2940.0 },
        { name = 'Annesburg',          x = 2935.0,  y = 1280.0 },
        { name = 'Van Horn',           x = 2983.0,  y = 565.0 },
        { name = 'Emerald Ranch',      x = 1421.0,  y = 322.0 },
        { name = 'Lagras',             x = 2123.0,  y = -637.0 },
        { name = 'Wapiti Reservation', x = 453.0,   y = 2210.0 },
        { name = 'Colter',             x = -1346.0, y = 2407.0 },
        { name = 'Manzanita Post',     x = -1981.0, y = -1648.0 },
        { name = "MacFarlane's Ranch", x = -2339.0, y = -2374.0 },
        { name = "Thieves' Landing",   x = -1410.0, y = -2294.0 },
        { name = 'Benedict Point',     x = -5225.0, y = -3471.0 },
        { name = 'Wallace Station',    x = -1294.0, y = 395.0 },
        { name = 'Riggs Station',      x = -1098.0, y = -575.0 },
    }

    local function resolveLastLocation(rawCoords)
        local coords = type(rawCoords) == 'table' and rawCoords or {}
        local x = tonumber(coords.x or coords[1])
        local y = tonumber(coords.y or coords[2])
        if not x or not y then return 'Unknown' end

        local closestName, closestDistance
        for _, point in ipairs(LAST_LOCATION_POINTS) do
            local dx, dy = x - point.x, y - point.y
            local distance = (dx * dx) + (dy * dy)
            if not closestDistance or distance < closestDistance then
                closestDistance = distance
                closestName = point.name
            end
        end

        return closestName or 'Unknown'
    end

    local function loadCharacters(source, attempt)
        source = tonumber(source)
        attempt = tonumber(attempt) or 0
        if not source or not GetPlayerName(source) then return end

        -- Ignore stray selector requests after a character has already been
        -- accepted. Character switching clears readiness before requesting the list.
        if core and type(core.isCharacterReady) == 'function' and core.isCharacterReady(source) then
            return
        end

        -- Opening the selector means the previously active character is no
        -- longer being played. Save its session before listing characters.
        persistAgingSession(source, false)

        local identifier = getIdentifier(source)
        local user = getUser(source)
        if not identifier or not user then
            if attempt < 40 then
                SetTimeout(250, function()
                    loadCharacters(source, attempt + 1)
                end)
            else
                notify(source, _Up(source, 'ch_character_data_is_not_ready_reconnect'), 6000)
            end
            return
        end

        PutPlayerinInstance(source)

        local rows = MySQL.query.await([[
            SELECT c.*,
                   DATE_FORMAT(c.dateofbirth, '%Y-%m-%d') AS dateofbirth,
                   cc.peddata AS creatorPedData,
                   cc.informations AS creatorInformations,
                   jc.clothes AS currentClothes,
                   jc.outfit_id AS currentOutfitId,
                   jb.hairstyle AS currentHairstyle,
                   jb.overlays AS currentBarberOverlays,
                   jb.permanentoverlay AS currentBarberPermanent,
                   jb.outfit_id AS currentBarberOutfitId,
                   jas.scale AS adminCharacterScale
            FROM jrs_characters c
            LEFT JOIN jrs_character_creator cc ON cc.charid = c.charidentifier
            LEFT JOIN jrs_clothing_current jc ON jc.charid = c.charidentifier
            LEFT JOIN jrs_barber jb ON jb.charid = c.charidentifier
            LEFT JOIN jrs_admin_character_scale jas ON jas.character_id = c.charidentifier
            WHERE c.identifier = ?
            ORDER BY c.charidentifier ASC
        ]], { identifier }) or {}

        local characters = {}
        local characterCount = 0
        for _, row in ipairs(rows) do
            local charid = tonumber(row.charidentifier)
            local skin = decode(row.skinPlayer, {})
            local savedCoords = decode(row.coords, {})
            local components = decode(row.currentClothes, nil)
            local profileInfo = decode(row.creatorInformations, {
                lore = '', birthday = '', birthmonth = '', birthyear = '', birthdate = '',
                nickname = '', occupation = ''
            })

            local storedBirthDate = tostring(row.dateofbirth or profileInfo.birthdate or '')
            local normalizedBirthDate, birthDay, birthMonth, birthYear = normalizeBirthDate(storedBirthDate)
            if normalizedBirthDate then
                local minAge = math.max(1, math.floor(tonumber(Config and Config.MinimumAge) or 18))
                local bYear = tonumber(birthYear)
                local currentYear = (type(worldToday) == 'function' and worldToday().year) or (Config and Config.WorldDate and tonumber(Config.WorldDate.year)) or 1899
                if bYear and (currentYear - bYear) < minAge then
                    bYear = currentYear - minAge
                    birthYear = tostring(bYear)
                    normalizedBirthDate = ('%04d-%02d-%02d'):format(bYear, tonumber(birthMonth) or 1, tonumber(birthDay) or 1)
                end
                profileInfo.birthdate = normalizedBirthDate
                profileInfo.birthday = birthDay
                profileInfo.birthmonth = birthMonth
                profileInfo.birthyear = birthYear
            end
            profileInfo.nickname = tostring(row.nickname or profileInfo.nickname or '')
            profileInfo.occupation = tostring(row.occupation or profileInfo.occupation or '')
            local aging = getLiveAgingSnapshot(source, charid, identifier, profileInfo.birthdate, row)
            if not components or next(components) == nil then
                components = decode(row.compPlayer, {})
            end
            if charid then characterCount = characterCount + 1 end
            local peddata = ResolveCreatorPedData(row.creatorPedData, skin)
            -- Resolve authoritative height: admin-set scale takes priority over
            -- creator peddata.height, which itself takes priority over legacy skin.Scale.
            local adminScale    = tonumber(row.adminCharacterScale)
            local creatorHeight = type(peddata) == 'table' and tonumber(peddata.height) or nil
            local skinScale     = tonumber(skin.Scale)
            local finalHeight   = adminScale or creatorHeight or skinScale or 1.0
            if finalHeight <= 0 then finalHeight = 1.0 end
            -- Patch peddata.height so FinalizeCharacter also uses the correct value.
            if type(peddata) == 'table' then peddata.height = finalHeight end
            characters[charid] = {
                charIdentifier = charid,
                money = tonumber(row.money) or 0,
                gold = tonumber(row.gold) or 0,
                dirtymoney = tonumber(row.dirtymoney) or 0,
                firstname = row.firstname or '',
                lastname = row.lastname or '',
                skin = skin,
                components = components,
                coords = savedCoords,
                lastLocation = resolveLastLocation(savedCoords),
                isDead = tonumber(row.isdead) or 0,
                job = row.job or 'unemployed',
                grade = tonumber(row.jobgrade) or 0,
                group = GetCharGroup(source),
                age = aging.ageYears,
                baseAge = aging.baseAge,
                playtimeSeconds = aging.playtimeSeconds,
                playtimeHours = math.floor((aging.playtimeSeconds / 3600) * 10) / 10,
                hoursPerYear = tonumber(Config and Config.HoursPerYear) or 100,
                nickname = profileInfo.nickname,
                occupation = profileInfo.occupation,
                dateofbirth = profileInfo.birthdate,
                gender = skin.sex == 'mp_female' and 'Female' or 'Male',
                charDesc = '',
                peddata = peddata,
                height = finalHeight,
                barber = {
                    hairstyle = decode(row.currentHairstyle, {}),
                    overlays = decode(row.currentBarberOverlays, {}),
                    permanentoverlay = decode(row.currentBarberPermanent, {}),
                    outfit_id = row.currentBarberOutfitId
                },
                informations = profileInfo,
            }
        end

        -- A selector request may have started before the player pressed Play
        -- and finish after jrs_core has already accepted the character. Never
        -- let that stale response reopen the selector or put the player back in
        -- the character routing bucket. This also covers a restart of THIS
        -- resource alone (jrs_core untouched) while an already-playing
        -- character stays connected: the client script reloads from scratch
        -- and its own bootstrap re-requests the list, but jrs_core still says
        -- the character is ready, so the selector/creator must never reopen.
        -- Tell the client explicitly instead of silently doing nothing - its
        -- fresh script state defaults to the character gate being ACTIVE
        -- (frozen controls, hidden HUD/radar) until told otherwise, and no
        -- other event ever reaches an already-ready character to release it.
        if core and type(core.isCharacterReady) == 'function' and core.isCharacterReady(source) then
            RemovePlayerFromInstance(source)
            TriggerClientEvent('jrs_character_creator:AlreadyReady', source)
            return
        end

        local slotLimit = getSlotLimit(source)
        TriggerClientEvent('jrs_character_creator:LaunchCharSelect', source,
            characters, getPedPermission(source), slotLimit, characterCount)
    end

    RegisterNetEvent('jrs_character_creator:getCharacters', function()
        local src = tonumber(source)
        if not JRSAllowRequest(src, 'get_characters', 6, 5000) then return end
        loadCharacters(src, 0)
    end)

    -- The creator now includes clothing and barber editors. Final spawn only
    -- leaves the private selector routing bucket and clears stale onboarding
    -- rows created by older releases; it never opens external customization UIs.
    RegisterNetEvent('jrs_character_creator:spawnFinalized', function(expectedCharId)
        local src = tonumber(source)
        if not JRSAllowRequest(src, 'spawn_finalized', 6, 10000) then return end
        if not src then return end

        local activeCharId = tonumber(GetCharIdentifier(src))
        expectedCharId = tonumber(expectedCharId)
        if not activeCharId or (expectedCharId and expectedCharId ~= activeCharId) then return end

        RemovePlayerFromInstance(src)
    end)

    RegisterNetEvent('jrs_character_creator:selectCharacter', function(charIdentifier)
        local src = tonumber(source)
        if not JRSAllowRequest(src, 'select_character', 5, 8000) then return end
        -- Selection is only valid from the selector. With a character already
        -- loaded, a client firing this hot-swapped characters and skipped the
        -- save + inventory hand-off that the admin switch path performs.
        local readyApi = jrsCore or core
        if readyApi and type(readyApi.isCharacterReady) == 'function' and readyApi.isCharacterReady(src) then
            return
        end
        local identifier = getIdentifier(src)
        local charid = tonumber(charIdentifier)
        if not src or not identifier or not charid then
            TriggerClientEvent('jrs_character_creator:SelectionFailed', src,
                _U('character_invalid_character_selection'))
            return
        end

        local row = MySQL.single.await([[
            SELECT c.*,
                   DATE_FORMAT(c.dateofbirth, '%Y-%m-%d') AS dateofbirth,
                   cc.peddata AS creatorPedData,
                   jc.clothes AS currentClothes,
                   jb.hairstyle AS currentHairstyle,
                   jb.overlays AS currentBarberOverlays,
                   jb.permanentoverlay AS currentBarberPermanent,
                   jb.outfit_id AS currentBarberOutfitId,
                   jas.scale AS adminCharacterScale
            FROM jrs_characters c
            LEFT JOIN jrs_character_creator cc ON cc.charid = c.charidentifier
            LEFT JOIN jrs_clothing_current jc ON jc.charid = c.charidentifier
            LEFT JOIN jrs_barber jb ON jb.charid = c.charidentifier
            LEFT JOIN jrs_admin_character_scale jas ON jas.character_id = c.charidentifier
            WHERE c.identifier = ? AND c.charidentifier = ?
            LIMIT 1
        ]], { identifier, charid })

        if not row then
            notify(src, _Up(src, 'ch_character_not_found'), 4000)
            TriggerClientEvent('jrs_character_creator:SelectionFailed', src,
                _U('character_character_not_found'))
            return
        end

        if not selectCoreCharacter(src, charid, row) then
            notify(src, _Up(src, 'ch_character_selection_failed_try_again'), 5000)
            TriggerClientEvent('jrs_character_creator:SelectionFailed', src,
                _U('character_character_selection_failed_please_try_again'))
            return
        end

        TriggerEvent('jrs_core:server:characterSelected', src, charid)
        if exports.jrs_core and exports.jrs_core.MarkCharacterAsExisting then
            pcall(exports.jrs_core.MarkCharacterAsExisting, charid)
        end

        local agingSnapshot = startAgingSession(src, charid, identifier, row.dateofbirth, row)
        RemovePlayerFromInstance(src)

        local components = decode(row.currentClothes, nil)
        if not components or next(components) == nil then
            components = decode(row.compPlayer, {})
        end

        local skin = decode(row.skinPlayer, {})
        local peddata = ResolveCreatorPedData(row.creatorPedData, skin)
        local adminScale = tonumber(row.adminCharacterScale)
        local creatorHeight = type(peddata) == 'table' and tonumber(peddata.height) or nil
        local skinScale = tonumber(skin.Scale)
        local finalHeight = adminScale or creatorHeight or skinScale or 1.0
        if finalHeight <= 0 then finalHeight = 1.0 end
        if type(peddata) == 'table' then peddata.height = finalHeight end

        TriggerClientEvent('jrs_character_creator:FinalizeCharacter', src, {
            charIdentifier = charid,
            skin = skin,
            components = components,
            coords = decode(row.coords, {}),
            isDead = tonumber(row.isdead) or 0,
            peddata = peddata,
            height = finalHeight,
            barber = {
                hairstyle = decode(row.currentHairstyle, {}),
                overlays = decode(row.currentBarberOverlays, {}),
                permanentoverlay = decode(row.currentBarberPermanent, {}),
                outfit_id = row.currentBarberOutfitId,
            },
            age = agingSnapshot and agingSnapshot.ageYears or nil,
        })

    end)

    local function GetEnabledSpawnBookCities()
        local book = type(Config.SpawnBook) == 'table' and Config.SpawnBook or {}
        local configuredCities = type(book.Cities) == 'table' and book.Cities or {}
        local enabled = {}

        for _, city in ipairs(configuredCities) do
            if type(city) == 'table' and city.Enabled ~= false and city.SpawnCoords then
                enabled[#enabled + 1] = city
            end
        end

        if #enabled == 0 and type(configuredCities[1]) == 'table' and configuredCities[1].SpawnCoords then
            enabled[1] = configuredCities[1]
        end

        return enabled
    end

    local function ResolveConfiguredNewCharacterSpawn(data)
        data = type(data) == 'table' and data or {}
        local cities = GetEnabledSpawnBookCities()
        local selected = nil
        local requestedKey = tostring(data.spawnLocationKey or data.SpawnLocationKey or '')

        if requestedKey ~= '' then
            for _, city in ipairs(cities) do
                if tostring(city.Key or city.key or '') == requestedKey then
                    selected = city
                    break
                end
            end
        end

        if not selected then
            local requestedId = math.floor(tonumber(data.SpawnLocationId) or 1)
            selected = cities[requestedId]
        end

        selected = selected or cities[1]
        if not selected then return nil end

        local coords = toCoords(selected.SpawnCoords)
        coords.heading = tonumber(selected.SpawnHeading) or coords.heading or 0.0
        return coords, tostring(selected.Key or selected.key or '')
    end

    -- Character row inserted by jrs_core but not yet fully saved (profile,
    -- creator, clothing, barber). If creation throws in that window the row is
    -- rolled back, otherwise the player is sent back to the selector holding a
    -- bare default character at jrs_core's DefaultSpawnCoords.
    local unfinishedNewCharacters = {}

    local function rollbackUnfinishedCharacter(pending)
        local charid = tonumber(pending and pending.charid)
        local ownerIdentifier = pending and tostring(pending.identifier or '') or ''
        if not charid or ownerIdentifier == '' then return end

        pcall(function() exports.jrs_core:RunCharacterDeleteHooks(charid, ownerIdentifier, 'before') end)
        local ok, err = pcall(function()
            return MySQL.transaction.await({
                { query = 'DELETE FROM jrs_character_creator WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_barber_preset WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_barber WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_clothing_outfits WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_clothing_current WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_characters WHERE charidentifier = ? AND identifier = ?', values = { charid, ownerIdentifier } },
            })
        end)
        if not ok or err == false then
            printconsole('Could not roll back unfinished character', charid, tostring(err))
            return
        end
        if core and type(core.RemoveCharacterFromCache) == 'function' then
            pcall(core.RemoveCharacterFromCache, charid)
        end
        pcall(function() exports.jrs_core:RunCharacterDeleteHooks(charid, ownerIdentifier, 'after') end)
        printconsole('Rolled back unfinished character', charid)
    end

    local function CreateNewCharacterImpl(source, data)
        local identifier = getIdentifier(source)
        local user = getUser(source)
        if not identifier or not user then
            creatingCharacters[source] = nil
            return false
        end

        local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM jrs_characters WHERE identifier = ?', { identifier })) or 0
        local slots = getSlotLimit(source)
        if count >= slots then
            notify(source, _Up(source, 'ch_you_have_reached_the_character_limit', count, slots), 5000)
            creatingCharacters[source] = nil
            return false
        end

        local firstname = JRSCleanText(data.firstname, 50)
        local lastname = JRSCleanText(data.lastname, 50)
        local nickname = JRSCleanText(data.nickname, 50)
        local occupation = JRSCleanText(data.occupation, 80)
        data.lore = JRSCleanText(data.lore, 4000)
        local birthdate, birthDay, birthMonth, birthYear = normalizeBirthDate(data.birthdate)

        if type(data._pedData) ~= 'table' or not JRSJsonWithinLimit(data._pedData, 262144) then
            creatingCharacters[source] = nil
            return false
        end
        if data._clothes ~= nil and (type(data._clothes) ~= 'table' or not JRSJsonWithinLimit(data._clothes, 262144)) then
            creatingCharacters[source] = nil
            return false
        end
        if data._barber ~= nil and (type(data._barber) ~= 'table' or not JRSJsonWithinLimit(data._barber, 262144)) then
            creatingCharacters[source] = nil
            return false
        end

        data.gender = data.gender == 'Female' and 'Female' or 'Male'
        local pedModel = type(data._pedData.pedmodel) == 'table' and tostring(data._pedData.pedmodel.model or '') or ''
        if pedModel == '' or #pedModel > 80 or not pedModel:match('^[%w_]+$') then
            creatingCharacters[source] = nil
            return false
        end
        if getPedPermission(source) ~= true and pedModel ~= 'mp_male' and pedModel ~= 'mp_female' then
            creatingCharacters[source] = nil
            return false
        end

        if firstname == '' or lastname == '' then
            notify(source, _Up(source, 'ch_first_name_and_last_name_are'), 5000)
            creatingCharacters[source] = nil
            return false
        end
        if not birthdate then
            notify(source, _Up(source, 'ch_a_valid_date_of_birth_is'), 5000)
            creatingCharacters[source] = nil
            return false
        end
        -- Authoritative check: the client validates this too, but only the
        -- server can be trusted not to skip it.
        if calculateBaseAge(birthdate) < Config.MinimumAge then
            notify(source, _Up(source, 'ch_your_character_must_be_at_least', Config.MinimumAge), 6000)
            creatingCharacters[source] = nil
            return false
        end

        local function hasAnyClothingModel(clothesTable)
            if type(clothesTable) ~= 'table' then return false end
            for _, item in pairs(clothesTable) do
                if type(item) == 'table' and (tonumber(item.model) or 0) > 0 then
                    return true
                end
            end
            return false
        end

        local skin = BuildJRSBaseSkin(data)
        local creatorClothes = type(data._clothes) == 'table' and data._clothes or nil
        local components
        if creatorClothes and hasAnyClothingModel(creatorClothes) then
            components = creatorClothes
        else
            local seed = math.random(1, 1000)
            local gender = (data.gender == 'Female' and 'female' or 'male')
            components = GetDiverseStarterClothing(gender, seed)
        end
        -- Never trust arbitrary client coordinates for a new character. Resolve
        -- the selected page against the enabled cities in the shared config.
        local coords, selectedSpawnKey = ResolveConfiguredNewCharacterSpawn(data)
        if not coords then
            notify(source, _Up(source, 'ch_no_enabled_character_spawn_city_is'), 6000)
            creatingCharacters[source] = nil
            return false
        end
        data.spawnLocationKey = selectedSpawnKey
        local completed, success, newCharId = false, false, nil

        core.addCharacter(source, firstname, lastname, json.encode(skin), json.encode(components), function(ok, charid)
            success = ok == true and tonumber(charid) ~= nil
            newCharId = tonumber(charid)
            completed = true
        end)

        local timeout = GetGameTimer() + 15000
        while not completed and GetGameTimer() < timeout do Wait(0) end
        if not success or not newCharId then
            creatingCharacters[source] = nil
            notify(source, _Up(source, 'ch_character_creation_failed'), 5000)
            return false
        end
        unfinishedNewCharacters[source] = { charid = newCharId, identifier = identifier }

        TriggerEvent('jrs_core:server:characterCreated', source, newCharId, identifier)
        if exports.jrs_core and exports.jrs_core.MarkCharacterAsNew then
            pcall(exports.jrs_core.MarkCharacterAsNew, newCharId)
        end

        ensureCoordsColumnCapacity()
        if not profileColumnsReady then ensureCharacterProfileColumns() end
        ensureCharacterAgingColumns()

        if profileColumnsReady then
            MySQL.update.await([[
                UPDATE jrs_characters
                SET coords = ?, dateofbirth = ?, nickname = ?, occupation = ?, gender = ?, character_desc = ?
                WHERE identifier = ? AND charidentifier = ?
            ]], {
                encodeCoordsForDatabase(coords), birthdate, nickname, occupation,
                (data.gender == 'Female' and 'female' or 'male'), JRSCleanText(data.lore or '', 512),
                identifier, newCharId
            })
        else
            -- Creation still succeeds if the database account cannot ALTER the
            -- schema; the profile is retained in jrs_character_creator and the
            -- included migration SQL can be imported later.
            MySQL.update.await(
                'UPDATE jrs_characters SET coords = ? WHERE identifier = ? AND charidentifier = ?',
                { encodeCoordsForDatabase(coords), identifier, newCharId }
            )
        end

        if agingColumnsReady then
            local baseAge = calculateBaseAge(birthdate)
            MySQL.update.await([[
                UPDATE jrs_characters
                SET base_age = ?, age_years = ?, playtime_seconds = 0
                WHERE identifier = ? AND charidentifier = ?
            ]], { baseAge, baseAge, identifier, newCharId })
        end

        MySQL.query.await([[
            INSERT INTO jrs_character_creator (charid, peddata, informations)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                peddata = VALUES(peddata),
                informations = VALUES(informations)
        ]], {
            newCharId,
            json.encode(data._pedData or {}),
            json.encode({
                lore = data.lore or '',
                birthdate = birthdate,
                birthday = birthDay,
                birthmonth = birthMonth,
                birthyear = birthYear,
                nickname = nickname,
                occupation = occupation
            })
        })

        -- Save the creator's independent clothing editor to the same tables
        -- used by jrs_clothing. The regular clothing resource will load it on
        -- every later login without opening its shop UI during creation.
        local clothingJson = json.encode(components or {})
        local clothingOutfitId = 'creator_default_' .. tostring(newCharId)
        local clothingGender = data.gender == 'Female' and 'female' or 'male'
        MySQL.query.await([[
            INSERT INTO jrs_clothing_current (charid, clothes, outfit_id)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                clothes = VALUES(clothes),
                outfit_id = VALUES(outfit_id)
        ]], { newCharId, clothingJson, clothingOutfitId })
        MySQL.query.await([[
            INSERT INTO jrs_clothing_outfits
                (charid, outfit_id, price, name, clothes, singleitems, gender)
            VALUES (?, ?, 0, 'Default', ?, '{}', ?)
            ON DUPLICATE KEY UPDATE
                charid = VALUES(charid),
                price = 0,
                name = 'Default',
                clothes = VALUES(clothes),
                singleitems = '{}',
                gender = VALUES(gender)
        ]], { newCharId, clothingOutfitId, clothingJson, clothingGender })

        -- Save the creator's independent hair/barber editor to the same tables
        -- used by jrs_barber.
        local barberData = type(data._barber) == 'table' and data._barber or {}
        local hairstyleData = type(barberData.hairstyle) == 'table' and barberData.hairstyle or {}
        if not hasAnyClothingModel(hairstyleData) then
            local seed = tonumber(newCharId) or math.random(1, 1000)
            local gender = (data.gender == 'Female' and 'female' or 'male')
            hairstyleData = GetDiverseStarterBarber(gender, seed)
        end
        local hairstyleJson = json.encode(hairstyleData)
        local overlaysJson = json.encode(type(barberData.overlays) == 'table' and barberData.overlays or {})
        local permanentJson = json.encode(type(barberData.permanentoverlay) == 'table' and barberData.permanentoverlay or {})
        local barberOutfitId = GenerateJRSBarberOutfitId()
        MySQL.query.await([[
            INSERT INTO jrs_barber (charid, hairstyle, overlays, permanentoverlay, outfit_id)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                hairstyle = VALUES(hairstyle),
                overlays = VALUES(overlays),
                permanentoverlay = VALUES(permanentoverlay),
                outfit_id = VALUES(outfit_id)
        ]], { newCharId, hairstyleJson, overlaysJson, permanentJson, barberOutfitId })
        MySQL.query.await([[
            INSERT INTO jrs_barber_preset
                (charid, outfit_id, price, name, hairstyle, overlays, gender)
            VALUES (?, ?, 0, 'Base', ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                charid = VALUES(charid),
                price = 0,
                name = 'Base',
                hairstyle = VALUES(hairstyle),
                overlays = VALUES(overlays),
                gender = VALUES(gender)
        ]], { newCharId, barberOutfitId, hairstyleJson, overlaysJson, clothingGender })

        pcall(function() exports.jrs_core:RefreshAppearanceCache(newCharId) end)
        -- Every row is saved; from here the character is complete and must stay.
        unfinishedNewCharacters[source] = nil

        local coreCharacterRow = MySQL.single.await(
            'SELECT * FROM jrs_characters WHERE identifier = ? AND charidentifier = ? LIMIT 1',
            { identifier, newCharId }
        )

        if not selectCoreCharacter(source, newCharId, coreCharacterRow) then
            creatingCharacters[source] = nil
            notify(source, _Up(source, 'ch_character_was_created_but_could_not'), 6000)
            return false
        end

        local agingSnapshot = startAgingSession(source, newCharId, identifier, birthdate, coreCharacterRow)
        RemovePlayerFromInstance(source)
        creatingCharacters[source] = nil

        local payload = {
            charIdentifier = newCharId,
            skin = skin,
            components = components,
            coords = coords,
            isDead = 0,
            peddata = type(data._pedData) == 'table' and data._pedData or {},
            -- Same shape as the selectCharacter payload, so the first spawn
            -- applies hair/beard before reveal instead of the async fallback.
            barber = {
                hairstyle = type(barberData.hairstyle) == 'table' and barberData.hairstyle or {},
                overlays = type(barberData.overlays) == 'table' and barberData.overlays or {},
                permanentoverlay = type(barberData.permanentoverlay) == 'table' and barberData.permanentoverlay or {},
                outfit_id = barberOutfitId,
            },
            age = agingSnapshot and agingSnapshot.ageYears or nil,
        }

        -- Finalization must not depend only on the custom callback response.
        -- A focus change or another resource can interrupt that callback while
        -- the character has already been created and selected in jrs_core.
        TriggerClientEvent('jrs_character_creator:FinalizeCharacter', source, payload)
        return payload
    end

    function CreateNewCharacter(src, data)
        local source = tonumber(src)
        if not source or creatingCharacters[source] then return false end
        creatingCharacters[source] = true

        -- Run the actual creation under pcall so an unexpected error (a bad
        -- ped/skin field, a DB hiccup, jrs_core/jrs_clothing/jrs_barber
        -- returning a stale or missing export after one of them restarts,
        -- etc) cannot skip the cleanup below. Before this fix, any uncaught
        -- error inside creation left creatingCharacters[source] stuck true
        -- for the rest of that connection: every later "Create Character"
        -- click then returned false instantly and silently (the guard on the
        -- line above), so the player could never create a character again
        -- without fully reconnecting. That matches the recurring "character
        -- creation just doesn't work" reports - one bad attempt permanently
        -- soft-locked further attempts in the same session.
        unfinishedNewCharacters[source] = nil
        local ok, result = xpcall(CreateNewCharacterImpl, function(err)
            return debug and debug.traceback(tostring(err), 2) or tostring(err)
        end, source, data)
        creatingCharacters[source] = nil
        local unfinished = unfinishedNewCharacters[source]
        unfinishedNewCharacters[source] = nil

        if not ok then
            printconsole('CreateNewCharacter error:', tostring(result))
            if unfinished then rollbackUnfinishedCharacter(unfinished) end
            notify(source, _Up(source, 'ch_character_creation_failed'), 5000)
            return false
        end

        return result
    end

    local function canDelete(source)
        if CreatorConfig.CharacterDeletion.enabled ~= true then return false end
        if CreatorConfig.CharacterDeletion.restrictToRoles ~= true then return true end
        local identifier = getIdentifier(source)
        if identifier and CreatorConfig.CharacterDeletion.identifier[identifier] == true then return true end
        return CreatorConfig.CharacterDeletion.role[GetCharGroup(source)] == true
    end

    local function deleteCharacter(charid)
        charid = tonumber(charid)
        if not charid then return false end

        local charRow = MySQL.single.await(
            'SELECT identifier, charidentifier FROM jrs_characters WHERE charidentifier = ? LIMIT 1',
            { charid }
        )
        local ownerIdentifier = charRow and tostring(charRow.identifier or '') or ''
        if not charRow then return false end

        local hooksOk = true
        local okHooks, resultHooks = pcall(function()
            return exports.jrs_core:RunCharacterDeleteHooks(charid, ownerIdentifier, 'before')
        end)
        if okHooks and resultHooks == false then hooksOk = false end
        if not okHooks then hooksOk = false end
        if not hooksOk then
            print(('^1[jrs_character] delete hook rejected character %s^0'):format(charid))
            return false
        end

        -- Delete from optional integration tables safely (won't abort if table is missing)
        pcall(function() MySQL.query.await('DELETE FROM jrs_clothing_wearables WHERE charid = ?', { charid }) end)
        pcall(function() MySQL.query.await('DELETE FROM jrs_appearance_legacy_backup WHERE charid = ?', { charid }) end)
        pcall(function() MySQL.query.await('DELETE FROM jrs_idcard WHERE charid = ?', { tostring(charid) }) end)
        pcall(function() MySQL.query.await('DELETE FROM jrs_id_numbers WHERE charid = ?', { tostring(charid) }) end)

        local ok, deleted = pcall(function()
            return MySQL.transaction.await({
                { query = 'DELETE FROM jrs_character_creator WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_barber_preset WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_barber WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_clothing_outfits WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_clothing_current WHERE charid = ?', values = { charid } },
                { query = 'DELETE FROM jrs_characters WHERE charidentifier = ? AND identifier = ?', values = { charid, ownerIdentifier } },
            })
        end)
        deleted = (ok == true and deleted == true)
        if deleted and core and type(core.RemoveCharacterFromCache) == 'function' then
            core.RemoveCharacterFromCache(charid)
        end
        if deleted then
            pcall(function() exports.jrs_core:RunCharacterDeleteHooks(charid, ownerIdentifier, 'after') end)
            TriggerEvent('jrs_pedmenu:server:characterDeleted', charid)
            TriggerEvent('jrs_core:server:characterDeleted', charid, ownerIdentifier)
        end
        return deleted == true
    end

    -- Server-only APIs used by jrs_admin. Permission checks stay in jrs_admin;
    -- jrs_character performs ownership/readiness checks and owns lifecycle changes.
    exports('AdminOpenCharacterEditor', function(playerSource, durationMs)
        local target = tonumber(playerSource)
        if not target or not GetPlayerName(target) then return false, 'player_not_found' end
        if not getActiveCharacter(target) then return false, 'character_not_ready' end
        if not JRSOpenCreatorEditSession(target, durationMs) then return false, 'session_failed' end
        TriggerClientEvent('jrs_character:adminPrepareCharacterEditor', target)
        return true
    end)

    exports('AdminOpenCharacterSelector', function(playerSource, durationMs)
        local target = tonumber(playerSource)
        if not target or not GetPlayerName(target) then return false, 'player_not_found' end
        if not getActiveCharacter(target) then return false, 'character_not_ready' end
        local token = JRSCreateAdminSelectorSession(target, durationMs)
        if not token then return false, 'session_failed' end
        TriggerClientEvent('jrs_character:adminOpenSelector', target, token)
        return true
    end)

    exports('AdminDeleteActiveCharacter', function(playerSource)
        local target = tonumber(playerSource)
        if not target or not GetPlayerName(target) then return false, 'player_not_found' end

        local character = getActiveCharacter(target)
        local charid = character and tonumber(character.charIdentifier) or nil
        local identifier = getIdentifier(target)
        if not charid or not identifier then return false, 'character_not_ready' end

        local owned = MySQL.scalar.await(
            'SELECT 1 FROM jrs_characters WHERE identifier = ? AND charidentifier = ? LIMIT 1',
            { identifier, charid }
        )
        if not owned then return false, 'character_not_owned' end

        persistAgingSession(target, false)
        TriggerEvent('jrs_inventory:server:prepareCharacterSwitch', target)
        if not deleteCharacter(charid) then return false, 'delete_failed' end

        if core and type(core.ClearCharacter) == 'function' then
            core.ClearCharacter(target, 'admin_delete_character')
        end

        SetTimeout(300, function()
            if GetPlayerName(target) then loadCharacters(target, 0) end
        end)
        return true
    end)

    RegisterNetEvent('jrs_character_creator:deleteCharacter', function(charIdentifier)
        local src = tonumber(source)
        if not JRSAllowRequest(src, 'delete_character', 2, 8000) then return end
        local charid = tonumber(charIdentifier)
        local identifier = getIdentifier(src)
        if not canDelete(src) then
            notify(src, _Up(src, 'ch_character_deletion_is_disabled'), 5000)
            return
        end
        local owned = MySQL.scalar.await('SELECT 1 FROM jrs_characters WHERE identifier = ? AND charidentifier = ? LIMIT 1', {
            identifier, charid
        })
        if not owned then
            notify(src, _Up(src, 'ch_character_not_found'), 4000)
            return
        end
        -- Never delete the character that is loaded in the world right now.
        if tonumber(GetCharIdentifier(src)) == charid then
            local readyApi = jrsCore or core
            if readyApi and type(readyApi.isCharacterReady) == 'function' and readyApi.isCharacterReady(src) then
                notify(src, _Up(src, 'ch_character_deletion_failed'), 5000)
                return
            end
        end
        if not deleteCharacter(charid) then
            notify(src, _Up(src, 'ch_character_deletion_failed'), 5000)
            return
        end
        notify(src, _Up(src, 'ch_character_deleted_successfully'), 4000)
        SetTimeout(300, function() if GetPlayerName(src) then loadCharacters(src, 0) end end)
    end)

    Callback.register('jrs_character_creator:GetCharSkinTone', function(source, male, characterid)
        local charid = tonumber(characterid) or GetCharIdentifier(source)
        local identifier = getIdentifier(source)
        if not charid or not identifier then return 0 end
        local row = MySQL.single.await([[
            SELECT cc.peddata, c.skinPlayer
            FROM jrs_characters c
            LEFT JOIN jrs_character_creator cc ON cc.charid = c.charidentifier
            WHERE c.identifier = ? AND c.charidentifier = ? LIMIT 1
        ]], { identifier, charid })
        if not row then return 0 end
        local peddata = decode(row.peddata, {})
        if next(peddata) and peddata.skintone then
            local gender = male and 'Male' or 'Female'
            local set = DefaultChar[gender] and DefaultChar[gender][tonumber(peddata.skintone) or 1]
            if set then return GetHashKey(set.HeadTexture[1]) end
        end
        local skin = decode(row.skinPlayer, {})
        return tonumber(skin.albedo) or 0
    end)

    local function hasAdminPermission(source, commandConfig)
        if source == 0 then return true end
        local group = GetCharGroup(source)
        for _, role in ipairs(commandConfig.allowedRoles or {}) do
            if role == group then return true end
        end
        local ids = GetPlayerIdentifiers(source)
        for _, playerId in ipairs(ids) do
            for _, allowed in ipairs(commandConfig.allowedIdentifiers or {}) do
                if playerId == allowed then return true end
            end
        end
        return false
    end

    if CreatorConfig.Commands.deleteCharacter.enabled then
        RegisterCommand(CreatorConfig.Commands.deleteCharacter.command, function(source, args)
            if not hasAdminPermission(source, CreatorConfig.Commands.deleteCharacter) then
                notify(source, _Up(source, 'ch_you_do_not_have_permission'), 4000)
                return
            end
            local charid = tonumber(args[1])
            if not charid then
                notify(source, _Up(source, 'ch_usage_charidentifier', CreatorConfig.Commands.deleteCharacter.command), 5000)
                return
            end
            local row = MySQL.single.await('SELECT firstname, lastname FROM jrs_characters WHERE charidentifier = ? LIMIT 1', { charid })
            if not row then
                notify(source, _Up(source, 'ch_character_not_found'), 4000)
                return
            end
            if not deleteCharacter(charid) then
                notify(source, _Up(source, 'ch_character_deletion_failed'), 5000)
                return
            end
            notify(source, _Up(source, 'ch_deleted_id', row.firstname or '', row.lastname or '', charid), 5000)
        end, false)
    end

    if CreatorConfig.Commands.secondChance.enabled then
        RegisterCommand(CreatorConfig.Commands.secondChance.command, function(source, args)
            if not hasAdminPermission(source, CreatorConfig.Commands.secondChance) then
                notify(source, _Up(source, 'ch_you_do_not_have_permission'), 4000)
                return
            end
            local target = tonumber(args[1])
            if not target or not GetPlayerName(target) then
                notify(source, _Up(source, 'ch_player_not_found'), 4000)
                return
            end
            JRSOpenCreatorEditSession(target, 600000)
            TriggerClientEvent('jrs_character_creator:SecondChance', target)
            notify(source, _Up(source, 'ch_character_editor_opened_for_the_player'), 4000)
            notify(target, _Up(target, 'ch_an_administrator_opened_character_customization'), 5000)
        end, false)
    end

    RegisterNetEvent('jrs_character:requestAgeSnapshot', function()
        local src = tonumber(source)
        if not JRSAllowRequest(src, 'age_snapshot', 8, 10000) then return end
        if not src then return end

        local session = activeAgingSessions[src]
        local snapshot = nil
        if session then
            snapshot = getLiveAgingSnapshot(
                src,
                session.charid,
                session.identifier,
                session.birthdate,
                nil
            )
        else
            local character = getActiveCharacter(src)
            local charid = character and tonumber(character.charIdentifier)
            local identifier = character and tostring(character.identifier or getIdentifier(src) or '') or ''
            if charid and identifier ~= '' then
                local row = MySQL.single.await([[
                    SELECT DATE_FORMAT(dateofbirth, '%Y-%m-%d') AS dateofbirth, playtime_seconds, base_age, age_years
                    FROM jrs_characters
                    WHERE identifier = ? AND charidentifier = ?
                    LIMIT 1
                ]], { identifier, charid })
                if row then
                    snapshot = ensureCharacterAgingState(identifier, charid, row.dateofbirth, row)
                end
            end
        end

        if snapshot then
            TriggerClientEvent('jrs_character:ageUpdated', src, {
                age = snapshot.ageYears,
                playtimeSeconds = snapshot.playtimeSeconds,
                hoursPerYear = tonumber(Config and Config.HoursPerYear) or 100,
                secondsToNextYear = snapshot.secondsToNextYear,
            })
        end
    end)

    AddEventHandler('jrs_character:agingStopSession', function(playerSource)
        persistAgingSession(tonumber(playerSource), false)
    end)

    CreateThread(function()
        Wait(5000)
        while true do
            local minutes = math.max(1, tonumber(Config and Config.AgingSaveIntervalMinutes) or 5)
            Wait(math.floor(minutes * 60000))
            if isPlaytimeAgingEnabled() then
                local sources = {}
                for src in pairs(activeAgingSessions) do sources[#sources + 1] = src end
                for _, src in ipairs(sources) do
                    persistAgingSession(src, true)
                end
            end
        end
    end)

    -- Restore sessions when this resource is restarted while players are online.
    CreateThread(function()
        Wait(3500)
        if not isPlaytimeAgingEnabled() then return end
        ensureCharacterAgingColumns()
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            local character = getActiveCharacter(src)
            local charid = character and tonumber(character.charIdentifier)
            local identifier = character and tostring(character.identifier or getIdentifier(src) or '') or ''
            if src and charid and identifier ~= '' then
                local row = MySQL.single.await([[
                    SELECT DATE_FORMAT(dateofbirth, '%Y-%m-%d') AS dateofbirth, playtime_seconds, base_age, age_years
                    FROM jrs_characters
                    WHERE identifier = ? AND charidentifier = ?
                    LIMIT 1
                ]], { identifier, charid })
                if row then startAgingSession(src, charid, identifier, row.dateofbirth, row) end
            end
        end
    end)

    AddEventHandler('playerDropped', function()
        local src = tonumber(source)
        persistAgingSession(src, false)
        creatingCharacters[src] = nil
    end)

    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName ~= GetCurrentResourceName() then return end
        local sources = {}
        for src in pairs(activeAgingSessions) do sources[#sources + 1] = src end
        for _, src in ipairs(sources) do
            persistAgingSession(src, false)
        end
    end)

    exports('GetCharacterAge', function(playerSource)
        local src = tonumber(playerSource)
        if not src then return nil end

        local session = activeAgingSessions[src]
        if session then
            local snapshot = getLiveAgingSnapshot(
                src,
                session.charid,
                session.identifier,
                session.birthdate,
                nil
            )
            return snapshot.ageYears, snapshot
        end

        local character = getActiveCharacter(src)
        local charid = character and tonumber(character.charIdentifier)
        local identifier = character and tostring(character.identifier or getIdentifier(src) or '') or ''
        if not charid or identifier == '' then return nil end
        local row = MySQL.single.await([[
            SELECT identifier, charidentifier, DATE_FORMAT(dateofbirth, '%Y-%m-%d') AS dateofbirth, playtime_seconds, base_age, age_years
            FROM jrs_characters
            WHERE identifier = ? AND charidentifier = ?
            LIMIT 1
        ]], { identifier, charid })
        if not row then return nil end
        local snapshot = ensureCharacterAgingState(identifier, charid, row.dateofbirth, row)
        return snapshot.ageYears, snapshot
    end)

    exports('GetCharacterAgeById', function(characterId)
        local charid = tonumber(characterId)
        if not charid then return nil end
        local row = MySQL.single.await([[
            SELECT identifier, charidentifier, DATE_FORMAT(dateofbirth, '%Y-%m-%d') AS dateofbirth, playtime_seconds, base_age, age_years
            FROM jrs_characters
            WHERE charidentifier = ?
            LIMIT 1
        ]], { charid })
        if not row then return nil end
        local snapshot = ensureCharacterAgingState(
            row.identifier,
            row.charidentifier,
            row.dateofbirth,
            row
        )
        return snapshot.ageYears, snapshot
    end)
end
end
