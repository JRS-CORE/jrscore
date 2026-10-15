

Locales = Locales or {}

local function loadLocaleFile(lang)
    local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
    if not raw then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end
    return decoded
end

local function normalizeLang(lang)
    if type(lang) ~= 'string' then return 'en' end
    lang = lang:lower():gsub('_', '-'):match('^[a-z]+') or 'en'
    return lang
end

local selectedLang = normalizeLang((Config and Config.Locale) or 'en')

Locales.fallback = loadLocaleFile('en') or {}
Locales.current = (selectedLang ~= 'en' and loadLocaleFile(selectedLang)) or Locales.fallback


function Locale(key, ...)
    local phrase = Locales.current[key] or Locales.fallback[key] or key
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, phrase, ...)
        if ok then return formatted end
    end
    return phrase
end

Locales.lang = selectedLang

function GetLocaleStrings()
    local out = {}
    for k, v in pairs(Locales.fallback) do out[k] = v end
    for k, v in pairs(Locales.current or {}) do out[k] = v end
    return out
end

function GetLocaleLang()
    return Locales.lang or 'en'
end
