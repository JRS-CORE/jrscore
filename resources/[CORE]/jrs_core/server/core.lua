LoadedUsers = {}
UserBySource = {}
AllCharacters = {}
CanSaveCoords = {}
PlayerTable = {}
PlayerData = {}

jrsCore = {}
Character = {}
User = {}

-- Account permission-group cache. The users table remains authoritative, while
-- these helpers keep LoadedUsers/UserBySource/PlayerData synchronized so every
-- resource sees the same group immediately.
local groupSyncBusy = {}
local groupLastMutation = {}

local function normalizeGroupName(value)
    local group = tostring(value or '')
    group = group:match('^%s*(.-)%s*$') or ''
    return string.lower(group)
end

-- Config.CoreOwners identifiers keep the full "owner" group even when the users
-- database row says otherwise, so a database edit can never lock the owner out.
local function isCoreOwnerIdentifier(identifier)
    local owners = Config.CoreOwners
    if type(owners) ~= 'table' then return false end
    local wanted = string.lower(tostring(identifier or ''))
    return wanted ~= '' and owners[wanted] == true
end

local function isCoreOwnerSource(source)
    local src = tonumber(source)
    if not src or src <= 0 then return false end
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if isCoreOwnerIdentifier(identifier) then return true end
    end
    return false
end

-- Keep the persisted users.group in step with Config.CoreOwners. Fire-and-forget:
-- the in-memory value is already authoritative for the current connection.
local function persistCoreOwnerGroup(identifier)
    if not isCoreOwnerIdentifier(identifier) then return end
    exports.oxmysql:execute(
        "UPDATE jrs_users SET `group` = 'owner' WHERE identifier = @identifier AND (`group` IS NULL OR `group` <> 'owner')",
        { identifier = identifier }
    )
end

jrsCore.IsCoreOwnerIdentifier = isCoreOwnerIdentifier
jrsCore.IsCoreOwnerSource = isCoreOwnerSource

local function getCoreIdentifier(source)
    return GetPlayerIdentifierByType(source, "steam") or GetPlayerIdentifier(source)
end

local function getCoreIdentifierSet(source)
    local identifiers = {}
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        identifiers[identifier] = true
    end
    return identifiers
end

local function findLoadedUserByIdentifier(identifier)
    if identifier == nil then return nil end

    local direct = LoadedUsers[identifier]
    if direct then return direct end

    local wanted = tostring(identifier)
    for loadedIdentifier, user in pairs(LoadedUsers) do
        if tostring(loadedIdentifier) == wanted then
            return user
        end
    end
    return nil
end

local function sourceOwnsIdentifier(source, identifier)
    if identifier == nil then return false end
    local identifiers = getCoreIdentifierSet(source)
    return identifiers[tostring(identifier)] == true
end

local function loadUserForSelection(identifier)
    local existing = findLoadedUserByIdentifier(identifier)
    if existing then return existing end

    local deferred = promise.new()
    exports.oxmysql:execute(
        'SELECT * FROM jrs_users WHERE identifier = @identifier LIMIT 1',
        { identifier = identifier },
        function(result)
            deferred:resolve(result and result[1] or false)
        end
    )

    local row = Citizen.Await(deferred)
    if not row then return nil end

    local user = {
        identifier = row.identifier,
        group = row.group or 'user',
        chars = tonumber(row.chars_override) or tonumber(row.chars) or tonumber(Config.Char_Count) or 1,
        warnings = tonumber(row.warnings) or 0,
        banned = tonumber(row.banned) or 0,
        setUsedCharacter = User.setUsedCharacter,
        addCharacter = jrsCore.addCharacter,
        setGroup = User.setGroup,
    }

    -- Core owners always load with the owner group, whatever the row says.
    if isCoreOwnerIdentifier(row.identifier) then
        user.group = 'owner'
        persistCoreOwnerGroup(row.identifier)
    end

    LoadedUsers[row.identifier] = user
    return user
end

local function getActiveCharacter(source)
    local src = tonumber(source)
    if not src then return nil end

    if type(jrsCore.GetCharacter) == "function" then
        return jrsCore.GetCharacter(src)
    end

    local user = jrsCore.getUser and jrsCore.getUser(src) or nil
    local character = user and (user.character or user.getUsedCharacter) or nil
    return type(character) == "table" and character or nil
end

local function getSourceFromTarget(target)
    if not target then return nil end
    if target.source and tonumber(target.source) and tonumber(target.source) > 0 then
        return tonumber(target.source)
    end
    if target.playerSource and tonumber(target.playerSource) and tonumber(target.playerSource) > 0 then
        return tonumber(target.playerSource)
    end
    local charId = tonumber(target.charIdentifier)
    if charId and PlayerData then
        for src, pData in pairs(PlayerData) do
            if tonumber(pData.charIdentifier) == charId then
                return tonumber(src)
            end
        end
    end
    return nil
end

local function applyCharacterRow(target, row)
    if type(target) ~= "table" or type(row) ~= "table" then return false end

    target.setJob = Character.setJob
    target.setMeta = Character.setMeta
    target.addCurrency = Character.addCurrency
    target.removeCurrency = Character.removeCurrency
    target.buySkin = Character.buySkin
    target.changeSkin = Character.changeSkin
    target.buySkinPlayer = Character.buySkinPlayer

    target.addXP = function(arg1, arg2, arg3, arg4)
        local src, amt, rsn, cb
        if tonumber(arg1) and tonumber(arg2) then
            src, amt, rsn, cb = tonumber(arg1), tonumber(arg2), arg3, arg4
        else
            src = getSourceFromTarget(target)
            amt, rsn, cb = tonumber(arg1), arg2, arg3
        end
        if not src then return false, 'player_not_found' end
        return JRSXP.Add(src, amt, rsn, cb)
    end
    target.addXp = target.addXP
    target.AddXP = target.addXP

    target.removeXP = function(arg1, arg2, arg3, arg4)
        local src, amt, rsn, cb
        if tonumber(arg1) and tonumber(arg2) then
            src, amt, rsn, cb = tonumber(arg1), tonumber(arg2), arg3, arg4
        else
            src = getSourceFromTarget(target)
            amt, rsn, cb = tonumber(arg1), arg2, arg3
        end
        if not src then return false, 'player_not_found' end
        return JRSXP.Remove(src, amt, rsn, cb)
    end
    target.removeXp = target.removeXP
    target.RemoveXP = target.removeXP

    target.setXP = function(arg1, arg2, arg3, arg4)
        local src, amt, rsn, cb
        if tonumber(arg1) and tonumber(arg2) then
            src, amt, rsn, cb = tonumber(arg1), tonumber(arg2), arg3, arg4
        else
            src = getSourceFromTarget(target)
            amt, rsn, cb = tonumber(arg1), arg2, arg3
        end
        if not src then return false, 'player_not_found' end
        return JRSXP.Set(src, amt, rsn, cb)
    end
    target.setXp = target.setXP
    target.SetXP = target.setXP

    target.getXP = function()
        return target.xp or 0
    end
    target.getXp = target.getXP
    target.GetXP = target.getXP

    target.getLevel = function()
        return target.level or 1
    end
    target.getLvl = target.getLevel
    target.GetLevel = target.getLevel

    target.setLevel = function(arg1, arg2, arg3, arg4)
        local src, lvl, rsn, cb
        if tonumber(arg1) and tonumber(arg2) then
            src, lvl, rsn, cb = tonumber(arg1), tonumber(arg2), arg3, arg4
        else
            src = getSourceFromTarget(target)
            lvl, rsn, cb = tonumber(arg1), arg2, arg3
        end
        if not src then return false, 'player_not_found' end
        return JRSXP.SetLevel(src, lvl, rsn, cb)
    end
    target.setLvl = target.setLevel
    target.SetLevel = target.setLevel

    target.addLevel = function(arg1, arg2, arg3, arg4)
        local src, delta, rsn, cb
        if tonumber(arg1) and tonumber(arg2) then
            src, delta, rsn, cb = tonumber(arg1), tonumber(arg2), arg3, arg4
        else
            src = getSourceFromTarget(target)
            delta, rsn, cb = tonumber(arg1), arg2, arg3
        end
        if not src then return false, 'player_not_found' end
        return JRSXP.AddLevel(src, delta, rsn, cb)
    end
    target.addLvl = target.addLevel
    target.AddLevel = target.addLevel

    target.removeLevel = function(arg1, arg2, arg3, arg4)
        local src, delta, rsn, cb
        if tonumber(arg1) and tonumber(arg2) then
            src, delta, rsn, cb = tonumber(arg1), tonumber(arg2), arg3, arg4
        else
            src = getSourceFromTarget(target)
            delta, rsn, cb = tonumber(arg1), arg2, arg3
        end
        if not src then return false, 'player_not_found' end
        return JRSXP.RemoveLevel(src, delta, rsn, cb)
    end
    target.removeLvl = target.removeLevel
    target.RemoveLevel = target.removeLevel

    target.identifier = row.identifier
    target.charIdentifier = tonumber(row.charidentifier or row.charIdentifier)
    target.firstname = row.firstname
    target.lastname = row.lastname
    target.skin = row.skinPlayer or row.skin or '{}'
    target.comp = row.compPlayer or row.comp or '{}'
    target.inventory = row.inventory or '[]'
    target.meta = row.meta or '{}'
    target.money = tonumber(row.money) or 0
    target.gold = tonumber(row.gold) or 0
    target.rol = tonumber(row.rol) or 0
    target.dirtymoney = tonumber(row.dirtymoney) or tonumber(target.dirtymoney) or 0
    target.job = row.job or 'unemployed'
    target.jobgrade = tonumber(row.jobgrade) or 0
    target.joblabel = row.joblabel or row.job or 'unemployed'
    target.onduty = (row.onduty == true or tonumber(row.onduty) == 1)
    target.multijobs = type(row.multijobs) == 'table' and row.multijobs or (function()
        local ok, value = pcall(json.decode, row.multijobs or '{}')
        return ok and type(value) == 'table' and value or {}
    end)()
    target.skills = type(row.skills) == 'table' and row.skills or (function()
        local ok, value = pcall(json.decode, row.skills or '{}')
        return ok and type(value) == 'table' and value or {}
    end)()
    target.nickname = row.nickname or ''
    target.occupation = row.occupation or ''
    target.dateofbirth = row.dateofbirth
    target.character_desc = row.character_desc or ''
    target.gender = row.gender
    target.last_played = row.last_played
    target.appearance_version = tonumber(row.appearance_version) or 1
    target.healthState = type(row.health_state) == 'table' and row.health_state or (function()
        local ok, value = pcall(json.decode, row.health_state or '{}')
        return ok and type(value) == 'table' and value or {}
    end)()
    target.coords = row.coords or '{}'
    return target.identifier ~= nil and target.charIdentifier ~= nil
end

-- Synchronize a character row supplied by jrs_character into the authoritative
-- core cache before selection. This avoids stale AllCharacters data after a
-- new character is created or when the asynchronous startup query is late.
function jrsCore.CacheCharacterRow(row)
    if type(row) ~= "table" then return false end

    local identifier = row.identifier
    local charIdentifier = tonumber(row.charidentifier or row.charIdentifier)
    if identifier == nil or charIdentifier == nil then return false end

    local cachedCharacter = nil
    for _, character in ipairs(AllCharacters) do
        if tostring(character.identifier) == tostring(identifier)
            and tonumber(character.charIdentifier) == charIdentifier then
            cachedCharacter = character
            break
        end
    end

    if not cachedCharacter then
        cachedCharacter = {}
        table.insert(AllCharacters, cachedCharacter)
    end

    if not applyCharacterRow(cachedCharacter, row) then
        return nil
    end
    return cachedCharacter
end

function Character.setJob(source, job, grade)
    grade = tonumber(grade) or 0
    if not source or not job then
        jrsCore.Error("Character.setJob(source, job, grade) - missing arguments")
        return false
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local identifier = character.identifier
    local charIdentifier = character.charIdentifier

    local allowed, reason = JRSJobIdentity.CanAssign(charIdentifier, job)
    if not allowed then
        TriggerClientEvent('jrsCore:notify', tonumber(source), 'IDENTITY REQUIRED',
            reason == 'identity_unavailable' and _U('core_identity_verification_is_unavailable_try_again')
                or _U('core_you_must_obtain_your_own_identity'), 'placeholder', 5000)
        return false, reason
    end
    -- The registry query yields; never mutate a different/reconnected character.
    if getActiveCharacter(source) ~= character or character.identifier ~= identifier
        or character.charIdentifier ~= charIdentifier then return false, 'character_changed' end
    character.job = tostring(job)
    character.jobgrade = grade

    if type(character.multijobs) ~= 'table' then character.multijobs = {} end
    character.multijobs[tostring(job)] = character.multijobs[tostring(job)] or {
        grade = tonumber(grade) or 0,
        label = tostring(character.joblabel or job)
    }
    character.multijobs[tostring(job)].grade = tonumber(grade) or 0

    if type(PlayerData[tonumber(source)]) == 'table' then
        PlayerData[tonumber(source)].job = tostring(job)
        PlayerData[tonumber(source)].jobGrade = tonumber(grade) or 0
        PlayerData[tonumber(source)].jobgrade = tonumber(grade) or 0
    end
    local player = Player(tonumber(source))
    if player and player.state then
        player.state:set('Job', tostring(job), true)
        player.state:set('JobGrade', tonumber(grade) or 0, true)
        player.state:set('JobLabel', tostring(character.joblabel or job), true)
    end

    if Config.Info_print then
        jrsCore.Debug("CharIdentifier: " .. charIdentifier .. " Job set to " .. job .. " grade " .. grade)
    end

    exports.oxmysql:execute(
        "UPDATE jrs_characters SET job = @job, jobgrade = @jobgrade, multijobs = @multijobs WHERE identifier = @identifier AND charidentifier = @charidentifier",
        {
            identifier = identifier,
            charidentifier = charIdentifier,
            job = job,
            jobgrade = grade,
            multijobs = json.encode(character.multijobs or {})
        }
    )
    TriggerEvent('jrs_core:server:jobChanged', tonumber(source), tostring(job), tonumber(grade) or 0)
    TriggerClientEvent('jrs_core:client:jobChanged', tonumber(source), tostring(job), tonumber(grade) or 0)
    TriggerEvent('jrs_core:setJob', tonumber(source), tostring(job), tonumber(grade) or 0)
    TriggerClientEvent('jrs_core:client:setJob', tonumber(source), { job = tostring(job), grade = tonumber(grade) or 0 })
    return true
end

function Character.setMeta(source, metaTable)
    if not source or not metaTable then
        jrsCore.Error("Character.setMeta(source, metaTable) - missing arguments")
        return
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local identifier = character.identifier
    local charIdentifier = character.charIdentifier

    character.meta = json.encode(metaTable)

    exports.oxmysql:execute(
        "UPDATE jrs_characters SET meta = @meta WHERE identifier = @identifier AND charidentifier = @charidentifier",
        { identifier = identifier, charidentifier = charIdentifier, meta = character.meta }
    )
    return true
end

function Character.addCurrency(source, currencyType, amount)
    if not source or not currencyType or not amount then
        jrsCore.Error("Character.addCurrency(source, type, amount) - missing arguments")
        return
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local identifier = character.identifier
    local charIdentifier = character.charIdentifier
    local currencyType = tonumber(currencyType)
    amount = tonumber(amount)
    -- Security (2026-10-02): NaN passes `amount <= 0` (every comparison with NaN
    -- is false) and would turn the balance into NaN; infinity would too.
    if currencyType == nil or not amount or amount ~= amount or amount <= 0 or amount > 1e9 then return false end

    if currencyType == 0 then
        character.money = character.money + amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET money = @money WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, money = character.money },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    elseif currencyType == 1 then
        character.gold = character.gold + amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET gold = @gold WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, gold = character.gold },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    elseif currencyType == 2 then
        character.rol = character.rol + amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET rol = @rol WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, rol = character.rol },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    elseif currencyType == 3 then
        character.dirtymoney = (tonumber(character.dirtymoney) or 0) + amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET dirtymoney = @dirtymoney WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, dirtymoney = character.dirtymoney },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    else
        jrsCore.Error("Invalid currency type: " .. currencyType)
        return false
    end

    if PlayerData[tonumber(source)] and PlayerData[tonumber(source)].account then
        PlayerData[tonumber(source)].account[currencyType] = currencyType == 0 and character.money
            or currencyType == 1 and character.gold
            or currencyType == 2 and character.rol
            or character.dirtymoney
    end
    TriggerClientEvent('jrs_core:hud:updateCurrencies', tonumber(source), character.money or 0, character.gold or 0, character.dirtymoney or 0)
    return true
end

function Character.removeCurrency(source, currencyType, amount)
    if not source or not currencyType or not amount then
        jrsCore.Error("Character.removeCurrency(source, type, amount) - missing arguments")
        return
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local identifier = character.identifier
    local charIdentifier = character.charIdentifier
    local currencyType = tonumber(currencyType)
    amount = tonumber(amount)
    -- Security (2026-10-02): NaN passes `amount <= 0` (every comparison with NaN
    -- is false) and would turn the balance into NaN; infinity would too.
    if currencyType == nil or not amount or amount ~= amount or amount <= 0 or amount > 1e9 then return false end

    if currencyType == 0 then
        character.money = character.money - amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET money = @money WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, money = character.money },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    elseif currencyType == 1 then
        character.gold = character.gold - amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET gold = @gold WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, gold = character.gold },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    elseif currencyType == 2 then
        character.rol = character.rol - amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET rol = @rol WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, rol = character.rol },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    elseif currencyType == 3 then
        character.dirtymoney = (tonumber(character.dirtymoney) or 0) - amount
        exports.oxmysql:execute(
            "UPDATE jrs_characters SET dirtymoney = @dirtymoney WHERE identifier = @identifier AND charidentifier = @charidentifier",
            { identifier = identifier, charidentifier = charIdentifier, dirtymoney = character.dirtymoney },
            function() TriggerEvent("jrs_inventory:get_money_sec", tonumber(source)) end
        )
    else
        jrsCore.Error("Invalid currency type: " .. currencyType)
        return false
    end

    if PlayerData[tonumber(source)] and PlayerData[tonumber(source)].account then
        PlayerData[tonumber(source)].account[currencyType] = currencyType == 0 and character.money
            or currencyType == 1 and character.gold
            or currencyType == 2 and character.rol
            or character.dirtymoney
    end
    TriggerClientEvent('jrs_core:hud:updateCurrencies', tonumber(source), character.money or 0, character.gold or 0, character.dirtymoney or 0)
    return true
end

function Character.buySkin(source, name, clothingTable)
    if not source or not name or not clothingTable then
        jrsCore.Error("Character.buySkin(source, name, clothingTable) - missing arguments")
        return
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local charIdentifier = character.charIdentifier

    if GetResourceState('jrs_clothing') == 'started' then
        local ok, saved = pcall(function()
            return exports.jrs_clothing:SetCharacterClothes(charIdentifier, clothingTable, 0)
        end)
        if ok and saved then
            TriggerClientEvent('jrs_clothes:reloadCurrentClothes', source)
            return true
        end
    end

    jrsCore.Error('jrs_clothing rejected Character.buySkin for charid ' .. tostring(charIdentifier))
    return false
end

function Character.buySkinPlayer(source, skinData)
    if not source or not skinData then
        jrsCore.Error("Character.buySkinPlayer(source, skinData) - missing arguments")
        return
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local identifier = character.identifier
    local charIdentifier = character.charIdentifier

    character.skin = json.encode(skinData)

    exports.oxmysql:execute(
        "UPDATE jrs_characters SET skinPlayer = @skinPlayer WHERE identifier = @identifier AND charidentifier = @charidentifier",
        { identifier = identifier, charidentifier = charIdentifier, skinPlayer = json.encode(skinData) }
    )
    return true
end

function Character.changeSkin(source, clothingTable)
    if not source or not clothingTable then
        jrsCore.Error("Character.changeSkin(source, clothingTable) - missing arguments")
        return
    end

    local character = getActiveCharacter(source)
    if not character then return false end
    local charIdentifier = character.charIdentifier

    if GetResourceState('jrs_clothing') == 'started' then
        local ok, saved = pcall(function()
            return exports.jrs_clothing:SetCharacterClothes(charIdentifier, clothingTable, 0)
        end)
        if ok and saved then
            TriggerClientEvent('jrs_clothes:reloadCurrentClothes', source)
            return true
        end
    end

    jrsCore.Error('jrs_clothing rejected Character.changeSkin for charid ' .. tostring(charIdentifier))
    return false
end

function User.setGroup(source, targetId, groupName)
    if source == nil or not targetId or not groupName then
        jrsCore.Error("User.setGroup(source, targetId, groupName) - missing arguments")
        return false
    end

    return jrsCore.SetGroup(tonumber(targetId), groupName)
end

local function clearSelectedCharacterState(source, user)
    if user then user.character = nil; user.getUsedCharacter = nil end
    PlayerTable[source] = nil
    PlayerData[source] = nil
    CanSaveCoords[source] = nil
end

-- Select a character from an authoritative database row. This path does not
-- depend on the asynchronous AllCharacters / LoadedUsers startup queries.
function jrsCore.SelectCharacterFromRow(source, characterRow)
    source = tonumber(source)
    if not source or type(characterRow) ~= 'table' then
        return false, 'invalid_arguments'
    end

    local identifier = characterRow.identifier
    local charIdentifier = tonumber(characterRow.charidentifier or characterRow.charIdentifier)
    if identifier == nil or charIdentifier == nil then
        return false, 'invalid_character_row'
    end

    if not sourceOwnsIdentifier(source, identifier) then
        return false, 'identifier_mismatch'
    end

    local user = UserBySource[source] or findLoadedUserByIdentifier(identifier)
    if not user then
        user = loadUserForSelection(identifier)
    end
    if not user then
        return false, 'user_not_loaded'
    end

    UserBySource[source] = user

    local selectedCharacter = jrsCore.CacheCharacterRow(characterRow)
    if type(selectedCharacter) ~= 'table' then
        return false, 'character_cache_failed'
    end

    if jrsCore.SetCharacterReady then
        local unloadOk, unloadResult = pcall(jrsCore.SetCharacterReady, source, false, 'selecting')
        if not unloadOk then
            return false, 'ready_reset_error:' .. tostring(unloadResult)
        end
    end

    selectedCharacter.source = source
    selectedCharacter.playerSource = source
    user.character = selectedCharacter
        user.getUsedCharacter = selectedCharacter
    PlayerTable[source] = {
        sourceData = source,
        firstname = selectedCharacter.firstname,
        lastname = selectedCharacter.lastname,
        charid = selectedCharacter.charIdentifier,
        steamid = selectedCharacter.identifier,
        playerName = GetPlayerName(source)
    }
    PlayerData[source] = {
        identifier = selectedCharacter.identifier,
        charIdentifier = selectedCharacter.charIdentifier,
        firstname = selectedCharacter.firstname,
        lastname = selectedCharacter.lastname,
        job = selectedCharacter.job,
        jobGrade = selectedCharacter.jobgrade,
        account = {
            [0] = selectedCharacter.money or 0,
            [1] = selectedCharacter.gold or 0,
            [2] = selectedCharacter.rol or 0,
            [3] = selectedCharacter.dirtymoney or 0
        },
        coords = selectedCharacter.coords,
        group = (jrsCore.GetGroup and jrsCore.GetGroup(source)) or user.group or 'user',
        gender = nil,
        dob = nil,
        clan = nil,
        identity_id = nil,
        default_weapon = nil,
        inventory_capacity = nil
    }
    CanSaveCoords[source] = true

    if jrsCore.SetCharacterReady then
        local readyOk, readyResult = pcall(jrsCore.SetCharacterReady, source, true, 'selected')
        if not readyOk then
            clearSelectedCharacterState(source, user)
            return false, 'ready_error:' .. tostring(readyResult)
        end
        if readyResult ~= true then
            clearSelectedCharacterState(source, user)
            return false, 'ready_rejected'
        end
    end

    TriggerClientEvent('jrs:SelectedCharacter', source, selectedCharacter.charIdentifier)
    TriggerClientEvent('jrs:isPlayerready', source)
    TriggerClientEvent('jrs_core:refreshPlayerVisibility', -1, source)
    return true, 'selected'
end

-- Cross-resource character selection API. Use a direct server export instead
-- of passing the jrsCore table through an event, because function members are
-- not guaranteed to survive cross-resource serialization.
exports('SelectCharacterFromRow', function(source, characterRow)
    return jrsCore.SelectCharacterFromRow(source, characterRow)
end)

function User.setUsedCharacter(source, charIdentifier, characterRow)
    source = tonumber(source)
    charIdentifier = tonumber(charIdentifier)
    if not source or not charIdentifier then return false end

    if type(characterRow) == 'table' then
        local rowCharId = tonumber(characterRow.charidentifier or characterRow.charIdentifier)
        if rowCharId ~= charIdentifier then return false end
        local selected = jrsCore.SelectCharacterFromRow(source, characterRow)
        return selected == true
    end

    local identifiers = getCoreIdentifierSet(source)
    for _, character in ipairs(AllCharacters) do
        local ownsCharacter = character.identifier ~= nil and identifiers[tostring(character.identifier)] == true
        if ownsCharacter and tonumber(character.charIdentifier) == charIdentifier then
            local selected = jrsCore.SelectCharacterFromRow(source, character)
            return selected == true
        end
    end
    return false
end

function jrsCore.getCharacter(source)
    return jrsCore.GetCharacter and jrsCore.GetCharacter(source) or nil
end

function jrsCore.isCharacterReady(source)
    return jrsCore.IsCharacterReady and jrsCore.IsCharacterReady(source) or false
end

function jrsCore.getUser(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end

    -- The source-to-user association is established when character selection
    -- succeeds. Keep it stable for the whole connection, including the period
    -- where the selected character is cleared during a character switch.
    local cachedUser = UserBySource[source]
    if cachedUser then
        return cachedUser
    end

    local identifiers = getCoreIdentifierSet(source)
    local user = nil
    for identifier in pairs(identifiers) do
        if LoadedUsers[identifier] then
            user = LoadedUsers[identifier]
            break
        end
    end

    if not user then
        for identifier in pairs(identifiers) do
            local row = MySQL.single.await('SELECT * FROM jrs_users WHERE identifier = ? LIMIT 1', { identifier })
            if row then
                user = {
                    identifier = row.identifier,
                    group = row.group or 'user',
                    chars = tonumber(row.chars_override) or tonumber(row.chars) or Config.Char_Count,
                    warnings = row.warnings or 0,
                    banned = row.banned or 0,
                    setUsedCharacter = User.setUsedCharacter,
                    addCharacter = jrsCore.addCharacter,
                    setGroup = User.setGroup,
                }
                LoadedUsers[identifier] = user
                break
            end
        end
    end

    if not user then return nil end

    UserBySource[source] = user
    return user
end

-- Stable direct user exports for integrated resources.
-- Returning the user through a dedicated export avoids depending on a table of
-- cross-resource function references returned by getCoreApi(), which can be
-- incomplete/stale across resource restarts on some RedM artifacts.
exports('GetUser', function(playerSource)
    return jrsCore.getUser(tonumber(playerSource))
end)

exports('getUser', function(playerSource)
    return jrsCore.getUser(tonumber(playerSource))
end)

local function applyGroupToCaches(source, user, groupName)
    local src = tonumber(source)
    local group = normalizeGroupName(groupName)
    if not src or src <= 0 or group == '' or type(user) ~= 'table' then return false end

    user.group = group

    local identifier = user.identifier and tostring(user.identifier) or nil
    if identifier then
        local loaded = LoadedUsers[identifier]
        if loaded then loaded.group = group end
    end

    local sourceUser = UserBySource[src]
    if sourceUser and (not identifier or tostring(sourceUser.identifier) == identifier) then
        sourceUser.group = group
    end

    local data = PlayerData[src]
    if type(data) == 'table' and (not identifier or tostring(data.identifier) == identifier) then
        data.group = group
    end

    return true
end

-- Fast authoritative in-memory group read. It also repairs PlayerData if an
-- older code path changed the user object without updating the selected-player cache.
function jrsCore.GetGroup(source)
    local src = tonumber(source)
    if not src or src <= 0 then return nil end

    local user = jrsCore.getUser(src)
    if type(user) == 'table' then
        local group = normalizeGroupName(user.group)
        if group == '' then group = 'user' end

        -- Config.CoreOwners can never lose the owner group: neither a stale
        -- database row nor a runtime mutation may downgrade them.
        if isCoreOwnerSource(src) or isCoreOwnerIdentifier(user.identifier) then
            group = 'owner'
        end

        applyGroupToCaches(src, user, group)
        return group
    end

    if isCoreOwnerSource(src) then return 'owner' end

    local data = PlayerData[src]
    if type(data) == 'table' then
        local group = normalizeGroupName(data.group)
        return group ~= '' and group or 'user'
    end
    return nil
end

jrsCore.getGroup = jrsCore.GetGroup

-- Refresh one connected player's account group directly from users.group.
-- Useful after a manual database edit; normal server-side SetGroup updates all
-- caches immediately and does not need this round-trip.
function jrsCore.RefreshGroup(source, callback)
    local src = tonumber(source)
    if not src or src <= 0 then
        if callback then callback(false, nil, 'invalid_source') end
        return false
    end

    local user = jrsCore.getUser(src)
    if type(user) ~= 'table' or not user.identifier then
        if callback then callback(false, nil, 'user_not_loaded') end
        return false
    end

    if groupSyncBusy[src] then
        if callback then callback(false, jrsCore.GetGroup(src), 'sync_busy') end
        return false
    end

    local identifier = tostring(user.identifier)
    local requestedAt = GetGameTimer()
    groupSyncBusy[src] = true

    exports.oxmysql:execute(
        'SELECT `group` FROM jrs_users WHERE identifier = @identifier LIMIT 1',
        { identifier = identifier },
        function(result)
            groupSyncBusy[src] = nil
            local row = result and result[1] or nil
            local group = row and normalizeGroupName(row.group) or ''

            -- Ignore a database result that started before a local SetGroup write.
            if (groupLastMutation[identifier] or -1) > requestedAt then
                if callback then callback(true, jrsCore.GetGroup(src), 'superseded') end
                return
            end

            -- Core owners stay owner even if the database row was edited manually.
            if isCoreOwnerIdentifier(identifier) then
                group = 'owner'
                persistCoreOwnerGroup(identifier)
            end

            if group == '' then
                if callback then callback(false, jrsCore.GetGroup(src), 'group_not_found') end
                return
            end

            local currentUser = jrsCore.getUser(src)
            if currentUser and tostring(currentUser.identifier) == identifier then
                local previous = normalizeGroupName(currentUser.group)
                applyGroupToCaches(src, currentUser, group)
                if Config.Info_print and previous ~= group then
                    jrsCore.Debug(('User %s group refreshed from database: %s -> %s'):format(identifier, previous ~= '' and previous or 'user', group))
                end
            end

            if callback then callback(true, group) end
        end
    )
    return true
end

jrsCore.refreshGroup = jrsCore.RefreshGroup

-- Server-side group mutation. Memory is updated immediately, then persisted.
-- This is the only group setter other core code should use.
function jrsCore.SetGroup(source, groupName, callback)
    local src = tonumber(source)
    local group = normalizeGroupName(groupName)
    if not src or src <= 0 or group == '' then
        if callback then callback(false, nil, 'invalid_arguments') end
        return false
    end

    local user = jrsCore.getUser(src)
    if type(user) ~= 'table' or not user.identifier then
        if callback then callback(false, nil, 'user_not_loaded') end
        return false
    end

    local identifier = tostring(user.identifier)
    -- A Config.CoreOwners account can never be downgraded from owner.
    if isCoreOwnerIdentifier(identifier) and group ~= 'owner' then
        if callback then callback(false, 'owner', 'core_owner_protected') end
        if Config.Info_print then
            jrsCore.Debug(('Refused group change for core owner %s: %s'):format(identifier, group))
        end
        return false
    end
    groupLastMutation[identifier] = GetGameTimer()
    applyGroupToCaches(src, user, group)

    exports.oxmysql:execute(
        'UPDATE jrs_users SET `group` = @group WHERE identifier = @identifier',
        { identifier = identifier, group = group },
        function(result)
            if Config.Info_print then
                jrsCore.Debug(('User %s group set to %s and synchronized in core cache'):format(identifier, group))
            end
            if callback then callback(true, group, result) end
        end
    )
    return true
end

jrsCore.setGroup = jrsCore.SetGroup

-- One lightweight database query keeps account groups synchronized even when an
-- administrator edits users.group manually while players are online.
function jrsCore.RefreshAllGroups()
    local sourcesByIdentifier = {}
    local params = {}
    local placeholders = {}

    for _, rawSource in ipairs(GetPlayers()) do
        local src = tonumber(rawSource)
        local user = src and jrsCore.getUser(src) or nil
        if type(user) == 'table' and user.identifier then
            local identifier = tostring(user.identifier)
            sourcesByIdentifier[identifier] = sourcesByIdentifier[identifier] or {}
            table.insert(sourcesByIdentifier[identifier], src)
            local key = 'identifier' .. tostring(#placeholders + 1)
            placeholders[#placeholders + 1] = '@' .. key
            params[key] = identifier
        end
    end

    if #placeholders == 0 then return false end
    local requestedAt = GetGameTimer()
    local query = 'SELECT identifier, `group` FROM jrs_users WHERE identifier IN (' .. table.concat(placeholders, ',') .. ')'

    exports.oxmysql:execute(query, params, function(rows)
        for _, row in ipairs(rows or {}) do
            local identifier = tostring(row.identifier or '')
            local group = normalizeGroupName(row.group)

            -- Never let the periodic database sync downgrade a core owner.
            if isCoreOwnerIdentifier(identifier) then
                group = 'owner'
                persistCoreOwnerGroup(identifier)
            end

            if identifier ~= '' and group ~= '' and (groupLastMutation[identifier] or -1) <= requestedAt then
                local sources = sourcesByIdentifier[identifier] or {}
                local loaded = LoadedUsers[identifier]
                if loaded then loaded.group = group end
                for _, src in ipairs(sources) do
                    local currentUser = jrsCore.getUser(src)
                    if currentUser and tostring(currentUser.identifier) == identifier then
                        applyGroupToCaches(src, currentUser, group)
                    end
                end
            end
        end
    end)
    return true
end
-- Account helpers are thin wrappers over the authoritative currency path.
-- They used to mutate only the PlayerData cache, which meant every balance
-- written through them was lost on restart and diverged from `characters`.
local ACCOUNT_CURRENCY_FIELD = { [0] = 'money', [1] = 'gold', [2] = 'rol', [3] = 'dirtymoney' }

local function accountCurrencyType(currencyType)
    local numeric = tonumber(currencyType)
    if numeric == nil or ACCOUNT_CURRENCY_FIELD[numeric] == nil then return nil end
    return numeric
end

function jrsCore.getAccount(source, currencyType)
    local src = tonumber(source)
    local numeric = accountCurrencyType(currencyType)
    if not src or numeric == nil then
        jrsCore.Error("Currency type " .. tostring(currencyType) .. " does not exist")
        return 0
    end

    -- The live character row is authoritative; the cache is only a fallback for
    -- the short window before/after the character object exists.
    local character = getActiveCharacter(src)
    if type(character) == 'table' then
        local balance = tonumber(character[ACCOUNT_CURRENCY_FIELD[numeric]])
        if balance then
            if PlayerData[src] and PlayerData[src].account then
                PlayerData[src].account[numeric] = balance
            end
            return balance
        end
    end

    if PlayerData[src] and PlayerData[src].account and PlayerData[src].account[numeric] then
        return tonumber(PlayerData[src].account[numeric]) or 0
    end

    return 0
end

function jrsCore.addAccount(source, currencyType, quantity)
    local src = tonumber(source)
    local numeric = accountCurrencyType(currencyType)
    local amount = tonumber(quantity)
    if not src or numeric == nil then
        jrsCore.Error("Currency type " .. tostring(currencyType) .. " does not exist")
        return false
    end
    if not amount or amount <= 0 then return false end

    return Character.addCurrency(src, numeric, amount) == true
end

function jrsCore.removeAccount(source, currencyType, quantity)
    local src = tonumber(source)
    local numeric = accountCurrencyType(currencyType)
    local amount = tonumber(quantity)
    if not src or numeric == nil then
        jrsCore.Error("Currency type " .. tostring(currencyType) .. " does not exist")
        return false
    end
    if not amount or amount <= 0 then return false end

    -- Preserve the historical "never go below zero" behaviour unless the server
    -- explicitly allows negative balances.
    if not Config.NegativeValueOnAccounts then
        local balance = jrsCore.getAccount(src, numeric)
        if balance <= 0 then return false end
        if amount > balance then amount = balance end
    end

    return Character.removeCurrency(src, numeric, amount) == true
end

function jrsCore.getPlayers()
    return PlayerTable
end

function jrsCore.addCharacter(source, firstname, lastname, skinData, clothingTable, onComplete)
    local identifier = getCoreIdentifier(tonumber(source))
    local coordsStart = Config.DefaultSpawnCoords
    local itemsStart = {}

    for itemName, count in pairs(Config.StartItems) do
        table.insert(itemsStart, { itemId = math.random(1, 76062001718755), item = itemName, count = count, metadata = {} })
    end

    local status = Config.DefaultCharacterStatus

    exports.oxmysql:execute(
        "INSERT INTO jrs_characters (`identifier`, `firstname`, `lastname`, `skinPlayer`, `compPlayer`, `inventory`, `coords`, `meta`, `money`, `gold`, `dirtymoney`) VALUES (@identifier, @firstname, @lastname, @skinPlayer, @compPlayer, @inventory, @coords, @meta, @money, @gold, @dirtymoney)",
        {
            identifier = identifier,
            firstname = firstname,
            lastname = lastname,
            skinPlayer = skinData,
            money = Config.StartMoney,
            gold = Config.StartGold or 0.15,
            dirtymoney = Config.StartDirtyMoney or 0,
            compPlayer = clothingTable,
            inventory = json.encode(itemsStart),
            coords = json.encode(coordsStart),
            meta = status,
        },
        function()
            exports.oxmysql:execute('SELECT * FROM jrs_characters WHERE identifier = @identifier', { identifier = identifier }, function(result)
                local createdCharIdentifier = nil
                if result then
                    for _, row in ipairs(result) do
                        if identifier == row.identifier then
                            local alreadyLoaded = false
                            for _, character in ipairs(AllCharacters) do
                                if character.charIdentifier == row.charidentifier then
                                    alreadyLoaded = true
                                    break
                                end
                            end

                            if not alreadyLoaded then
                                createdCharIdentifier = tonumber(row.charidentifier)
                                table.insert(AllCharacters, {
                                setJob = Character.setJob,
                                setMeta = Character.setMeta,
                                addCurrency = Character.addCurrency,
                                removeCurrency = Character.removeCurrency,
                                buySkin = Character.buySkin,
                                changeSkin = Character.changeSkin,
                                buySkinPlayer = Character.buySkinPlayer,
                                identifier = row.identifier,
                                charIdentifier = row.charidentifier,
                                firstname = row.firstname,
                                lastname = row.lastname,
                                skin = row.skinPlayer,
                                comp = row.compPlayer,
                                money = row.money,
                                meta = row.meta,
                                gold = row.gold,
                                rol = row.rol,
                                dirtymoney = row.dirtymoney,
                                inventory = row.inventory,
                                job = row.job,
                                jobgrade = row.jobgrade,
                                joblabel = row.joblabel or row.job,
                                onduty = (row.onduty == true or tonumber(row.onduty) == 1),
                                multijobs = {},
                                skills = {},
                                nickname = row.nickname or '',
                                occupation = row.occupation or '',
                                dateofbirth = row.dateofbirth,
                                character_desc = row.character_desc or '',
                                gender = row.gender,
                                coords = coordsStart,
                                })
                            end
                        end
                    end
                end

                if createdCharIdentifier then
                    TriggerEvent('jrs_core:server:characterCreated', tonumber(source), createdCharIdentifier, identifier)
                    if JRSCharacterService and type(JRSCharacterService.RunStarterHooks) == 'function' then
                        pcall(JRSCharacterService.RunStarterHooks, tonumber(source), createdCharIdentifier)
                    end
                end
                if onComplete then onComplete(result ~= nil, createdCharIdentifier) end
            end)
        end
    )
end

CreateThread(function()
    local interval = math.max(0, tonumber(Config.GroupSyncIntervalMs) or 0)
    if interval <= 0 then return end

    while true do
        Wait(interval)
        jrsCore.RefreshAllGroups()
    end
end)

function jrsCore.Error(text)
    print("^2JRS Core - ^8Error Message^0 - ^8" .. text .. "^0")
end

function jrsCore.Debug(text)
    print("^2JRS Core - ^5" .. text .. "^0")
end

function jrsCore.Report(id, title, text)
    print('^8!!REPORT ID : ' .. id .. ' !!^0')
    print("^2Title - ^5" .. title .. "^0")
    print("^2Text - ^5" .. text .. "^0")
end
