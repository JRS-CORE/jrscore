-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Arabic menu strings, sharing the same keys as the existing English menu.
local labels = {
    menuTitle='إدارة JRS', menuSubTitle='القائمة الرئيسية', menuSubTitleAdmin='إدارة اللاعبين', menuSubTitleBooster='أدوات المشرف', menuSubTitleDatabase='الممتلكات والمخزون', menuSubTitleCoords='الإحداثيات', menuSubTitleTeleport='الانتقال', menuSubTitleRequestStaff='طلب المساعدة', menuSubTitleCommands='الأوامر', menuSubTitleScoreboard='قائمة اللاعبين', menuSubTitleDevTools='أدوات المطور',
    confirm='تأكيد', serverID='أدخل رقم اللاعب في السيرفر',
    administration='الإدارة', booster='أدوات المشرف', database='الممتلكات والمخزون', teleport='الانتقال', devTools='أدوات المطور',
    playersList='قائمة اللاعبين', adminActions='إجراءات الإدارة', offLineActions='اللاعبون غير المتصلين', viewReports='البلاغات', searchPlayer='البحث عن لاعب',
    playerSteamName='اسم الحساب:', playerServerID='رقم اللاعب:', playerName='اسم الشخصية:', playerGroup='الصلاحية:', playerJob='الوظيفة:', playerGrade='الرتبة:', playerIdentifier='معرّف الحساب:', playerMoney='النقود:', playerGold='الذهب:', playerStaticID='الرقم الثابت:', playerWhitelist='القائمة البيضاء:',
    simpleActions='الإجراءات الأساسية', advancedActions='الإجراءات المتقدمة', trollActions='التأثيرات على اللاعب',
    deleteMountHorse='حذف الخيل الذي تركبه', deleteMountWagon='حذف العربة التي تركبها', deleteWagonInRadius='حذف العربات القريبة', getCoords='إحداثيات اللاعب', adminAnnounce='إعلان إداري',
    getCoordsXYZ='نسخ إحداثيات XYZ', getCoordsVec3='نسخ Vector3', getCoordsVec4='نسخ Vector4', getHeading='نسخ اتجاه الشخصية',
    killPlayer='قتل اللاعب', invisPlayer='إخفاء اللاعب', lightningStrikePlayer='صاعقة على اللاعب', setPlayerOnFire='إشعال النار', teleportToHeaven='رفع اللاعب إلى السماء', ragdollPlayer='إسقاط اللاعب', drainPlayerStam='تفريغ طاقة اللاعب', cuffPlayer='تقييد اللاعب', tempHighPlayer='تأثير بصري مؤقت',
    banOrUnban='الحظر وفك الحظر', whiteOrUnwhite='القائمة البيضاء',
    freezePlayer='تجميد اللاعب', bringPlayer='إحضار اللاعب', goToPlayer='الانتقال إلى اللاعب', revivePlayer='إنعاش اللاعب', healPlayer='علاج اللاعب', spectatePlayer='مراقبة اللاعب',
    respawnPlayer='إعادة ظهور اللاعب', kickPlayer='طرد اللاعب', banPlayer='حظر اللاعب', unbanPlayer='فك الحظر', unWhitelistPlayer='إزالة القائمة البيضاء', setPlayerGroup='تغيير صلاحية اللاعب', setPlayerJob='تغيير وظيفة اللاعب',
    give='إعطاء ممتلكات', remove='إزالة ممتلكات', playerDatabase='بيانات اللاعب',
    showInventory='عرض مخزون اللاعب', giveItem='إعطاء عنصر', giveWeapon='إعطاء سلاح', giveCurrency='إعطاء نقود أو ذهب', giveHorse='إعطاء خيل', giveWagon='إعطاء ملكية عربة', removeMoney='إزالة جميع النقود', removeGold='إزالة جميع الذهب', clearAllItems='مسح جميع العناصر', clearAllWeapons='مسح جميع الأسلحة',
    interiorId='رقم المبنى الداخلي', spawnPedWithList='إنشاء شخصية أو حيوان من القائمة', spawnPedWithInput='إنشاء شخصية أو حيوان بالاسم', coordsMenu='الإحداثيات', spawnWagonWithList='إنشاء عربة من القائمة', spawnWagonWithInput='إنشاء عربة بالاسم', objectMenu='الأجسام القريبة', imapViwer='عارض الخرائط الداخلية', scenarioHashViwer='معرّف النشاط الحالي', printModel='معرّف الجسم القريب', deleteModel='حذف الجسم القريب', devtoolOn='شعاع فحص الكائنات',
    tpmAuto='الانتقال التلقائي إلى العلامة', tpmToMarker='الانتقال إلى علامة الخريطة', tpToCoords='الانتقال إلى إحداثيات', tpToPlayer='الانتقال إلى لاعب', adminGoBackLastLocation='العودة إلى مكانك السابق', sendPlayerToLastLocation='إرجاع اللاعب إلى مكانه', teleportToGuarma='الذهاب إلى غوارما أو العودة',
    godMode='الحماية من الضرر', infiniteAmmo='ذخيرة غير محدودة', noClip='الطيران الحر', selfHeal='علاج نفسك', selfRevive='إنعاش نفسك', spawnHorse='إنشاء خيل مؤقت', spawnWagon='إنشاء عربة مؤقتة', goldenCores='تفعيل النوى الذهبية', selfInvisible='إخفاء نفسك',
    scoreboard='قائمة اللاعبين', report='إرسال بلاغ', requestStaff='طلب مساعدة مشرف', showInfo='معلومات الشخصية', commands='الأوامر', animations='قائمة الحركات',
    needHelp='طلب المساعدة', foundBug='الإبلاغ عن خلل', rulesBroken='مخالفة القوانين', someoneCheating='اشتباه بالغش', delHorse='حذف الخيل', delWagon='حذف العربة', hideUi='إظهار أو إخفاء الواجهة', cancelAnimation='إلغاء الحركة',
    selfNoClip='تفعيل الطيران الحر', selfGodMode='تفعيل الحماية من الضرر', enabledInfinityAmmo='تفعيل الذخيرة غير المحدودة', selfGoldCores='تفعيل النوى الذهبية', speedMode='LShift لتغيير السرعة', cammode='H لتغيير اتجاه الحركة', move='W/A/S/D/Q/Z للحركة',
    up='أعلى', down='أسفل', forward='أمام', backward='خلف', speed='السرعة', cancel='إلغاء',
    playerReport='إرسال بلاغ', playerRequestStaff='طلب مساعدة مشرف', selfShowInfo='معلومات شخصيتي', playerWalkAndClothesStyle='المشي والملابس', playerCommands='الأوامر',
    playerSpectate='مراقبة اللاعب', playerSendBack='إرجاع اللاعب', playerBring='إحضار اللاعب', playerGoBack='العودة إلى مكانك', playerRevive='إنعاش اللاعب', playerFreeze='تجميد اللاعب', playerHeal='علاج اللاعب', playerGoTo='الانتقال إلى اللاعب',
    playerBan='حظر اللاعب', playerRespawn='إعادة ظهور اللاعب', playerKick='طرد اللاعب', playerSetJob='تغيير وظيفة اللاعب', playerUnWhitelist='إزالة القائمة البيضاء', playerUnBan='فك الحظر', playerSetGroup='تغيير صلاحية اللاعب', giveMoneyOrGold='إعطاء نقود أو ذهب',
}
local descriptions = {
    administration_desc='إدارة اللاعبين والبلاغات والإعلانات والصلاحيات.', booster_desc='الحماية والطيران والإنعاش وإنشاء الخيل والعربات المؤقتة.', database_desc='عرض مخزون اللاعبين وإعطاء الممتلكات أو إزالتها.', teleport_desc='الانتقال إلى اللاعبين والعلامات والإحداثيات.', devTools_desc='إنشاء الموديلات وفحص الكائنات ونسخ الإحداثيات.',
    adminActions_desc='حذف الخيل والعربات ونسخ الإحداثيات ونشر إعلان.', offLineActions_desc='الحظر وفك الحظر وإدارة القائمة البيضاء لغير المتصلين.', viewReports_desc='قراءة بلاغات اللاعبين وإغلاق البلاغات المعالجة.', searchPlayer_desc='ابحث برقم اللاعب في السيرفر.',
    playerSpectate_desc='راقب اللاعب. استخدم /adminstop لإنهاء المراقبة والعودة إلى موقعك.', playerFreeze_desc='تجميد اللاعب أو فك تجميده.', playerRevive_desc='إنعاش اللاعب في مكانه.', playerHeal_desc='استعادة صحة اللاعب وطاقته.', playerGoTo_desc='انتقل إلى موقع اللاعب.', playerGoBack_desc='العودة إلى موقعك السابق.', playerBring_desc='إحضار اللاعب إلى موقعك.', playerSendBack_desc='إرجاع اللاعب إلى موقعه قبل الإحضار.',
    playerBan_desc='حظر اللاعب لمدة تحددها؛ 0 للحظر الدائم.', playerRespawn_desc='إعادة ظهور اللاعب حسب إعدادات الكور.', playerKick_desc='طرد اللاعب مع كتابة السبب.', playerSetJob_desc='تغيير اسم الوظيفة والرتبة واسم العرض.', playerUnWhitelist_desc='إزالة الحساب من القائمة البيضاء.', playerUnBan_desc='إزالة الحظر عن الحساب.', playerSetGroup_desc='تغيير صلاحية اللاعب ضمن الرتب المسموحة لك.',
    showInventory_desc='عرض محتويات مخزون اللاعب.', giveItem_desc='إعطاء عنصر باسم الموديل والكمية.', giveWeapon_desc='إضافة سلاح إلى مخزون اللاعب.', giveMoneyOrGold_desc='اكتب 0 للنقود أو 1 للذهب، ثم المبلغ. يمكن استخدام مبلغ عشري.',
    selfNoClip_desc='تفعيل الطيران الحر أو إيقافه.', selfGodMode_desc='تفعيل الحماية من الضرر أو إيقافها.', selfGoldCores_desc='تفعيل النوى الذهبية أو إيقافها.', enabledInfinityAmmo_desc='ذخيرة غير محدودة للسلاح الذي تمسكه عند التفعيل.',
    interiorId_desc='طباعة رقم المبنى الداخلي في سجل F8.', scenarioHashViwer_desc='تفعيل طباعة معرّف النشاط في سجل F8 أو إيقافها.',
    playersList_desc='عرض اللاعبين المتصلين وبيانات شخصياتهم.',
    banOrUnban_desc='اكتب ban ثم الرقم الثابت والمدة، مثل ban 6 1d. لفك الحظر: unban 6. المدة 0 تعني حظرًا دائمًا.',
    whiteOrUnwhite_desc='للسماح: whitelist steam:123. للإزالة: unwhitelist steam:123.',
    removeMoney_desc='إزالة نقود الجيب فقط، دون الرصيد البنكي.', removeGold_desc='إزالة ذهب الجيب فقط، دون الرصيد البنكي.',
    clearAllItems_desc='مسح جميع عناصر مخزون اللاعب بعد تأكيد العملية.', clearAllWeapons_desc='مسح جميع أسلحة اللاعب وذخيرتها بعد التأكيد.',
    giveCurrency_desc='اكتب نوع العملة ثم المبلغ: 0 للنقود، و1 للذهب. مثال: 0 125.50.',
    giveHorse_desc='إضافة خيل إلى إسطبل اللاعب. اكتب الموديل ثم الاسم ثم الجنس: 0 للذكر و1 للأنثى.',
    giveWagon_desc='يتطلب سكربتًا متصلًا يدعم ملكية العربات.',
    spawnPeds_desc='اختر الموديل لإنشاء شخصية أو حيوان.', spawnPed_desc='اختر الموديل لإنشاء شخصية أو حيوان.', spawnVehicle_desc='اختر الموديل لإنشاء عربة مؤقتة.',
    devtool_desc='فحص الكائن الذي تصوّب نحوه ونسخ بياناته.',
}
local inputs = {
    MenuAdminInput={'البحث عن لاعب','رقم اللاعب في السيرفر'}, DelWagonRadiusInput={'حذف العربات القريبة','نصف القطر بالمتر، من 1 إلى 100'}, AnnounceInput={'إعلان إداري','اكتب نص الإعلان'},
    BanTypeInput={'حظر لاعب غير متصل','ban 6 1d / unban 6'}, WhiteTypeInput={'القائمة البيضاء','whitelist steam:123 / unwhitelist steam:123'},
    KickInput={'طرد اللاعب','سبب الطرد'}, BanInput={'حظر اللاعب','0 / 12h / 1d / 1w / 1m / 1y'}, GroupInput={'تغيير الصلاحية','user / moderator / admin / owner'}, JobInput={'تغيير الوظيفة','police 1 Police Officer'},
    GiveItemInput={'إعطاء عنصر','water 2'}, GiveWeaponInput={'إعطاء سلاح','WEAPON_REVOLVER_CATTLEMAN'}, GiveCurrencyInput={'إعطاء نقود أو ذهب','0 125.50 / 1 2.50'}, GiveHorseInput={'إعطاء خيل','a_c_horse_arabian_white MyHorse 0'}, GiveWagonInput={'إعطاء عربة','wagon02x MyWagon'},
    RemoveAllItemInput={'مسح جميع العناصر','نعم / لا / yes / no'}, RemoveAllWeaponInput={'مسح جميع الأسلحة','نعم / لا / yes / no'}, SpawnPedInput={'إنشاء شخصية أو حيوان','A_C_Alligator_03'}, SpawnWagonInput={'إنشاء عربة','wagon02x'}, SpawnHorseInput={'إنشاء خيل','a_c_horse_arabian_white'}, InsertCoordsInput={'الانتقال إلى إحداثيات','vector3(100.0, 200.0, 50.0)'}, ReportInput={'إرسال بلاغ','اشرح المشكلة أو المخالفة'},
}
local function build(source)
    local out = {}
    for key, value in pairs(source) do
        if type(value) == 'table' then
            out[key] = build(value)
            if inputs[key] then
                out[key].title = inputs[key][1]
                out[key].placeholder = inputs[key][2]
                out[key].errorMsg = 'أدخل قيمة صحيحة بالصيغة الموضحة.'
            end
        elseif type(value) == 'string' then
            local base = key:match('^(.-)_desc$')
            out[key] = labels[key] or descriptions[key] or (base and ('اختر لتنفيذ: ' .. (labels[base] or 'هذا الإجراء'))) or value
        else out[key] = value end
    end
    return out
end
Translation.Langs.Arabic = { Menus = build(Translation.Langs.English.Menus), Webhooks = Translation.Langs.English.Webhooks }
Translation.Langs.Arabic.Notify = {
    noperms='لا تملك صلاحية تنفيذ هذا الإجراء.', userNotExist='اللاعب غير متصل أو شخصيته غير جاهزة.', switchedOn='تم التفعيل', switchedOff='تم الإيقاف', cantKickStaff='لا يمكنك طرد مشرف بنفس رتبتك أو أعلى.', cantBanStaff='لا يمكنك حظر مشرف بنفس رتبتك أو أعلى.', empty='لم تدخل قيمة.', whiteApproved='تمت الإضافة إلى القائمة البيضاء.', whiteRemoved='تمت الإزالة من القائمة البيضاء.', incorrectType='نوع الإجراء غير صحيح.', missingArgument='البيانات ناقصة. راجع المثال.', needWeaponInHands='يجب أن تمسك سلاحًا.', reviseRules='يرجى مراجعة قوانين السيرفر.', actionCancell='تم الإلغاء', closesObject='معرّف الجسم:', goToPlayerFirst='انتقل إلى اللاعب أولًا.', reportTitle='البلاغات', reportSent='تم إرسال البلاغ إلى الإدارة.', requestSent='تم إرسال طلب المساعدة.', waitToReportAgain='انتظر قبل إرسال بلاغ جديد: ', youNeedtoSeatead='يجب أن تكون في مقعد القيادة.', youDeletedWagon='تم حذف العربة.', kickedNotify='تم طردك', bannedNotify='تم حظرك', respawnedNotify='ستتم إعادة ظهورك', lostAllItems='قد تفقد ممتلكاتك بحسب إعدادات إعادة الظهور.', invalidAdd='بيانات الإضافة غير صحيحة.', doesNotExistInDB='العنصر غير موجود في قاعدة البيانات.', inventoryFull='مخزون اللاعب ممتلئ.', itemLimit='لا يستطيع اللاعب حمل هذه الكمية.', receivedItem='استلمت: ', of=' من: ', itemGiven='تم إعطاء العنصر.', cantCarryWeapon='لا يستطيع اللاعب حمل سلاح إضافي.', receivedWeapon='استلمت سلاحًا.', weaponGiven='تم إعطاء السلاح.', addQuantity='أدخل مبلغًا صحيحًا.', money=' نقود', gold=' ذهب', ofRoll=' من النقود غير القانونية', sent='تم الإرسال.', horseReceived='استلمت خيلًا. يمكنك استدعاؤه من الإسطبل.', horseGiven='تم إعطاء الخيل.', wagonReceived='تمت إضافة ملكية العربة.', givenWagon='تم إعطاء العربة.', itemsWiped='تم مسح العناصر.', itemWipe='مسح مشرف جميع عناصر مخزونك.', weaponsWiped='تم مسح الأسلحة.', weaponWipe='مسح مشرف جميع أسلحتك.', moneyRemoved='تمت إزالة نقود اللاعب.', moneyRemovedFromAdmin='أزال مشرف نقود جيبك.', goldRemoved='تمت إزالة ذهب اللاعب.', goldRemovedFromAdmin='أزال مشرف ذهب جيبك.', groupGiven='تم منحك الصلاحية: ', jobGiven='تم منحك الوظيفة: ', gradeGiven='الرتبة: ', jobLabelGiven='اسم الوظيفة: ', announce='إعلان', player='اللاعب: ', reportedToDiscord=' أرسل بلاغًا للإدارة.', requestingAssistance=' يطلب المساعدة: ', new=' لاعب جديد يحتاج مساعدة', foundBug=' وجد خللًا', someoneBrokerules=' مخالفة للقوانين', someoneCheating=' اشتباه بالغش', copied='تم نسخ الإحداثيات.', notAvailable='هذا الخيار غير متاح.',
}
