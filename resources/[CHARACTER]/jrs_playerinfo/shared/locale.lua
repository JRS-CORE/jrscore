-- jrs_playerinfo | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
Locales = {
    en = {
        title     = 'Player Info',
        cmd_help  = 'Show your character info',
        job       = 'Job',
        grade     = 'grade',
        cash      = 'Cash',
        gold      = 'Gold',
        dirty     = 'Dirty money',
        bank      = 'Bank',
        char_id   = 'Character ID',
        server_id = 'Server ID',
        no_data   = 'No data',
        unemployed = 'Unemployed',
    },
    ar = {
        title     = 'معلومات اللاعب',
        cmd_help  = 'عرض معلومات شخصيتك',
        job       = 'الوظيفة',
        grade     = 'الرتبة',
        cash      = 'الكاش',
        gold      = 'الذهب',
        dirty     = 'المال القذر',
        bank      = 'بنك',
        char_id   = 'رقم الشخصية',
        server_id = 'رقم السيرفر',
        no_data   = 'لا توجد بيانات',
        unemployed = 'عاطل',
    },
}

function L(key)
    local lang = Locales[Config.Language] or Locales.en
    return lang[key] or Locales.en[key] or key
end
