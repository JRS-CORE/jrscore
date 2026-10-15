-- Follow the language selected by jrs_character and published by jrs_core.
local uiEnglish = Translations
local uiArabic = {
    Saddlecloths='بطانيات السرج', SaddleHorns='قرون السرج', SaddleBags='حقائب السرج',
    Tails='الذيول', Manes='الأعراف', Saddles='السروج', Stirrups='الركاب', Bedrolls='أغطية النوم',
    Masks='الأقنعة', Mustaches='الشوارب', Holsters='حافظات الأسلحة', Bridles='اللجام', Horseshoes='حدوات الخيل',
    noPersonalHorse='ليس لديك خيل، افتح متجر الخيل', renamePersonalHorse='تغيير الاسم',
    sellPersonalHorse='بيع', sellConfirmation='هل تريد البيع؟', sellConfirmationButton='بيع',
    sellConfirmationCancelButton='إلغاء', stableButton='أحصنتك', traderButton='شراء حصان',
    tackShopButton='تجهيزات الخيل', saveButton='حفظ', rotateText='تدوير', cancelButton='إغلاق',
    confirmationTitle='تأكيد الشراء', confirmationText='اختر الدفع بالنقود أو الذهب',
    confirmationButtonCancel='إلغاء', confirmationButtonClose='إغلاق',
}
local text = {
    en = {
        horses='Horses', wagons='Wagons', stableButton='Your Wagons', traderButton='Wagon Trader',
        noPersonalHorse='No wagons yet. Visit the Wagon Trader.', selectGender='Select Gender', male='Male', female='Female',
        call='Spawn Wagon', returnWagon='Return Wagon', cargo='Wagon Inventory', repair='Repair Wagon', trade='Transfer Ownership', brake='Brake',
        condition='Condition', name='Name your wagon', playerId='Recipient server ID', confirm='Confirm', cancel='Cancel',
        tradeWarning='Ownership and cargo transfer to this player.', select='Select a wagon first',
        busy='Please wait for the current action.', unavailable='Wagons are temporarily unavailable.',
        invalid='Invalid wagon or request.', forbidden='You do not own this wagon.', job='Your job cannot buy this wagon.',
        tooFar='Move closer to the stable or wagon.', limit='You have reached your wagon limit.',
        cash='Not enough cash.', gold='Not enough gold.', purchased='Wagon purchased.', renamed='Wagon renamed.',
        sold='Wagon sold.', returned='Wagon returned.', alreadyOut='Return your current wagon first.',
        noWagon='No wagon is out.', spawnFailed='Could not spawn the wagon. Try a clear area.',
        emptyCargo='Empty the cargo before selling the wagon.', returnFirst='Return the wagon before selling or giving it.',
        repaired='Wagon repaired.', fullCondition='The wagon is already in good condition.',
        repairItem='You need a repair hammer.', traded='Wagon ownership transferred.',
        target='The recipient must be nearby and have a loaded character.', targetLimit='The recipient has reached the wagon limit.',
        broken='The wagon needs repairs before it can move.', saved='Saved.', cargoDisabled='This wagon has no cargo storage.',
        menuPrompt='Wagon Menu', brakeOn='Apply Brake', brakeOff='Release Brake',
    },
    ar = {
        horses='الخيل', wagons='العربات', stableButton='عرباتك', traderButton='متجر العربات',
        noPersonalHorse='ليس لديك عربات، افتح متجر العربات', selectGender='اختر الجنس', male='ذكر', female='أنثى',
        call='استدعاء العربة', returnWagon='إرجاع العربة', cargo='مخزون العربة', repair='إصلاح العربة', trade='نقل ملكية العربة', brake='الفرامل',
        condition='الحالة', name='اسم العربة', playerId='رقم اللاعب المستلم', confirm='تأكيد', cancel='إلغاء',
        tradeWarning='تنتقل ملكية العربة ومحتويات مخزونها إلى هذا اللاعب', select='اختر عربة أولاً',
        busy='انتظر انتهاء العملية الحالية', unavailable='العربات غير متاحة مؤقتاً',
        invalid='العربة أو الطلب غير صالح', forbidden='هذه العربة ليست ملكك', job='وظيفتك لا تسمح بشراء هذه العربة',
        tooFar='اقترب من الإسطبل أو العربة', limit='وصلت إلى الحد المسموح من العربات',
        cash='النقود غير كافية', gold='الذهب غير كافٍ', purchased='تم شراء العربة', renamed='تم تغيير اسم العربة',
        sold='تم بيع العربة', returned='تم إرجاع العربة', alreadyOut='أرجع عربتك الحالية أولاً',
        noWagon='لا توجد عربة مستدعاة', spawnFailed='تعذر استدعاء العربة، جرّب مكاناً خالياً',
        emptyCargo='أفرغ مخزون العربة قبل بيعها', returnFirst='أرجع العربة قبل بيعها أو إعطائها',
        repaired='تمت صيانة العربة', fullCondition='العربة بحالة جيدة بالفعل', repairItem='تحتاج مطرقة لصيانة العربة',
        traded='تم نقل ملكية العربة', target='يجب أن يكون اللاعب المستلم قريباً ولديه شخصية محملة',
        targetLimit='وصل اللاعب المستلم إلى الحد المسموح من العربات', broken='تحتاج العربة إلى صيانة قبل التحرك',
        saved='تم الحفظ', cargoDisabled='هذه العربة لا تحتوي على مخزون', menuPrompt='قائمة العربة',
        brakeOn='تفعيل الفرامل', brakeOff='تحرير الفرامل',
    },
}
function StableLanguage(src)
    return (src and JrsLang.Of(src) or JrsLang.Current()) == 'ar' and 'ar' or 'en'
end
function WagonText(key, src)
    return text[StableLanguage(src)][key] or text.en[key] or key
end
function WagonLabel(value, src)
    if StableLanguage(src) ~= 'ar' then return value end
    local labels = { Buggies='العربات الخفيفة', Coaches='عربات الركاب', Carts='عربات الحمل', Wagons='العربات الكبيرة',
        ['Hunter Cart']='عربة الصيد', ['Supply Wagon']='عربة الإمدادات', ['Travel Wagon']='عربة السفر' }
    if labels[value] then return labels[value] end
    local prefixes = { ['Buggy']='عربة خفيفة', ['Coach']='عربة ركاب', ['Cart']='عربة حمل',
        ['Wagon']='عربة كبيرة', ['Chuck Wagon']='عربة تموين' }
    local prefix, number = value:match('^(.-) (%d+)$')
    return prefixes[prefix] and prefixes[prefix] .. ' ' .. number or value
end
function StableTitle(site)
    local names = {valentine='إسطبل فالنتاين',strawberry='إسطبل ستروبيري',vanhorn='إسطبل فان هورن',
        lemoyne='إسطبل ليموين',saintdenis='إسطبل سان دينيس',blackwater='إسطبل بلاكووتر',
        armadillo='إسطبل أرماديلو',tumbleweed='إسطبل تمبلويد',guarma='إسطبل غوارما'}
    return StableLanguage() == 'ar' and names[site] or Stables[site].shop.name
end
function StableTranslations(family)
    local lang, result = StableLanguage(), {}
    for key,value in pairs(uiEnglish) do result[key] = value end
    if lang == 'ar' then for key,value in pairs(uiArabic) do result[key] = value end end
    for key,value in pairs(text[lang]) do
        if family == 'wagon' or key ~= 'stableButton' and key ~= 'traderButton' and key ~= 'noPersonalHorse' then
            result[key] = value
        end
    end
    if HorseTranslations then for key,value in pairs(HorseTranslations()) do result[key]=value end end
    return result
end
-- Preserve the legacy horse translation keys while following the chosen language.
local legacyU, legacyUp = _U, _Up
local function horseText(src, key, ...)
    local lang = StableLanguage(src)
    local value = Locales[lang .. '_lang'] and Locales[lang .. '_lang'][key]
        or Locales.en_lang and Locales.en_lang[key]
    if not value then
        if src and legacyUp then return legacyUp(src, key, ...) end
        return legacyU(key, ...)
    end
    if select('#', ...) == 0 then return value end
    return string.format(value, ...)
end
function _U(key, ...) return horseText(nil, key, ...) end
function _Up(src, key, ...) return horseText(src, key, ...) end
