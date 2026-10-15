if ClothingConfig.framework == 'jrs_core' then
    local JRS = exports.jrs_core:getCoreApi()
    local ServerAPI = exports.jrs_core:getCoreApi()
    local Inventory = nil

    local function getInventory()
        if type(Inventory) ~= 'table' or Inventory.addItem == nil then
            local ok, api = pcall(function()
                return exports.jrs_inventory:jrs_inventoryApi()
            end)
            if ok and type(api) == 'table' then
                Inventory = api
            end
        end
        return Inventory
    end

    -- Resolve the active JRS character without depending on the legacy
    -- PlayerData-only `loaded()` flag. The authoritative inventory and character
    -- resources both use getUser(source).getUsedCharacter, so clothing does too.
    local CharacterCache = {}

    local function refreshCoreApi()
        if type(ServerAPI) ~= 'table' or ServerAPI.getUser == nil then
            local ok, api = pcall(function() return exports.jrs_core:getCoreApi() end)
            if ok and type(api) == 'table' then
                ServerAPI = api
                JRS = api
            end
        end
        return ServerAPI
    end

    local function getActiveCharacter(source)
        source = tonumber(source)
        if not source or source <= 0 then return nil end

        local api = refreshCoreApi()
        if type(api) ~= 'table' then return nil end

        -- Important: getUser/getUsedCharacter does not depend on the old
        -- PlayerData.loaded flag and is the same source jrs_inventory trusts.
        if api.getUser ~= nil then
            local ok, user = pcall(api.getUser, source)
            if ok and type(user) == 'table' and type(user.getUsedCharacter) == 'table' then
                local character = user.getUsedCharacter
                if tonumber(character.charIdentifier or character.charidentifier) then
                    return character
                end
            end
        end

        if api.GetUser ~= nil then
            local ok, user = pcall(api.GetUser, source)
            if ok and type(user) == 'table' and type(user.getUsedCharacter) == 'table' then
                local character = user.getUsedCharacter
                if tonumber(character.charIdentifier or character.charidentifier) then
                    return character
                end
            end
        end

        -- Authoritative ready API when the core state is fully synchronized.
        local getCharacter = api.GetCharacter or api.getCharacter
        if getCharacter ~= nil then
            local ok, character = pcall(getCharacter, source)
            if ok and type(character) == 'table'
                and tonumber(character.charIdentifier or character.charidentifier) then
                return character
            end
        end

        return nil
    end

    local function getConnectionIdentifier(source)
        source = tonumber(source)
        if not source then return nil end
        local ok, identifier = pcall(function()
            if GetPlayerIdentifierByType then
                local steam = GetPlayerIdentifierByType(source, 'steam')
                if steam and steam ~= '' then return steam end
            end
            return GetPlayerIdentifier(source)
        end)
        if ok and identifier and identifier ~= '' then return tostring(identifier) end
        return nil
    end

    local function characterBelongsToPlayer(source, charid)
        source = tonumber(source)
        charid = tonumber(charid)
        if not source or not charid then return false end

        local identifier = getConnectionIdentifier(source)
        if not identifier then return false end

        local ok, owned = pcall(MySQL.scalar.await, [[
            SELECT 1 FROM `jrs_characters`
            WHERE `identifier` = ? AND `charidentifier` = ?
            LIMIT 1
        ]], { identifier, charid })
        return ok and owned ~= nil
    end

    local function getStateCharacterId(source)
        source = tonumber(source)
        if not source then return nil end
        local ok, charid = pcall(function()
            local player = Player(source)
            local state = player and player.state or nil
            return state and tonumber(state.CharacterId) or nil
        end)
        return ok and charid or nil
    end

    AddEventHandler('jrs_core:server:characterReady', function(playerSource, character)
        local src = tonumber(playerSource)
        local charid = type(character) == 'table'
            and tonumber(character.charIdentifier or character.charidentifier) or nil
        if src and charid then CharacterCache[src] = charid end
    end)

    AddEventHandler('jrs_core:server:characterUnloaded', function(playerSource)
        local src = tonumber(playerSource)
        if src then CharacterCache[src] = nil end
    end)

    AddEventHandler('playerDropped', function()
        local src = tonumber(source)
        if src then CharacterCache[src] = nil end
    end)

    function GetCharIdentifier(source, hintedCharId)
        source = tonumber(source)
        if not source or source <= 0 then return nil end

        -- 1) Exact active character object used by jrs_inventory.
        local character = getActiveCharacter(source)
        if type(character) == 'table' then
            local charid = tonumber(character.charIdentifier or character.charidentifier)
            if charid then
                CharacterCache[source] = charid
                return charid
            end
        end

        local api = refreshCoreApi()

        -- 2) Legacy PlayerData accessor, called directly without gating it behind
        --    loaded(). It is safe to use when populated and harmless when nil.
        if type(api) == 'table' and api.getCharacterIdentifier ~= nil then
            local ok, charid = pcall(api.getCharacterIdentifier, source)
            charid = ok and tonumber(charid) or nil
            if charid then
                CharacterCache[source] = charid
                return charid
            end
        end

        -- 3) CharacterReady event cache survives normal core refreshes.
        local cached = tonumber(CharacterCache[source])
        if cached and characterBelongsToPlayer(source, cached) then
            return cached
        end

        -- 4) Server-owned replicated CharacterId state. Validate ownership before use.
        local stateCharId = getStateCharacterId(source)
        if stateCharId and characterBelongsToPlayer(source, stateCharId) then
            CharacterCache[source] = stateCharId
            return stateCharId
        end

        -- 5) Client sends its current replicated CharacterId with the save request.
        --    Never trust it blindly: ownership is checked against `characters`.
        local hinted = tonumber(hintedCharId)
        if hinted and characterBelongsToPlayer(source, hinted) then
            CharacterCache[source] = hinted
            return hinted
        end

        return nil
    end

    function GetCharJob(source)
        local character = getActiveCharacter(source)
        if character and character.job ~= nil then return character.job end
        local api = refreshCoreApi()
        if type(api) == 'table' and api.getJob ~= nil then
            local ok, value = pcall(api.getJob, tonumber(source))
            if ok then return value end
        end
        return nil
    end

    function GetCharJobGrade(source)
        local character = getActiveCharacter(source)
        if character and character.jobgrade ~= nil then return character.jobgrade end
        local api = refreshCoreApi()
        if type(api) == 'table' and api.getJobGrade ~= nil then
            local ok, value = pcall(api.getJobGrade, tonumber(source))
            if ok then return value end
        end
        return nil
    end

    function GetCharFirstname(source)
        local character = getActiveCharacter(source)
        if character and character.firstname ~= nil then return character.firstname end
        local api = refreshCoreApi()
        if type(api) == 'table' and api.getFirstName ~= nil then
            local ok, value = pcall(api.getFirstName, tonumber(source))
            if ok then return value end
        end
        return nil
    end

    function GetCharLastname(source)
        local character = getActiveCharacter(source)
        if character and character.lastname ~= nil then return character.lastname end
        local api = refreshCoreApi()
        if type(api) == 'table' and api.getLastName ~= nil then
            local ok, value = pcall(api.getLastName, tonumber(source))
            if ok then return value end
        end
        return nil
    end

    -- Money operations use the same server events as JRS itself instead of
    -- trusting the Lua type reported for cross-resource function references.
    -- CFX function refs are callable but their `type()` is not guaranteed to be
    -- "function", which previously caused valid payments to be rejected.
    local function getDatabaseMoney(source)
        local charid = GetCharIdentifier(source)
        if not charid then return nil end
        local ok, value = pcall(function()
            return MySQL.scalar.await(
                'SELECT `money` FROM `jrs_characters` WHERE `charidentifier` = ? LIMIT 1',
                { tonumber(charid) }
            )
        end)
        if not ok or value == nil then return nil end
        return tonumber(value)
    end

    local function waitForMoneyChange(source, expectedPredicate, timeoutMs)
        local deadline = GetGameTimer() + (tonumber(timeoutMs) or 1500)
        repeat
            local value = getDatabaseMoney(source)
            if value ~= nil and expectedPredicate(value) then
                return true, value
            end
            Wait(50)
        until GetGameTimer() >= deadline
        return false, getDatabaseMoney(source)
    end

    local function callCrossResource(callable, ...)
        if callable == nil then return false, nil end
        local args = table.pack(...)
        return pcall(function()
            return callable(table.unpack(args, 1, args.n))
        end)
    end

    function GetCharMoney(source)
        source = tonumber(source)
        if not source then return 0 end

        -- DB is authoritative for purchases. This also avoids a stale core cache
        -- after a resource restart making the clothing shop reject/accept the
        -- wrong balance.
        local dbMoney = getDatabaseMoney(source)
        if dbMoney ~= nil then return dbMoney end

        local character = getActiveCharacter(source)
        if character and tonumber(character.money) ~= nil then
            return tonumber(character.money) or 0
        end

        local api = refreshCoreApi()
        local accountGetter = type(api) == 'table' and api.getAccount or nil
        local ok, value = callCrossResource(accountGetter, source, 0)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
        return 0
    end

    local function getLiveCoreMoney(source)
        local api = refreshCoreApi()
        if type(api) ~= 'table' then return nil end
        local getter = api.GetCharacter or api.getCharacter
        local ok, character = callCrossResource(getter, tonumber(source))
        if ok and type(character) == 'table' and tonumber(character.money) ~= nil then
            return tonumber(character.money)
        end
        return nil
    end

    function AddCurrency(source, amount)
        source = tonumber(source)
        amount = tonumber(amount) or 0
        if amount <= 0 then return true end
        if not source or source <= 0 then return false end

        local before = getDatabaseMoney(source)
        if before == nil then return false end
        local expected = before + amount

        -- First call the unified core API without checking type(fn). CFX function
        -- references can be callable while reporting a non-function Lua type.
        local api = refreshCoreApi()
        local addMoney = type(api) == 'table' and (api.addMoney or api.AddMoney) or nil
        local ok, result = callCrossResource(addMoney, source, 0, amount)
        if ok and result == true then return true end

        -- Stable legacy core event fallback. Do not retry another debit/credit path
        -- after this event: Character.addCurrency mutates the core cache immediately
        -- and writes SQL asynchronously, so retrying could duplicate the refund.
        TriggerEvent('jrs:addMoney', source, 0, amount)
        local live = getLiveCoreMoney(source)
        if live ~= nil and live >= (expected - 0.001) then return true end

        local changed = waitForMoneyChange(source, function(value)
            return value >= (expected - 0.001)
        end, 2000)
        return changed == true
    end

    function RemoveCurrency(source, amount)
        source = tonumber(source)
        amount = tonumber(amount) or 0
        if amount <= 0 then return true end
        if not source or source <= 0 then return false end

        local before = getDatabaseMoney(source)
        if before == nil or before + 0.001 < amount then return false end
        local expected = before - amount

        -- Preferred core API path. The old code rejected this function before
        -- calling it because type(removeMoney) was not always "function" in CFX.
        local api = refreshCoreApi()
        local removeMoney = type(api) == 'table' and (api.removeMoney or api.RemoveMoney) or nil
        local ok, result = callCrossResource(removeMoney, source, 0, amount)
        if ok and result == true then return true end

        -- Stable JRS event fallback. Character.removeCurrency updates its live
        -- character synchronously, then persists SQL and refreshes inventory/HUD.
        -- We verify the live/DB balance and never invoke another debit afterwards,
        -- preventing a delayed SQL write from causing a double charge.
        TriggerEvent('jrs:removeMoney', source, 0, amount)
        local live = getLiveCoreMoney(source)
        if live ~= nil and live <= (expected + 0.001) then return true end

        local changed = waitForMoneyChange(source, function(value)
            return value <= (expected + 0.001)
        end, 2000)
        return changed == true
    end

    -- City treasury (jrs_government): every successful clothing charge is income
    -- for the city the tailor is in.
    local chargeClothingCustomer = RemoveCurrency
    function RemoveCurrency(source, amount)
        local paid = chargeClothingCustomer(source, amount)
        if paid == true and (tonumber(amount) or 0) > 0 and GetResourceState('jrs_government') == 'started' then
            pcall(function()
                local ped = GetPlayerPed(tonumber(source))
                local coords = (ped and ped ~= 0 and DoesEntityExist(ped)) and GetEntityCoords(ped) or nil
                exports.jrs_government:RecordCityRevenue(tonumber(source), tonumber(amount), 'cash', {
                    category = 'clothing',
                    label = 'Clothing store',
                    coords = coords,
                })
            end)
        end
        return paid
    end

    function GetCharGroup(source)
        local api = refreshCoreApi()
        local getter = type(api) == 'table' and (api.GetGroup or api.getGroup) or nil
        if getter ~= nil then
            local ok, value = pcall(getter, tonumber(source))
            if ok then return value end
        end
        return nil
    end

    -- Ordinary inventory item path. Prefer jrs_inventory's concrete synchronous
    -- export; it returns the real mutation result and exact itemId used by rollback.
    function GiveItem(source, item, amount, metadata)
        source = tonumber(source)
        item = tostring(item or '')
        amount = tonumber(amount) or 0
        if not source or source <= 0 or item == '' or amount <= 0 then
            return false, 'invalid_item', nil
        end

        if GetResourceState('jrs_inventory') == 'started' then
            local ok, success, reason, data = pcall(function()
                return exports.jrs_inventory:addItemSync(source, item, amount, metadata or {}, 'jrs_clothing')
            end)
            if ok then
                return success == true, reason, type(data) == 'table' and data or nil
            end
        end

        local inv = getInventory()
        if type(inv) ~= 'table' or inv.addItem == nil then
            return false, 'inventory_not_ready', nil
        end

        local ok, success, reason, data = pcall(function()
            return inv.addItem(source, item, amount, metadata or {}, 'jrs_clothing')
        end)
        if not ok then
            return false, 'inventory_error', nil
        end
        return success == true, reason, type(data) == 'table' and data or nil
    end

    function IsInventoryReady(source)
        local inv = getInventory()
        if type(inv) ~= 'table' or inv.getUserInventory == nil then
            return false
        end
        local ok, inventory = pcall(function()
            return inv.getUserInventory(tonumber(source))
        end)
        return ok and type(inventory) == 'table'
    end

    function CanCarryItem(source, item, amount)
        local inv = getInventory()
        if type(inv) ~= 'table' then return false, 'inventory_not_ready' end

        if inv.getCarryInfo ~= nil then
            local ok, info = pcall(function()
                return inv.getCarryInfo(tonumber(source), tostring(item), tonumber(amount))
            end)
            if ok and type(info) == 'table' then
                return info.canCarry == true, tostring(info.reason or (info.canCarry and 'ok' or 'full'))
            end
        end

        if inv.canCarryItem ~= nil then
            local ok, canCarry = pcall(function()
                return inv.canCarryItem(tonumber(source), tostring(item), tonumber(amount))
            end)
            if ok then return canCarry == true, canCarry and 'ok' or 'full' end
        end
        return false, 'inventory_not_ready'
    end

    function RemoveItem(source, item, amount)
        local inv = getInventory()
        if type(inv) ~= 'table' or inv.subItem == nil then return false end
        local ok, success = pcall(function()
            return inv.subItem(tonumber(source), tostring(item), tonumber(amount), 'jrs_clothing')
        end)
        return ok and success == true
    end

    function RemoveItemById(source, itemId, amount)
        local inv = getInventory()
        if type(inv) ~= 'table' or inv.subItemByID == nil then return false end
        local ok, success = pcall(function()
            return inv.subItemByID(tonumber(source), tonumber(itemId), tonumber(amount), 'jrs_clothing')
        end)
        return ok and success == true
    end

    function GetItemAmount(source, item)
        local inv = getInventory()
        if type(inv) ~= 'table' or inv.getItemCount == nil then return 0 end
        local ok, count = pcall(function()
            return inv.getItemCount(tonumber(source), tostring(item))
        end)
        return ok and (tonumber(count) or 0) or 0
    end

    function OpenStash(source, stash, weight)
        local inv = getInventory()
        if type(inv) ~= 'table' then return false end
        if inv.createstorage ~= nil then
            inv.createstorage(tonumber(source), stash, tonumber(weight) or 0)
        end
        if inv.openstorage ~= nil then
            inv.openstorage(tonumber(source), stash)
        end
        return true
    end

    RegisterNetEvent('jrs_clothes:LoadSkin', function()
        local src = source
        local charId = tonumber(GetCharIdentifier(src))
        if not charId then return end

        local rows = MySQL.query.await(
            'SELECT `skinPlayer` FROM `jrs_characters` WHERE `charidentifier` = ? LIMIT 1',
            { charId }
        )
        local skin = rows and rows[1] and json.decode(rows[1].skinPlayer or '{}') or {}
        TriggerClientEvent('jrs_clothes:GetSkin', src, {
            albedo = skin.albedo,
            bodies_upper = skin.BodyType,
            bodies_lower = skin.LegsType
        })

        TriggerEvent('jrs_clothes:retrieveClothes', charId, function(result)
            if not result then
                TriggerClientEvent('jrs_clothes:GetLoadSkin', src, {}, skin)
                return
            end

            local clothes = json.decode(result.clothes or '{}') or {}
            TriggerClientEvent('jrs_clothes:GetLoadSkin', src, clothes, skin)
        end)
    end)
end
