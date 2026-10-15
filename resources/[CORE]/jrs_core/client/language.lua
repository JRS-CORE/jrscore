-- ---------------------------------------------------------------------------
-- Per-player language - client side
--
-- The authority is the server (server/language.lua) and the transport is the
-- replicated player state bag, which shared/jrs_lang.lua reads directly inside
-- every resource. This file exists for the two things a state bag cannot do:
-- expose an export for code that would rather call than read a bag, and give
-- the character screen an explicit sync event to hang its picker off.
-- ---------------------------------------------------------------------------

local currentLanguage = JrsLang.Default
local hasChosen = false

-- Broadcast replicated changes from core only, including after a restart.
AddStateBagChangeHandler(JrsLang.StateKey, nil, function(bagName, _, value)
    if bagName ~= ('player:' .. GetPlayerServerId(PlayerId())) then return end
    local normalized = JrsLang.Normalize(value)
    if not normalized or normalized == currentLanguage then return end
    currentLanguage = normalized
    TriggerEvent('jrs_core:language:changed', normalized)
end)

RegisterNetEvent('jrs_core:language:sync', function(language, chosen)
    hasChosen = chosen == true
    local normalized = JrsLang.Normalize(language) or JrsLang.Default
    TriggerEvent('jrs_core:language:synced', normalized, hasChosen)
    if normalized == currentLanguage then return end
    currentLanguage = normalized
    TriggerEvent('jrs_core:language:changed', currentLanguage)
end)

AddEventHandler('jrs_core:language:changed', function(language)
    currentLanguage = JrsLang.Normalize(language) or JrsLang.Default
end)

exports('GetLanguage', function()
    return JrsLang.Normalize(currentLanguage) or JrsLang.Current()
end)

--- False until the player has actually picked. The character screen makes the
--- language step mandatory while this is false.
exports('HasChosenLanguage', function()
    return hasChosen
end)

exports('IsLanguageRTL', function()
    return JrsLang.IsRTL(exports.jrs_core:GetLanguage())
end)

exports('GetSupportedLanguages', function()
    return JrsLang.List()
end)

--- Ask the server to store a new choice. The character screen uses this; so
--- does anything else that wants to offer a language switch.
exports('SetLanguage', function(language)
    local normalized = JrsLang.Normalize(language)
    if not normalized then return false end
    TriggerServerEvent('jrs_core:language:set', normalized)
    return true
end)

--- Historic name, kept so nothing that still calls it breaks. Switching used to
--- kick the player back to the connect screen so every resource reloaded in the
--- new language; it is live now, so this is just SetLanguage.
exports('SetLanguageAndReset', function(language)
    local normalized = JrsLang.Normalize(language)
    if not normalized then return false end
    TriggerServerEvent('jrs_core:language:set', normalized)
    return true
end)

CreateThread(function()
    -- Pull the stored choice as soon as the client is live, so anything that
    -- draws before the character screen is already in the right language.
    Wait(1000)
    TriggerServerEvent('jrs_core:language:request')
end)
