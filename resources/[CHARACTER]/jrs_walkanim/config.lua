-- jrs_walkanim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_walkanim  |  config.lua
--  Walk style menu. The chosen style is saved on the character.
-- ==========================================================================

Config = {
    Language   = 'en',          -- 'en' or 'ar'
    MenuAlign  = 'top-left',

    MenuCommand = 'walkanim',   -- opens the menu
    SlowCommand = 'walkSlow',   -- /walkSlow 0.4  -> walk slower (0.1 .. 3.0), run again to stop
}

-- Game names of the walk styles. Order = order in the menu.
Config.Styles = {
    { key = 'casual',      name = 'MP_Style_Casual' },
    { key = 'crazy',       name = 'MP_Style_Crazy' },
    { key = 'drunk',       name = 'MP_Style_drunk' },
    { key = 'easyrider',   name = 'MP_Style_EasyRider' },
    { key = 'flamboyant',  name = 'MP_Style_Flamboyant' },
    { key = 'greenhorn',   name = 'MP_Style_Greenhorn' },
    { key = 'gunslinger',  name = 'MP_Style_Gunslinger' },
    { key = 'inquisitive', name = 'MP_Style_inquisitive' },
    { key = 'refined',     name = 'MP_Style_Refined' },
    { key = 'silent',      name = 'MP_Style_SilentType' },
    { key = 'veteran',     name = 'MP_Style_Veteran' },
}

Config.Text = {
    en = {
        title = 'WALK STYLE', subtitle = 'Pick a style, it is saved on your character',
        pick = 'Use this style', reset = 'Default style', resetHint = 'Go back to the normal walk',
        casual = 'Casual', crazy = 'Crazy', drunk = 'Drunk', easyrider = 'Easy Rider', flamboyant = 'Flamboyant',
        greenhorn = 'Greenhorn', gunslinger = 'Gunslinger', inquisitive = 'Inquisitive', refined = 'Refined',
        silent = 'Silent', veteran = 'Veteran',
        slowNeedsValue = 'Add a speed, for example /walkSlow 0.3', slowOn = 'Slow walk on', slowOff = 'Slow walk off',
        suggestMenu = 'Open the walk style menu', suggestSlow = 'Walk slowly: a number from 0.1 to 3.0',
    },
    ar = {
        title = 'أسلوب المشي', subtitle = 'اختر أسلوباً وسيُحفظ على شخصيتك',
        pick = 'استخدم هذا الأسلوب', reset = 'الأسلوب الافتراضي', resetHint = 'الرجوع للمشي العادي',
        casual = 'عادي', crazy = 'مجنون', drunk = 'سكران', easyrider = 'هادئ', flamboyant = 'متباهي',
        greenhorn = 'مبتدئ', gunslinger = 'مسلّح', inquisitive = 'فضولي', refined = 'راقي',
        silent = 'صامت', veteran = 'محنّك',
        slowNeedsValue = 'أضف سرعة، مثال: /walkSlow 0.3', slowOn = 'تم تفعيل المشي البطيء', slowOff = 'تم إيقاف المشي البطيء',
        suggestMenu = 'فتح قائمة أساليب المشي', suggestSlow = 'مشي بطيء: رقم من 0.1 إلى 3.0',
    },
}
