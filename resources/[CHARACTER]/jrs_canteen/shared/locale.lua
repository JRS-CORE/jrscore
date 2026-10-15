Locales = {
    en = {
        empty        = 'Your canteen is empty - refill it in a river or lake.',
        refilled     = 'Canteen refilled.',
        drank        = 'You took a sip from your canteen.',
        busy         = 'You are already doing something.',
        not_here     = 'You cannot do that right now.',
        refilling    = 'Refilling canteen...',
        drinking     = 'Drinking...',
    },
    ar = {
        empty        = 'المطارة فاضية - عبّها من نهر أو بحيرة.',
        refilled     = 'تم تعبئة المطارة.',
        drank        = 'شربت من المطارة.',
        busy         = 'أنت مشغول بشيء ثاني.',
        not_here     = 'ما تقدر تسوي هذا الحين.',
        refilling    = 'جاري تعبئة المطارة...',
        drinking     = 'جاري الشرب...',
    },
}

function L(key)
    local lang = Locales[Config.Language] or Locales.en
    return lang[key] or Locales.en[key] or key
end
