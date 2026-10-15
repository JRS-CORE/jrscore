-- ---------------------------------------------------------------------------
-- Keep a resource's own NUI page in the player's language
--
-- A resource with an html/ page adds this next to the runtime:
--
--     client_scripts {
--         '@jrs_core/shared/jrs_lang.lua',
--         '@jrs_core/shared/jrs_lang_nui.lua',
--         ...
--     }
--
-- and includes html/jrs-i18n.js plus html/locales/*.js in its page. Nothing
-- else is needed: the language is pushed on resource start, whenever jrs_core
-- publishes a change, and whenever the page says it is ready.
--
-- SendNUIMessage always addresses the calling resource's own page, so this file
-- being loaded into many resources is exactly what makes it work.
-- ---------------------------------------------------------------------------

if IsDuplicityVersion() then return end

local function push(language)
    SendNUIMessage({ type = 'jrsLanguage', language = JrsLang.Normalize(language) or JrsLang.Current() })
end

--- Resources can call this after they build a page late, or from their own
--- "NUI ready" callback.
function JrsPushLanguageToNUI()
    push()
end

AddEventHandler('jrs_core:language:changed', function(language)
    push(language)
end)

--- A page that finishes loading after the last push asks for the value itself.
RegisterNUICallback('jrsLanguageReady', function(_, cb)
    push()
    cb({ ok = true })
end)

CreateThread(function()
    -- The page is not up on the first tick, and the player's stored language
    -- arrives a moment after connect. Push a few times early, then stop; the
    -- language:changed handler covers everything after that.
    for _ = 1, 6 do
        Wait(1500)
        push()
    end
end)
