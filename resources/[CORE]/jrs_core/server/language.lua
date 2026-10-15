-- ---------------------------------------------------------------------------
-- Per-player language - server authority
--
-- The player picks a language on the character screen, before spawning. That
-- choice lives on the account (users.language), not on the character, so it is
-- known the moment the player connects and applies to every character.
--
-- The chosen language is published on the player state bag under
-- JrsLang.StateKey ('jrsLanguage'), replicated. Any other resource then reads
-- it with no event round trip:
--
--     server:  JrsLang.Of(src)          -- or exports.jrs_core:GetPlayerLanguage(src)
--     client:  JrsLang.Current()        -- or LocalPlayer.state.jrsLanguage
--
-- shared/jrs_lang.lua is what actually does those reads; this file only decides
-- what the value is and keeps it in the database.
-- ---------------------------------------------------------------------------

local DEFAULT_LANGUAGE = JrsLang.Normalize(Config and Config.defaultlang) or JrsLang.Default

-- identifier -> language code. Survives a player reconnecting within a session.
local languageByIdentifier = {}
-- src -> language code, for the window before the state bag settles.
local languageBySource = {}
-- identifier -> true once the account has an explicit stored choice. A NULL
-- users.language means the player has never been asked, which is what makes
-- the character screen show the language step before anything else.
local hasChosenByIdentifier = {}

local columnReady = false
local columnCheckStarted = false
local columnWaiters = {}

local function coreIdentifier(source)
    local src = tonumber(source)
    if not src or src <= 0 then return nil end
    if jrsCore and type(jrsCore.getUser) == 'function' then
        local user = jrsCore.getUser(src)
        if user and user.identifier then
            return user.identifier
        end
    end
    return GetPlayerIdentifierByType(src, 'steam')
        or GetPlayerIdentifierByType(src, 'license')
        or GetPlayerIdentifier(src)
end

--- Write the language onto the replicated player state bag.
local function publish(source, language)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    local player = Player(src)
    if not player or not player.state then return end
    player.state:set(JrsLang.StateKey, language, true)
end

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

-- users.language is added on boot when it is missing, so an existing database
-- does not need the .sql applied by hand. sql/language.sql holds the same
-- statement for a clean install.
local function ensureColumn(done)
    if columnReady then
        if done then done() end
        return
    end

    if done then columnWaiters[#columnWaiters + 1] = done end
    if columnCheckStarted then return end
    columnCheckStarted = true

    local function finishColumnCheck()
        columnReady = true
        local waiters = columnWaiters
        columnWaiters = {}
        for i = 1, #waiters do
            local ok, err = pcall(waiters[i])
            if not ok then
                print(('[jrs_core] language schema waiter failed: %s'):format(tostring(err)))
            end
        end
    end

    exports.oxmysql:execute([[
        SELECT COUNT(*) AS present
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'jrs_users'
          AND COLUMN_NAME = 'language'
    ]], {}, function(result)
        local present = result and result[1] and tonumber(result[1].present) or 0
        if present > 0 then
            finishColumnCheck()
            return
        end

        exports.oxmysql:execute(
            "ALTER TABLE `jrs_users` ADD COLUMN `language` VARCHAR(8) NULL DEFAULT NULL",
            {},
            function()
                print('[jrs_core] users.language column created.')
                finishColumnCheck()
            end
        )
    end)
end

CreateThread(function()
    -- oxmysql is not necessarily up on the first tick.
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    ensureColumn()
end)

-- ---------------------------------------------------------------------------
-- Load / save
-- ---------------------------------------------------------------------------

local function loadLanguage(source, callback)
    local src = tonumber(source)
    local identifier = coreIdentifier(src)

    if not identifier then
        if callback then callback(DEFAULT_LANGUAGE) end
        return
    end

    local cached = languageByIdentifier[identifier]
    if cached then
        languageBySource[src] = cached
        publish(src, cached)
        if callback then callback(cached, hasChosenByIdentifier[identifier] == true) end
        return
    end

    if not columnReady then
        -- Wait for the schema check instead of presenting a returning player
        -- as new or overwriting the language already stored for the account.
        ensureColumn(function()
            loadLanguage(src, callback)
        end)
        return
    end

    exports.oxmysql:execute(
        'SELECT `language` FROM jrs_users WHERE identifier = @identifier LIMIT 1',
        { identifier = identifier },
        function(result)
            local stored = result and result[1] and result[1].language
            local language = JrsLang.Normalize(stored) or DEFAULT_LANGUAGE
            local chosen = JrsLang.Normalize(stored) ~= nil
            languageByIdentifier[identifier] = language
            hasChosenByIdentifier[identifier] = chosen
            languageBySource[src] = language
            publish(src, language)
            if callback then callback(language, chosen) end
        end
    )
end

local function saveLanguage(source, language, onComplete)
    local src = tonumber(source)
    local identifier = coreIdentifier(src)
    local normalized = JrsLang.Normalize(language)

    if not identifier or not normalized then
        if onComplete then onComplete(false) end
        return false
    end

    languageByIdentifier[identifier] = normalized
    hasChosenByIdentifier[identifier] = true
    languageBySource[src] = normalized
    publish(src, normalized)

    local function persist(done)
        exports.oxmysql:execute(
            'UPDATE jrs_users SET `language` = @language WHERE identifier = @identifier',
            { language = normalized, identifier = identifier },
            function(result)
                if done then done(true) end
            end
        )
    end

    local function finish()
        TriggerClientEvent('jrs_core:language:sync', src, normalized, true)
        TriggerEvent('jrs_core:language:serverChanged', src, normalized)
        if onComplete then onComplete(true, normalized) end
    end

    if columnReady then
        persist(finish)
    else
        -- A fast first selection can arrive while the schema check is still
        -- running. Queue the write so the choice is never session-only.
        ensureColumn(function()
            persist(finish)
        end)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

AddEventHandler('playerJoining', function()
    local src = source
    CreateThread(function()
        -- The state bag only exists once the player object does.
        Wait(500)
        loadLanguage(src)
    end)
end)

AddEventHandler('playerDropped', function()
    languageBySource[source] = nil
end)

-- ---------------------------------------------------------------------------
-- Client contract
-- ---------------------------------------------------------------------------

--- The character screen asks for the stored choice while it builds the picker.
RegisterNetEvent('jrs_core:language:request', function()
    local src = source
    loadLanguage(src, function(language, chosen)
        TriggerClientEvent('jrs_core:language:sync', src, language, chosen == true)
    end)
end)

--- The character screen sends the player's pick. Anything not in
--- JrsLang.Supported is dropped - a client can only ever choose from the list
--- the server ships.
RegisterNetEvent('jrs_core:language:set', function(language)
    local src = source
    if not saveLanguage(src, language) then
        TriggerClientEvent('jrs_core:language:sync', src, JrsLang.Of(src), false)
    end
end)

--- Historic name. It used to persist the choice and then DropPlayer() the
--- player so every client resource reloaded in the new language. Switching is
--- live now - every resource re-reads the state bag and repaints in place - so
--- this is kept only so an older client script cannot kick anyone, and does
--- exactly what 'jrs_core:language:set' does.
RegisterNetEvent('jrs_core:language:setAndReset', function(language)
    local src = tonumber(source)
    if not src or src <= 0 then return end

    if not saveLanguage(src, language) then
        TriggerClientEvent('jrs_core:language:sync', src, JrsLang.Of(src), false)
    end
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('GetPlayerLanguage', function(playerSource)
    local src = tonumber(playerSource)
    if not src or src <= 0 then return DEFAULT_LANGUAGE end
    return JrsLang.Normalize(languageBySource[src]) or JrsLang.Of(src)
end)

exports('SetPlayerLanguage', function(playerSource, language)
    return saveLanguage(playerSource, language)
end)

exports('GetSupportedLanguages', function()
    return JrsLang.List()
end)

--- True once the account has an explicit stored choice. The character screen
--- uses this to decide whether the language step is mandatory this session.
exports('HasChosenLanguage', function(playerSource)
    local identifier = coreIdentifier(playerSource)
    return identifier ~= nil and hasChosenByIdentifier[identifier] == true
end)

-- ---------------------------------------------------------------------------
-- Admin / player command
-- ---------------------------------------------------------------------------

-- Admin command: change the admin's own stored language.
-- Regular players select their language through the character selection UI;
-- all chat commands are strictly reserved for administrators and console.
local langCmdName = (Config.Commands and Config.Commands.language) or 'language'
RegisterCommand(langCmdName, function(source, args)
    local src = tonumber(source) or 0
    if not isAdminOrConsole(source, 'language') then return end

    local wanted = JrsLang.Normalize(args and args[1])
    if not wanted then
        local codes = {}
        for _, entry in ipairs(JrsLang.Supported) do codes[#codes + 1] = entry.code end
        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, {
                args = { 'Language', (_Up(src, 'core_usage_language') or _U('core_usage_language')):format(table.concat(codes, ' | ')) }
            })
        else
            print('[jrs_core] Usage: /' .. langCmdName .. ' <' .. table.concat(codes, ' | ') .. '>')
        end
        return
    end

    if src > 0 then
        saveLanguage(src, wanted)
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'Language', _Up(src, 'language_changed') }
        })
    else
        print('[jrs_core] Server console should use: /setlang <playerId> <' .. wanted .. '>')
    end
end, false)

--- Admin command: change another player's stored language. Goes through the
--- same saveLanguage() as the player-facing /language command above, so it
--- updates users.language, the replicated state bag, and every resource that
--- reads JrsLang.Of(src) - nothing sees a stale language after this runs.
local function notifySetLang(target, message)
    local dst = tonumber(target) or 0
    if dst <= 0 then
        print('[jrs_core] ' .. tostring(message))
        return
    end
    TriggerClientEvent('chat:addMessage', dst, { args = { 'Language', message } })
end

RegisterCommand(Config.Commands.setlang, function(source, args)
    if not isAdminOrConsole(source, 'setlang') then return end

    local targetId = tonumber(args and args[1])
    if not targetId or not GetPlayerName(targetId) then
        notifySetLang(source, _Up(source, 'player_not_found'))
        return
    end

    local wanted = JrsLang.Normalize(args and args[2])
    if not wanted then
        local codes = {}
        for _, entry in ipairs(JrsLang.Supported) do codes[#codes + 1] = entry.code end
        notifySetLang(source, (_Up(source, 'usage_setlang')):format(table.concat(codes, ' | ')))
        return
    end

    saveLanguage(targetId, wanted)
    notifySetLang(source, _Up(source, 'cmd_set_player_language_to', targetId, wanted))
    notifySetLang(targetId, _Up(targetId, 'cmdt_your_language_was_set_to', wanted))
end, false)
