local characterReady = {}
local characterTransition = {}
local restoreAttemptAt = {}
AddEventHandler('playerDropped', function() restoreAttemptAt[tonumber(source)] = nil end)
local legacyGetUser = jrsCore.getUser
local CHARACTER_API_VERSION = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown'

local function normalizeSource(playerSource)
    local src = tonumber(playerSource)
    if not src or src <= 0 then return nil end
    return src
end

local function setPlayerState(src, key, value)
    local player = Player(src)
    if player and player.state then
        player.state:set(key, value, true)
    end
end

local function findLoadedUser(identifier)
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

local function restoreSelectedCharacter(src, user)
    if not user or type(user.getUsedCharacter) == "table" then
        return user
    end

    local playerData = PlayerData[src]
    if type(playerData) ~= "table" or playerData.charIdentifier == nil then
        return user
    end

    for _, character in ipairs(AllCharacters) do
        if tostring(character.identifier) == tostring(playerData.identifier)
            and tonumber(character.charIdentifier) == tonumber(playerData.charIdentifier) then
            user.getUsedCharacter = character
            break
        end
    end
    return user
end

-- Replace repeated identifier lookups with one connection-scoped association.
-- PlayerData is an authoritative recovery path because it is populated only
-- after User.setUsedCharacter has validated ownership of the character.
function jrsCore.getUser(playerSource)
    local src = normalizeSource(playerSource)
    if not src then return nil end

    local user = UserBySource[src]
    if not user then
        local playerData = PlayerData[src]
        if type(playerData) == "table" then
            user = findLoadedUser(playerData.identifier)
        end
    end

    if not user and type(legacyGetUser) == "function" then
        user = legacyGetUser(src)
    end

    if user then
        UserBySource[src] = user
        return restoreSelectedCharacter(src, user)
    end
    return nil
end

function jrsCore.IsCharacterReady(playerSource)
    local src = normalizeSource(playerSource)
    if not src then return false end

    local user = jrsCore.getUser(src)
    local character = user and user.getUsedCharacter or nil
    local validCharacter = type(character) == "table"
        and character.identifier ~= nil
        and character.charIdentifier ~= nil

    if characterReady[src] == true then
        return validCharacter
    end

    -- PlayerData and getUsedCharacter are cleared synchronously when the
    -- selector opens. If both still describe the same complete character,
    -- they are the authoritative source and a stale transition flag must not
    -- keep the player permanently unready.
    if not validCharacter then
        -- State bag still says the client is playing a character but our
        -- memory lost it (restart race: the boot-time reattach ran before
        -- LoadedUsers had them). Self-heal on demand, throttled, instead of
        -- blocking every callback until the player relogs.
        local now = GetGameTimer()
        if (restoreAttemptAt[src] or 0) <= now then
            restoreAttemptAt[src] = now + 10000
            local player = Player(src)
            if player and player.state and player.state.CharacterReady == true
                and type(jrsCore.RestoreConnectedCharacter) == "function" then
                pcall(jrsCore.RestoreConnectedCharacter, src)
            end
        end
        return false
    end

    local playerData = PlayerData[src]
    if type(playerData) ~= "table"
        or tostring(playerData.identifier) ~= tostring(character.identifier)
        or tostring(playerData.charIdentifier) ~= tostring(character.charIdentifier) then
        return false
    end

    return jrsCore.SetCharacterReady(src, true, "reconciled") == true
end

function jrsCore.GetCharacter(playerSource)
    local src = normalizeSource(playerSource)
    if not src or not jrsCore.IsCharacterReady(src) then return nil end

    local user = jrsCore.getUser(src)
    return user and user.getUsedCharacter or nil
end

function jrsCore.SetCharacterReady(playerSource, ready, reason)
    local src = normalizeSource(playerSource)
    if not src then return false end

    ready = ready == true
    if ready then
        local user = jrsCore.getUser(src)
        local character = user and user.getUsedCharacter or nil
        if type(character) ~= "table" or character.identifier == nil or character.charIdentifier == nil then
            return false
        end

        -- Idempotency guard: if the player is already ready for this exact character,
        -- avoid re-broadcasting characterLoaded and characterReady lifecycle events.
        if characterReady[src] == true
            and PlayerData[src] ~= nil
            and tostring(PlayerData[src].charIdentifier) == tostring(character.charIdentifier) then
            return true
        end

        characterReady[src] = true
        characterTransition[src] = false
        setPlayerState(src, "CharacterIdentifier", tostring(character.identifier))
        setPlayerState(src, "CharacterId", tonumber(character.charIdentifier) or character.charIdentifier)
        setPlayerState(src, "FirstName", tostring(character.firstname or ''))
        setPlayerState(src, "LastName", tostring(character.lastname or ''))
        setPlayerState(src, "Job", tostring(character.job or 'unemployed'))
        setPlayerState(src, "JobGrade", tonumber(character.jobgrade or character.jobGrade) or 0)
        setPlayerState(src, "JobLabel", tostring(character.joblabel or character.job or 'unemployed'))
        setPlayerState(src, "OnDuty", character.onduty == true)
        setPlayerState(src, "Gender", tostring(character.gender or ''))
        setPlayerState(src, "CharacterReady", true)

        TriggerEvent("jrs_core:server:characterLoaded", src, character)
        TriggerEvent("jrs_core:server:characterReady", src, character)
        TriggerClientEvent("jrs_core:client:characterLoaded", src, tonumber(character.charIdentifier) or character.charIdentifier)
        TriggerClientEvent("jrs_core:client:characterReady", src, tonumber(character.charIdentifier) or character.charIdentifier)
        return true
    end

    local previous = nil
    local user = jrsCore.getUser(src)
    if user and type(user.getUsedCharacter) == "table" then
        previous = user.getUsedCharacter
    end

    characterReady[src] = false
    characterTransition[src] = true
    setPlayerState(src, "CharacterReady", false)
    setPlayerState(src, "CharacterId", false)
    setPlayerState(src, "CharacterIdentifier", false)
    setPlayerState(src, "FirstName", false)
    setPlayerState(src, "LastName", false)
    setPlayerState(src, "Job", false)
    setPlayerState(src, "JobGrade", false)
    setPlayerState(src, "JobLabel", false)
    setPlayerState(src, "OnDuty", false)
    setPlayerState(src, "Gender", false)

    TriggerEvent("jrs_core:server:characterUnloaded", src, previous, reason or "unknown")
    TriggerClientEvent("jrs_core:client:characterUnloaded", src, reason or "unknown")
    return true
end

function jrsCore.ClearCharacter(playerSource, reason)
    local src = normalizeSource(playerSource)
    if not src then return false end

    jrsCore.SetCharacterReady(src, false, reason or "clear")
    local user = jrsCore.getUser(src)
    if user then user.getUsedCharacter = nil end
    PlayerTable[src] = nil
    PlayerData[src] = nil
    CanSaveCoords[src] = nil
    return true
end

-- Reattach an already-connected player's character bookkeeping after jrs_core's
-- own resource restart wiped PlayerData/UserBySource/characterReady in memory.
-- The player never disconnected - the client is still walking around with a
-- fully loaded character - while every server-side IsCharacterReady/GetCharacter
-- check now says NO_CHARACTER until they relog. This was the actual root cause
-- behind repeated STATIC_ACCESS_DENIED reason=NO_CHARACTER failures in
-- jrs_stores, surfacing even after jrs_stores itself was fixed three times.
-- State bag keys (CharacterReady/CharacterIdentifier/CharacterId) are server-
-- core state, not script memory, so they survive this resource's restart
-- intact and are the only reliable record of which character to reattach.
-- Deliberately does NOT call SetCharacterReady or fire any characterLoaded/
-- characterReady/SelectedCharacter event - those are consumed by 70+ other
-- resources as "run first-time spawn setup", and re-firing them on an
-- already-playing session risks duplicate initialization (extra starting
-- items, doubled blips/threads) instead of fixing anything. This only repairs
-- jrs_core's own bookkeeping so other resources' access checks see the truth.
-- Async (callback-based, no Citizen.Await) so this is safe to call from
-- inside another resource's oxmysql callback, where coroutine context is not
-- guaranteed. Fire-and-forget: callers don't need the result synchronously.
function jrsCore.RestoreConnectedCharacter(playerSource)
    local src = normalizeSource(playerSource)
    if not src then return end
    if characterReady[src] == true then return end

    local player = Player(src)
    local state = player and player.state
    if not state or state.CharacterReady ~= true then return end

    local identifier = state.CharacterIdentifier
    local charIdentifier = tonumber(state.CharacterId)
    if identifier == nil or identifier == '' or charIdentifier == nil then return end

    local user = findLoadedUser(identifier)
    if not user then return end

    exports.oxmysql:execute(
        'SELECT * FROM jrs_characters WHERE identifier = @identifier AND charidentifier = @charidentifier LIMIT 1',
        { identifier = identifier, charidentifier = charIdentifier },
        function(result)
            local row = result and result[1]
            if not row then return end
            jrsCore.ApplyRestoredCharacter(src, user, row)
        end
    )
end

function jrsCore.ApplyRestoredCharacter(src, user, row)
    -- The player may have dropped, relogged, or already been reattached
    -- (e.g. by their own client re-triggering selection) while this query
    -- was in flight - re-check both before writing anything.
    if characterReady[src] == true then return end
    if GetPlayerName(src) == nil then return end

    local character = jrsCore.CacheCharacterRow(row)
    if type(character) ~= 'table' then return end
    character.source = src
    character.playerSource = src

    user.getUsedCharacter = character
    UserBySource[src] = user
    PlayerTable[src] = {
        sourceData = src,
        firstname = character.firstname,
        lastname = character.lastname,
        charid = character.charIdentifier,
        steamid = character.identifier,
        playerName = GetPlayerName(src)
    }
    PlayerData[src] = {
        identifier = character.identifier,
        charIdentifier = character.charIdentifier,
        firstname = character.firstname,
        lastname = character.lastname,
        job = character.job,
        jobGrade = character.jobgrade,
        account = {
            [0] = character.money or 0,
            [1] = character.gold or 0,
            [2] = character.rol or 0,
            [3] = character.dirtymoney or 0
        },
        coords = character.coords,
        group = user.group or 'user',
        gender = nil,
        dob = nil,
        clan = nil,
        identity_id = nil,
        default_weapon = nil,
        inventory_capacity = nil
    }
    CanSaveCoords[src] = true
    characterReady[src] = true
    characterTransition[src] = false

    print(('^2[jrs_core]^7 Reattached src=%s to identifier=%s charIdentifier=%s after resource restart'):format(src, tostring(character.identifier), tostring(character.charIdentifier)))
end

exports("GetCharacter", function(playerSource)
    return jrsCore.GetCharacter(playerSource)
end)

exports("IsCharacterReady", function(playerSource)
    return jrsCore.IsCharacterReady(playerSource)
end)

-- Identity gate: true only when the player has a character loaded against their
-- account identifier. Scripts should call this (or IsCharacterReady) before any
-- player-bound action so nothing works without a verified identity.
exports("IsIdentityReady", function(playerSource)
    return jrsCore.IsCharacterReady(playerSource)
end)

function jrsCore.getCharacter(playerSource)
    return jrsCore.GetCharacter(playerSource)
end

function jrsCore.isCharacterReady(playerSource)
    return jrsCore.IsCharacterReady(playerSource)
end

function jrsCore.getCharacterState(playerSource)
    local src = normalizeSource(playerSource)
    if not src then return { ready = false, version = CHARACTER_API_VERSION } end

    local character = jrsCore.GetCharacter(src)
    return {
        ready = character ~= nil,
        version = CHARACTER_API_VERSION,
        identifier = character and tostring(character.identifier) or nil,
        charIdentifier = character and (tonumber(character.charIdentifier) or character.charIdentifier) or nil
    }
end

exports("GetCharacterState", function(playerSource)
    return jrsCore.getCharacterState(playerSource)
end)

AddEventHandler("jrs_core:server:clearCharacter", function(playerSource, reason)
    jrsCore.ClearCharacter(playerSource, reason)
end)

AddEventHandler("playerJoining", function()
    local src = tonumber(source)
    if src then jrsCore.SetCharacterReady(src, false, "joining") end
end)

AddEventHandler("playerDropped", function()
    local src = tonumber(source)
    if not src then return end
    -- Mark unavailable immediately, but let older playerDropped handlers save
    -- coordinates/meta from the still-attached character during this tick.
    jrsCore.SetCharacterReady(src, false, "dropped")
    SetTimeout(0, function()
        local user = jrsCore.getUser(src)
        if user then user.getUsedCharacter = nil end
        PlayerTable[src] = nil
        PlayerData[src] = nil
        CanSaveCoords[src] = nil
        UserBySource[src] = nil
        characterReady[src] = nil
        characterTransition[src] = nil
    end)
end)

-- (Startup diagnostic print removed: it only reported Lua types on boot.)
