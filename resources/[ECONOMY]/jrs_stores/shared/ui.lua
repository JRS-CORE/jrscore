-- jrs_stores | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
StoresShared = {}
function StoresShared.IsClosed(store)
    if not store.StoreHoursAllowed then return false end
    -- RedM exposes the world clock on the client. The client enforces opening hours.
    if type(GetClockHours)~='function' then return false end
    local hour = GetClockHours()
    if store.StoreClose < store.StoreOpen then
        return not (hour >= store.StoreOpen or hour < store.StoreClose)
    end
    return not (hour >= store.StoreOpen and hour < store.StoreClose)
end
function StoresShared.JobAllowed(store, job, grade)
    if not store.AllowedJobs or not next(store.AllowedJobs) then return true end
    for _, allowed in ipairs(store.AllowedJobs) do
        if allowed == job and (tonumber(grade) or 0) >= (tonumber(store.JobGrade) or 0) then return true end
    end
    return false
end
function StoresShared.Language(src)
    if JrsLang then return src and JrsLang.Of(src) or JrsLang.Current() end
    return Lang == 'Arabic' and 'ar' or 'en'
end
TranslationStores.Langs.Arabic = {
    SubPrompt='فتح المتجر', StoreInUse='المتجر مستخدم من لاعب آخر', cantcarryitem='لا يمكنك حمل المزيد من الأغراض',
    youdontgold='لا تملك ذهبًا كافيًا', youdontcash='لا تملك أموالًا كافية', noManyQty='لا تملك هذه الكمية للبيع',
    limitBuy='الكمية المطلوبة غير متوفرة في المتجر', limitSell='المتجر لا يشتري المزيد من هذا الغرض',
    notAllowItem='لا تملك أغراضًا يمكن بيعها في هذا المتجر', yousold='بعت ', youbought='اشتريت ',
    fr=' مقابل ', frcash=' مقابل $', ofcash=' نقدًا', ofgold=' ذهبًا', hassold='باع', hasbought='اشترى',
    invalid='الطلب غير صالح', unavailable='المتجر غير متاح الآن', failed='تعذّرت العملية؛ لم تُحتسب كعملية ناجحة'
}
TranslationStores.Langs.English.invalid='Invalid store request'
TranslationStores.Langs.English.unavailable='This store is currently unavailable'
TranslationStores.Langs.English.failed='The operation could not be completed'
function StoresShared.Text(src,key)
    local pack=StoresShared.Language(src)=='ar' and TranslationStores.Langs.Arabic or TranslationStores.Langs.English
    return (pack[key] or TranslationStores.Langs.English[key] or key):gsub('~[%w_]+~','')
end
function StoresShared.IsProductAllowed(entry)
    if type(entry) ~= 'table' or type(entry.itemName) ~= 'string' then return false end
    if entry.equipment=='fishingrod' and entry.itemName=='WEAPON_FISHINGROD' and entry.category=='tools' then return true end
    local name=entry.itemName:lower()
    return not entry.weapon and entry.category~='weapons' and entry.category~='ammo'
        and not name:match('^weapon_') and not name:match('^ammo')
end
