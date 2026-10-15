-- jrs_paycheck | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_paycheck  |  config.lua
--  Pays online players once a minute: a wage for their job and grade, plus a stipend for their group.
-- ==========================================================================

Config = {}

Config.DevMode = false          -- prints what is paid; never leave on for a live server
Config.PayEverySeconds = 60

-- Currency ids: 0 = dollars, 1 = gold, 2 = the server's own extra currency

-- Stipend for staying on the server, by character group (paid per interval)
Config.Groups = {
    Special = { payment = 0.10, currency = 0 },
}

-- Wage tables by grade (paid per interval)
Config.Grades = {
    law   = { [0] = 0.20, [1] = 0.40, [2] = 0.60, [3] = 0.80 },
    medic = { [0] = 0.20, [1] = 0.40, [2] = 0.60, [3] = 0.80 },
}

-- Each paid job:
--   payment      wage table (see Config.Grades)
--   mustbeonduty only pay while on duty (checked on the server)
--   statebagKey  duty flag name; jrs_police ("isPoliceDuty") and jrs_medic ("isMedicDuty") are asked directly
--   IsOnDuty     optional function(source, job, grade) -> boolean for any other duty system
--   currency     optional, defaults to 0
local function sheriff() return { payment = Config.Grades.law,   mustbeonduty = true, statebagKey = 'isPoliceDuty' } end
local function medic()   return { payment = Config.Grades.medic, mustbeonduty = true, statebagKey = 'isMedicDuty'  } end

Config.Jobs = {
    BWSheriff  = sheriff(),
    RhoSheriff = sheriff(),
    SDSheriff  = sheriff(),
    StrSheriff = sheriff(),
    ArmSheriff = sheriff(),
    ValSheriff = sheriff(),

    doctor     = medic(),
    headdoctor = medic(),
    shaman     = medic(),
}
