if BarberConfig.framework == 'jrs_core' then
    -- These used to be plain load-time export calls. If jrs_core or
    -- jrs_inventory was not started yet the call raised, the rest of this file
    -- never ran, and GetCharIdentifier/GetCharMoney/RemoveCurrency plus the
    -- GetCharSkinTone callback simply did not exist - the barber was dead with
    -- no obvious error. Both APIs are now resolved lazily and re-resolved on
    -- demand after a dependency restart.
    local JRS = nil
    local ServerAPI = nil
    local Inventory = nil

    local function refreshCoreApi()
        if type(ServerAPI) ~= 'table' then
            local ok, api = pcall(function() return exports.jrs_core:getCoreApi() end)
            if ok and type(api) == 'table' then
                ServerAPI = api
                JRS = api
            end
        end
        return ServerAPI
    end

    local function getInventory()
        if type(Inventory) ~= 'table' then
            local ok, api = pcall(function() return exports.jrs_inventory:jrs_inventoryApi() end)
            if ok and type(api) == 'table' then Inventory = api end
        end
        return Inventory
    end

    refreshCoreApi()

    local function isLoaded(source)
        source = tonumber(source)
        local api = refreshCoreApi()
        if not source or type(api) ~= 'table' or api.loaded == nil then return false end
        local ok, loaded = pcall(api.loaded, source)
        return ok and loaded == true
    end

    -- Resolve the active character from the DB as a fallback when JRS
    -- has no in-memory PlayerData for this source yet (same root cause that left
    -- jrs_doorlocks unusable). Without this the barber can never save/load hair.
    local function resolveCharIdFromDatabase(source)
        source = tonumber(source)
        if not source then return nil end
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

        local activeCharId = nil
        local okState, stateValue = pcall(function()
            local p = Player(source)
            return p and p.state and (p.state.CharacterId or p.state.charId) or nil
        end)
        if okState then activeCharId = tonumber(stateValue) or nil end
        if activeCharId and activeCharId <= 0 then activeCharId = nil end

        local placeholders, params = {}, {}
        for i = 1, #identifiers do placeholders[#placeholders + 1] = '?'; params[#params + 1] = identifiers[i] end

        if activeCharId then
            params[#params + 1] = math.floor(activeCharId)
            local ok, row = pcall(MySQL.single.await,
                ('SELECT `charidentifier` FROM `jrs_characters` WHERE `identifier` IN (%s) AND `charidentifier` = ? LIMIT 1'):format(table.concat(placeholders, ',')),
                params)
            if ok and row and tonumber(row.charidentifier) then return tonumber(row.charidentifier) end
        end

        local ok, row = pcall(MySQL.single.await,
            ('SELECT `charidentifier` FROM `jrs_characters` WHERE `identifier` IN (%s) ORDER BY `lastupdate` DESC LIMIT 1'):format(table.concat(placeholders, ',')),
            params)
        if ok and row and tonumber(row.charidentifier) then return tonumber(row.charidentifier) end
        return nil
    end

    function GetCharIdentifier(source)
        local charId = isLoaded(source) and tonumber(ServerAPI.getCharacterIdentifier(tonumber(source))) or nil
        if charId and charId > 0 then return charId end
        return resolveCharIdFromDatabase(source)
    end

    -- The database is authoritative for purchases; a stale core cache after a
    -- resource restart must not decide whether the barber can charge.
    local function getDatabaseMoney(source)
        local charId = GetCharIdentifier(source)
        if not charId then return nil end
        local ok, value = pcall(MySQL.scalar.await,
            'SELECT `money` FROM `jrs_characters` WHERE `charidentifier` = ? LIMIT 1', { charId })
        if not ok or value == nil then return nil end
        return tonumber(value)
    end

    function GetCharMoney(source)
        local dbMoney = getDatabaseMoney(source)
        if dbMoney ~= nil then return dbMoney end
        if isLoaded(source) then
            local ok, value = pcall(ServerAPI.getAccount, tonumber(source), 0)
            if ok then return tonumber(value) or 0 end
        end
        return 0
    end

    local function getLiveCoreMoney(source)
        local api = refreshCoreApi()
        if type(api) ~= 'table' then return nil end
        local getter = api.GetCharacter or api.getCharacter
        if getter == nil then return nil end
        local ok, character = pcall(getter, tonumber(source))
        if ok and type(character) == 'table' and tonumber(character.money) ~= nil then
            return tonumber(character.money)
        end
        return nil
    end

    local function waitForMoneyChange(source, predicate, timeoutMs)
        local deadline = GetGameTimer() + (tonumber(timeoutMs) or 2000)
        repeat
            local value = getDatabaseMoney(source)
            if value ~= nil and predicate(value) then return true end
            Wait(50)
        until GetGameTimer() >= deadline
        local final = getDatabaseMoney(source)
        return final ~= nil and predicate(final)
    end

    -- This used to fire removeMoney and unconditionally `return true`, so every
    -- caller believed the player had paid even when the charge never landed.
    -- Now the balance is actually verified before reporting success.
    function RemoveCurrency(source, amount)
        source, amount = tonumber(source), tonumber(amount) or 0
        if not source or source <= 0 then return false end
        if amount <= 0 then return true end

        local before = getDatabaseMoney(source)
        if before == nil or before + 0.001 < amount then return false end
        local expected = before - amount

        local api = refreshCoreApi()
        local removeMoney = type(api) == 'table' and (api.removeMoney or api.RemoveMoney) or nil
        local ok, result = pcall(function() return removeMoney(source, 0, amount) end)
        if ok and result == true then return true end

        -- Legacy core event fallback. Never invoke a second debit after this:
        -- the core mutates its live character immediately and writes SQL
        -- asynchronously, so a retry would double-charge.
        TriggerEvent('jrs:removeMoney', source, 0, amount)
        local live = getLiveCoreMoney(source)
        if live ~= nil and live <= (expected + 0.001) then return true end

        return waitForMoneyChange(source, function(value)
            return value <= (expected + 0.001)
        end, 2000)
    end

    -- City treasury (jrs_government): every successful barber charge is income
    -- for the city the shop is in.
    local chargeBarberCustomer = RemoveCurrency
    function RemoveCurrency(source, amount)
        local paid = chargeBarberCustomer(source, amount)
        if paid == true and (tonumber(amount) or 0) > 0 and GetResourceState('jrs_government') == 'started' then
            pcall(function()
                local ped = GetPlayerPed(tonumber(source))
                local coords = (ped and ped ~= 0 and DoesEntityExist(ped)) and GetEntityCoords(ped) or nil
                exports.jrs_government:RecordCityRevenue(tonumber(source), tonumber(amount), 'cash', {
                    category = 'barber',
                    label = 'Barber service',
                    coords = coords,
                })
            end)
        end
        return paid
    end

    -- Refund path. Without this the barber had no way to undo a charge when a
    -- later step of a purchase failed.
    function AddCurrency(source, amount)
        source, amount = tonumber(source), tonumber(amount) or 0
        if not source or source <= 0 then return false end
        if amount <= 0 then return true end

        local before = getDatabaseMoney(source)
        if before == nil then return false end
        local expected = before + amount

        local api = refreshCoreApi()
        local addMoney = type(api) == 'table' and (api.addMoney or api.AddMoney) or nil
        local ok, result = pcall(function() return addMoney(source, 0, amount) end)
        if ok and result == true then return true end

        TriggerEvent('jrs:addMoney', source, 0, amount)
        local live = getLiveCoreMoney(source)
        if live ~= nil and live >= (expected - 0.001) then return true end

        return waitForMoneyChange(source, function(value)
            return value >= (expected - 0.001)
        end, 2000)
    end

    local function hashesMatch(left, right)
        left = tonumber(left)
        right = tonumber(right)
        if not left or not right then return false end
        if left == right then return true end
        if left < 0 then left = left + 4294967296 end
        if right < 0 then right = right + 4294967296 end
        return left == right
    end

    -- Seeds the barber's eye-colour selector for characters created before the
    -- barber owned eyes: their choice only exists as a raw hash in
    -- characters.skinPlayer.Eyes, so map it back to a 1-based index.
    Callback.register('jrs_barber:GetCharEyeIndex', function(source, male)
        local charId = tonumber(GetCharIdentifier(source))
        if not charId then return 0 end

        local row = MySQL.single.await(
            'SELECT `skinPlayer` FROM `jrs_characters` WHERE `charidentifier` = ? LIMIT 1', { charId })
        local skin = row and json.decode(row.skinPlayer or '{}') or {}
        local stored = tonumber(skin.Eyes)
        if not stored then return 0 end

        local genderKey = male and 'Male' or 'Female'
        if skin.sex ~= nil then
            genderKey = (tostring(skin.sex):lower() == 'mp_female') and 'Female' or 'Male'
        end
        for index, hash in ipairs((type(Eyes) == 'table' and Eyes[genderKey]) or {}) do
            if hashesMatch(hash, stored) then return index end
        end
        return 0
    end)

    Callback.register('jrs_barber:GetCharSkinTone', function(source, male, characterId)
        local charId = tonumber(characterId) or tonumber(GetCharIdentifier(source))
        if not charId then return 0 end

        local rows = MySQL.query.await(
            'SELECT `skinPlayer` FROM `jrs_characters` WHERE `charidentifier` = ? LIMIT 1',
            { charId }
        )
        local skin = rows and rows[1] and json.decode(rows[1].skinPlayer or '{}') or {}
        local albedo = tonumber(skin.albedo) or 0
        if albedo ~= 0 then return albedo end

        return GetHashKey(male and 'mp_head_mr1_sc08_c0_000_ab' or 'mp_head_fr1_sc08_c0_000_ab')
    end)
end
