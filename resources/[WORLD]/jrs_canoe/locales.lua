local strings = {
    en = {
        ['CANNOT_CARRY_NOT_ENOUGH_STAMINA'] = "You don't have enough strength to keep carrying the canoe",
        ['DROP_CANOE_ACTION']               = "Canoe",
        ['STORE_BUSY']                      = "The carpenter is busy right now, please wait a few seconds.",
        ['STORE_PICKUP']                    = "Please carry the canoe away from the table.",
        ['NOT_ENOUGH_MONEY']                = "You don't have enough money.",
        ['SUCCESSFULLY_RENTED']             = "You have just rented a canoe.",
        ['MENU_EXIT']                       = "Exit",
        ['CANOE_READY']                     = "Your canoe is ready, come and carry it away.",
        ['PROMPT_TEXT']                     = "Rent a canoe",
    },
    ar = {
        ['CANNOT_CARRY_NOT_ENOUGH_STAMINA'] = "ما عندك قوة كافية تكمل شيل القارب",
        ['DROP_CANOE_ACTION']               = "قارب",
        ['STORE_BUSY']                      = "النجّار مشغول الحين، انتظر ثواني.",
        ['STORE_PICKUP']                    = "شيل القارب من على الطاولة.",
        ['NOT_ENOUGH_MONEY']                = "ما عندك فلوس كافية.",
        ['SUCCESSFULLY_RENTED']             = "استأجرت قارب.",
        ['MENU_EXIT']                       = "خروج",
        ['CANOE_READY']                     = "قاربك جاهز، تعال وشيله.",
        ['PROMPT_TEXT']                     = "استئجار قارب",
    },
}

-- English strings for game prompts (the game font has no Arabic glyphs)
LocalesEN = strings.en

Locales = setmetatable({}, { __index = function(_, key)
    local lang = strings[Config and Config.Language or 'en'] or strings.en
    return lang[key] or strings.en[key] or key
end })
