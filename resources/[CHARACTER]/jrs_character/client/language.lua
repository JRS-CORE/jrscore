-- ---------------------------------------------------------------------------
-- Language step on the character screen
--
-- This is where a player chooses the language the whole server speaks to them
-- in, before they pick a character and before they spawn. jrs_core owns the
-- value (users.language, per account); everything here is presentation.
--
-- On a brand new account the step is mandatory: the overlay appears over
-- Character Selection and cannot be dismissed until a language is picked. On
-- an account that already chose, the overlay stays closed and a small
-- "Language" button sits on the selector so the choice can be changed without
-- relogging.
-- ---------------------------------------------------------------------------

local languageOverlayShown = false
-- True while Character Selection is the screen the player is looking at.
local selectorVisible = false

local function supportedLanguages()
    if GetResourceState('jrs_core') == 'started' then
        local ok, list = pcall(function()
            return exports.jrs_core:GetSupportedLanguages()
        end)
        if ok and type(list) == 'table' and #list > 0 then return list end
    end
    return JrsLang.List()
end

local function currentLanguage()
    if GetResourceState('jrs_core') == 'started' then
        local ok, code = pcall(function()
            return exports.jrs_core:GetLanguage()
        end)
        if ok and type(code) == 'string' and code ~= '' then return code end
    end
    return JrsLang.Current()
end

local function hasChosenLanguage()
    if GetResourceState('jrs_core') ~= 'started' then return true end
    local ok, chosen = pcall(function()
        return exports.jrs_core:HasChosenLanguage()
    end)
    return not ok or chosen == true
end

--- Hand the UI the option list plus which one is active.
local function pushLanguageState()
    local lang = currentLanguage()
    SendNUIMessage({
        type = 'setLanguageOptions',
        languages = supportedLanguages(),
        current = lang,
    })
    SendNUIMessage({ type = 'setLanguage', language = lang })
    SendNUIMessage({ type = 'jrsLanguage', language = lang })
end

--- Called by the NUI as soon as Character Selection is on screen.
RegisterNUICallback('languageScreenReady', function(_, cb)
    selectorVisible = true
    pushLanguageState()
    SendNUIMessage({ type = 'showLanguageSwitch', visible = true })

    if not hasChosenLanguage() then
        languageOverlayShown = true
        SendNUIMessage({
            type = 'openLanguageMenu',
            languages = supportedLanguages(),
            current = currentLanguage(),
            mandatory = true,
        })
    end

    cb({ ok = true })
end)

--- The player picked. jrs_core validates the code and persists it; the state
--- bag update comes back through jrs_core:language:changed.
--- The player picked. The choice applies immediately, in place: jrs_core saves
--- it, republishes the state bag, and every resource repaints. The player is
--- never disconnected for changing language.
RegisterNUICallback('selectLanguage', function(data, cb)
    local wanted = type(data) == 'table' and data.language or nil
    if JrsLang.Normalize(wanted) and GetResourceState('jrs_core') == 'started' then
        pcall(function() exports.jrs_core:SetLanguage(wanted) end)
    end
    languageOverlayShown = false
    SendNUIMessage({ type = 'hideLanguageMenu' })
    cb({ ok = true })
end)

--- Character Selection closed - take the switcher and any open overlay with it.
RegisterNUICallback('languageScreenClosed', function(_, cb)
    selectorVisible = false
    languageOverlayShown = false
    SendNUIMessage({ type = 'hideLanguageMenu' })
    SendNUIMessage({ type = 'showLanguageSwitch', visible = false })
    cb({ ok = true })
end)

AddEventHandler('jrs_core:language:changed', function(language)
    SendNUIMessage({ type = 'setLanguage', language = language })
    pushLanguageState()
end)

AddEventHandler('jrs_core:language:synced', function(language, chosen)
    SendNUIMessage({ type = 'setLanguage', language = language })
    pushLanguageState()

    -- The stored value can arrive after Character Selection is already up. If
    -- it says the account never chose, raise the step now rather than letting
    -- the player through untranslated.
    if chosen ~= true and selectorVisible and not languageOverlayShown then
        languageOverlayShown = true
        SendNUIMessage({
            type = 'openLanguageMenu',
            languages = supportedLanguages(),
            current = language,
            mandatory = true,
        })
    end
end)

-- ---------------------------------------------------------------------------
-- Locale markers in NUI payloads
-- ---------------------------------------------------------------------------
--
-- The creator's label tables (Lang.Creator, Lang.Categories, CategoryLabels)
-- and the menu structures built from them are globals assembled once at load
-- time - long before the player has picked a language. Putting _U() in there
-- would freeze whichever language was active at boot.
--
-- So those tables hold @@ markers instead, and every payload on its
-- way to the NUI is walked here and resolved against the language in force at
-- that moment. One hook, and the whole creator follows a language switch with
-- no rebuild.

local MARKER = '^@@([%w_%.]+)$'

local function resolveMarkers(value, depth)
    local kind = type(value)

    if kind == 'string' then
        local key = value:match(MARKER)
        if key then
            local lang = currentLanguage()
            local translated = _UL(lang, key)
            if translated and translated ~= key then
                return translated
            end
            return _U(key)
        end
        return value
    end

    if kind ~= 'table' or depth > 12 then return value end

    local out = {}
    for k, v in pairs(value) do
        out[k] = resolveMarkers(v, depth + 1)
    end
    return out
end

--- Public helper, for code that builds a payload without going through
--- SendNUIMessage.
function JrsResolveLocaleMarkers(value)
    return resolveMarkers(value, 0)
end

do
    local rawSendNUIMessage = SendNUIMessage

    SendNUIMessage = function(payload)
        if type(payload) == 'table' then
            return rawSendNUIMessage(resolveMarkers(payload, 0))
        end
        return rawSendNUIMessage(payload)
    end
end
