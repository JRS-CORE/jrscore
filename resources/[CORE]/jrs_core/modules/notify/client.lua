-- ============================================================================
--  jrs_notify / client/notify.lua
--  JRS unified notifications - the single renderer for the whole server.
--
--  Every other resource reaches this file. Nothing else on the server is
--  allowed to own a notification NUI: jrs_core's CoreNotifications, jrs_ranch,
--  jrs_farming, jrs_inventory, jrs_lib and the job scripts all delegate here,
--  which is what makes one style apply everywhere without editing hundreds of
--  call sites.
--
--  Hard rule for everything below: an export must NEVER yield. Exports run on
--  the caller's thread, so a Wait() here would freeze the script that raised
--  the notification (the old jrs_notify did exactly that).
-- ============================================================================

local settings = Config.Notifications
local keywords = Config.NotificationKeywords or {}

JRSToast = JRSToast or {}

local function moduleMessage(payload)
    SendNUIMessage({ __jrsModule = 'notify', payload = payload })
end

local function JRSRegisterToastApi(name, fn)
    JRSToast[name] = fn
end

-- A fullscreen menu owned by another resource is open; toasts dock elsewhere
-- so they are not hidden behind it.
local menuOpen = false
local menuSources = {}

local function refreshMenuOpen()
    menuOpen = next(menuSources) ~= nil
    moduleMessage({ type = 'notify_menu_state', menuOpen = menuOpen })
end

function JRSNotifySetMenuOpen(state, sourceName)
    sourceName = tostring(sourceName or '')
    if sourceName == '' then sourceName = 'legacy' end
    if state == true then menuSources[sourceName] = true else menuSources[sourceName] = nil end
    refreshMenuOpen()
    return menuOpen
end

-- Resources that render toasts inside their own NUI while their panel is open
-- (see render). Keyed by resource so a crashed owner is cleared on stop.
local captureSources = {}

function JRSNotifySetCapture(state, sourceName)
    sourceName = tostring(sourceName or '')
    if sourceName == '' then return false end
    captureSources[sourceName] = (state == true) or nil
    return next(captureSources) ~= nil
end

AddEventHandler('onClientResourceStop', function(stopped)
    captureSources[stopped] = nil
end)

local function setMenuOpenFor(sourceName, state)
    sourceName = tostring(sourceName or '')
    if sourceName == '' then sourceName = 'legacy' end
    if state == true then menuSources[sourceName] = true else menuSources[sourceName] = nil end
    refreshMenuOpen()
    return menuOpen
end

-- ---------------------------------------------------------------------------
-- Source naming: jrs_metal_detector -> "Metal Detector", jrs-Radio -> "Radio".
-- ---------------------------------------------------------------------------
local PRETTY_OVERRIDES = {
    jrs_core = 'Core',
    jrs_notify = '',
    jrs_lib = '',
    jrs_npc_outfits = 'NPC Outfits',
    jrs_idcard = 'ID Card',
    jrs_mdt = 'MDT',
    ['jrs-Radio'] = 'Radio',
}

local TITLE_TRANSLATIONS = {
    ['safezone'] = { en = 'Safe Zone', ar = 'المنطقة الآمنة' },
    ['safe zone'] = { en = 'Safe Zone', ar = 'المنطقة الآمنة' },
    ['المنطقة الآمنة'] = { en = 'Safe Zone', ar = 'المنطقة الآمنة' },
    ['منطقة آمنة'] = { en = 'Safe Zone', ar = 'المنطقة الآمنة' },

    ['police'] = { en = 'Police', ar = 'الشرطة' },
    ['الشرطة'] = { en = 'Police', ar = 'الشرطة' },

    ['store'] = { en = 'Store', ar = 'المتجر' },
    ['stores'] = { en = 'Store', ar = 'المتجر' },
    ['المتجر'] = { en = 'Store', ar = 'المتجر' },

    ['bank'] = { en = 'Bank', ar = 'البنك' },
    ['banking'] = { en = 'Bank', ar = 'البنك' },
    ['البنك'] = { en = 'Bank', ar = 'البنك' },

    ['medical'] = { en = 'Medical', ar = 'الطبابة' },
    ['doctors'] = { en = 'Medical', ar = 'الطبابة' },
    ['downed'] = { en = 'Downed', ar = 'إصابة حرجة' },
    ['الطبابة'] = { en = 'Medical', ar = 'الطبابة' },

    ['hunting'] = { en = 'Hunting', ar = 'الصيد' },
    ['الصيد'] = { en = 'Hunting', ar = 'الصيد' },

    ['mining'] = { en = 'Mining', ar = 'التعدين' },
    ['التعدين'] = { en = 'Mining', ar = 'التعدين' },

    ['lumberjack'] = { en = 'Lumberjack', ar = 'الحطاب' },
    ['الحطاب'] = { en = 'Lumberjack', ar = 'الحطاب' },

    ['farming'] = { en = 'Farming', ar = 'الزراعة' },
    ['farming admin'] = { en = 'Farming Admin', ar = 'إدارة المزارع' },
    ['الزراعة'] = { en = 'Farming', ar = 'الزراعة' },

    ['doors'] = { en = 'Doors', ar = 'الأبواب' },
    ['doorlocks'] = { en = 'Doors', ar = 'الأبواب' },
    ['الأبواب'] = { en = 'Doors', ar = 'الأبواب' },

    ['weapon'] = { en = 'Weapons', ar = 'الأسلحة' },
    ['weapons'] = { en = 'Weapons', ar = 'الأسلحة' },
    ['الأسلحة'] = { en = 'Weapons', ar = 'الأسلحة' },

    ['robbery network'] = { en = 'Robbery Network', ar = 'شبكة السرقات' },
    ['theftsystem'] = { en = 'Robbery Network', ar = 'شبكة السرقات' },
    ['theft'] = { en = 'Robberies', ar = 'السرقات' },
    ['شبكة السرقات'] = { en = 'Robbery Network', ar = 'شبكة السرقات' },

    ['character'] = { en = 'Character', ar = 'الشخصية' },
    ['الشخصية'] = { en = 'Character', ar = 'الشخصية' },

    ['delivery'] = { en = 'Delivery', ar = 'التوصيل' },
    ['التوصيل'] = { en = 'Delivery', ar = 'التوصيل' },

    ['mailbox'] = { en = 'Mailbox', ar = 'صندوق البريد' },
    ['صندوق البريد'] = { en = 'Mailbox', ar = 'صندوق البريد' },

    ['business'] = { en = 'Business', ar = 'الأعمال' },
    ['الأعمال'] = { en = 'Business', ar = 'الأعمال' },

    ['government'] = { en = 'Government', ar = 'الحكومة' },
    ['الحكومة'] = { en = 'Government', ar = 'الحكومة' },

    ['stable'] = { en = 'Stable', ar = 'الإسطبل' },
    ['الإسطبل'] = { en = 'Stable', ar = 'الإسطبل' },

    ['pets'] = { en = 'Pets', ar = 'الحيوانات الأليفة' },
    ['الحيوانات الأليفة'] = { en = 'Pets', ar = 'الحيوانات الأليفة' },

    ['radio'] = { en = 'Radio', ar = 'الراديو' },
    ['الراديو'] = { en = 'Radio', ar = 'الراديو' },

    ['newspaper'] = { en = 'Newspaper', ar = 'الصحيفة' },
    ['الصحيفة'] = { en = 'Newspaper', ar = 'الصحيفة' },

    ['fast travel'] = { en = 'Fast Travel', ar = 'السفر السريع' },
    ['fasttravel'] = { en = 'Fast Travel', ar = 'السفر السريع' },
    ['السفر السريع'] = { en = 'Fast Travel', ar = 'السفر السريع' },

    ['casino'] = { en = 'Casino', ar = 'الكازينو' },
    ['الكازينو'] = { en = 'Casino', ar = 'الكازينو' },

    ['trash'] = { en = 'Trash Search', ar = 'البحث في القمامة' },
    ['البحث في القمامة'] = { en = 'Trash Search', ar = 'البحث في القمامة' },

    ['tattoos'] = { en = 'Tattoos', ar = 'الوشوم' },
    ['tattoo'] = { en = 'Tattoos', ar = 'الوشوم' },
    ['الوشوم'] = { en = 'Tattoos', ar = 'الوشوم' },

    ['barber'] = { en = 'Barber', ar = 'الحلاق' },
    ['الحلاق'] = { en = 'Barber', ar = 'الحلاق' },

    ['clothing'] = { en = 'Clothing', ar = 'الملابس' },
    ['الملابس'] = { en = 'Clothing', ar = 'الملابس' },

    ['inventory'] = { en = 'Inventory', ar = 'الحقيبة' },
    ['الحقيبة'] = { en = 'Inventory', ar = 'الحقيبة' },

    ['id card'] = { en = 'ID Card', ar = 'بطاقة الهوية' },
    ['idcard'] = { en = 'ID Card', ar = 'بطاقة الهوية' },
    ['بطاقة الهوية'] = { en = 'ID Card', ar = 'بطاقة الهوية' },
    ['الهوية'] = { en = 'ID Card', ar = 'بطاقة الهوية' },

    ['herbs'] = { en = 'Herbs', ar = 'الأعشاب' },
    ['الأعشاب'] = { en = 'Herbs', ar = 'الأعشاب' },

    ['animation'] = { en = 'Animations', ar = 'الحركات' },
    ['animations'] = { en = 'Animations', ar = 'الحركات' },
    ['الحركات'] = { en = 'Animations', ar = 'الحركات' },

    ['bee'] = { en = 'Beekeeping', ar = 'تربية النحل' },
    ['beekeeping'] = { en = 'Beekeeping', ar = 'تربية النحل' },
    ['تربية النحل'] = { en = 'Beekeeping', ar = 'تربية النحل' },

    ['crafting'] = { en = 'Crafting', ar = 'الصناعة' },
    ['الصناعة'] = { en = 'Crafting', ar = 'الصناعة' },

    ['train'] = { en = 'Train', ar = 'القطار' },
    ['القطار'] = { en = 'Train', ar = 'القطار' },

    ['auction house'] = { en = 'Auction House', ar = 'المزاد العلني' },
    ['المزاد'] = { en = 'Auction House', ar = 'المزاد العلني' },
    ['المزاد العلني'] = { en = 'Auction House', ar = 'المزاد العلني' },

    ['boats'] = { en = 'Boats', ar = 'القوارب' },
    ['boat'] = { en = 'Boats', ar = 'القوارب' },
    ['القوارب'] = { en = 'Boats', ar = 'القوارب' },

    ['fight'] = { en = 'Fight', ar = 'القتال' },
    ['القتال'] = { en = 'Fight', ar = 'القتال' },

    ['moonshine'] = { en = 'Moonshine', ar = 'صناعة المشروب' },
    ['صناعة المشروب'] = { en = 'Moonshine', ar = 'صناعة المشروب' },

    ['lootnpcs'] = { en = 'Looting', ar = 'الغنيمة' },
    ['الغنيمة'] = { en = 'Looting', ar = 'الغنيمة' },

    ['freecam'] = { en = 'FreeCam', ar = 'الكاميرا الحرة' },
    ['الكاميرا الحرة'] = { en = 'FreeCam', ar = 'الكاميرا الحرة' },

    ['hookah'] = { en = 'Hookah', ar = 'الشيشة' },
    ['الشيشة'] = { en = 'Hookah', ar = 'الشيشة' },

    ['housing'] = { en = 'Housing', ar = 'المنازل' },
    ['المنازل'] = { en = 'Housing', ar = 'المنازل' },

    ['mdt'] = { en = 'MDT', ar = 'سجل الشرطة' },
    ['سجل الشرطة'] = { en = 'MDT', ar = 'سجل الشرطة' },

    ['admin'] = { en = 'Admin', ar = 'لوحة الإدارة' },
    ['scriptadmin'] = { en = 'Script Admin', ar = 'إدارة السكربتات' },
    ['spooner'] = { en = 'Spooner', ar = 'سبونر' },
    ['لوحة الإدارة'] = { en = 'Admin', ar = 'لوحة الإدارة' },

    ['core'] = { en = 'System', ar = 'النظام' },
    ['النظام'] = { en = 'System', ar = 'النظام' },

    ['metabolism'] = { en = 'Metabolism', ar = 'الأيض' },
    ['الأيض'] = { en = 'Metabolism', ar = 'الأيض' },
    ['jrs_metabolism'] = { en = 'Metabolism', ar = 'الأيض' },

    ['poison'] = { en = 'Poison', ar = 'السم' },
    ['السم'] = { en = 'Poison', ar = 'السم' },

    ['hunger'] = { en = 'Hunger', ar = 'الجوع' },
    ['الجوع'] = { en = 'Hunger', ar = 'الجوع' },

    ['thirst'] = { en = 'Thirst', ar = 'العطش' },
    ['العطش'] = { en = 'Thirst', ar = 'العطش' },

    ['stress'] = { en = 'Stress', ar = 'التوتر' },
    ['التوتر'] = { en = 'Stress', ar = 'التوتر' },

    ['temperature'] = { en = 'Temperature', ar = 'درجة الحرارة' },
    ['درجة الحرارة'] = { en = 'Temperature', ar = 'درجة الحرارة' },

    ['drunk'] = { en = 'Drunk', ar = 'السُكر' },
    ['السُكر'] = { en = 'Drunk', ar = 'السُكر' },

    ['cleanliness'] = { en = 'Cleanliness', ar = 'النظافة' },
    ['النظافة'] = { en = 'Cleanliness', ar = 'النظافة' },

    ['bathing'] = { en = 'Bathing', ar = 'الاستحمام' },
    ['الاستحمام'] = { en = 'Bathing', ar = 'الاستحمام' },
    ['jrs_bathing'] = { en = 'Bathing', ar = 'الاستحمام' },

    ['urine'] = { en = 'Restroom', ar = 'الحمام' },
    ['الحمام'] = { en = 'Restroom', ar = 'الحمام' },

    ['chicha'] = { en = 'Hookah', ar = 'الشيشة' },
    ['jrs_chicha'] = { en = 'Hookah', ar = 'الشيشة' },

    ['ranch'] = { en = 'Ranch', ar = 'المزرعة' },
    ['المزرعة'] = { en = 'Ranch', ar = 'المزرعة' },
    ['jrs_ranch'] = { en = 'Ranch', ar = 'المزرعة' },

    ['horses'] = { en = 'Horses', ar = 'الخيول' },
    ['الخيول'] = { en = 'Horses', ar = 'الخيول' },

    ['canon'] = { en = 'Cannon', ar = 'المدفع' },
    ['المدفع'] = { en = 'Cannon', ar = 'المدفع' },
    ['jrs_canon'] = { en = 'Cannon', ar = 'المدفع' },

    ['guarma'] = { en = 'Guarma', ar = 'غوارما' },
    ['غوارما'] = { en = 'Guarma', ar = 'غوارما' },
    ['jrs_guarma'] = { en = 'Guarma', ar = 'غوارما' },

    ['cinema'] = { en = 'Cinema', ar = 'السينما' },
    ['السينما'] = { en = 'Cinema', ar = 'السينما' },
    ['jrs_cinema'] = { en = 'Cinema', ar = 'السينما' },

    ['organizations'] = { en = 'Organizations', ar = 'المنظمات' },
    ['المنظمات'] = { en = 'Organizations', ar = 'المنظمات' },
    ['jrs_organizations'] = { en = 'Organizations', ar = 'المنظمات' },

    ['family'] = { en = 'Family', ar = 'العائلة' },
    ['العائلة'] = { en = 'Family', ar = 'العائلة' },

    ['backpack'] = { en = 'Backpack', ar = 'حقيبة الظهر' },
    ['حقيبة الظهر'] = { en = 'Backpack', ar = 'حقيبة الظهر' },

    ['camera'] = { en = 'Camera', ar = 'الكاميرا' },
    ['الكاميرا'] = { en = 'Camera', ar = 'الكاميرا' },

    ['city'] = { en = 'Town', ar = 'البلدة' },
    ['البلدة'] = { en = 'Town', ar = 'البلدة' },

    ['microphone'] = { en = 'Microphone', ar = 'الميكروفون' },
    ['الميكروفون'] = { en = 'Microphone', ar = 'الميكروفون' },

    ['minigames'] = { en = 'Minigames', ar = 'الألعاب المصغرة' },
    ['الألعاب المصغرة'] = { en = 'Minigames', ar = 'الألعاب المصغرة' },

    ['pausemenu'] = { en = 'Menu', ar = 'القائمة' },
    ['القائمة'] = { en = 'Menu', ar = 'القائمة' },

    ['rcboat'] = { en = 'RC Boat', ar = 'قارب التحكم' },
    ['قارب التحكم'] = { en = 'RC Boat', ar = 'قارب التحكم' },

    ['chat'] = { en = 'Chat', ar = 'الدردشة' },
    ['الدردشة'] = { en = 'Chat', ar = 'الدردشة' },

    ['alert'] = { en = 'Alert', ar = 'تنبيه' },
    ['تنبيه'] = { en = 'Alert', ar = 'تنبيه' },

    ['eagle eye'] = { en = 'Eagle Eye', ar = 'عين النسر' },
    ['عين النسر'] = { en = 'Eagle Eye', ar = 'عين النسر' },
    ['eagleeye'] = { en = 'Eagle Eye', ar = 'عين النسر' },

    ['bounty'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['bounty hunter'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['bountyhunter'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['bounty_hunter'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['صائد الجوائز'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['البونتي هنتر'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['بونتي هنتر'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },
    ['jrs_bounty'] = { en = 'Bounty Hunter', ar = 'بونتي هنتر' },

    ['fishing'] = { en = 'Fishing', ar = 'صيد الأسماك' },
    ['صيد الأسماك'] = { en = 'Fishing', ar = 'صيد الأسماك' },
    ['jrs_fishing'] = { en = 'Fishing', ar = 'صيد الأسماك' },

    ['freelance'] = { en = 'Freelance', ar = 'المهام الحرة' },
    ['المهام الحرة'] = { en = 'Freelance', ar = 'المهام الحرة' },
    ['jrs_freelance'] = { en = 'Freelance', ar = 'المهام الحرة' },

    ['multijob'] = { en = 'Jobs', ar = 'الوظائف' },
    ['الوظائف'] = { en = 'Jobs', ar = 'الوظائف' },
    ['jrs_multijob'] = { en = 'Jobs', ar = 'الوظائف' },

    ['stashes'] = { en = 'Stashes', ar = 'المخازن' },
    ['المخازن'] = { en = 'Stashes', ar = 'المخازن' },
    ['jrs_stashes'] = { en = 'Stashes', ar = 'المخازن' },

    ['truck'] = { en = 'Wagon Delivery', ar = 'توصيل العربات' },
    ['توصيل العربات'] = { en = 'Wagon Delivery', ar = 'توصيل العربات' },
    ['jrs_truck'] = { en = 'Wagon Delivery', ar = 'توصيل العربات' },

    ['key'] = { en = 'Keys', ar = 'المفاتيح' },
    ['المفاتيح'] = { en = 'Keys', ar = 'المفاتيح' },
    ['jrs_key'] = { en = 'Keys', ar = 'المفاتيح' },

    ['armour'] = { en = 'Armour', ar = 'الدرع' },
    ['الدرع'] = { en = 'Armour', ar = 'الدرع' },
    ['jrs_armour'] = { en = 'Armour', ar = 'الدرع' },

    ['npc outfits'] = { en = 'NPC Outfits', ar = 'أزياء الشخصيات' },
    ['أزياء الشخصيات'] = { en = 'NPC Outfits', ar = 'أزياء الشخصيات' },
    ['jrs_npc_outfits'] = { en = 'NPC Outfits', ar = 'أزياء الشخصيات' },

    ['ability card'] = { en = 'Ability Cards', ar = 'بطاقات القدرات' },
    ['بطاقات القدرات'] = { en = 'Ability Cards', ar = 'بطاقات القدرات' },
    ['jrs_ability_card'] = { en = 'Ability Cards', ar = 'بطاقات القدرات' },

    ['announce'] = { en = 'Announcement', ar = 'إعلان' },
    ['إعلان'] = { en = 'Announcement', ar = 'إعلان' },
    ['jrs_announce'] = { en = 'Announcement', ar = 'إعلان' },

    ['loadingscreen'] = { en = 'Loading', ar = 'جارٍ التحميل' },
    ['جارٍ التحميل'] = { en = 'Loading', ar = 'جارٍ التحميل' },
    ['jrs_loadingscreen'] = { en = 'Loading', ar = 'جارٍ التحميل' },

    ['church bells'] = { en = 'Church Bells', ar = 'أجراس الكنيسة' },
    ['أجراس الكنيسة'] = { en = 'Church Bells', ar = 'أجراس الكنيسة' },
    ['jrs_church_bells'] = { en = 'Church Bells', ar = 'أجراس الكنيسة' },

    ['killcam'] = { en = 'Killcam', ar = 'كاميرا الموت' },
    ['كاميرا الموت'] = { en = 'Killcam', ar = 'كاميرا الموت' },
    ['jrs_killcam'] = { en = 'Killcam', ar = 'كاميرا الموت' },

    ['prop items'] = { en = 'Props', ar = 'المجسمات' },
    ['المجسمات'] = { en = 'Props', ar = 'المجسمات' },
    ['rl_prop_items'] = { en = 'Props', ar = 'المجسمات' },

    ['herbs'] = { en = 'Herbalism', ar = 'الأعشاب' },
    ['herbalism'] = { en = 'Herbalism', ar = 'الأعشاب' },
    ['الأعشاب'] = { en = 'Herbalism', ar = 'الأعشاب' },
    ['chimneysweep'] = { en = 'Chimney Sweep', ar = 'منظف المداخن' },
    ['منظف المداخن'] = { en = 'Chimney Sweep', ar = 'منظف المداخن' },
    ['metal detector'] = { en = 'Metal Detector', ar = 'كاشف المعادن' },
    ['metal_detector'] = { en = 'Metal Detector', ar = 'كاشف المعادن' },
    ['كاشف المعادن'] = { en = 'Metal Detector', ar = 'كاشف المعادن' },
    ['business'] = { en = 'Business', ar = 'الأعمال والتجارة' },
    ['الأعمال والتجارة'] = { en = 'Business', ar = 'الأعمال والتجارة' },
    ['crafting'] = { en = 'Crafting', ar = 'الحِرفة والتصنيع' },
    ['الحِرفة والتصنيع'] = { en = 'Crafting', ar = 'الحِرفة والتصنيع' },
    ['blacksmith'] = { en = 'Blacksmith', ar = 'الحداد' },
    ['الحداد'] = { en = 'Blacksmith', ar = 'الحداد' },
    ['beekeeping'] = { en = 'Beekeeping', ar = 'تربية النحل' },
    ['تربية النحل'] = { en = 'Beekeeping', ar = 'تربية النحل' },
}

local function localizeTitle(title, source)
    local lang = (type(JrsLang) == 'table' and type(JrsLang.Current) == 'function' and JrsLang.Current()) or 'ar'
    local clean = tostring(title or ''):gsub('^%s+', ''):gsub('%s+$', '')

    -- Strip server brand prefix if present (e.g. "JRS CORE | Metabolism" -> "Metabolism")
    local brand = tostring(settings.Brand or 'JRS CORE')
    if brand ~= '' then
        clean = clean:gsub('^' .. brand:gsub('[%-%^%$%(%)%%%.%[%]%*%+%?]', '%%%1') .. '%s*|%s*', '')
    end
    clean = clean:gsub('^[Rr][Ee][Dd]%s*[Ee][Mm][Pp][Ii][Rr][Ee]%s*|%s*', '')

    if clean == '' and source then
        clean = tostring(source):gsub('^[Jj][Rr][Ss][_%-]', ''):gsub('[_%-]+', ' ')
    end
    if clean == '' then return '' end

    local key = string.lower(clean)
    if TITLE_TRANSLATIONS[key] and TITLE_TRANSLATIONS[key][lang] then
        return TITLE_TRANSLATIONS[key][lang]
    end
    if TITLE_TRANSLATIONS[clean] and TITLE_TRANSLATIONS[clean][lang] then
        return TITLE_TRANSLATIONS[clean][lang]
    end

    local stripped = key:gsub('^jrs_', ''):gsub('^jrs%-', '')
    if TITLE_TRANSLATIONS[stripped] and TITLE_TRANSLATIONS[stripped][lang] then
        return TITLE_TRANSLATIONS[stripped][lang]
    end

    return clean
end

local function prettyName(resource)
    resource = tostring(resource or '')
    if resource == '' then return '' end

    local override = PRETTY_OVERRIDES[resource]
    if override ~= nil then return override end

    return localizeTitle('', resource)
end

-- Build the title line. A caller that already branded its own title keeps it;
-- otherwise the brand (plus the calling resource) is stamped on.
local function buildTitle(explicitTitle, source)
    local brand = tostring(settings.Brand or '')
    local rawText = explicitTitle ~= nil and tostring(explicitTitle) or ''
    local text = ''

    if rawText ~= '' then
        text = localizeTitle(rawText, source)
    end

    if brand == '' then
        if text ~= '' then return text end
        return nil
    end

    if text ~= '' then
        -- Never brand twice: "JRS CORE | JRS CORE | Mining".
        if text:upper():find(brand:upper(), 1, true) then return text end
        return brand .. ' | ' .. text
    end

    if settings.ShowSource == false then return brand end

    local name = localizeTitle('', source)
    if name == '' then name = prettyName(source) end
    if name == '' then return brand end
    return brand .. ' | ' .. name
end

-- ---------------------------------------------------------------------------
-- Type inference. Callers that pass a type keep it; the rest are classified
-- from their wording so the right icon and sound are chosen automatically.
-- ---------------------------------------------------------------------------
local VALID_TYPES = { info = true, success = true, error = true, warning = true, reward = true }

local function matchesAny(haystack, list)
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if haystack:find(tostring(list[i]), 1, true) then return true end
    end
    return false
end

local function inferType(text, requested)
    local wanted = string.lower(tostring(requested or ''))
    if VALID_TYPES[wanted] then return wanted end

    -- Common aliases used across the older scripts.
    if wanted == 'fail' or wanted == 'danger' or wanted == 'red' then return 'error' end
    if wanted == 'ok' or wanted == 'green' then return 'success' end
    if wanted == 'money' or wanted == 'gold' or wanted == 'cash' then return 'reward' end
    if wanted == 'warn' then return 'warning' end

    local value = string.lower(tostring(text or ''))
    if matchesAny(value, keywords.error) then return 'error' end
    if matchesAny(value, keywords.reward) then return 'reward' end
    if matchesAny(value, keywords.success) then return 'success' end
    if matchesAny(value, keywords.warning) then return 'warning' end
    return 'info'
end

local function clampDuration(duration)
    local ms = tonumber(duration) or tonumber(settings.DefaultDuration) or 4500
    -- A few old call sites pass seconds. Anything under 100 is not a duration
    -- in milliseconds, so read it as seconds instead of flashing the toast.
    if ms > 0 and ms < 100 then ms = ms * 1000 end
    local minimum = tonumber(settings.MinimumDuration) or 1200
    local maximum = tonumber(settings.MaximumDuration) or 30000
    if ms < minimum then ms = minimum end
    if ms > maximum then ms = maximum end
    return math.floor(ms)
end

local function soundFor(kind)
    local sound = settings.Sound
    if not sound or sound.Enabled == false then return nil end
    local files = sound.Files or {}
    local file = files[kind]
    if file == false then return false end
    return file
end

local function itemImage(icon)
    local pattern = settings.ItemImagePath
    if not pattern or pattern == '' then return nil end
    local name = tostring(icon or '')
    if name == '' then return nil end
    -- Only plain item names; never let a caller inject a path.
    if name:find('[^%w_%-]') then return nil end
    return string.format(pattern, string.lower(name))
end

local recentLuaNotifications = {}

local function isLuaDuplicate(text, title, kind)
    local now = GetGameTimer()
    for k, at in pairs(recentLuaNotifications) do
        if (now - at) > 3500 then recentLuaNotifications[k] = nil end
    end
    local clean = tostring(text or ''):gsub('^%s*(.-)%s*$', '%1'):gsub('[%.%!%?%s،؛%:%-_]+$', ''):gsub('%s+', ' ')
    local key = string.format('%s|%s|%s', clean, tostring(title or ''), tostring(kind or ''))
    if recentLuaNotifications[key] and (now - recentLuaNotifications[key] < 2000) then
        return true
    end
    recentLuaNotifications[key] = now
    return false
end

-- ---------------------------------------------------------------------------
-- The one place a notification is rendered.
-- ---------------------------------------------------------------------------
local function render(payload)
    if settings.Enabled == false then return false end

    local text = payload.text
    if text == nil or tostring(text) == '' then return false end
    if type(text) == 'string' and type(_U) == 'function' then
        text = _U(text)
    end

    local lang = (type(JrsLang) == 'table' and type(JrsLang.Current) == 'function' and JrsLang.Current()) or 'ar'
    if lang == 'ar' and type(text) == 'string' then
        local amt, rawJob = text:match('^%+(%d+)%s+(.-)%s+[Xx][Pp]$')
        if amt then
            rawJob = rawJob:gsub('^%s+', ''):gsub('%s+$', '')
            if rawJob ~= '' then
                local arJob = localizeTitle(rawJob)
                if arJob and arJob ~= '' and arJob:lower() ~= rawJob:lower() then
                    text = ('+%s خبرة %s'):format(amt, arJob)
                else
                    text = ('+%s خبرة %s'):format(amt, rawJob)
                end
            else
                text = ('+%s خبرة'):format(amt)
            end
        else
            local singleAmt = text:match('^%+(%d+)%s+[Xx][Pp]$')
            if singleAmt then
                text = ('+%s خبرة'):format(singleAmt)
            end
        end
    end

    local titlePayload = payload.title
    if type(titlePayload) == 'string' and titlePayload ~= '' and type(_U) == 'function' then
        titlePayload = _U(titlePayload)
    end

    local kind = inferType(text, payload.notifyType)
    if isLuaDuplicate(text, titlePayload, kind) then
        return true
    end
    local sound = payload.sound
    if sound == nil then sound = soundFor(kind) end

    local position = payload.position
    if position == nil or tostring(position) == '' then
        position = menuOpen and tostring(settings.MenuOpenPosition or 'top-right')
            or tostring(settings.ClosedPosition or 'top-right')
    end

    local message = {
        type = 'show_notification',
        text = tostring(text),
        title = buildTitle(titlePayload, payload.source),
        notifyType = kind,
        duration = clampDuration(payload.duration),
        position = position,
        image = payload.image,
        sound = sound,
        soundVolume = settings.Sound and tonumber(settings.Sound.Volume) or 0.22,
        soundGap = settings.Sound and tonumber(settings.Sound.MinimumGapMs) or 180,
    }

    -- Every resource's NUI is its own browser layer and CSS z-index cannot cross
    -- layers, so a panel from a resource started after jrs_core (jrs_admin) is
    -- drawn OVER these toasts. While such a panel has claimed capture, it draws
    -- the toast inside its own layer; this page still plays the sound.
    if next(captureSources) ~= nil then
        TriggerEvent('jrs_core:notify:captured', message)
        message.soundOnly = true
    end

    moduleMessage(message)

    return true
end

-- Exposed to the rest of this resource (server bridge, legacy shims).
function JRSNotifyRender(payload)
    return render(payload or {})
end

-- ---------------------------------------------------------------------------
-- Primary API
-- ---------------------------------------------------------------------------

--- Notify(text, notifyType, duration, title)
--- The call every JRS script should use. Returns true when the toast was
--- rendered, false when notifications are off - callers may then fall back.
JRSRegisterToastApi('Notify', function(text, notifyType, duration, title)
    return render({
        text = text,
        notifyType = notifyType,
        duration = duration,
        title = title,
        source = GetInvokingResource(),
    })
end)

--- Show(payload) - full control:
--- { text, title, type, duration, position, image, sound }
JRSRegisterToastApi('Show', function(payload)
    if type(payload) ~= 'table' then return false end
    return render({
        text = payload.text or payload.message,
        title = payload.title,
        notifyType = payload.type or payload.notifyType,
        duration = payload.duration,
        position = payload.position,
        image = payload.image,
        sound = payload.sound,
        source = payload.source or GetInvokingResource(),
    })
end)

--- Convenience wrappers so call sites read clearly.
local function typed(kind)
    return function(text, duration, title)
        return render({
            text = text,
            notifyType = kind,
            duration = duration,
            title = title,
            source = GetInvokingResource(),
        })
    end
end

JRSRegisterToastApi('Info', typed('info'))
JRSRegisterToastApi('Success', typed('success'))
JRSRegisterToastApi('Error', typed('error'))
JRSRegisterToastApi('Warning', typed('warning'))
JRSRegisterToastApi('Reward', typed('reward'))

--- A resource with a fullscreen NUI calls this so toasts move out of its way.
JRSRegisterToastApi('SetMenuOpen', function(state, sourceName)
    local caller = sourceName
    if caller == nil and type(GetInvokingResource) == 'function' then
        local ok, value = pcall(GetInvokingResource)
        if ok then caller = value end
    end
    return setMenuOpenFor(caller, state)
end)

JRSRegisterToastApi('IsEnabled', function()
    return settings.Enabled ~= false
end)

JRSRegisterToastApi('Clear', function()
    moduleMessage({ type = 'clear_notifications' })
end)

-- ---------------------------------------------------------------------------
-- Legacy API. These signatures are still used by jrs_inventory, jrs_alert,
-- jrs_lib and a few jobs; they now render as the same unified toast instead of
-- the old bespoke NUI or a raw RDR2 native.
-- ---------------------------------------------------------------------------

--- DisplayLeftNotification(title, subtext, icon, duration)
JRSRegisterToastApi('DisplayLeftNotification', function(title, subtext, icon, duration)
    local source = GetInvokingResource()
    local hasSub = subtext ~= nil and tostring(subtext) ~= ''
    return render({
        text = hasSub and subtext or title,
        title = hasSub and title or nil,
        duration = duration,
        image = itemImage(icon),
        source = source,
    })
end)

--- DisplayNotification(text, duration) - was a bottom tip native.
JRSRegisterToastApi('DisplayNotification', function(text, duration)
    return render({ text = text, duration = duration, source = GetInvokingResource() })
end)

--- DisplayLocationNotification(text, location, duration) - location is a header.
JRSRegisterToastApi('DisplayLocationNotification', function(text, location, duration)
    return render({
        text = text,
        title = location,
        duration = duration,
        source = GetInvokingResource(),
    })
end)

--- ShowAdvancedRightNotification(text, dict, icon, text_color, duration)
--- The texture dictionary and colour are game-native concepts with no meaning
--- in the shared toast; the message and its duration are what carry over.
JRSRegisterToastApi('ShowAdvancedRightNotification', function(text, dict, icon, text_color, duration)
    return render({
        text = text,
        duration = duration,
        notifyType = 'reward',
        image = itemImage(icon),
        source = GetInvokingResource(),
    })
end)

-- ---------------------------------------------------------------------------
-- Net events. Server code and older scripts trigger these instead of calling
-- an export; they all land on the same renderer.
-- ---------------------------------------------------------------------------

local function legacyEvent(title, subtext, icon, duration)
    local hasSub = subtext ~= nil and tostring(subtext) ~= ''
    render({
        text = hasSub and subtext or title,
        title = hasSub and title or nil,
        duration = duration,
        image = itemImage(icon),
    })
end

RegisterNetEvent('jrs_notify:notify', legacyEvent)

RegisterNetEvent('jrs_notify:show', function(payload)
    if type(payload) ~= 'table' then return end
    render({
        text = payload.text or payload.message,
        title = payload.title,
        notifyType = payload.type or payload.notifyType,
        duration = payload.duration,
        position = payload.position,
        image = payload.image,
        source = payload.source,
    })
end)

RegisterNetEvent('jrs_notify:setMenuOpen', function(state, sourceName)
    setMenuOpenFor(sourceName or 'net', state)
end)

AddEventHandler('onClientResourceStop', function(stopped)
    if menuSources[stopped] then
        menuSources[stopped] = nil
        refreshMenuOpen()
    end
end)

-- ---------------------------------------------------------------------------
-- Layout settings handshake. A SendNUIMessage sent before the page has run its
-- script is dropped, so the page asks for the settings itself once it is ready
-- rather than us guessing at a delay.
-- ---------------------------------------------------------------------------
local function pushSettings()
    local s = (Config and Config.Notifications) or settings or {}
    moduleMessage({
        type = 'notify_settings',
        maxVisible = tonumber(s.MaxVisible) or 4,
        defaultPosition = tostring(s.ClosedPosition or 'top-right'),
        menuOpenPosition = tostring(s.MenuOpenPosition or 'top-right'),
    })
    moduleMessage({ type = 'notify_menu_state', menuOpen = menuOpen })
end

RegisterNUICallback('ready', function(_, cb)
    pushSettings()
    cb('ok')
end)

-- Belt and braces: if the callback never lands (page reloaded by a NUI restart,
-- for instance) the settings are pushed anyway shortly after start.
CreateThread(function()
    Wait(2000)
    pushSettings()
end)
