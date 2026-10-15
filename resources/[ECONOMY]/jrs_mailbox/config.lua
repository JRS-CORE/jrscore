-- jrs_mailbox | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_mailbox  |  config.lua
--  Telegrams: write to any character, or shout one to the whole server, at a post office.
-- ==========================================================================

Config = {
    Language       = 'en',      -- 'en' or 'ar'

    ReadKey        = 0xD8F73058, -- U  read your mail
    BroadcastKey   = 0x760A9C6F, -- G  telegram to everyone
    UseDistance    = 2.0,        -- metres from the post office clerk

    SendPrice      = 10,         -- dollars for one telegram to one person
    BroadcastPrice = 3,          -- dollars for a telegram to everyone
    SendCooldown   = 600,        -- seconds between two telegrams from the same player (0 = none)
    BroadcastCooldown = 600,     -- seconds between two broadcasts (0 = none)

    DirectoryRefresh = 0,        -- seconds between reloads of the list of characters (0 = once at start)

    ClerkModel     = 'U_M_M_BIVFOREMAN_01',
    BlipName       = 'Mail Box',
    BlipSprite     = 1475382911,
}

Config.Offices = {
    { label = 'Valentine',     at = vector4(-177.9952, 628.0817, 114.0896, 145.8196) },
    { label = 'Blackwater',    at = vector4(-875.00, -1329.27, 43.96, 90.0) },
    { label = 'Strawberry',    at = vector4(-1765.18, -384.21, 157.74, 180.0) },
    { label = 'Rhodes',        at = vector4(1289.91, -1300.89, 77.04, 180.0) },
    { label = 'Saint Denis',   at = vector4(2747.23, -1394.92, 46.23, 180.0) },
    { label = 'Emerald',       at = vector4(1522.05, 438.76, 90.68, 180.0) },
    { label = 'Van Horn',      at = vector4(2985.92, 568.21, 44.63, 180.0) },
    { label = 'Annesburg',     at = vector4(2931.48, 1283.01, 44.65, 180.0) },
    { label = 'Big Valley',    at = vector4(-1301.32, 398.50, 95.43, 180.0) },
    { label = 'Riggs Station', at = vector4(-1094.42, -574.89, 82.41, 180.0) },
    { label = 'Armadillo',     at = vector4(-3729.17, -2603.31, -12.94, 180.0) },
    { label = 'Rio Bravo',     at = vector4(-5227.21, -3471.09, -20.55, 180.0) },
}

Config.Text = {
    en = {
        prompt = 'Mailbox', read = 'Read mail', shout = 'Telegram to everyone',
        received = 'You just received a message from {name}',
        shouted = 'New Telegram:\n{message}\nPaid by {name}',
        sent = 'Telegram sent', wait = 'You have to wait {seconds} sec before sending another',
        poor = 'Insufficient money. You need ${price}',
        -- page
        title = 'US Postal Telegram', close = 'Close', write = 'Write', delete = 'Delete', answer = 'Answer',
        cancel = 'Cancel', send = 'Send', from = 'From', empty = 'No message received', yourMessage = 'Your message',
        destination = 'Destination', search = 'Search a name',
    },
    ar = {
        prompt = 'البريد', read = 'اقرأ بريدك', shout = 'برقية للجميع',
        received = 'وصلتك رسالة من {name}',
        shouted = 'برقية جديدة:\n{message}\nدفعها {name}',
        sent = 'تم إرسال البرقية', wait = 'لازم تنتظر {seconds} ثانية قبل إرسال أخرى',
        poor = 'ما عندك فلوس كافية. تحتاج ${price}',
        title = 'برقية البريد الأمريكي', close = 'إغلاق', write = 'كتابة', delete = 'حذف', answer = 'رد',
        cancel = 'إلغاء', send = 'إرسال', from = 'من', empty = 'ما وصلتك رسائل', yourMessage = 'رسالتك',
        destination = 'إلى', search = 'ابحث عن اسم',
    },
}
