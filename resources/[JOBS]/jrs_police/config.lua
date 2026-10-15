-- jrs_police | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_police  |  config.lua
--  Law enforcement: stations, duty, cuffs and dragging, jail, emergency calls.
-- ==========================================================================

Config = {
    Language   = 'en',             -- 'en' or 'ar' (prompts and blip names stay English: the game font has no Arabic)
    DevMode    = false,            -- never on a live server
    MenuAlign  = 'top-left',

    PromptKey  = 0x4CC0E2FE,       -- B
    Reach      = 2.0,              -- metres to a station point

    -- Commands
    MenuCommand   = 'policeMenu',          -- duty + teleports
    DragCommand   = 'Drag',                -- drag the nearest player
    CallCommand   = 'callpolice',          -- ask for the police
    CancelCommand = 'cancelPoliceAlert',   -- the caller cancels
    FinishCommand = 'finishPoliceAlert',   -- the officer ends the call
    OnlyDeadCanCall = true,

    EveryoneCanCuff = false,       -- true: anyone holding handcuffs; false: officers on duty only
    CuffItem   = 'handcuffs',      -- put on someone with it
    KeyItem    = 'handcuffkey',    -- take them off again
    CuffIsUsedUp = true,           -- the handcuffs are consumed; the key gives one back

    ShareStorage    = true,        -- one storage for every station (false: one each)
    StorageLimit    = 1000,
    UseTeleportMenu = true,
}

Config.Jail = {
    center  = vector3(3339.23, -670.12, 45.83),   -- middle of the prison area
    radius  = 50.0,                               -- leave it and you are sent back
    spawn   = vector3(3339.07, -669.41, 45.83), spawnHeading = 194.42,          -- where prisoners start
    release = vector3(2518.42, -1308.34, 49.01), releaseHeading = 275.49,       -- where they are freed
    maxMinutes = 600,
    commands = {
        jail = 'jail',                    -- /jail <id> <minutes>
        unjail = 'unjail',                -- /unjail <id>
        change = 'changejailtime',        -- /changejailtime <id> <minutes>   (negative = shorter)
        check  = 'checkjailtime',         -- prisoners: see how long is left
    },
}

-- Who works here. grade -> { label, manager (hire/fire), jail (jail commands) }
Config.Jobs = {
    Police = {
        [0] = { label = 'Sheriff', manager = true, jail = true },
        [1] = { label = 'Deputy',  manager = true, jail = true },
    },
}

-- name, boss menu point, storage point (and its name), teleport point
local function station(name, boss, storage, storageName, teleport)
    return { name = name, boss = boss, storage = storage, storageName = storageName, teleport = teleport }
end

Config.Stations = {
    station('Valentine',   vector3(-277.73, 804.84, 119.38),   vector3(-276.97, 810.83, 119.38),   'Storage', vector3(-278.17, 814.88, 119.28)),
    station('Strawberry',  vector3(-1807.03, -348.47, 164.65), vector3(-1814.17, -354.75, 164.65), 'Storage', vector3(-1805.13, -355.05, 164.14)),
    station('Blackwater',  vector3(-761.95, -1272.62, 44.05),  vector3(-765.12, -1272.37, 44.04),  'Armoury', vector3(-752.53, -1266.10, 43.43)),
    station('Rhodes',      vector3(1361.57, -1303.40, 77.77),  vector3(1361.17, -1305.83, 77.76),  'Armoury', vector3(1354.90, -1306.85, 76.94)),
    station('Saint Denis', vector3(2508.46, -1308.56, 48.95),  vector3(2494.62, -1304.30, 48.95),  'Armoury', vector3(2510.00, -1318.00, 48.53)),
    station('Tumbleweed',  vector3(-5529.55, -2929.25, -1.36), vector3(-5526.59, -2928.51, -1.36), 'Armoury', vector3(-5531.39, -2935.31, -1.91)),
    station('Annesburg',   vector3(2907.11, 1313.93, 44.94),   vector3(2904.03, 1309.86, 44.94),   'Armoury', vector3(2916.59, 1317.09, 44.35)),
    station('Armadillo',   vector3(-3624.70, -2601.96, -13.34), vector3(-3622.69, -2600.00, -13.34), 'Armoury', vector3(-3610.40, -2599.16, -13.88)),
}

Config.Blips = {
    station = { color = 'COLOR_WHITE', style = 'BLIP_STYLE_FRIENDLY_ON_RADAR',   sprite = 'blip_mp_bounty_hunter_introduction' },
    call    = { color = 'COLOR_RED',   style = 'BLIP_STYLE_CHALLENGE_OBJECTIVE', sprite = 'blip_mp_bounty_hunter_introduction', name = 'Police Alert' },
}

-- Discord logs (leave empty to turn a log off)
Config.Logs = {
    Hire = '', Duty = '', Jail = '', Storage = '',
    name = 'Police logs', color = 16711680, logo = '', footer = '', avatar = '',
}

Config.Text = {
    en = {
        press = 'Press', hirePlayer = 'Hire Player', firePlayer = 'Fire Player', sheriffMenu = 'Sheriff Menu',
        hireFire = 'Hire/Fire Menu', sub = 'SubMenu', pressEnter = 'Press Enter',
        teleportTo = 'Teleport to ', teleportMenu = 'Teleport Menu', teleportAll = 'Teleport to different locations',
        goOn = 'Go on duty', goOff = 'Go off duty', onDuty = 'On Duty', offDuty = 'Off Duty',
        notOnDuty = 'You are not on duty', nowOnDuty = 'You are now on duty',
        job = 'Job', notOfficer = 'You are not a police officer', noLabel = 'job doesnt have label in config please add',
        playerId = 'Player ID', confirm = 'Confirm', numbersOnly = 'Only numbers are allowed',
        notFound = 'player not found can only hire players in session', alreadyHired = 'player is already a ',
        notNear = 'player is not near you to be hired', hired = 'you have been hired as ',
        cantFire = 'player is not a police officer you cant fire them', youFired = 'you have fired the player', fired = 'you have been fired',
        noRights = 'You are not allowed to do that',
        alreadyCuffed = 'player is already cuffed remove cuffs first', notCuffed = 'player is not cuffed to use the keys',
        menuDenied = 'You Are Not Allowed ToOpen This Menu', playerNearby = 'There Is A Player Nearby Cant Open Inventory',
        alreadyCalled = 'You already alerted the police to cancel it do /cancelPoliceAlert', noOfficers = 'No one to receive alert at this moment',
        notDeadCall = 'You are not dead to alert police', needsHelp = 'Player needs help look in the map to see location',
        alerted = 'Police have been alerted, stay where you are so they can find you', noCall = 'You have not alerted the police',
        canceledByPlayer = 'Player has canceled the alert', canceled = 'You have canceled the alert',
        notOnCall = 'You are not on call to cancel an alert', canceledByOfficer = 'Police has canceled the alert',
        dropped = 'Player has disconnected call canceled', arrived = 'you have arrived to the location look for the player',
        callName = 'player alert',
        jailNoTime = 'Jail time not found', jailLeft = 'You still have %d minutes and %d seconds left in jail',
        jailNoId = 'No player ID', jailBadTime = 'Invalid time was provided', jailNotOnline = 'Player not found, can only jail online players',
        jailAlready = 'Player is already jailed', jailDenied = 'You do not have permission to jail players or you are not on duty',
        jailed = 'Player was jailed', jailedFor = 'You were jailed for %d minutes', released = 'Player was released from jail',
        notJailed = 'Player is not jailed', unjailDenied = 'You do not have permission to unjail players or you are not on duty',
        changeDenied = 'You do not have permission to modify jail time or you are not on duty', noTime = 'Time was not provided',
        jailChanged = 'Jail time was modified from %d minutes to %d minutes', jailExpired = 'Player was released from jail because the time was up',
        callInJail = "you are in jail you can't alert police", cantLeave = "you are in jail you can't leave",
        jailHint = 'to check your jail time and get released use /%s', freed = 'Player was released from jail',
        suggestMenu = 'Open Police Menu',
    },
    ar = {
        press = 'Press', hirePlayer = 'توظيف لاعب', firePlayer = 'فصل لاعب', sheriffMenu = 'قائمة الشريف',
        hireFire = 'التوظيف والفصل', sub = 'قائمة فرعية', pressEnter = 'اضغط Enter',
        teleportTo = 'انتقال إلى ', teleportMenu = 'قائمة الانتقال', teleportAll = 'انتقل لأماكن مختلفة',
        goOn = 'بدء الدوام', goOff = 'إنهاء الدوام', onDuty = 'في الدوام', offDuty = 'خارج الدوام',
        notOnDuty = 'أنت مو في الدوام', nowOnDuty = 'بدأت الدوام',
        job = 'الوظيفة', notOfficer = 'أنت مو رجل شرطة', noLabel = 'الوظيفة ما لها اسم في الإعدادات',
        playerId = 'رقم اللاعب', confirm = 'تأكيد', numbersOnly = 'أرقام فقط',
        notFound = 'ما لقينا اللاعب. تقدر توظف المتصلين بس', alreadyHired = 'اللاعب أصلاً ',
        notNear = 'اللاعب مو قريب منك', hired = 'توظفت كـ ',
        cantFire = 'اللاعب مو رجل شرطة', youFired = 'فصلت اللاعب', fired = 'انفصلت من الوظيفة',
        noRights = 'ما يحق لك هذا',
        alreadyCuffed = 'اللاعب مقيّد أصلاً', notCuffed = 'اللاعب مو مقيّد',
        menuDenied = 'مو مسموح لك تفتح هالقائمة', playerNearby = 'فيه لاعب قريب، ما تقدر تفتح المخزن',
        alreadyCalled = 'نبهت الشرطة من قبل. للإلغاء /cancelPoliceAlert', noOfficers = 'ما فيه أحد يستقبل البلاغ الحين',
        notDeadCall = 'أنت مو ميت عشان تنبه الشرطة', needsHelp = 'لاعب يحتاج مساعدة. شوف الخريطة',
        alerted = 'تم تنبيه الشرطة، ابق مكانك', noCall = 'ما نبهت الشرطة',
        canceledByPlayer = 'اللاعب ألغى البلاغ', canceled = 'ألغيت البلاغ',
        notOnCall = 'أنت مو في بلاغ', canceledByOfficer = 'الشرطة ألغت البلاغ',
        dropped = 'اللاعب طلع من السيرفر', arrived = 'وصلت للموقع، دور على اللاعب',
        callName = 'بلاغ لاعب',
        jailNoTime = 'ما فيه وقت سجن', jailLeft = 'باقي لك %d دقيقة و%d ثانية في السجن',
        jailNoId = 'ما حددت رقم لاعب', jailBadTime = 'وقت غير صحيح', jailNotOnline = 'اللاعب مو متصل',
        jailAlready = 'اللاعب مسجون أصلاً', jailDenied = 'ما عندك صلاحية السجن أو أنت مو في الدوام',
        jailed = 'تم سجن اللاعب', jailedFor = 'تم سجنك %d دقيقة', released = 'تم إطلاق سراح اللاعب',
        notJailed = 'اللاعب مو مسجون', unjailDenied = 'ما عندك صلاحية الإفراج أو أنت مو في الدوام',
        changeDenied = 'ما عندك صلاحية تعديل مدة السجن أو أنت مو في الدوام', noTime = 'ما حددت الوقت',
        jailChanged = 'تغيرت مدة السجن من %d إلى %d دقيقة', jailExpired = 'تم إطلاق سراحه لانتهاء المدة',
        callInJail = 'أنت مسجون، ما تقدر تبلغ الشرطة', cantLeave = 'أنت مسجون، ما تقدر تطلع',
        jailHint = 'لمعرفة وقتك المتبقي استخدم /%s', freed = 'تم إطلاق سراح اللاعب',
        suggestMenu = 'فتح قائمة الشرطة',
    },
}
