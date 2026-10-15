Locales = {
    en = {
        group          = 'Player',
        rob            = 'Rob',
        uncuff         = 'Uncuff',
        need_cuffs     = 'You need handcuffs to rob someone.',
        too_far        = 'Too far away.',
        already_cuffed = 'That player is already restrained.',
        not_cuffed     = 'That player is not restrained.',
        not_handsup    = 'Their hands are not up.',
        in_vehicle     = 'You cannot rob someone on a horse or in a wagon.',
        cooldown       = 'Wait a little before robbing again.',
        protected      = 'You cannot rob this person.',
        cuffing        = 'You restrain them and start searching...',
        being_robbed   = 'You are being robbed!',
        uncuffed_you   = 'You have been released.',
        uncuffed_other = 'You released the player.',
        broke_free     = 'You broke free!',
        you_cuffed     = 'You are restrained.',
        handsup_help   = 'Raise / lower your hands',
    },
    ar = {
        group          = 'لاعب',
        rob            = 'سرقة',
        uncuff         = 'فك القيد',
        need_cuffs     = 'تحتاج أصفاد عشان تسرق أحد.',
        too_far        = 'بعيد مرة.',
        already_cuffed = 'هذا اللاعب مقيّد من قبل.',
        not_cuffed     = 'هذا اللاعب مو مقيّد.',
        not_handsup    = 'يديه مو مرفوعة.',
        in_vehicle     = 'ما تقدر تسرق أحد على خيل أو في عربة.',
        cooldown       = 'انتظر شوي قبل ما تسرق مرة ثانية.',
        protected      = 'ما تقدر تسرق هذا الشخص.',
        cuffing        = 'قيّدته وبديت تفتشه...',
        being_robbed   = 'أنت تنسرق!',
        uncuffed_you   = 'تم فك قيدك.',
        uncuffed_other = 'فكيت قيد اللاعب.',
        broke_free     = 'فكيت نفسك!',
        you_cuffed     = 'أنت مقيّد.',
        handsup_help   = 'ارفع / نزّل يديك',
    },
}

function L(key)
    local lang = Locales[Config.Language] or Locales.en
    return lang[key] or Locales.en[key] or key
end
