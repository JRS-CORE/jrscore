-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Config.Language = 'en' or 'ar'. The prompt title stays English (no Arabic glyphs in the game font).
local strings = {
  en = {
    ['PROMPT_PASSPORT_REGISTRATION_OFFICE'] = 'Identity Registrations Office Department',
    ['ALREADY_REGISTERED']                  = "~e~You have already registered on our department.",
    ['ALREADY_REGISTERED_TARGET']           = "~e~This person is already registered on our department.",
    ['NOT_REGISTERED']                      = "~e~You don't have registered on our department.",

    ['INPUT_REGISTER_TITLE']                = "Registrations Office Department",
    ['INPUT_REGISTER_DESCRIPTION']          = "The cost to register on our department is %s dollars.\n\nInsert a valid Avatar URL (https://postimages.org)",
    ['INPUT_REGISTER_ACCEPT_BUTTON']        = "Register",
    ['INPUT_REGISTER_CANCEL_BUTTON']        = "Cancel",
    ['REGISTRATION_REQUIRES_AVATAR_URL']    = "~e~Invalid Avatar Url!",
    ['PASSPORT_CREATE_SELF_SUCCESS']        = "You have successfully registered to our department.",
    ['TARGET_PASSPORT_CREATE_SUCCESS']      = "You have successfully registered a user to our department.",
    ['PLAYER_INVALID']                      = "~e~The target player is on session.",
    ['NOT_ENOUGH_MONEY_REGISTER']           = "~e~You don't have enough money.",
    ['TARGET_DOES_NOT_HAVE_ENOUGH_MONEY']   = "~e~Target does not have enough money.",

    ['INPUT_RETRIEVE_TITLE']                = "Registrations Office Department",
    ['INPUT_RETRIEVE_DESCRIPTION']          = "The cost to retrieve your passport is %s dollars.\n\nWould you like to retrieve it?",
    ['INPUT_RETRIEVE_ACCEPT_BUTTON']        = "Retrieve",
    ['INPUT_RETRIEVE_CANCEL_BUTTON']        = "Cancel",
    ['NOT_ENOUGH_MONEY_RETRIEVE']           = "~e~You don't have enough money.",
    ['PASSPORT_RETRIEVED']                  = "You have retrieved a passport.",

    ['INPUT_RENEWAL_TITLE']                 = "Registrations Office Department",
    ['INPUT_RENEWAL_DESCRIPTION']           = "The cost to renew your existing passport is %s dollars.\n\nWould you like to renew it?",
    ['INPUT_RENEWAL_ACCEPT_BUTTON']         = "Renew",
    ['INPUT_RENEWAL_CANCEL_BUTTON']         = "Cancel",

    ['NOT_ENOUGH_MONEY_RENEW']              = "~e~You don't have enough money.",
    ['PASSPORT_NOT_EXPIRED']                = "~e~Your passport has not been expired.",
    ['PASSPORT_RENEWED']                    = "Passport has been renewed.",

    ['SEX_0']                               = "Male",
    ['SEX_1']                               = "Female",

    ['PASSPORT_DISPLAY_FULL_NAME_TITLE']    = "Full Name:",
    ['PASSPORT_DISPLAY_DOB_TITLE']          = "Date Of Birth:",
    ['PASSPORT_DISPLAY_SEX_TITLE']          = "Sex (Gender):",
    ['PASSPORT_DISPLAY_SIGNATURE_TITLE']    = "Signature",
    ['PASSPORT_DISPLAY_EXPIRATION_TITLE']   = "Valid Until: %s",

    ['DEVTOOLS_INJECTION_DETECTED_TITLE_LOG'] = "DevTools / Injection Cheat Found!",
    ['DEVTOOLS_INJECTION_DETECTED']           = "You have been kicked due to cheating by using DevTools or Injection cheat.",
  },
  ar = {
    ['PROMPT_PASSPORT_REGISTRATION_OFFICE'] = 'Identity Registrations Office Department',
    ['ALREADY_REGISTERED']                  = "~e~أنت مسجّل عندنا من قبل.",
    ['ALREADY_REGISTERED_TARGET']           = "~e~هالشخص مسجّل عندنا من قبل.",
    ['NOT_REGISTERED']                      = "~e~أنت مو مسجّل عندنا.",

    ['INPUT_REGISTER_TITLE']                = "مكتب تسجيل الهويات",
    ['INPUT_REGISTER_DESCRIPTION']          = "رسوم التسجيل %s دولار.\n\nحط رابط صورة صحيح (https://postimages.org)",
    ['INPUT_REGISTER_ACCEPT_BUTTON']        = "تسجيل",
    ['INPUT_REGISTER_CANCEL_BUTTON']        = "إلغاء",
    ['REGISTRATION_REQUIRES_AVATAR_URL']    = "~e~رابط الصورة غير صحيح!",
    ['PASSPORT_CREATE_SELF_SUCCESS']        = "تم تسجيلك بنجاح.",
    ['TARGET_PASSPORT_CREATE_SUCCESS']      = "سجّلت الشخص بنجاح.",
    ['PLAYER_INVALID']                      = "~e~اللاعب المحدد غير متاح.",
    ['NOT_ENOUGH_MONEY_REGISTER']           = "~e~ما عندك فلوس كافية.",
    ['TARGET_DOES_NOT_HAVE_ENOUGH_MONEY']   = "~e~الشخص ما عنده فلوس كافية.",

    ['INPUT_RETRIEVE_TITLE']                = "مكتب تسجيل الهويات",
    ['INPUT_RETRIEVE_DESCRIPTION']          = "رسوم استلام الجواز %s دولار.\n\nتبي تستلمه؟",
    ['INPUT_RETRIEVE_ACCEPT_BUTTON']        = "استلام",
    ['INPUT_RETRIEVE_CANCEL_BUTTON']        = "إلغاء",
    ['NOT_ENOUGH_MONEY_RETRIEVE']           = "~e~ما عندك فلوس كافية.",
    ['PASSPORT_RETRIEVED']                  = "استلمت جواز.",

    ['INPUT_RENEWAL_TITLE']                 = "مكتب تسجيل الهويات",
    ['INPUT_RENEWAL_DESCRIPTION']           = "رسوم تجديد جوازك %s دولار.\n\nتبي تجدده؟",
    ['INPUT_RENEWAL_ACCEPT_BUTTON']         = "تجديد",
    ['INPUT_RENEWAL_CANCEL_BUTTON']         = "إلغاء",

    ['NOT_ENOUGH_MONEY_RENEW']              = "~e~ما عندك فلوس كافية.",
    ['PASSPORT_NOT_EXPIRED']                = "~e~جوازك ما انتهى.",
    ['PASSPORT_RENEWED']                    = "تجدّد الجواز.",

    ['SEX_0']                               = "ذكر",
    ['SEX_1']                               = "أنثى",

    ['PASSPORT_DISPLAY_FULL_NAME_TITLE']    = "الاسم الكامل:",
    ['PASSPORT_DISPLAY_DOB_TITLE']          = "تاريخ الميلاد:",
    ['PASSPORT_DISPLAY_SEX_TITLE']          = "الجنس:",
    ['PASSPORT_DISPLAY_SIGNATURE_TITLE']    = "التوقيع",
    ['PASSPORT_DISPLAY_EXPIRATION_TITLE']   = "صالح حتى: %s",

    ['DEVTOOLS_INJECTION_DETECTED_TITLE_LOG'] = "DevTools / Injection Cheat Found!",
    ['DEVTOOLS_INJECTION_DETECTED']           = "انطردت بسبب استخدام أدوات الغش.",
  },
}

Locales = setmetatable({}, { __index = function(_, key)
  local lang = strings[Config and Config.Language or 'en'] or strings.en
  return lang[key] or strings.en[key] or key
end })
