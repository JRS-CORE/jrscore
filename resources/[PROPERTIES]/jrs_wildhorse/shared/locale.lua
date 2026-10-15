-- jrs_wildhorse | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local strings = {
    en = {
        prompt       = 'Sell horse',
        no_mount     = "You aren't riding a horse.",
        not_wanted   = "I won't buy that animal.",
        sold         = 'Thanks for the deal! You got $%s',
        sold_gold    = ' and %s gold',
        not_trainer  = 'You need the trainer job.',
        not_broken   = 'You have not broken this horse in.',
        not_net      = 'This horse cannot be sold.',
        blip         = 'Horse Trainer',
    },
    ar = {
        prompt       = 'بيع الحصان',
        no_mount     = 'أنت مو راكب حصان.',
        not_wanted   = 'ما أشتري هالحيوان.',
        sold         = 'صفقة موفقة! أخذت $%s',
        sold_gold    = ' و %s ذهب',
        not_trainer  = 'تحتاج وظيفة مروّض الخيل.',
        not_broken   = 'ما روّضت هالحصان.',
        not_net      = 'ما ينباع هالحصان.',
        blip         = 'مروّض الخيل',
    },
}

-- prompts / blips: English only (the game font has no Arabic glyphs)
function LE(key, ...)
    local text = strings.en[key] or key
    if select('#', ...) > 0 then return text:format(...) end
    return text
end

function L(key, ...)
    local lang = strings[Config.Language] or strings.en
    local text = lang[key] or strings.en[key] or key
    if select('#', ...) > 0 then return text:format(...) end
    return text
end
