-- jrs_mdt | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local currentLocale = 'en'
local localeData = {}

local function loadJson(lang)
    local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
    if not raw then return nil end
    return json.decode(raw)
end

local function loadLocale(lang)
    local ok, data = pcall(loadJson, lang)
    if ok and data then
        localeData = data
        currentLocale = lang
        return true
    end
    return false
end

if not loadLocale(Config and Config.Language or currentLocale) then
    loadLocale('en')
end

_G.locale = function(key, ...)
    local value = localeData[key]
    if value == nil then
        return key
    end
    if select('#', ...) > 0 then
        return value:format(...)
    end
    return value
end
