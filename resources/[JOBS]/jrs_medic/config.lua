-- jrs_medic | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_medic  |  config.lua
--  Doctors: stations (boss menu, shared storage, teleport), duty, healing items and emergency calls.
-- ==========================================================================

Config = {
    Language   = 'en',             -- 'en' or 'ar' (prompts and blip names stay English: the game font has no Arabic)
    DevMode    = false,            -- /doctormenu for everybody. Never on a live server.
    MenuAlign  = 'top-left',

    PromptKey  = 0x4CC0E2FE,       -- B
    Reach      = 2.0,              -- metres to a station point

    -- Commands
    MenuCommand    = 'doctormenu',         -- duty + teleports (doctors)
    CallCommand    = 'calldoctor',         -- ask for a doctor
    CancelCommand  = 'cancelDoctorAlert',  -- the caller cancels
    FinishCommand  = 'finishDoctorAlert',  -- the doctor ends the call
    OnlyDeadCanCall = true,

    ShareStorage     = true,       -- one storage for every station (false: one each)
    StorageLimit     = 1000,
    UseTeleportMenu  = true,       -- teleport list in the duty menu (false: only at the teleport points)
}

-- Who works here. grade -> { label, manager }. A manager can hire and fire.
Config.Jobs = {
    doctor = {
        [0] = { label = 'Doctor', manager = true },
        [1] = { label = 'Nurse' },
    },
}

-- name, boss menu point, storage point, teleport point
local function station(name, boss, storage, teleport)
    return { name = name, boss = boss, storage = storage, teleport = teleport }
end

Config.Stations = {
    station('Valentine',  vector3(-288.82, 808.44, 119.43),  vector3(-288.74, 808.77, 119.44),  vector3(-280.38, 817.81, 119.38)),
    station('Strawberry', vector3(-1807.87, -430.77, 158.83), vector3(-1803.33, -432.59, 158.83), vector3(-1793.37, -422.81, 155.97)),
    station('SaintDenis', vector3(2721.29, -1233.11, 50.37),  vector3(2733.10, -1230.26, 50.42),  vector3(2723.10, -1238.92, 49.95)),
}

Config.Blips = {
    station = { color = 'COLOR_WHITE', style = 'BLIP_STYLE_FRIENDLY_ON_RADAR', sprite = 'blip_mp_travelling_saleswoman' },
    call    = { color = 'COLOR_RED',   style = 'BLIP_STYLE_CHALLENGE_OBJECTIVE', sprite = 'blip_mp_travelling_saleswoman' },
}

-- Items that heal or revive. health / stamina: points to add. revive: bring a dead player back.
-- onDuty: only a doctor who is on duty may use it.
Config.Items = {
    bandage = { health = 50,  stamina = 100, revive = false, onDuty = false },
    potion  = { health = 100, stamina = 0,   revive = false, onDuty = false },
    syringe = { health = 0,   stamina = 0,   revive = true,  onDuty = true },
}

-- Discord logs (leave empty to turn a log off)
Config.Logs = {
    Hire = '', Duty = '', Storage = '',
    name = 'Medic logs', color = 16711680, logo = '', footer = '', avatar = '',
}

Config.Text = {
    en = {
        press = 'Press', hire = 'Hire', fire = 'Fire', hirePlayer = 'Hire Player', firePlayer = 'Fire Player',
        doctorMenu = 'Doctor Menu', hireFire = 'Hire/Fire Menu', openMenu = 'Open Doctor Menu', sub = 'SubMenu', pressEnter = 'Press Enter',
        teleportTo = 'Teleport to', teleportMenu = 'Teleport Menu', teleportAll = 'Teleport to different locations',
        goOn = 'Go on duty', goOff = 'Go off duty', onDuty = 'On Duty', offDuty = 'Off Duty',
        notOnDuty = 'You are not on duty', nowOnDuty = 'You are now on duty',
        job = 'Job', notDoctor = 'You are not a doctor', noLabel = "Job doesn't have a label in config, please add",
        notDead = 'Player is not dead', playerId = 'Player ID', confirm = 'Confirm', numbersOnly = 'Only numbers are allowed',
        notFound = 'Player not found. You can only hire players in session.', alreadyHired = 'Player is already a ',
        notNear = 'Player is not near you to be hired', hired = 'You have been hired as ',
        cantFire = "Player is not a doctor, you can't fire them", youFired = 'You have fired the player', fired = 'You have been fired',
        nobodyToRevive = 'No player close to you to revive',
        menuDenied = 'You are not allowed to open this menu', playerNearby = 'There is a player nearby. Cannot open inventory',
        alreadyCalled = 'You already alerted the doctors. To cancel, use /cancelDoctorAlert', noDoctors = 'No doctors available at this moment',
        notDeadCall = 'You are not dead to alert doctors', noCall = 'You have not alerted the doctors', notOnCall = 'You are not on call',
        needsHelp = 'Player needs help. Look at the map for their location', alerted = 'Doctors have been alerted',
        canceled = 'You have canceled the alert', canceledByPlayer = 'Player has canceled the alert',
        canceledByDoctor = 'Doctor has canceled the alert', dropped = 'Player has disconnected, alert canceled',
        arrived = 'You have arrived at the location', callName = 'player alert',
    },
    ar = {
        press = 'Press', hire = 'توظيف', fire = 'فصل', hirePlayer = 'توظيف لاعب', firePlayer = 'فصل لاعب',
        doctorMenu = 'قائمة الطبيب', hireFire = 'التوظيف والفصل', openMenu = 'فتح قائمة الطبيب', sub = 'قائمة فرعية', pressEnter = 'اضغط Enter',
        teleportTo = 'انتقال إلى', teleportMenu = 'قائمة الانتقال', teleportAll = 'انتقل لأماكن مختلفة',
        goOn = 'بدء الدوام', goOff = 'إنهاء الدوام', onDuty = 'في الدوام', offDuty = 'خارج الدوام',
        notOnDuty = 'أنت مو في الدوام', nowOnDuty = 'بدأت الدوام',
        job = 'الوظيفة', notDoctor = 'أنت مو طبيب', noLabel = 'الوظيفة ما لها اسم في الإعدادات، أضفه',
        notDead = 'اللاعب مو ميت', playerId = 'رقم اللاعب', confirm = 'تأكيد', numbersOnly = 'أرقام فقط',
        notFound = 'ما لقينا اللاعب. تقدر توظف اللاعبين المتصلين بس.', alreadyHired = 'اللاعب أصلاً ',
        notNear = 'اللاعب مو قريب منك عشان توظفه', hired = 'توظفت كـ ',
        cantFire = 'اللاعب مو طبيب، ما تقدر تفصله', youFired = 'فصلت اللاعب', fired = 'انفصلت من الوظيفة',
        nobodyToRevive = 'ما فيه لاعب قريب تنعشه',
        menuDenied = 'مو مسموح لك تفتح هالقائمة', playerNearby = 'فيه لاعب قريب، ما تقدر تفتح المخزن',
        alreadyCalled = 'نبهت الأطباء من قبل. للإلغاء استخدم /cancelDoctorAlert', noDoctors = 'ما فيه أطباء متوفرين الحين',
        notDeadCall = 'أنت مو ميت عشان تنبه الأطباء', noCall = 'ما نبهت الأطباء', notOnCall = 'أنت مو في نداء',
        needsHelp = 'لاعب يحتاج مساعدة. شوف الخريطة لموقعه', alerted = 'تم تنبيه الأطباء',
        canceled = 'ألغيت التنبيه', canceledByPlayer = 'اللاعب ألغى التنبيه',
        canceledByDoctor = 'الطبيب ألغى التنبيه', dropped = 'اللاعب طلع من السيرفر، انلغى التنبيه',
        arrived = 'وصلت للموقع', callName = 'تنبيه لاعب',
    },
}
