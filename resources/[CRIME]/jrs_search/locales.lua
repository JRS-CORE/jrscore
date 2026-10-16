-- jrs_search | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Config.Language = 'en' or 'ar'
local strings = {
    en = {
        ['PLAYER_TARGET_NOT_SURRENDERED']   = { text = 'That person has not surrendered.', duration = 3 },
        ['NOT_REQUIRED_JOB']                = { text = "You don't have the required job to search.", duration = 4 },
        ['PLAYER_TARGET_UNDER_PROTECTION']  = { text = "The specified player is new to the server, you can't search this player at the moment.", duration = 7 },
        ['PLAYER_TARGET_BLACKLISTED_JOB']   = { text = "The specified player cannot be searched.", duration = 4 },
        ['CANNOT_SEARCH_PLAYER_IS_BUSY']    = { text = "You cannot search this person while being already searched.", duration = 5 },

        ['DEVTOOLS_INJECTION_DETECTED_TITLE_LOG'] = "DevTools / Injection Cheat Found!",
        ['DEVTOOLS_INJECTION_DETECTED']           = "You have been kicked due to cheating by using DevTools or Injection cheat.",
    },
    ar = {
        ['PLAYER_TARGET_NOT_SURRENDERED']   = { text = 'هالشخص ما استسلم.', duration = 3 },
        ['NOT_REQUIRED_JOB']                = { text = "ما عندك الوظيفة المطلوبة للتفتيش.", duration = 4 },
        ['PLAYER_TARGET_UNDER_PROTECTION']  = { text = "هاللاعب جديد بالسيرفر، ما تقدر تفتشه الحين.", duration = 7 },
        ['PLAYER_TARGET_BLACKLISTED_JOB']   = { text = "هاللاعب ما ينفتش.", duration = 4 },
        ['CANNOT_SEARCH_PLAYER_IS_BUSY']    = { text = "ما تقدر تفتش هالشخص، أحد يفتشه الحين.", duration = 5 },

        ['DEVTOOLS_INJECTION_DETECTED_TITLE_LOG'] = "DevTools / Injection Cheat Found!",
        ['DEVTOOLS_INJECTION_DETECTED']           = "انطردت بسبب استخدام أدوات الغش.",
    },
}

Locales = setmetatable({}, { __index = function(_, key)
    local lang = strings[Config and Config.Language or 'en'] or strings.en
    return lang[key] or strings.en[key] or key
end })
