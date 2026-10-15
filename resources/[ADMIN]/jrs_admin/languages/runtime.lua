-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local additions = {
    uiBusy={'Close the other interface first.','أغلق الواجهة الأخرى أولًا.'}, actionFailed={'The action failed. Check the server/client log.','تعذر تنفيذ الإجراء. راجع سجل السيرفر أو اللعبة.'}, integrationMissing={'The required resource is not configured or started.','السكربت المطلوب غير متصل أو غير مشغّل.'}, invalidModel={'Invalid model or loading timed out.','الموديل غير صالح أو تعذر تحميله.'}, reportsEmpty={'No reports yet.','لا توجد بلاغات حاليًا.'}, reportClosed={'Report closed.','تم إغلاق البلاغ.'},
    inventoryEmpty={'The inventory is empty.','المخزون فارغ.'}, invalidGroup={'This group is not configured.','هذه الصلاحية غير موجودة في الإعدادات.'}, cannotGiveGroup={'You cannot change this rank.','لا يمكنك تغيير هذه الرتبة.'}, noWaypoint={'Set a waypoint on the map first.','حدد علامة على الخريطة أولًا.'}, noPreviousLocation={'There is no saved location to return to.','لا يوجد موقع سابق محفوظ للعودة إليه.'},
    laserOn={'Inspection beam enabled. Aim at an entity.','تم تفعيل شعاع الفحص. صوّب نحو كائن.'}, laserOff={'Inspection beam disabled.','تم إيقاف شعاع الفحص.'}, copiedConsole={'Copied text printed to the console.','تم عرض النص المنسوخ في سجل F8.'}, adminHelp={'Open the admin menu (Page Down).','فتح قائمة الإدارة (Page Down).'},
}
for key, values in pairs(additions) do
    Translation.Langs.English.Notify[key] = values[1]
    Translation.Langs.Arabic.Notify[key] = values[2]
end
Translation.Langs.English.Menus.Reports = { open='Open', closed='Closed', closeTitle='Close report', confirm='yes / no' }
Translation.Langs.Arabic.Menus.Reports = { open='جديد', closed='مغلق', closeTitle='إغلاق البلاغ', confirm='نعم / لا / yes / no' }
local en = Translation.Langs.English.Menus
en.MainAdminOptions.MenuAdminInput.errorMsg = 'Enter the server player ID, for example 2.'
en.SubActionsAdminOptions.DelWagonRadiusInput.placeholder = 'Radius in metres: 1 to 100'
en.SubActionsAdminOptions.DelWagonRadiusInput.errorMsg = 'Enter a whole number between 1 and 100.'
en.SubOfflineOptions.BanTypeInput.placeholder = 'ban 6 1d / unban 6'
en.SubOfflineOptions.BanTypeInput.errorMsg = 'Use ban ID duration or unban ID. Duration 0 is permanent.'
en.SubOfflineOptions.WhiteTypeInput.placeholder = 'whitelist steam:123 / unwhitelist steam:123'
en.SubOfflineOptions.WhiteTypeInput.errorMsg = 'Use whitelist identifier or unwhitelist identifier.'
en.SubDatabaseGiveOptions.GiveCurrencyInput.placeholder = '0 125.50 / 1 2.50'
en.SubDatabaseGiveOptions.GiveCurrencyInput.errorMsg = 'Currency 0 = cash, 1 = gold, followed by a positive amount.'
en.SubDatabaseGiveOptions.GiveHorseInput.placeholder = 'a_c_horse_arabian_white MyHorse 0'
en.SubDatabaseGiveOptions.GiveHorseInput.errorMsg = 'Model, horse name, sex: 0 = male, 1 = female.'
en.SubDatabaseGiveOptions.GiveWagonInput.placeholder = 'wagon02x MyWagon'
en.MainDevToolsOptions.SpawnWagonInput.placeholder = 'wagon02x'
en.SubSimpleActionOptions.playerSpectate_desc = 'Spectate this player. Use /adminstop to stop and return to your position.'
en.Inspect = {coords='Coords',hash='Model hash',model='Model name',heading='Heading',rotation='Rotation',unknown='Unknown',copyHelp='H: copy entity info | G: copy vector3 coordinates'}
Translation.Langs.Arabic.Menus.Inspect = {coords='الإحداثيات',hash='معرّف الموديل',model='اسم الموديل',heading='الاتجاه',rotation='الدوران',unknown='غير معروف',copyHelp='H: نسخ بيانات الكائن | G: نسخ إحداثيات vector3'}
en.Speeds = {['Very Slow']='Very Slow',Slow='Slow',Normal='Normal',Fast='Fast',['Very Fast']='Very Fast',Max='Max'}
Translation.Langs.Arabic.Menus.Speeds = {['Very Slow']='بطيء جدًا',Slow='بطيء',Normal='عادي',Fast='سريع',['Very Fast']='سريع جدًا',Max='أقصى سرعة'}
-- Repair historic typos referenced by action callbacks.
for _, lang in pairs(Translation.Langs) do
    lang.Notify.wagonGiven = lang.Notify.givenWagon
    lang.Menus.MainDevToolsOptions.spawnPeds_desc = lang.Menus.MainDevToolsOptions.spawnPed_desc
end

local function selected(code)
    return code == 'ar' and Translation.Langs.Arabic or Translation.Langs.English
end
function Translation.ForPlayer(source) return selected(JrsLang.Of(source)) end
function Translation.Current()
    -- Existing local T references follow live language changes.
    return setmetatable({}, { __index = function(_, key) return selected(JrsLang.Current())[key] end })
end

local maps = { en = {}, ar = {} }
local fragments = { en = {}, ar = {} }
local function collect(en, ar)
    for key, english in pairs(en) do
        local arabic = ar[key]
        if type(english) == 'table' and type(arabic) == 'table' then collect(english, arabic)
        elseif type(english) == 'string' and type(arabic) == 'string' then
            maps.en[english], maps.en[arabic] = english, english
            maps.ar[english], maps.ar[arabic] = arabic, arabic
            if english ~= arabic and #english > 3 then
                fragments.ar[#fragments.ar + 1] = { english, arabic }
                fragments.en[#fragments.en + 1] = { arabic, english }
            end
        end
    end
end
collect(Translation.Langs.English.Menus, Translation.Langs.Arabic.Menus)
collect(Translation.Langs.English.Notify, Translation.Langs.Arabic.Notify)
for _, list in pairs(fragments) do table.sort(list, function(a, b) return #a[1] > #b[1] end) end
function Translation.RenderText(value, code)
    local text = tostring(value or '')
    code = code == 'ar' and 'ar' or 'en'
    if maps[code][text] then return maps[code][text] end
    -- Composite player descriptions contain translated prefixes plus values.
    if text:find('<', 1, true) then
        for _, pair in ipairs(fragments[code]) do
            text = text:gsub(pair[1]:gsub('(%W)', '%%%1'), function() return pair[2] end)
        end
    end
    return text
end
