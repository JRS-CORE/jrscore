-- Server-only compatibility event. Do not register this as a network event.
-- Existing server resources may continue to use:
-- TriggerEvent('jrs:addxp', playerSource, amount, reason, callback)
AddEventHandler('jrs:addxp', function(playerSource, amount, reason, callback)
    JRSXP.Add(playerSource, amount, reason, callback)
end)

AddEventHandler('jrs:removexp', function(playerSource, amount, reason, callback)
    JRSXP.Remove(playerSource, amount, reason, callback)
end)

-- Clear aliases for new server resources. These are intentionally not network events.
AddEventHandler('jrs_core:addXP', function(playerSource, amount, reason, callback)
    JRSXP.Add(playerSource, amount, reason, callback)
end)

AddEventHandler('jrs_core:removeXP', function(playerSource, amount, reason, callback)
    JRSXP.Remove(playerSource, amount, reason, callback)
end)

AddEventHandler('jrs:setxp', function(playerSource, amount, reason, callback)
    JRSXP.Set(playerSource, amount, reason, callback)
end)

-- Server-only compatibility event. Do NOT expose group mutation as a network
-- event: clients must never be able to promote themselves by triggering it.
AddEventHandler('jrs:setGroup', function(playerSource, group)
    jrsCore.SetGroup(playerSource, group)
end)

-- Trusted server compatibility only. All job changes use the guarded setter.
AddEventHandler('jrs:setJob', function(playerSource, job, grade)
    Character.setJob(tonumber(playerSource), job, grade)
end)

AddEventHandler('jrs:setJobGrade', function(playerSource, charId, grade)
    if not charId or not grade then return end
    for _, character in ipairs(AllCharacters) do
        if tonumber(character.charIdentifier) == tonumber(charId) then
            if not JRSJobIdentity.CanAssign(character.charIdentifier, character.job) then return end
            character.jobgrade = tonumber(grade)
            exports.oxmysql:execute(
                "UPDATE jrs_characters SET jobgrade = @jobgrade WHERE identifier = @identifier AND charidentifier = @charidentifier",
                { identifier = character.identifier, charidentifier = charId, jobgrade = tonumber(grade) }
            )
        end
    end
end)

-- Server-only compatibility event. Do NOT register this as a network event:
-- every caller in this codebase uses TriggerEvent (server-internal) and passes
-- the target playerSource explicitly as the first argument. RegisterServerEvent
-- would let any client call TriggerServerEvent('jrs:addMoney', anyId, type, amount)
-- directly, overriding that first argument and crediting arbitrary money to anyone.
AddEventHandler('jrs:addMoney', function(source, currencyType, amount)
    if not source or not currencyType or not amount then
        jrsCore.Error("jrs:addMoney - missing arguments")
        return
    end

    Character.addCurrency(source, tonumber(currencyType), tonumber(amount))
end)

-- Server-only compatibility event, same reasoning as jrs:addMoney above.
AddEventHandler('jrs:removeMoney', function(source, currencyType, amount)
    if not source or not currencyType or not amount then
        jrsCore.Error("jrs:removeMoney - missing arguments")
        return
    end

    Character.removeCurrency(source, tonumber(currencyType), tonumber(amount))
end)

-- Server-only compatibility event. Do NOT register this as a network event: a
-- client could otherwise register/override a core callback under any name.
AddEventHandler('jrs:addNewCallBack', function(callbackName, fn)
    -- Cross-resource Cfx function references are callable, but their Lua
    -- type is not guaranteed to be reported as "function".
    if type(callbackName) ~= 'string' or fn == nil then
        print('^1[JRS] Rejected invalid callback registration.^0')
        return
    end
    if type(setCallbackResource) == 'function' then
        setCallbackResource(callbackName, GetInvokingResource())
    end
    if type(addCallbackHandler) == 'function' then
        addCallbackHandler(callbackName, function(cb, source, ...)
            local args = table.pack(...)
            local packed = table.pack(xpcall(function()
                return fn(source, table.unpack(args, 1, args.n))
            end, function(err)
                return debug.traceback(tostring(err), 2)
            end))
            if not packed[1] then
                print(('^1[JRS] Callback "%s" failed: %s^0'):format(callbackName, tostring(packed[2])))
                cb(nil)
                return
            end
            cb(table.unpack(packed, 2, packed.n))
        end)
    end
end)

RegisterNetEvent('jrs_core:returnCoords')
AddEventHandler('jrs_core:returnCoords', function(coords)
    if Config.HudDebug then
        print("^2[jrs_core] Coords from " .. source .. ": " .. json.encode(coords))
    end
end)

RegisterNetEvent('jrs:selectcharacter')
AddEventHandler('jrs:selectcharacter', function()
    if Config.Info_print then
        print("^2[jrs_core] Player " .. source .. " requested character selection")
    end
end)

local function getServerMaxClients()
    -- Same max slots as the admin panel / txAdmin (jrs_loadingscreen), else convar.
    if GetResourceState('jrs_loadingscreen') == 'started' then
        local ok, m = pcall(function() return exports.jrs_loadingscreen:GetListedMaxClients() end)
        m = ok and tonumber(m) or nil
        if m and m > 0 then return math.floor(m) end
    end
    local maxClients = GetConvarInt('sv_maxclients', 0)
    if maxClients <= 0 then
        maxClients = Config.MaxPlayers or 48
    end
    return maxClients
end

-- Same number the admin panel / txAdmin show (jrs_loadingscreen display count),
-- never lower than the real player count.
local function getOnlinePlayerCount()
    local real = #GetPlayers()
    if GetResourceState('jrs_loadingscreen') == 'started' then
        local ok, listed = pcall(function() return exports.jrs_loadingscreen:GetDisplayPlayerCount() end)
        listed = ok and tonumber(listed) or nil
        if listed then return math.max(math.floor(listed), real) end
    end
    return real
end

RegisterNetEvent('jrs_core:checkPlayersOnline')
AddEventHandler('jrs_core:checkPlayersOnline', function()
    local _source = source
    TriggerClientEvent("jrs_core:sendBack", _source, getOnlinePlayerCount(), getServerMaxClients())
end)

-- Central authoritative coordinate save. Character switches call this before
-- clearing User.getUsedCharacter; delayed periodic saves simply return false.
function jrsCore.SaveCharacterCoords(playerSource, coordSend)
    local src = tonumber(playerSource)
    if not src or type(coordSend) ~= "table" then return false end

    local character
    if type(jrsCore.GetCharacter) == "function" then
        character = jrsCore.GetCharacter(src)
    else
        local user = jrsCore.getUser(src)
        character = user and (user.character or user.getUsedCharacter) or nil
    end

    if type(character) ~= "table"
        or character.identifier == nil
        or character.charIdentifier == nil then
        return false
    end

    local x = tonumber(coordSend.x)
    local y = tonumber(coordSend.y)
    local z = tonumber(coordSend.z)
    if not x or not y or not z or x == 0 then return false end

    local coords = { x = x, y = y, z = z }
    local heading = tonumber(coordSend.heading)
    if heading then coords.heading = heading end

    exports.oxmysql:execute(
        "UPDATE jrs_characters SET coords = @coords WHERE identifier = @identifier AND charidentifier = @charidentifier",
        {
            identifier = character.identifier,
            charidentifier = character.charIdentifier,
            coords = json.encode(coords)
        }
    )

    if Config.Info_print then
        jrsCore.Debug("CharIdentifier " .. character.charIdentifier .. " coords saved: " .. x .. ", " .. y .. ", " .. z)
    end

    return true
end

RegisterServerEvent('jrsCore:save_coords')
AddEventHandler('jrsCore:save_coords', function(coordSend)
    jrsCore.SaveCharacterCoords(source, coordSend)
end)

if Config.Onesync then
    AddEventHandler('playerDropped', function(reason)
        local user = jrsCore.getUser(tonumber(source))
        local identifier = GetPlayerIdentifier(tonumber(source))

        PlayerTable[source] = nil

        if user and (type(user.character) == 'table' or type(user.getUsedCharacter) == 'table') and CanSaveCoords[tonumber(source)] then
            local character = user.getUsedCharacter
            local playerCoords = GetEntityCoords(GetPlayerPed(source))

            if playerCoords.x ~= 0 then
                local coordsTable = { x = playerCoords.x, y = playerCoords.y, z = playerCoords.z }

                exports.oxmysql:execute(
                    "UPDATE jrs_characters SET meta = @meta WHERE identifier = @identifier AND charidentifier = @charidentifier",
                    {
                        identifier = character.identifier,
                        charidentifier = character.charIdentifier,
                        meta = type(character.meta) == 'table' and json.encode(character.meta) or tostring(character.meta or '{}')
                    }
                )

                exports.oxmysql:execute(
                    "UPDATE jrs_characters SET coords = @coords WHERE identifier = @identifier AND charidentifier = @charidentifier",
                    { identifier = character.identifier, charidentifier = character.charIdentifier, coords = json.encode(coordsTable) }
                )

                if Config.Info_print then
                    jrsCore.Debug("CharIdentifier " .. character.charIdentifier .. " dropped with coords " .. playerCoords.x .. ", " .. playerCoords.y .. ", " .. playerCoords.z)
                end
            else
                -- Ped was already destroyed or not loaded when player disconnected.
                -- Try to fall back to the last coords saved by the periodic client sender.
                local lastSaved = character.coords
                if type(lastSaved) == 'string' and lastSaved ~= '' and lastSaved ~= '{}' then
                    -- coords column already has valid data from the last periodic save; nothing to do.
                    if Config.Info_print then
                        jrsCore.Debug("CharIdentifier " .. character.charIdentifier .. " dropped with ped at (0,0,0); using last periodic save.")
                    end
                elseif type(lastSaved) == 'table' and (lastSaved.x or 0) ~= 0 then
                    exports.oxmysql:execute(
                        "UPDATE jrs_characters SET coords = @coords WHERE identifier = @identifier AND charidentifier = @charidentifier",
                        { identifier = character.identifier, charidentifier = character.charIdentifier, coords = json.encode(lastSaved) }
                    )
                    if Config.Info_print then
                        jrsCore.Debug("CharIdentifier " .. character.charIdentifier .. " dropped with ped at (0,0,0); fallback coords used.")
                    end
                else
                    if Config.Info_print then
                        jrsCore.Debug("CharIdentifier " .. character.charIdentifier .. " dropped with ped at (0,0,0); no fallback available.")
                    end
                end
            end
        end
    end)
else
    AddEventHandler('playerDropped', function(reason)
        PlayerTable[source] = nil
    end)
end

AddEventHandler('playerDropped', function(reason)
    local identifier = GetPlayerIdentifier(tonumber(source))
    if LoadedUsers[identifier] then
        LoadedUsers[identifier].setUsedCharacter = User.setUsedCharacter
    end
end)

AddEventHandler('playerDropped', function()
    local droppedPlayer = source
    TriggerClientEvent('jrs_core:removePlayerPed', -1, droppedPlayer)
end)

Citizen.CreateThread(function()
    while true do
        TriggerClientEvent("jrs_core:sendBack", -1, getOnlinePlayerCount(), getServerMaxClients())
        Citizen.Wait(math.max(tonumber(Config.PlayerCountInterval) or 30000, 15000)) -- Discord throttles presence updates (~15 s)
    end
end)

-- Server-only compatibility event, same reasoning as jrs:addMoney above: the
-- explicit `source` parameter must not be reachable via TriggerServerEvent.
AddEventHandler('jrsCore:GetPlayerIds', function(source, charId, firstname, lastname, cb)
    local playerId = 0

    if tonumber(charId) == 0 then
        for id, data in pairs(PlayerTable) do
            if firstname == data.firstname and lastname == data.lastname then
                playerId = id
            end
        end
    else
        for id, data in pairs(PlayerTable) do
            if tonumber(charId) == data.charid then
                playerId = id
            end
        end
    end

    cb(playerId ~= 0 and playerId or false)
end)

local legacyCallbackRate = {}
local LEGACY_CALLBACK_WINDOW_MS = 1000
local LEGACY_CALLBACK_MAX_CALLS = 30
local LEGACY_CALLBACK_MAX_PAYLOAD = 65536
local LEGACY_CLIENT_BLOCKED = {
    ["jrs:addMoney"] = true, ["jrs:removeMoney"] = true,
    ["jrs:addGold"] = true, ["jrs:removeGold"] = true,
    ["jrs:addDirtyMoney"] = true, ["jrs:removeDirtyMoney"] = true,
    ["jrs:setPlayerJob"] = true, ["jrs:setPlayerGroup"] = true,
    ["jrs:addItem"] = true, ["jrs:removeItem"] = true,
    ["jrs:giveWeapon"] = true, ["jrs:removeWeapon"] = true,
    ["jrs:addXp"] = true, ["jrs:teleportToCoords"] = true,
}

local function allowLegacyCallback(src)
    local now = GetGameTimer()
    local bucket = legacyCallbackRate[src]
    if not bucket or now - bucket.started >= LEGACY_CALLBACK_WINDOW_MS then
        legacyCallbackRate[src] = { started = now, count = 1 }
        return true
    end
    bucket.count = bucket.count + 1
    return bucket.count <= LEGACY_CALLBACK_MAX_CALLS
end

RegisterNetEvent("jrs:triggercallback")
AddEventHandler("jrs:triggercallback", function(callbackName, ticket, ...)
    local playerSource = tonumber(source)
    callbackName = tostring(callbackName or '')
    ticket = tostring(ticket or '')
    if not playerSource or playerSource <= 0 or callbackName == '' or #callbackName > 128 or ticket == '' or #ticket > 96 then return end
    if not allowLegacyCallback(playerSource) then
        TriggerClientEvent("jrs:endcallback", playerSource, callbackName, ticket, { success = false, error = 'rate_limited' })
        return
    end
    if LEGACY_CLIENT_BLOCKED[callbackName] then
        print(('^3[JRS] Blocked client mutation callback "%s" from %s. Use server exports instead.^0'):format(callbackName, playerSource))
        TriggerClientEvent("jrs:endcallback", playerSource, callbackName, ticket, { success = false, error = 'server_only' })
        return
    end
    local packedArgs = table.pack(...)
    local okPayload, encoded = pcall(json.encode, packedArgs)
    if not okPayload or #encoded > LEGACY_CALLBACK_MAX_PAYLOAD then
        TriggerClientEvent("jrs:endcallback", playerSource, callbackName, ticket, { success = false, error = 'invalid_payload' })
        return
    end
    local fn = getCallbackHandler(callbackName)
    if not fn then
        print(('^3[JRS] Callback "%s" was requested by %s but is not registered.^0'):format(tostring(callbackName), tostring(playerSource)))
        TriggerClientEvent("jrs:endcallback", playerSource, callbackName, ticket, nil)
        return
    end

    -- Identity gate: a player-side action cannot run through a core callback
    -- before the client has a loaded character identity. The creation/barber/
    -- clothing resources register their callbacks under a name owned by them and
    -- are exempt, so character creation still works before a character exists.
    local IDENTITY_EXEMPT = { ['jrs_character'] = true, ['jrs_barber'] = true, ['jrs_clothing'] = true }
    local reg = getCallbackResource(callbackName)
    if not (reg and IDENTITY_EXEMPT[tostring(reg):lower()]) and not jrsCore.IsCharacterReady(playerSource) then
        print(('^1[JRS] Callback "%s" BLOCKED for %s (no loaded identity)^0'):format(
            tostring(callbackName), tostring(playerSource)))
        TriggerClientEvent("jrs:endcallback", playerSource, callbackName, ticket, nil)
        return
    end

    fn(function(...)
        TriggerClientEvent("jrs:endcallback", playerSource, callbackName, ticket, ...)
    end, playerSource, ...)
end)

AddEventHandler('playerDropped', function() legacyCallbackRate[tonumber(source)] = nil end)

-- ===================================================================
-- JRS PVP Server Network Events (Native JRS Core)
-- ===================================================================
RegisterNetEvent('jrs_core:server:setPvp', function(state, silent)
    local src = source
    if not src or src == 0 then return end
    Player(src).state:set('jrsPvp', state == true, true)
    TriggerClientEvent('jrs_core:client:setPvp', src, state == true, silent == true)
end)

RegisterNetEvent('jrs_core:server:togglePvp', function()
    local src = source
    if not src or src == 0 then return end
    TriggerClientEvent('jrs_core:client:togglePvp', src)
end)
