-- jrs_chat | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Native JRS kit: lightweight helpers for notifications, character names, and permissions.
JRS = {}
JRS.IsServer = IsDuplicityVersion()

function L(key, ...)
    local lang = Locales and (Locales[Config and Config.Language or 'en'] or Locales.en) or {}
    local text = lang[key] or (Locales and Locales.en and Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, text, ...)
        if ok then return out end
    end
    return text
end

function LE(key, ...)
    local text = (Locales and Locales.en and Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, text, ...)
        if ok then return out end
    end
    return text
end

if JRS.IsServer then
    function JRS.Notify(src, text, ms)
        TriggerClientEvent('jrs_core:sendRightTipNotification', src, tostring(text), ms or 4000)
    end

    function JRS.Char(src)
        return exports.jrs_core:GetCharacter(tonumber(src))
    end

    function JRS.IsAdmin(src)
        return exports.jrs_core:IsAdmin(tonumber(src))
    end
else
    function JRS.Notify(text, ms)
        TriggerEvent('jrs_core:sendRightTipNotification', tostring(text), ms or 4000)
    end
end
