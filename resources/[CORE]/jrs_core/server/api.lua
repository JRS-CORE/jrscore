-- Internal core API builder. The public server export is registered once at
-- the end of this file as getCoreApi.
local function buildCoreAPI()
    local api = {}

    api.getCharacter = function(source)
        source = tonumber(source)
        if not source or source <= 0 then return nil end
        if jrsCore and type(jrsCore.GetCharacter) == 'function' then
            return jrsCore.GetCharacter(source)
        end
        return nil
    end

    api.NotifyClientRightTip = function(source, text, duration)
        api.NotifyRightTip(source, text, duration)
    end
    api.NotifyRightTip = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendRightTipNotification', source, text, duration)
    end
    api.NotifyLeft = function(source, firsttext, secondtext, dict, icon, duration, color)
        TriggerClientEvent('jrs_core:sendLeftNotification', source, firsttext, secondtext, dict, icon, duration, color)
    end
    api.NotifyTip = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendTipNotification', source, text, duration)
    end
    api.NotifyTop = function(source, text, location, duration)
        TriggerClientEvent('jrs_core:sendTopNotification', source, text, location, duration)
    end
    api.NotifyObjective = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendBottomTipNotification', source, text, duration)
    end
    api.NotifySimpleTop = function(source, title, subtitle, duration)
        TriggerClientEvent('jrs_core:sendSimpleTopNotification', source, title, subtitle, duration)
    end
    api.NotifyAdvanced = function(source, text, dict, icon, textColor, duration, quality)
        TriggerClientEvent('jrs_core:sendAdvancedRightNotification', source, text, dict, icon, textColor, duration, quality)
    end
    api.NotifyAvanced = function(source, ...)
        api.NotifyAdvanced(source, ...)
    end
    api.NotifyBasicTop = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendBasicTopNotification', source, text, duration)
    end
    api.NotifyCenter = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendSimpleCenterNotification', source, text, duration)
    end
    api.NotifyBottomRight = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendBottomRightNotification', source, text, duration)
    end
    api.NotifyFail = function(source, title, subtitle, duration)
        TriggerClientEvent('jrs_core:sendFailMissionNotification', source, title, subtitle, duration)
    end
    api.NotifyDead = function(source, title, audioRef, audioName, duration)
        TriggerClientEvent('jrs_core:sendDeadPlayerNotification', source, title, audioRef, audioName, duration)
    end
    api.NotifyUpdate = function(source, title, message, duration)
        TriggerClientEvent('jrs_core:sendMissionUpdateNotification', source, title, message, duration)
    end
    api.NotifyWarning = function(source, title, message, audioRef, audioName, duration)
        TriggerClientEvent('jrs_core:sendWarningNotification', source, title, message, audioRef, audioName, duration)
    end
    api.NotifyLeftRank = function(source, title, subtitle, dict, icon, duration, color)
        TriggerClientEvent('jrs_core:sendLeftRankNotification', source, title, subtitle, dict, icon, duration, color)
    end

    local function getCurrencyBalance(character, currency)
        if type(character) ~= 'table' then return nil end
        if currency == 0 then return tonumber(character.money) end
        if currency == 1 then return tonumber(character.gold) end
        if currency == 2 then return tonumber(character.rol) end
        if currency == 3 then return tonumber(character.dirtymoney) end
        return nil
    end

    -- When JRS's in-memory character object is not available (the readiness
    -- gate reports false), fall back to reading/writing the balance straight on the
    -- canonical `characters` row. This keeps money transfers/purchases working even
    -- when the selected character has not been re-marked ready. It never guesses
    -- between several characters: it trusts the server-set state id, otherwise a
    -- single unambiguous row for this account.
    local CURRENCY_COLUMNS = { [0] = 'money', [1] = 'gold', [2] = 'rol', [3] = 'dirtymoney' }

    local function resolveDbCharId(source)
        source = tonumber(source)
        if not source or GetPlayerName(source) == nil then return nil end
        local identifiers, seen = {}, {}
        local function add(v)
            if type(v) ~= 'string' then return end
            v = v:gsub('^%s+', ''):gsub('%s+$', '')
            if v ~= '' and not seen[v] then seen[v] = true; identifiers[#identifiers + 1] = v end
        end
        if type(GetPlayerIdentifierByType) == 'function' then
            for _, idType in ipairs({ 'steam', 'license', 'license2', 'fivem' }) do
                local ok, value = pcall(GetPlayerIdentifierByType, source, idType)
                if ok then add(value) end
            end
        end
        for _, value in ipairs(GetPlayerIdentifiers(source) or {}) do add(value) end
        if #identifiers == 0 then return nil end

        local placeholders = string.rep('?,', #identifiers - 1) .. '?'

        local activeCharId
        local stateP, stateV = pcall(function()
            local p = Player(source)
            return p and p.state and (p.state.CharacterId or p.state.charId) or nil
        end)
        if stateP then
            local v = tonumber(stateV)
            if v and v > 0 then activeCharId = math.floor(v) end
        end

        if activeCharId then
            local params = { activeCharId }
            for i = 1, #identifiers do params[#params + 1] = identifiers[i] end
            local ok, rows = pcall(function()
                return Citizen.Await(exports.oxmysql:fetch(
                    'SELECT `charidentifier` FROM `jrs_characters` WHERE `charidentifier` = ? AND `identifier` IN ('..placeholders..') LIMIT 1',
                    params))
            end)
            if ok and rows and rows[1] and tonumber(rows[1].charidentifier) then
                return tonumber(rows[1].charidentifier)
            end
        end

        local ok, rows = pcall(function()
            return Citizen.Await(exports.oxmysql:fetch(
                'SELECT `charidentifier` FROM `jrs_characters` WHERE `identifier` IN ('..placeholders..') LIMIT 2',
                identifiers))
        end)
        if ok and rows and #rows == 1 and tonumber(rows[1].charidentifier) then
            return tonumber(rows[1].charidentifier)
        end
        return nil
    end

    local function dbSetCurrency(source, currency, quantity, add)
        local charid = resolveDbCharId(source)
        if not charid then
            print(('^1[jrs_core][MONEY-DB] source=%s currency=%s %s amount=%s -> FAILED (could not resolve charid)^0'):format(
                tostring(source), tostring(currency), (add and 'ADD' or 'REMOVE'), tostring(quantity or 0)))
            return false
        end
        local column = CURRENCY_COLUMNS[currency]
        if not column then
            print(('^1[jrs_core][MONEY-DB] source=%s currency=%s -> FAILED (unknown currency type)^0'):format(tostring(source), tostring(currency)))
            return false
        end
        local ok, rows = pcall(function()
            return Citizen.Await(exports.oxmysql:fetch(
                'SELECT `'..column..'` FROM `jrs_characters` WHERE `charidentifier` = ? LIMIT 1', { charid }))
        end)
        if not ok or not rows or not rows[1] then
            print(('^1[jrs_core][MONEY-DB] source=%s charid=%s currency=%s -> FAILED (no row)^0'):format(
                tostring(source), tostring(charid), tostring(currency)))
            return false
        end
        local balance = tonumber(rows[1][column]) or 0
        if add == false then
            if balance < quantity then
                print(('^1[jrs_core][MONEY-DB] source=%s charid=%s %s=%.2f amount=%s -> FAILED (not enough)^0'):format(
                    tostring(source), tostring(charid), tostring(column), balance, tostring(quantity)))
                return false
            end
            balance = balance - quantity
        else
            balance = balance + quantity
        end
        local updOk = pcall(function()
            return Citizen.Await(exports.oxmysql:execute(
                'UPDATE `jrs_characters` SET `'..column..'` = ? WHERE `charidentifier` = ?', { balance, charid }))
        end)
        if updOk == true then
            print(('^2[jrs_core][MONEY-DB] source=%s charid=%s %s %.2f -> %.2f (%s %.2f) OK^0'):format(
                tostring(source), tostring(charid), tostring(column),
                (tonumber(rows[1][column]) or 0), balance, (add and '+' or '-'), quantity))
            return true
        end
        print(('^1[jrs_core][MONEY-DB] source=%s charid=%s %s -> FAILED (update error)^0'):format(
            tostring(source), tostring(charid), tostring(column)))
        return false
    end

    api.addMoney = function(source, currency, quantity)
        source, currency, quantity = tonumber(source), tonumber(currency), tonumber(quantity)
        if not source or source <= 0 or currency == nil or not quantity or quantity <= 0 then return false end
        -- Identity gate: no script can add money for a source with no loaded
        -- character identity.
        if not jrsCore.IsCharacterReady(source) then
            print(('^1[jrs_core][MONEY] source=%s ADD %.2f c=%s BLOCKED (no loaded identity)^0'):format(
                tostring(source), quantity, tostring(currency)))
            return false
        end
        if Character and type(Character.addCurrency) == 'function' and type(api.getCharacter(source)) == 'table' then
            local r = Character.addCurrency(source, currency, quantity) == true
            if r == false then
                print(('^1[jrs_core][MONEY] source=%s ADD %.2f c=%s -> live addCurrency failed, using DB fallback^0'):format(
                    tostring(source), quantity, tostring(currency)))
            end
            return r == true and r or dbSetCurrency(source, currency, quantity, true)
        end
        print(('^3[jrs_core][MONEY] source=%s ADD %.2f c=%s -> character not ready, DB fallback^0'):format(
            tostring(source), quantity, tostring(currency)))
        return dbSetCurrency(source, currency, quantity, true)
    end
    api.removeMoney = function(source, currency, quantity)
        source, currency, quantity = tonumber(source), tonumber(currency), tonumber(quantity)
        if not source or source <= 0 or currency == nil or not quantity or quantity <= 0 then return false end
        -- Identity gate: no money can be spent for a source with no loaded
        -- character identity.
        if not jrsCore.IsCharacterReady(source) then
            print(('^1[jrs_core][MONEY] source=%s REMOVE %.2f c=%s BLOCKED (no loaded identity)^0'):format(
                tostring(source), quantity, tostring(currency)))
            return false
        end
        if Character and type(Character.removeCurrency) == 'function' and type(api.getCharacter(source)) == 'table' then
            local balance = getCurrencyBalance(api.getCharacter(source), currency)
            -- A loaded character's live balance is authoritative: the DB row is
            -- overwritten from it on the next save, so charging a stale (higher)
            -- DB value here would hand out the purchase for free. Short is short.
            if balance ~= nil and balance < quantity then
                return false
            end
            if balance == nil then
                print(('^1[jrs_core][MONEY] source=%s REMOVE %.2f c=%s -> live balance %s unreadable, using DB fallback^0'):format(
                    tostring(source), quantity, tostring(currency), tostring(balance)))
                return dbSetCurrency(source, currency, quantity, false)
            end
            return Character.removeCurrency(source, currency, quantity) == true
        end
        print(('^3[jrs_core][MONEY] source=%s REMOVE %.2f c=%s -> character not ready, DB fallback^0'):format(
            tostring(source), quantity, tostring(currency)))
        return dbSetCurrency(source, currency, quantity, false)
    end
    api.setJob = function(source, job, grade)
        local changed, reason = Character.setJob(source, job, grade)
        if changed ~= true then return false, reason end
        TriggerClientEvent('jrs_core:getPlayerJob', source, { job = job, jobGrade = grade })
        return true
    end
    api.setGroup = function(source, group)
        return jrsCore.SetGroup(source, group)
    end
    api.setInstancePlayer = function(source, active)
        TriggerClientEvent('jrs:setInstancePlayer', source, active)
    end
    api.addNewCallBack = function(name, fn)
        if type(name) ~= 'string' or fn == nil then return false end
        if type(setCallbackResource) == 'function' then
            setCallbackResource(name, GetInvokingResource())
        end
        if type(addCallbackHandler) == 'function' then
            addCallbackHandler(name, function(cb, source, ...)
                local args = table.pack(...)
                local packed = table.pack(xpcall(function()
                    return fn(source, table.unpack(args, 1, args.n))
                end, function(err)
                    return debug.traceback(tostring(err), 2)
                end))
                if not packed[1] then
                    print(('^1[JRS] Callback "%s" failed: %s^0'):format(name, tostring(packed[2])))
                    cb(nil)
                    return
                end

                cb(table.unpack(packed, 2, packed.n))
            end)
            return true
        end
        return false
    end
    api.HealPlayer = function(source)
        TriggerClientEvent('jrs_core:healPlayer', source)
    end
    api.addxp = function(source, xp, reason, callback)
        return JRSXP.Add(source, xp, reason, callback)
    end
    api.addXP = api.addxp
    api.AddXP = api.addxp
    api.addXp = api.addxp
    api.removexp = function(source, xp, reason, callback)
        return JRSXP.Remove(source, xp, reason, callback)
    end
    api.removeXP = api.removexp
    api.RemoveXP = api.removexp
    api.removeXp = api.removexp
    api.setxp = function(source, xp, reason, callback)
        return JRSXP.Set(source, xp, reason, callback)
    end
    api.setXP = api.setxp
    api.SetXP = api.setxp
    api.setXp = api.setxp
    api.getxp = function(source)
        return JRSXP.GetSync(source)
    end
    api.getXP = api.getxp
    api.GetXP = api.getxp
    api.getXp = api.getxp
    api.getlevel = function(source)
        local data = JRSXP.GetSync(source)
        return data and math.max(1, math.floor(tonumber(data.level) or 1)) or 1, data
    end
    api.getLevel = api.getlevel
    api.GetLevel = api.getlevel
    api.getLvl = api.getlevel
    api.setlevel = function(source, level, reason, callback)
        return JRSXP.SetLevel(source, level, reason, callback)
    end
    api.setLevel = api.setlevel
    api.SetLevel = api.setlevel
    api.setLvl = api.setlevel
    api.addlevel = function(source, delta, reason, callback)
        return JRSXP.AddLevel(source, delta, reason, callback)
    end
    api.addLevel = api.addlevel
    api.AddLevel = api.addlevel
    api.addLvl = api.addlevel
    api.removelevel = function(source, delta, reason, callback)
        return JRSXP.RemoveLevel(source, delta, reason, callback)
    end
    api.removeLevel = api.removelevel
    api.RemoveLevel = api.removelevel
    api.removeLvl = api.removelevel
    api.getLevelData = function(totalXp)
        return Config.GetLevelData(totalXp)
    end
    api.GetLevelData = api.getLevelData
    api.getTotalXpForLevel = function(level)
        return Config.GetTotalXpForLevel(level)
    end
    api.GetTotalXpForLevel = api.getTotalXpForLevel

    return api
end

local function buildLegacyServerAPI()
    local serverApi = {}

    serverApi.GetTableLength = function(T)
        local count = 0
        for _ in pairs(T) do count = count + 1 end
        return count
    end
    -- Notifications
    serverApi.NotifyLeft = function(source, firsttext, secondtext, dict, icon, duration, color)
        TriggerClientEvent('jrs_core:sendLeftNotification', source, firsttext, secondtext, dict, icon, duration, color)
    end

    serverApi.NotifyTip = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendTipNotification', source, text, duration)
    end

    serverApi.NotifyTop = function(source, text, location, duration)
        TriggerClientEvent('jrs_core:sendTopNotification', source, text, location, duration)
    end

    serverApi.NotifyRightTip = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendRightTipNotification', source, text, duration)
    end

    serverApi.NotifyObjective = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendBottomTipNotification', source, text, duration)
    end

    serverApi.NotifySimpleTop = function(source, title, subtitle, duration)
        TriggerClientEvent('jrs_core:sendSimpleTopNotification', source, title, subtitle, duration)
    end

    serverApi.NotifyAdvanced = function(source, text, dict, icon, text_color, duration, quality)
        TriggerClientEvent('jrs_core:sendAdvancedRightNotification', source, text, dict, icon, text_color, duration, quality)
    end

    serverApi.NotifyAvanced = function(source, text, dict, icon, text_color, duration, quality)
        serverApi.NotifyAdvanced(source, text, dict, icon, text_color, duration, quality)
    end

    serverApi.NotifyBasicTop = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendBasicTopNotification', source, text, duration)
    end

    serverApi.NotifyCenter = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendSimpleCenterNotification', source, text, duration)
    end

    serverApi.NotifyBottomRight = function(source, text, duration)
        TriggerClientEvent('jrs_core:sendBottomRightNotification', source, text, duration)
    end

    serverApi.NotifyFail = function(source, title, subtitle, duration)
        TriggerClientEvent('jrs_core:sendFailMissionNotification', source, title, subtitle, duration)
    end

    serverApi.NotifyDead = function(source, title, audioRef, audioName, duration)
        TriggerClientEvent('jrs_core:sendDeadPlayerNotification', source, title, audioRef, audioName, duration)
    end

    serverApi.NotifyUpdate = function(source, utitle, umsg, duration)
        serverApi.NotifyWarning(source, utitle, umsg, nil, nil, duration)
    end

    serverApi.NotifyWarning = function(source, title, msg, audioRef, audioName, duration)
        TriggerClientEvent('jrs_core:sendWarningNotification', source, title, msg, audioRef, audioName, duration)
    end

    serverApi.NotifyLeftRank = function(source, title, subtitle, dict, icon, duration, color)
        TriggerClientEvent('jrs_core:sendLeftRankNotification', source, title, subtitle, dict, icon, duration, color)
    end -- End of notifications

    serverApi.loaded = function(source)
        return PlayerData[source] ~= nil
    end

    serverApi.getIdentifier = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].identifier or nil
    end

    serverApi.getCharacterIdentifier = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].charIdentifier or nil
    end

    serverApi.getGender = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].gender or nil
    end

    serverApi.getDob = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].dob or nil
    end

    serverApi.getGroup = function(source)
        return jrsCore.GetGroup(tonumber(source))
    end

    serverApi.setGroup = function(source, group)
        return jrsCore.SetGroup(tonumber(source), group)
    end

    serverApi.getClan = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].clan or nil
    end

    serverApi.setClan = function(source, clan)
        PlayerData[source].clan = clan
    end

    serverApi.getFirstName = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].firstname or nil
    end

    serverApi.getLastName = function(source)
        return PlayerData[tonumber(source)] and PlayerData[tonumber(source)].lastname or nil
    end

    serverApi.getJob = function(source)
        source = tonumber(source)
        if PlayerData[source] then
            return PlayerData[source].job
        end
        local user = jrsCore.getUser(source)
        return user and user.getUsedCharacter and user.getUsedCharacter.job or nil
    end

    serverApi.setJob = function(source, job, grade)
        source = tonumber(source)
        if not source or not job then return false end

        local user = jrsCore.getUser(source)
        if not user or not user.getUsedCharacter then return false end

        local character = user.getUsedCharacter
        grade = tonumber(grade) or tonumber(character.jobgrade) or 0
        local changed, reason = character.setJob(source, job, grade)
        if changed ~= true then return false, reason end

        if PlayerData[source] then
            PlayerData[source].job = job
            PlayerData[source].jobGrade = grade
        end
        return true
    end

    serverApi.getJobGrade = function(source)
        source = tonumber(source)
        if PlayerData[source] then
            return PlayerData[source].jobGrade
        end
        local user = jrsCore.getUser(source)
        return user and user.getUsedCharacter and user.getUsedCharacter.jobgrade or nil
    end

    serverApi.setJobGrade = function(source, grade)
        source = tonumber(source)
        grade = tonumber(grade)
        if not source or grade == nil then return false end

        local user = jrsCore.getUser(source)
        if not user or not user.getUsedCharacter then return false end

        local character = user.getUsedCharacter
        local changed, reason = character.setJob(source, character.job, grade)
        if changed ~= true then return false, reason end

        if PlayerData[source] then
            PlayerData[source].jobGrade = grade
        end
        return true
    end

    -- These delegate to the authoritative currency path so balances written
    -- through the legacy API actually reach the `characters` table.
    serverApi.getAccount = function(source, currency_type)
        return jrsCore.getAccount(tonumber(source), currency_type)
    end

    serverApi.addAccount = function(source, currency_type, quantity)
        return jrsCore.addAccount(tonumber(source), currency_type, quantity)
    end

    serverApi.removeAccount = function(source, currency_type, quantity)
        return jrsCore.removeAccount(tonumber(source), currency_type, quantity)
    end

    serverApi.getLastSavedLocation = function(source)
        local src = tonumber(source)
        local stored = src and PlayerData[src] and PlayerData[src].coords or nil

        if type(stored) == 'table' then return stored end
        if type(stored) ~= 'string' or stored == '' then return nil end

        local ok, decoded = pcall(json.decode, stored)
        if ok and type(decoded) == 'table' then return decoded end
        return nil
    end

    serverApi.saveLocation = function(source, coords, heading)
        local src = tonumber(source)
        if not src then return false end

        local newCoords
        if coords then
            newCoords = { x = coords.x, y = coords.y, z = coords.z, heading = tonumber(heading) }
        else
            local playerPed = GetPlayerPed(src)
            local pedCoords, pedHeading = GetEntityCoords(playerPed), GetEntityHeading(playerPed)
            newCoords = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z, heading = pedHeading }
        end

        if not tonumber(newCoords.x) or not tonumber(newCoords.y) or not tonumber(newCoords.z) then
            return false
        end

        -- PlayerData.coords mirrors the `characters.coords` column, which is a
        -- JSON string. Storing a raw table here used to break every later
        -- getLastSavedLocation call for that player.
        if PlayerData[src] then
            PlayerData[src].coords = json.encode(newCoords)
        end

        return jrsCore.SaveCharacterCoords(src, newCoords) == true
    end

    serverApi.saveCharacter = function(source)
        local src = tonumber(source)
        if not src then return false end

        local character = jrsCore.GetCharacter and jrsCore.GetCharacter(src) or nil
        if type(character) ~= 'table' then return false end

        -- Persist the parts of the character that are held in memory: meta and
        -- the current world position.
        if character.identifier ~= nil and character.charIdentifier ~= nil and character.meta ~= nil then
            exports.oxmysql:execute(
                "UPDATE jrs_characters SET meta = @meta WHERE identifier = @identifier AND charidentifier = @charidentifier",
                {
                    identifier = character.identifier,
                    charidentifier = character.charIdentifier,
                    meta = type(character.meta) == 'table' and json.encode(character.meta) or character.meta
                }
            )
        end

        return serverApi.saveLocation(src)
    end

    serverApi.GetJobPlayers = function(job)
        local data       = { players = {}, count = 0 }
        local playerList = GetPlayers()

		for index, player in pairs(playerList) do
            player = tonumber(player)
            if PlayerData[player] and PlayerData[player].job == job then
                data.count = data.count + 1
                table.insert(data.players, { source = player } )
            end

        end

        return data

    end



    serverApi.GetPlayers = function()
        local data       = { players = {}, count = 0 }
        local playerList = GetPlayers()

		for index, player in pairs(playerList) do

            player = tonumber(player)
            
            if PlayerData[player] then

                data.count = data.count + 1
                table.insert(data.players, { source = player } )
            end

        end

        return data

    end

    return serverApi
end

-- ============================================================
-- Callback system for external scripts
-- Usage: TriggerEvent("jrs_core:ExecuteServerCallBack", name, callback, data)
-- ============================================================

local CoreAPI = buildCoreAPI()

-- NOTIFICATIONS
CoreAPI.addNewCallBack("jrs:notifyRightTip", function(source, data)
    CoreAPI.NotifyRightTip(source, data.text, data.duration or 3000)
end)

CoreAPI.addNewCallBack("jrs:notifyLeft", function(source, data)
    CoreAPI.NotifyLeft(source, data.firstText, data.secondText, data.dict, data.icon, data.duration, data.color)
end)

CoreAPI.addNewCallBack("jrs:notifyTop", function(source, data)
    CoreAPI.NotifyTop(source, data.text, data.location, data.duration)
end)

CoreAPI.addNewCallBack("jrs:notifyWarning", function(source, data)
    CoreAPI.NotifyWarning(source, data.title, data.msg, data.audioRef, data.audioName, data.duration)
end)

CoreAPI.addNewCallBack("jrs:notifyCenter", function(source, data)
    CoreAPI.NotifyCenter(source, data.text, data.duration)
end)

CoreAPI.addNewCallBack("jrs:notifyFail", function(source, data)
    CoreAPI.NotifyFail(source, data.title, data.subtitle, data.duration)
end)

-- PLAYER DATA
CoreAPI.addNewCallBack("jrs:getPlayerData", function(source, data)
    local target = source
    if data and data.source then target = tonumber(data.source) end
    if not PlayerData[target] then return {} end
    local xPlayer = PlayerData[target]
    return {
        source = target,
        identifier = xPlayer.identifier,
        charIdentifier = tonumber(xPlayer.charIdentifier),
        firstname = xPlayer.firstname,
        lastname = xPlayer.lastname,
        gender = xPlayer.gender,
        dob = xPlayer.dob,
        job = xPlayer.job,
        jobGrade = xPlayer.jobGrade,
        group = xPlayer.group or "user",
        money = xPlayer.account and tonumber(xPlayer.account[0]) or 0,
        gold = xPlayer.account and tonumber(xPlayer.account[1]) or 0,
        rol = xPlayer.account and tonumber(xPlayer.account[2]) or 0,
        dirtymoney = xPlayer.account and tonumber(xPlayer.account[3]) or 0,
        blackmoney = xPlayer.account and tonumber(xPlayer.account[3]) or 0, -- compatibility alias for Dirty Money
        xp = tonumber(xPlayer.xp) or 0,
        identityId = xPlayer.identity_id,
        defaultWeapon = xPlayer.default_weapon,
        inventoryMaxWeight = xPlayer.inventory_capacity,
    }
end)

CoreAPI.addNewCallBack("jrs:getPlayerInfo", function(source, data)
    if not PlayerData[source] then return {} end
    return {
        firstname = PlayerData[source].firstname,
        lastname = PlayerData[source].lastname,
        job = PlayerData[source].job,
        jobGrade = PlayerData[source].jobGrade,
        group = PlayerData[source].group or "user",
    }
end)

-- MONEY / CURRENCY
CoreAPI.addNewCallBack("jrs:addMoney", function(source, data)
    if not data.amount or data.amount <= 0 then return { success = false, error = _U('err_invalid_amount') } end
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    User.getUsedCharacter.addCurrency(source, 0, data.amount)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:removeMoney", function(source, data)
    if not data.amount or data.amount <= 0 then return { success = false, error = _U('err_invalid_amount') } end
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    User.getUsedCharacter.removeCurrency(source, 0, data.amount)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:addGold", function(source, data)
    if not data.amount or data.amount <= 0 then return { success = false, error = _U('err_invalid_amount') } end
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    User.getUsedCharacter.addCurrency(source, 1, data.amount)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:removeGold", function(source, data)
    if not data.amount or data.amount <= 0 then return { success = false, error = _U('err_invalid_amount') } end
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    User.getUsedCharacter.removeCurrency(source, 1, data.amount)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:addDirtyMoney", function(source, data)
    if not data.amount or data.amount <= 0 then return { success = false, error = _U('err_invalid_amount') } end
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    User.getUsedCharacter.addCurrency(source, 3, data.amount)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:removeDirtyMoney", function(source, data)
    if not data.amount or data.amount <= 0 then return { success = false, error = _U('err_invalid_amount') } end
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    local balance = tonumber(User.getUsedCharacter.dirtymoney) or 0
    if balance < data.amount then return { success = false, error = _U('err_invalid_amount') } end
    User.getUsedCharacter.removeCurrency(source, 3, data.amount)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:getBalance", function(source, data)
    local character = jrsCore.GetCharacter(tonumber(source))
    if not character then return { money = 0, gold = 0, rol = 0, dirtymoney = 0, blackmoney = 0 } end
    local dirtymoney = tonumber(character.dirtymoney) or 0
    return {
        money = tonumber(character.money) or 0,
        gold = tonumber(character.gold) or 0,
        rol = tonumber(character.rol) or 0,
        dirtymoney = dirtymoney,
        blackmoney = dirtymoney,
    }
end)

-- JOB
CoreAPI.addNewCallBack("jrs:setPlayerJob", function(source, data)
    if not data.job then return { success = false, error = _U('err_job_required') } end
    CoreAPI.setJob(source, data.job, data.grade or 0)
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:getPlayerJob", function(source, data)
    if not PlayerData[source] then return {} end
    return { job = PlayerData[source].job, grade = PlayerData[source].jobGrade }
end)

-- GROUP
CoreAPI.addNewCallBack("jrs:setPlayerGroup", function(source, data)
    -- Group mutation is server-only. A client-accessible setter would allow
    -- privilege escalation to admin/owner. Use exports.jrs_core:getCoreApi()
    -- from a trusted server resource instead.
    return { success = false, error = 'server_only' }
end)

CoreAPI.addNewCallBack("jrs:getPlayerGroup", function(source, data)
    return jrsCore.GetGroup(source) or "user"
end)

-- INVENTORY ITEMS
CoreAPI.addNewCallBack("jrs:addItem", function(source, data)
    if not data.item then return { success = false, error = _U('err_item_required') } end
    local count = data.count or 1
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    local Character = User.getUsedCharacter
    local inv = json.decode(Character.inventory) or {}
    table.insert(inv, { itemId = math.random(1, 76062001718755), item = data.item, count = count, metadata = data.metadata or {} })
    Character.inventory = json.encode(inv)
    exports.oxmysql:execute("UPDATE jrs_characters SET inventory = @inventory WHERE identifier = @identifier AND charidentifier = @charidentifier",
        { identifier = Character.identifier, charidentifier = Character.charIdentifier, inventory = Character.inventory })
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:removeItem", function(source, data)
    if not data.item then return { success = false, error = _U('err_item_required') } end
    local count = data.count or 1
    local User = jrsCore.getUser(source)
    if not User then return { success = false, error = _U('err_user_not_found') } end
    local Character = User.getUsedCharacter
    local inv = json.decode(Character.inventory) or {}
    local removed = 0
    for i = #inv, 1, -1 do
        if inv[i].item == data.item and removed < count then
            local toRemove = math.min(inv[i].count, count - removed)
            inv[i].count = inv[i].count - toRemove
            removed = removed + toRemove
            if inv[i].count <= 0 then table.remove(inv, i) end
        end
    end
    Character.inventory = json.encode(inv)
    exports.oxmysql:execute("UPDATE jrs_characters SET inventory = @inventory WHERE identifier = @identifier AND charidentifier = @charidentifier",
        { identifier = Character.identifier, charidentifier = Character.charIdentifier, inventory = Character.inventory })
    return { success = true, removed = removed }
end)

CoreAPI.addNewCallBack("jrs:getInventory", function(source, data)
    if GetResourceState('jrs_inventory') ~= 'started' then return {} end
    local ok, result = pcall(function() return exports.jrs_inventory:getUserInventory(tonumber(source)) end)
    return ok and type(result) == 'table' and result or {}
end)

CoreAPI.addNewCallBack("jrs:hasItem", function(source, data)
    if type(data) ~= 'table' or not data.item then return { has = false, total = 0 } end
    if GetResourceState('jrs_inventory') ~= 'started' then return { has = false, total = 0 } end
    local ok, total = pcall(function() return exports.jrs_inventory:getItemCount(tonumber(source), tostring(data.item)) end)
    total = ok and (tonumber(total) or 0) or 0
    return { has = total >= math.max(1, math.floor(tonumber(data.count) or 1)), total = total }
end)

-- WEAPONS
CoreAPI.addNewCallBack("jrs:giveWeapon", function(source, data)
    if not data.weapon then return { success = false, error = _U('err_weapon_required') } end
    if GetResourceState('jrs_inventory') ~= 'started' then
        return { success = false, error = 'jrs_inventory is not started' }
    end

    local accepted = exports['jrs_inventory']:createWeaponOwned(source, data.weapon, data.ammo or 100, data.comps or {})
    if accepted == false then
        return { success = false, error = 'Unable to add weapon to inventory' }
    end
    return { success = true }
end)

CoreAPI.addNewCallBack("jrs:removeWeapon", function(source, data)
    if not data.weapon then return { success = false, error = _U('err_weapon_required') } end
    TriggerClientEvent('jrs_core:removeWeapon', source, GetHashKey(data.weapon))
    return { success = true }
end)

-- XP / LEVEL
-- Award XP from server scripts through exports.jrs_core:AddXP(...) or CoreAPI.addxp(...).
CoreAPI.addNewCallBack("jrs:addXp", function(source, data)
    if not Config.AllowClientXpCallbacks then
        return { success = false, error = "XP can only be awarded by a server script" }
    end

    if not data.amount or tonumber(data.amount) <= 0 then
        return { success = false, error = _U('err_invalid_amount') }
    end

    local pending = promise.new()
    JRSXP.Add(source, tonumber(data.amount), data.reason or "client_callback", function(success, levelData, oldData, changedAmount, errorCode)
        pending:resolve({
            success = success == true,
            error = errorCode,
            xp = levelData and levelData.totalXp or 0,
            level = levelData and levelData.level or 1,
            currentXp = levelData and levelData.currentXp or 0,
            requiredXp = levelData and levelData.requiredXp or Config.Levels[1],
        })
    end)
    return Citizen.Await(pending)
end)

CoreAPI.addNewCallBack("jrs:getXp", function(source, data)
    local levelData = JRSXP.GetSync(source)
    if not levelData then
        return { xp = 0, level = 1, currentXp = 0, requiredXp = Config.Levels[1], progress = 0 }
    end

    return {
        xp = levelData.totalXp,
        level = levelData.level,
        currentXp = levelData.currentXp,
        requiredXp = levelData.requiredXp,
        progress = levelData.progress,
        isMaxLevel = levelData.isMaxLevel,
    }
end)

-- TELEPORT
CoreAPI.addNewCallBack("jrs:teleportToCoords", function(source, data)
    if not data.x or not data.y or not data.z then return { success = false, error = _U('err_coords_required') } end
    TriggerClientEvent('jrs_core:teleportToCoords', source, data.x, data.y, data.z, data.heading or 0.0)
    return { success = true }
end)

-- ADMIN / UTILITY
CoreAPI.addNewCallBack("jrs:isPlayerLoaded", function(source, data)
    return { loaded = PlayerData[source] ~= nil }
end)

CoreAPI.addNewCallBack("jrs:getOnlinePlayers", function(source, data)
    local players = {}
    for _, v in pairs(GetPlayers()) do
        if PlayerData[tonumber(v)] then
            table.insert(players, { source = tonumber(v), name = GetPlayerName(v) })
        end
    end
    return players
end)

-- Unified public server API.
-- Usage: local JRS = exports.jrs_core:getCoreApi()
local function buildUnifiedServerAPI()
    local api = buildLegacyServerAPI()
    local core = buildCoreAPI()
    local caller = nil
    if type(GetInvokingResource) == 'function' then
        local ok, value = pcall(GetInvokingResource)
        if ok then caller = value end
    end

    for name, value in pairs(core or {}) do
        if api[name] == nil then api[name] = value end
    end

    -- Include the authoritative core methods (getUser, addCharacter,
    -- getPlayers, account helpers, and any future additions) in the same API.
    for name, value in pairs(jrsCore or {}) do
        if api[name] == nil then api[name] = value end
    end

    api.Debug = function(text)
        if jrsCore and type(jrsCore.Debug) == "function" then
            jrsCore.Debug(text)
        else
            print("^2JRS Core - ^5" .. tostring(text) .. "^0")
        end
    end
    api.Error = function(text)
        if jrsCore and type(jrsCore.Error) == "function" then
            jrsCore.Error(text)
        else
            print("^2JRS Core - ^8Error Message^0 - ^8" .. tostring(text) .. "^0")
        end
    end
    api.Report = function(id, title, text)
        if jrsCore and type(jrsCore.Report) == "function" then
            jrsCore.Report(id, title, text)
        else
            print('^8!!REPORT ID : ' .. tostring(id) .. ' !!^0')
            print("^2Title - ^5" .. tostring(title) .. "^0")
            print("^2Text - ^5" .. tostring(text) .. "^0")
        end
    end

    api.Rpc = function(name, handler)
        return core.addNewCallBack(name, handler)
    end
    api.GetUser = function(playerSource)
        return jrsCore.getUser(tonumber(playerSource))
    end
    api.getUser = api.GetUser
    api.GetCharacter = function(playerSource)
        return jrsCore.GetCharacter(tonumber(playerSource))
    end
    api.getCharacter = api.GetCharacter
    api.IsCharacterReady = function(playerSource)
        return jrsCore.IsCharacterReady(tonumber(playerSource))
    end
    api.isCharacterReady = api.IsCharacterReady
    api.IsIdentityReady = function(playerSource)
        return jrsCore.IsCharacterReady(tonumber(playerSource))
    end
    api.isIdentityReady = api.IsIdentityReady
    api.GetCharacterState = function(playerSource)
        return jrsCore.getCharacterState(tonumber(playerSource))
    end
    api.getCharacterState = api.GetCharacterState
    api.ClearCharacter = function(playerSource, reason)
        return jrsCore.ClearCharacter(tonumber(playerSource), reason)
    end

    -- Account permission groups belong to jrs_core, not jrs_character. These
    -- aliases always use the synchronized core cache/database implementation.
    api.GetGroup = function(playerSource)
        return jrsCore.GetGroup(tonumber(playerSource))
    end
    api.getGroup = api.GetGroup
    api.SetGroup = function(playerSource, group, callback)
        return jrsCore.SetGroup(tonumber(playerSource), group, callback)
    end
    api.setGroup = api.SetGroup
    api.RefreshGroup = function(playerSource, callback)
        return jrsCore.RefreshGroup(tonumber(playerSource), callback)
    end
    api.refreshGroup = api.RefreshGroup

    api.SelectCharacterFromRow = function(playerSource, characterRow)
        return jrsCore.SelectCharacterFromRow(tonumber(playerSource), characterRow)
    end

    api.AddXP = function(playerSource, amount, reason, callback)
        return JRSXP.Add(playerSource, amount, reason, callback)
    end
    api.addXP = api.AddXP
    api.addXp = api.AddXP
    api.addxp = api.AddXP
    api.RemoveXP = function(playerSource, amount, reason, callback)
        return JRSXP.Remove(playerSource, amount, reason, callback)
    end
    api.removeXP = api.RemoveXP
    api.removeXp = api.RemoveXP
    api.removexp = api.RemoveXP
    api.SetXP = function(playerSource, amount, reason, callback)
        return JRSXP.Set(playerSource, amount, reason, callback)
    end
    api.setXP = api.SetXP
    api.setXp = api.SetXP
    api.setxp = api.SetXP
    api.GetXP = function(playerSource)
        return JRSXP.GetSync(playerSource)
    end
    api.getXP = api.GetXP
    api.getXp = api.GetXP
    api.getxp = api.GetXP
    api.GetLevel = function(playerSource)
        local data = JRSXP.GetSync(playerSource)
        return data and math.max(1, math.floor(tonumber(data.level) or 1)) or 1, data
    end
    api.getLevel = api.GetLevel
    api.getlevel = api.GetLevel
    api.getLvl = api.GetLevel
    api.SetLevel = function(playerSource, level, reason, callback)
        return JRSXP.SetLevel(playerSource, level, reason, callback)
    end
    api.setLevel = api.SetLevel
    api.setlevel = api.SetLevel
    api.setLvl = api.SetLevel
    api.AddLevel = function(playerSource, delta, reason, callback)
        return JRSXP.AddLevel(playerSource, delta, reason, callback)
    end
    api.addLevel = api.AddLevel
    api.addlevel = api.AddLevel
    api.addLvl = api.AddLevel
    api.RemoveLevel = function(playerSource, delta, reason, callback)
        return JRSXP.RemoveLevel(playerSource, delta, reason, callback)
    end
    api.removeLevel = api.RemoveLevel
    api.removelevel = api.RemoveLevel
    api.removeLvl = api.RemoveLevel
    api.GetLevelData = function(totalXp)
        return Config.GetLevelData(totalXp)
    end
    api.getLevelData = api.GetLevelData
    api.GetTotalXpForLevel = function(level)
        return Config.GetTotalXpForLevel(level)
    end
    api.getTotalXpForLevel = api.GetTotalXpForLevel

    -- Per-script (per-job) leveling. Each job/script keeps its own level 1..100
    -- and each award feeds a balanced share into the global core level.
    api.AddJobXP = function(playerSource, job, amount, reason, callback)
        return JRSJobXP and JRSJobXP.Add(playerSource, job, amount, reason, callback)
    end
    api.RemoveJobXP = function(playerSource, job, amount, reason, callback)
        return JRSJobXP and JRSJobXP.Remove(playerSource, job, amount, reason, callback)
    end
    api.SetJobXP = function(playerSource, job, amount, reason, callback)
        return JRSJobXP and JRSJobXP.Set(playerSource, job, amount, reason, callback)
    end
    api.GetJobXP = function(playerSource, job)
        return exports[GetCurrentResourceName()]:GetJobXP(playerSource, job)
    end
    api.GetJobLevel = function(playerSource, job)
        return exports[GetCurrentResourceName()]:GetJobLevel(playerSource, job)
    end
    api.GetJobLevelData = function(playerSource, job)
        return exports[GetCurrentResourceName()]:GetJobLevelData(playerSource, job)
    end
    api.GetAllJobLevels = function(playerSource)
        return exports[GetCurrentResourceName()]:GetAllJobLevels(playerSource)
    end

    api.GetPerformanceMode = function()
        return GlobalState.jrsPerformanceMode or 'auto'
    end
    api.SetPerformanceMode = function(mode)
        return exports[GetCurrentResourceName()]:SetPerformanceMode(mode)
    end
    api.SetEntityProtected = function(entity, protected)
        return exports[GetCurrentResourceName()]:SetEntityProtected(entity, protected)
    end

    api.SetPlayerInstance = function(playerSource, instance)
        local src = tonumber(playerSource)
        if not src then return false end

        if tonumber(instance) then
            local bucket = math.max(0, math.floor(tonumber(instance)))
            SetPlayerRoutingBucket(src, bucket)
            TriggerClientEvent('jrs_core:instanceChanged', src, bucket)
            return true, bucket
        end

        if type(instance) ~= 'string' or instance == '' then return false end
        Namedinstances = Namedinstances or {}
        local bucket
        for id, entry in pairs(Namedinstances) do
            if entry.name == instance then bucket = id break end
        end
        if not bucket then
            repeat bucket = math.random(1, 63) until not Namedinstances[bucket]
            Namedinstances[bucket] = { name = instance, people = {} }
        end
        table.insert(Namedinstances[bucket].people, src)
        SetPlayerRoutingBucket(src, bucket)
        TriggerClientEvent('jrs_core:instanceChanged', src, bucket)
        return true, bucket
    end
    api.ApplyHudLayout = function(playerSource, layout, charId)
        local src = tonumber(playerSource)
        -- isAdmin() is a global defined in server/hud_export.lua.
        TriggerClientEvent('jrs_core:hud:applyLayout', src, layout, charId, type(isAdmin) == 'function' and isAdmin(src))
    end
    api.SyncWheel = function(playerSource)
        TriggerClientEvent('jrs_core:wheel:forceResync', tonumber(playerSource))
    end
    api.SetWaypoint = function(playerSource, coords, name, color)
        TriggerClientEvent('jrs_core:waypoint3d:setDestination', tonumber(playerSource), coords, name, color)
    end
    api.RemoveWaypoint = function(playerSource)
        TriggerClientEvent('jrs_core:waypoint3d:removeDestination', tonumber(playerSource))
    end
    api.HealPlayer = function(playerSource)
        TriggerClientEvent('jrs_core:healPlayer', tonumber(playerSource))
    end
    api.TeleportPlayer = function(playerSource, x, y, z, heading)
        TriggerClientEvent('jrs_core:teleportToCoords', tonumber(playerSource), x, y, z, heading)
    end

    -- 1899 / RDO economy: scale a positive gameplay REWARD by the configured
    -- multiplier. Used only by AddReward, so transfers/refunds/admin stay untouched.
    api.ScaleReward = function(amount, currency)
        amount = tonumber(amount) or 0
        if amount <= 0 then return 0 end
        local eco = Config.Economy or {}
        if eco.Enabled == false then return math.floor(amount * 100 + 0.5) / 100 end
        local mult = (tonumber(currency) == 1) and (tonumber(eco.GoldMultiplier) or 1) or (tonumber(eco.RewardMultiplier) or 1)
        local scaled = math.floor((amount * mult) * 100 + 0.5) / 100
        return math.max(tonumber(eco.MinReward) or 0.05, scaled)
    end
    -- Pay a gameplay reward (money currency 0, gold 1) with the RDO scale applied.
    api.AddReward = function(playerSource, currency, amount, reason)
        currency = tonumber(currency) or 0
        local scaled = api.ScaleReward(amount, currency)
        if scaled <= 0 then return false end
        if currency == 0 then
            if JRSPerks and JRSPerks.ApplyRewardBonus then
                scaled = JRSPerks.ApplyRewardBonus(playerSource, scaled)
            end
            if JRSJobPerks and JRSJobPerks.ApplyJobPayBonus and reason then
                scaled = JRSJobPerks.ApplyJobPayBonus(playerSource, reason, scaled)
            end
            scaled = math.floor(scaled * 100 + 0.5) / 100
        end
        return api.addMoney(playerSource, currency, scaled)
    end

    api.AddMoney = function(playerSource, amount)
        return api.addMoney(playerSource, 0, amount)
    end
    api.RemoveMoney = function(playerSource, amount)
        return api.removeMoney(playerSource, 0, amount)
    end
    api.AddGold = function(playerSource, amount)
        return api.addMoney(playerSource, 1, amount)
    end
    api.RemoveGold = function(playerSource, amount)
        return api.removeMoney(playerSource, 1, amount)
    end
    api.AddDirtyMoney = function(playerSource, amount)
        return api.addMoney(playerSource, 3, amount)
    end
    api.RemoveDirtyMoney = function(playerSource, amount)
        return api.removeMoney(playerSource, 3, amount)
    end
    api.GetDirtyMoney = function(playerSource)
        local character = jrsCore.GetCharacter(tonumber(playerSource))
        return character and (tonumber(character.dirtymoney) or 0) or 0
    end
    api.GetIdentifiers = function(playerSource)
        local src = tonumber(playerSource)
        if not src then return {} end
        local identifiers = {}
        for _, value in ipairs(GetPlayerIdentifiers(src)) do
            local key = tostring(value):match('^([^:]+):') or 'unknown'
            identifiers[key] = value
        end
        return identifiers
    end
    api.GetOnlinePlayerCount = function()
        return #GetPlayers()
    end
    api.GetRestartStatus = function()
        if JRSRestartManager and JRSRestartManager.GetStatus then
            return JRSRestartManager.GetStatus()
        end
        return { enabled = false, blocked = false }
    end
    api.IsConnectionStale = function(playerSource)
        return exports[GetCurrentResourceName()]:IsConnectionStale(tonumber(playerSource))
    end
    api.GetLastHeartbeatAge = function(playerSource)
        return exports[GetCurrentResourceName()]:GetLastHeartbeatAge(tonumber(playerSource))
    end

    api.GetBalance = function(playerSource)
        local character = jrsCore.GetCharacter(tonumber(playerSource))
        if not character then return { money = 0, gold = 0, rol = 0, dirtymoney = 0, blackmoney = 0 } end
        local dirtymoney = tonumber(character.dirtymoney) or 0
        return {
            money = tonumber(character.money) or 0,
            gold = tonumber(character.gold) or 0,
            rol = tonumber(character.rol) or 0,
            dirtymoney = dirtymoney,
            blackmoney = dirtymoney,
        }
    end

    -- Core.Notify and Core.Toast land on the same unified renderer. Notify
    -- reaches it through the client's CoreNotifications.NotifyRightTip, which
    -- routes to the toast (Config.Notifications.RouteLegacyNativeFeed), so both
    -- look identical on screen.
    api.Notify = function(playerSource, text, notifyType, duration, title)
        local src = tonumber(playerSource)
        if not src or src <= 0 or text == nil or tostring(text) == '' then return false end
        TriggerClientEvent('jrs_core:sendRightTipNotification', src, tostring(text), tonumber(duration) or 3500)
        return true
    end
    api.Toast = function(playerSource, text, notifyType, duration, title)
        local src = tonumber(playerSource)
        if not src or src <= 0 or text == nil or tostring(text) == '' then return false end
        TriggerClientEvent('jrs_notify:show', src, {
            text = tostring(text),
            type = notifyType,
            duration = duration,
            title = title,
            source = caller,
        })
        return true
    end
    api.ShowNotification = function(playerSource, payload)
        local src = tonumber(playerSource)
        if not src or src <= 0 or type(payload) ~= 'table' then return false end
        local copy = {}
        for k, v in pairs(payload) do copy[k] = v end
        if copy.source == nil then copy.source = caller end
        TriggerClientEvent('jrs_notify:show', src, copy)
        return true
    end

    -- Character convenience facade: common frameworks expose a normalized
    -- character snapshot. Keep the authoritative JRS character object untouched
    -- and offer a read-only normalized view for scripts that only need data.
    api.GetCharacterData = function(playerSource)
        local src = tonumber(playerSource)
        local character = src and jrsCore.GetCharacter(src) or nil
        if not character then return nil end
        return {
            source = src,
            identifier = character.identifier,
            charIdentifier = character.charIdentifier,
            charid = character.charIdentifier,
            firstname = character.firstname,
            lastname = character.lastname,
            job = character.job,
            jobGrade = tonumber(character.jobGrade or character.jobgrade) or 0,
            group = jrsCore.GetGroup(src),
            money = tonumber(character.money) or 0,
            gold = tonumber(character.gold) or 0,
            rol = tonumber(character.rol) or 0,
            dirtymoney = tonumber(character.dirtymoney) or 0,
            xp = tonumber(character.xp) or 0,
        }
    end
    api.GetCharacterName = function(playerSource)
        local data = api.GetCharacterData(playerSource)
        if not data then return nil end
        local name = ((tostring(data.firstname or '') .. ' ' .. tostring(data.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''))
        return name ~= '' and name or GetPlayerName(tonumber(playerSource))
    end

    -- Lazy inventory facade. jrs_inventory depends on jrs_core, so resolving it
    -- only when a script actually asks for inventory functionality avoids a boot
    -- cycle and automatically survives inventory restarts.
    local function inventoryAvailable()
        return GetResourceState('jrs_inventory') == 'started'
    end
    api.IsInventoryReady = inventoryAvailable
    api.GetInventoryApi = function()
        if not inventoryAvailable() then return nil end
        local ok, inv = pcall(function() return exports.jrs_inventory:jrs_inventoryApi() end)
        return ok and inv or nil
    end
    api.AddItem = function(playerSource, itemName, count, metadata)
        if not inventoryAvailable() then return false, 'inventory_unavailable' end
        local ok, success, reason, details = pcall(function()
            return exports.jrs_inventory:addItem(tonumber(playerSource), tostring(itemName), tonumber(count), metadata, { sourceResource = caller })
        end)
        if not ok then return false, 'inventory_error' end
        return success == true, reason, details
    end
    api.RemoveItem = function(playerSource, itemName, count)
        if not inventoryAvailable() then return false, 'inventory_unavailable' end
        local ok, success, reason, details = pcall(function()
            return exports.jrs_inventory:subItem(tonumber(playerSource), tostring(itemName), tonumber(count), { sourceResource = caller })
        end)
        if not ok then return false, 'inventory_error' end
        return success == true, reason, details
    end
    api.RemoveItemById = function(playerSource, itemId, count)
        if not inventoryAvailable() then return false, 'inventory_unavailable' end
        local ok, success, reason, details = pcall(function()
            return exports.jrs_inventory:subItemByID(tonumber(playerSource), tonumber(itemId), tonumber(count), { sourceResource = caller })
        end)
        if not ok then return false, 'inventory_error' end
        return success == true, reason, details
    end
    api.GetItemCount = function(playerSource, itemName)
        if not inventoryAvailable() then return 0 end
        local ok, count = pcall(function() return exports.jrs_inventory:getItemCount(tonumber(playerSource), tostring(itemName)) end)
        return ok and (tonumber(count) or 0) or 0
    end
    api.CanCarryItem = function(playerSource, itemName, count)
        if not inventoryAvailable() then return false end
        local ok, result = pcall(function() return exports.jrs_inventory:canCarryItem(tonumber(playerSource), tostring(itemName), tonumber(count)) end)
        return ok and result == true
    end
    api.GetInventory = function(playerSource)
        if not inventoryAvailable() then return {} end
        local ok, result = pcall(function() return exports.jrs_inventory:getUserInventory(tonumber(playerSource)) end)
        return ok and type(result) == 'table' and result or {}
    end
    api.GetInventoryItemById = function(playerSource, itemId)
        if not inventoryAvailable() then return nil end
        local ok, result = pcall(function() return exports.jrs_inventory:getItemById(tonumber(playerSource), tonumber(itemId)) end)
        return ok and result or nil
    end
    api.Inventory = {
        IsReady = api.IsInventoryReady,
        GetApi = api.GetInventoryApi,
        Get = api.GetInventory,
        GetItemById = api.GetInventoryItemById,
        GetItemCount = api.GetItemCount,
        AddItem = api.AddItem,
        RemoveItem = api.RemoveItem,
        RemoveItemById = api.RemoveItemById,
        CanCarry = api.CanCarryItem,
        Transaction = function(source, operations, context)
            if not inventoryAvailable() then return false, 'inventory_unavailable', {} end
            return exports.jrs_inventory:InventoryTransaction(source, operations, context)
        end,
        RegisterHook = function(eventName, name, callback)
            if not inventoryAvailable() then return false end
            return exports.jrs_inventory:RegisterInventoryHook(eventName, name, callback)
        end,
        GetFreeWeight = function(source)
            if not inventoryAvailable() then return 0, 0, 0 end
            return exports.jrs_inventory:GetFreeWeight(source)
        end,
    }

    -- Character / player service facade
    api.Character = JRSCharacterService
    api.RPC = JRSRPC
    api.RegisterServerCallback = function(name, cb) return JRSRPC and JRSRPC.Register(name, cb) end
    api.TriggerClientCallback = function(source, name, ...) return JRSRPC and JRSRPC.CallClient(source, name, ...) end
    api.Player = {
        Get = function(source) return JRSCharacterService and JRSCharacterService.GetPlayer(source) end,
        GetAll = function() return jrsCore.getPlayers() end,
    }
    api.Metadata = {
        Get = function(source, key, default) return JRSCharacterService and JRSCharacterService.GetMetadata(source, key, default) end,
        Set = function(source, key, value) return JRSCharacterService and JRSCharacterService.SetMetadata(source, key, value) end,
        Add = function(source, key, amount) return JRSCharacterService and JRSCharacterService.AddMetadata(source, key, amount) end,
        Remove = function(source, key, amount) return JRSCharacterService and JRSCharacterService.RemoveMetadata(source, key, amount) end,
    }
    api.Jobs = {
        Get = function(source) return JRSCharacterService and JRSCharacterService.GetJobs(source) or {} end,
        Add = function(source, job, grade, label) return JRSCharacterService and JRSCharacterService.AddJob(source, job, grade, label) end,
        Remove = function(source, job) return JRSCharacterService and JRSCharacterService.RemoveJob(source, job) end,
        Switch = function(source, job) return JRSCharacterService and JRSCharacterService.SwitchJob(source, job) end,
        SetDuty = function(source, state) return JRSCharacterService and JRSCharacterService.SetDuty(source, state) end,
        ToggleDuty = function(source) return JRSCharacterService and JRSCharacterService.ToggleDuty(source) end,
        GetDutyPlayers = function(job)
            if JRSCharacterService then return JRSCharacterService.GetDutyPlayers(job) end
            return {}, 0
        end,
    }
    api.Skills = {
        Get = function(source, skill) return JRSCharacterService and JRSCharacterService.GetSkill(source, skill) end,
        GetAll = function(source) return JRSCharacterService and JRSCharacterService.GetSkills(source) or {} end,
        SetXP = function(source, skill, xp) return JRSCharacterService and JRSCharacterService.SetSkillXP(source, skill, xp) end,
        AddXP = function(source, skill, xp) return JRSCharacterService and JRSCharacterService.AddSkillXP(source, skill, xp) end,
    }
    api.Appearance = {
        -- Numeric Get/Save references are character ids. Use GetForPlayer for a server source.
        Get = function(characterId) return JRSCharacterService and JRSCharacterService.GetAppearance(characterId) end,
        GetForPlayer = function(source) return JRSCharacterService and JRSCharacterService.GetAppearanceForSource(source) end,
        Save = function(characterId, data) return JRSCharacterService and JRSCharacterService.SaveAppearance(characterId, data) end,
    }
    api.Trade = {
        IsTrading = function(source)
            if GetResourceState('jrs_inventory') ~= 'started' then return false end
            local ok, value = pcall(function() return exports.jrs_inventory:IsTrading(tonumber(source)) end)
            return ok and value == true or false
        end,
        GetSession = function(source)
            if GetResourceState('jrs_inventory') ~= 'started' then return nil end
            local ok, value = pcall(function() return exports.jrs_inventory:GetTradeSession(tonumber(source)) end)
            return ok and value or nil
        end,
        RegisterValidator = function(name, callback)
            if GetResourceState('jrs_inventory') ~= 'started' then return false, 'inventory_not_started' end
            return exports.jrs_inventory:RegisterTradeValidator(name, callback)
        end,
    }
    api.GetOfflineCharacter = function(charId) return JRSCharacterService and JRSCharacterService.GetOfflineById(charId) end
    api.GetCharacterById = function(charId) return JRSCharacterService and JRSCharacterService.GetById(charId) end
    api.GetCharactersByIdentifier = function(identifier) return JRSCharacterService and JRSCharacterService.GetByIdentifier(identifier) or {} end
    api.FindCharactersByName = function(firstname, lastname) return JRSCharacterService and JRSCharacterService.FindByName(firstname, lastname) or {} end
    api.GetCharacterCount = function(source) return JRSCharacterService and JRSCharacterService.GetCount(source) or 0 end
    api.GetMaxCharacters = function(source) return JRSCharacterService and JRSCharacterService.GetMaxCharacters(source) or Config.Char_Count end
    api.CanCreateCharacter = function(source) return JRSCharacterService and JRSCharacterService.CanCreate(source) or false end
    api.SaveCharacter = function(source) return JRSCharacterService and JRSCharacterService.Save(source) or false end

    return api
end

exports('getCoreApi', buildUnifiedServerAPI)
exports('GetCoreObject', buildUnifiedServerAPI)

-- Direct economy aliases for resources that do not want to retain the API table.
exports('AddMoney', function(...) return buildUnifiedServerAPI().AddMoney(...) end)
exports('RemoveMoney', function(...) return buildUnifiedServerAPI().RemoveMoney(...) end)
exports('AddGold', function(...) return buildUnifiedServerAPI().AddGold(...) end)
exports('RemoveGold', function(...) return buildUnifiedServerAPI().RemoveGold(...) end)
exports('AddGoldNuggets', function(playerSource, count)
    playerSource = tonumber(playerSource)
    count = math.floor(tonumber(count) or 0)
    if not playerSource or count <= 0 then return false end
    local goldBars = math.floor((count / 100.0) * 100 + 0.5) / 100
    if goldBars <= 0 then return true end
    return buildUnifiedServerAPI().AddGold(playerSource, goldBars)
end)
exports('AddDirtyMoney', function(...) return buildUnifiedServerAPI().AddDirtyMoney(...) end)
exports('RemoveDirtyMoney', function(...) return buildUnifiedServerAPI().RemoveDirtyMoney(...) end)
exports('GetBalance', function(...) return buildUnifiedServerAPI().GetBalance(...) end)

-- Native RedM notification aliases. Their visual style is unchanged.
exports('NotifyRightTip', function(...) return buildUnifiedServerAPI().NotifyRightTip(...) end)
exports('NotifyLeft', function(...) return buildUnifiedServerAPI().NotifyLeft(...) end)
exports('NotifyTip', function(...) return buildUnifiedServerAPI().NotifyTip(...) end)
exports('NotifyTop', function(...) return buildUnifiedServerAPI().NotifyTop(...) end)
exports('NotifyObjective', function(...) return buildUnifiedServerAPI().NotifyObjective(...) end)
exports('NotifySimpleTop', function(...) return buildUnifiedServerAPI().NotifySimpleTop(...) end)
exports('NotifyAdvanced', function(...) return buildUnifiedServerAPI().NotifyAdvanced(...) end)
exports('NotifyBasicTop', function(...) return buildUnifiedServerAPI().NotifyBasicTop(...) end)
exports('NotifyCenter', function(...) return buildUnifiedServerAPI().NotifyCenter(...) end)
exports('NotifyBottomRight', function(...) return buildUnifiedServerAPI().NotifyBottomRight(...) end)
exports('NotifyFail', function(...) return buildUnifiedServerAPI().NotifyFail(...) end)
exports('NotifyDead', function(...) return buildUnifiedServerAPI().NotifyDead(...) end)
exports('NotifyUpdate', function(...) return buildUnifiedServerAPI().NotifyUpdate(...) end)
exports('NotifyWarning', function(...) return buildUnifiedServerAPI().NotifyWarning(...) end)
exports('NotifyLeftRank', function(...) return buildUnifiedServerAPI().NotifyLeftRank(...) end)

exports('Notify', function(...) return buildUnifiedServerAPI().Notify(...) end)
exports('Toast', function(...) return buildUnifiedServerAPI().Toast(...) end)
exports('ShowNotification', function(...) return buildUnifiedServerAPI().ShowNotification(...) end)
exports('GetCharacterData', function(...) return buildUnifiedServerAPI().GetCharacterData(...) end)
exports('GetCharacterName', function(...) return buildUnifiedServerAPI().GetCharacterName(...) end)
exports('InventoryAddItem', function(...) return buildUnifiedServerAPI().AddItem(...) end)
exports('InventoryRemoveItem', function(...) return buildUnifiedServerAPI().RemoveItem(...) end)
exports('InventoryRemoveItemById', function(...) return buildUnifiedServerAPI().RemoveItemById(...) end)
exports('InventoryGetItemCount', function(...) return buildUnifiedServerAPI().GetItemCount(...) end)
exports('InventoryCanCarryItem', function(...) return buildUnifiedServerAPI().CanCarryItem(...) end)
exports('InventoryGet', function(...) return buildUnifiedServerAPI().GetInventory(...) end)
exports('InventoryGetItemById', function(...) return buildUnifiedServerAPI().GetInventoryItemById(...) end)
exports('IsInventoryReady', function(...) return buildUnifiedServerAPI().IsInventoryReady(...) end)

-- Stable cross-resource job mutation export. Resources such as jrs_multijob
-- should prefer this over receiving a table that contains Lua function
-- references through getCoreApi().
exports('SetJob', function(playerSource, job, grade)
    local src = tonumber(playerSource)
    job = tostring(job or '')
    grade = math.max(0, math.floor(tonumber(grade) or 0))

    if not src or src <= 0 or job == '' then
        return false, 'invalid_arguments'
    end

    if type(jrsCore.IsCharacterReady) == 'function' and not jrsCore.IsCharacterReady(src) then
        return false, 'character_not_ready'
    end

    if type(Character) ~= 'table' or type(Character.setJob) ~= 'function' then
        return false, 'set_job_unavailable'
    end

    local changed, reason = Character.setJob(src, job, grade)
    if changed ~= true then
        return false, reason or 'set_job_failed'
    end

    if type(PlayerData[src]) == 'table' then
        PlayerData[src].job = job
        PlayerData[src].jobGrade = grade
        PlayerData[src].jobgrade = grade
    end

    TriggerClientEvent('jrs_core:getPlayerJob', src, { job = job, jobGrade = grade })
    return true
end)

exports('setJob', function(playerSource, job, grade)
    return exports['jrs_core']:SetJob(playerSource, job, grade)
end)

exports('GetGroup', function(playerSource)
    return jrsCore.GetGroup(tonumber(playerSource))
end)

-- Central permission check for trusted server resources.
-- Other JRS resources should use this instead of duplicating admin-group rules.
exports('CanUseCommand', function(playerSource, commandKey)
    local src = tonumber(playerSource)
    if src == 0 then return true end
    if not src or src < 1 then return false end

    local group = jrsCore.GetGroup(src)
    if not group then return false end

    return Config.CanUseCommand(group, tostring(commandKey or '')) == true
end)

exports('IsAdmin', function(playerSource)
    local src = tonumber(playerSource)
    if src == 0 then return true end
    if not src or src < 1 then return false end

    local group = jrsCore.GetGroup(src)
    return Config.IsAdminGroup(group) == true
end)
exports('SetGroup', function(playerSource, group)
    return jrsCore.SetGroup(tonumber(playerSource), group)
end)
exports('RefreshGroup', function(playerSource)
    return jrsCore.RefreshGroup(tonumber(playerSource))
end)
exports('GetPlayerInteractionsConfig', function()
    return Config.PlayerInteractions or { Enabled = false }
end)

-- ===================================================================
-- JRS PVP Server Exports (Native JRS Core)
-- ===================================================================
exports('IsPlayerPvpEnabled', function(playerSource)
    local src = tonumber(playerSource)
    if not src or src < 1 then return false end
    local pvp = Player(src).state.jrsPvp
    if pvp ~= nil then return pvp == true end
    return Config.Gameplay and Config.Gameplay.PVP ~= false
end)

exports('SetPlayerPvp', function(playerSource, state, silent)
    local src = tonumber(playerSource)
    if not src or src < 1 then return end
    Player(src).state:set('jrsPvp', state == true, true)
    TriggerClientEvent('jrs_core:client:setPvp', src, state == true, silent == true)
end)

exports('TogglePlayerPvp', function(playerSource)
    local src = tonumber(playerSource)
    if not src or src < 1 then return end
    TriggerClientEvent('jrs_core:client:togglePvp', src)
end)
