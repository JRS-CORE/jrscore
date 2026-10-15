-- jrs_doorlocks | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_doorlocks  |  config.lua
--  Locked doors: who may open them, which can be lockpicked, and the police alert.
-- ==========================================================================

Config = {
    Language        = 'en',    -- 'en' or 'ar' (the prompt text stays English: the game font has no Arabic)
    DevMode         = false,   -- doors work without character selection. Never on a live server.

    Reach           = 1.5,     -- metres from a door to get the prompt
    PickReach       = 2.0,     -- metres from a door to lockpick it
    ServerReach     = 3.0,     -- the server accepts a request from this close

    AlertChance     = 0.5,     -- chance that a lockpicked alert-door calls the police
    AlertOfficers   = 4,       -- how many of the closest on-duty officers hear about it
}

Config.Text = {
    en = {
        open = 'Open', close = 'Close', opened = 'Opened', closed = 'Closed',
        wrongJob = "You don't have the right job", wrongGrade = "You don't have the right grade",
        notNear = "You are not near a door or this door can't be lockpicked", alreadyOpen = 'The door is already open',
        notAllowed = 'You are not allowed to open this door',
        alertTitle = 'Police Alert', alertText = 'Someone lockpicked a door',
    },
    ar = {
        open = 'Open', close = 'Close', opened = 'Opened', closed = 'Closed',
        wrongJob = 'ما عندك الوظيفة المطلوبة', wrongGrade = 'رتبتك ما تكفي',
        notNear = 'أنت مو قريب من باب أو هالباب ما ينفتح بالمفك', alreadyOpen = 'الباب مفتوح أصلاً',
        notAllowed = 'ما يحق لك فتح هذا الباب',
        alertTitle = 'تنبيه للشرطة', alertText = 'أحد فتح باب بالمفك',
    },
}

-- ------------------------------------------------------------------ the door list
-- Door ids are the game's door hashes (see the rdr3_discoveries door hash list; Spooner shows door coordinates).

local function door(id, name, at, closed, opt)
    opt = opt or {}
    return {
        id = id, name = name, at = at, closed = closed == true,
        perm = opt.perm, unique = opt.unique,
        lockpick = opt.lockpick, tries = opt.tries or 3, alert = opt.alert == true,
        twin = opt.twin,
    }
end

-- door(hash, name, position, closedAtStart, { options })
-- options: perm (key of Config.Permissions), unique (key of Config.Unique), lockpick (item), tries, alert, twin (second door hash)
Config.Doors = {
    door(66424668, 'Front Door', vector3(-3624.6982, -2605.4158, -14.3515), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(79213682, 'Front Door 2', vector3(2715.9944, -1228.5043, 49.3712), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(82263429, 'side Door 1', vector3(2726.5542, -1234.8221, 49.3640), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(138361190, 'Room 2 Door', vector3(-610.1553, -30.7023, 84.9976), true, {  }),
    door(193903155, 'Door 1', vector3(-272.0521, 808.2583, 118.3685), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(295355979, 'Door 2', vector3(-273.4643, 809.9661, 118.3682), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(305296302, 'Front Door 3 (Right)', vector3(2497.6848, -1317.2827, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 2503834054 }),
    door(334467483, 'Door to Hall in Vault Antechamber', vector3(-302.9228, 767.6043, 117.6981), true, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(349074475, 'Front Door', vector3(1359.7096, -1305.9598, 76.7684), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(365712512, 'Room 1 Door', vector3(-611.5969, -31.2334, 84.9976), true, {  }),
    door(385812466, 'Front Gate 1 (Left)', vector3(356.9841, 1463.7023, 178.7265), false, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true, twin = 3093514944 }),
    door(395506985, 'Back Door', vector3(-275.8448, 812.0270, 118.4148), false, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(417362979, 'Back Door', vector3(772.6529, 841.2678, 117.9156), true, {  }),
    door(417663242, 'Back Door 1 (Left)', vector3(2516.1443, -1309.9276, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1611175760 }),
    door(531022111, 'Front Door', vector3(-809.1418, -1279.1901, 42.6615), false, { perm = 'BWBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(535323366, 'Door 3', vector3(-275.0233, 808.2740, 118.3686), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(576950805, 'Vault Door', vector3(-307.7538, 766.3490, 117.7016), true, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(586229709, 'inner Door', vector3(2723.9531, -1227.0920, 49.3678), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(603068205, 'Front Door 4 (Left)', vector3(2506.6062, -1317.2797, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1020479727 }),
    door(640077562, 'Back Door', vector3(1702.7976, 1514.3334, 146.8780), true, {  }),
    door(868379185, 'Front Door', vector3(1697.4684, 1508.2377, 146.8824), true, {  }),
    door(872775928, 'Front Door', vector3(-556.4168, 2698.8635, 319.3802), true, {  }),
    door(902070893, 'Cell Door 2', vector3(-1814.4004, -353.1471, 160.4418), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(906448125, 'Back Door', vector3(-608.7385, -26.6129, 84.9976), true, {  }),
    door(906662604, 'Back Gate 2 (Right)', vector3(3333.5808, -702.0560, 43.0685), true, { perm = 'Sisika', lockpick = 'lockpick', tries = 3, alert = true, twin = 3984556459 }),
    door(925575409, 'Iron Door 1', vector3(-290.8586, 813.3575, 118.4155), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(965922748, 'Manager\'s Office (Left)', vector3(2648.9805, -1300.0492, 51.2454), true, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 1634115439 }),
    door(994323006, 'side Door 2', vector3(2724.8232, -1234.8221, 49.3640), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1002666274, 'Room 1 Door', vector3(773.7313, 847.7337, 117.9156), true, {  }),
    door(1020479727, 'Front Door 4 (Right)', vector3(2508.3376, -1317.2797, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 603068205 }),
    door(1063695460, 'Room 2 Door', vector3(-1637.3914, -1355.4940, 83.4026), true, {  }),
    door(1104407261, 'back Door', vector3(2725.1470, -1221.6248, 49.3678), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1121239638, 'Back Gate 1 (Right)', vector3(3327.5723, -707.5178, 43.3831), true, { perm = 'Sisika', lockpick = 'lockpick', tries = 3, alert = true, twin = 2617210026 }),
    door(1151226872, 'Room 3 Door', vector3(1114.7045, -1301.3329, 65.4180), true, {  }),
    door(1163537966, '1th Office Door', vector3(347.7861, 1471.0980, 178.7798), false, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1189146288, 'Front Door', vector3(-615.9397, -27.0866, 84.9976), true, {  }),
    door(1207903970, 'Cell Door 1', vector3(-1812.0101, -351.9210, 160.4684), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(1223148325, 'Armory Door', vector3(363.3249, 1488.7296, 179.6615), true, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1289094734, 'office Door', vector3(2727.4341, -1229.1630, 49.3678), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1309495497, 'Room 1 Door', vector3(-1643.0652, -1365.2614, 83.4025), true, {  }),
    door(1340831050, 'Gate to Tellers', vector3(-311.7406, 774.6757, 117.7299), true, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1434140379, 'Front Door', vector3(-692.4268, 1042.9230, 134.0241), true, {  }),
    door(1462330364, 'Vault Door', vector3(-817.7866, -1274.3853, 42.6621), true, { perm = 'BWBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1485561723, 'Front Door', vector3(1114.6072, -1305.0754, 65.4183), true, {  }),
    door(1508776842, 'Back Jail Door', vector3(-270.7664, 810.0265, 118.3958), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1514359658, 'Back Door', vector3(-1812.6692, -345.0849, 163.6476), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(1532575796, 'Room 2 Door', vector3(1111.9355, -1303.3284, 65.4180), true, {  }),
    door(1535511805, 'Front Door', vector3(-2590.8411, 457.8380, 146.0140), true, {  }),
    door(1574473390, 'Front Door', vector3(2628.2214, 1694.3290, 114.6662), true, {  }),
    door(1606546482, 'Front Door', vector3(-1646.2410, -1367.1359, 83.4657), true, {  }),
    door(1611175760, 'Back Door 1 (Right)', vector3(2516.1445, -1307.7249, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 417663242 }),
    door(1614494720, 'Back Door', vector3(1359.0985, -1297.5347, 76.7876), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(1634115439, 'Manager\'s Office (Right)', vector3(2646.9802, -1300.9832, 51.2454), true, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 965922748 }),
    door(1634148892, 'Teller Gate', vector3(1295.7341, -1305.4749, 76.0330), true, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1674105116, 'Front Door 1 (Left)', vector3(2493.3726, -1305.6870, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1979938193 }),
    door(1694749582, 'Front Door 2 (Left)', vector3(2493.3726, -1310.2252, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1992193795 }),
    door(1711767580, 'Cell Door 4', vector3(2502.4277, -1307.8550, 47.9533), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1731691513, 'Bathroom Door', vector3(-1644.9806, -1363.3253, 83.4025), true, {  }),
    door(1733501235, 'West Entrance (Right)', vector3(2638.7222, -1300.0184, 51.2460), false, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 2158285782 }),
    door(1751238140, 'Vault Door', vector3(2643.3005, -1300.4268, 51.2558), true, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1821044729, 'Front Door', vector3(-1806.6752, -350.3128, 163.6476), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(1878514758, 'Cell Door', vector3(1357.3337, -1302.4539, 76.7602), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(1963415953, 'Front Door', vector3(-1682.8328, -340.6101, 172.9858), true, {  }),
    door(1979938193, 'Front Door 1 (Right)', vector3(2493.3726, -1307.4185, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1674105116 }),
    door(1988748538, 'Front Door', vector3(-276.0126, 802.5911, 118.4117), false, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(1992193795, 'Front Door 2 (Right)', vector3(2493.3726, -1311.9565, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1694749582 }),
    door(1995743734, 'Cell Door 2', vector3(2499.7522, -1309.8763, 47.9533), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2058564250, 'Door to Backrooms', vector3(1285.1476, -1303.1185, 76.0401), true, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2089945615, 'North Entrance (Right)', vector3(2640.1755, -1286.3425, 51.2460), false, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 2817024187 }),
    door(2117902999, 'Teller Gate', vector3(-816.7253, -1276.7510, 42.6412), true, { perm = 'BWBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2158285782, 'West Entrance (Left)', vector3(2637.7979, -1298.0364, 51.2460), false, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 1733501235 }),
    door(2167775834, 'Cell Door 2', vector3(-763.5279, -1262.4609, 43.0233), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2183007198, 'Front Door', vector3(-1347.9484, 2435.2036, 307.4961), true, {  }),
    door(2212914984, 'Front Door', vector3(-2182.5110, 716.4636, 121.6288), true, {  }),
    door(2307914732, 'Back Door', vector3(-301.5100, 762.9835, 117.7731), true, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2310818050, 'Back Door', vector3(-1637.7156, -1352.6481, 83.4665), true, {  }),
    door(2343746133, 'Door to Backrooms', vector3(-301.9362, 771.7520, 117.7299), true, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2381465602, 'Front Gate 2', vector3(3350.6387, -647.9702, 44.3546), false, { perm = 'Sisika', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2385374047, 'Back Door', vector3(-557.9640, 2708.9880, 319.4318), true, {  }),
    door(2395304827, 'Back Door', vector3(-2597.7019, 457.8384, 146.0140), true, {  }),
    door(2503834054, 'Front Door 3 (Left)', vector3(2495.9534, -1317.2827, 47.9526), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 305296302 }),
    door(2513778780, 'Back Door 2', vector3(1279.4114, -1311.4264, 76.0321), true, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2514996158, 'Cell Door 1', vector3(-765.8612, -1264.7039, 43.0233), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2515591150, 'Cell Door 1', vector3(2503.6387, -1309.8763, 47.9533), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2543619259, 'Strawberry Doctors', vector3(-1802.1118, -429.3925, 157.8320), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2617210026, 'Back Gate 1 (Left)', vector3(3325.8057, -705.5445, 43.3831), true, { perm = 'Sisika', lockpick = 'lockpick', tries = 3, alert = true, twin = 1121239638 }),
    door(2642457609, 'Front Door 1 (Left)', vector3(-309.0521, 779.7301, 117.7299), false, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 3886827663 }),
    door(2670400201, 'Room 1 Door', vector3(-2176.8496, 724.8560, 121.6199), true, {  }),
    door(2810801921, 'Back Door', vector3(-769.1376, -1268.7454, 43.0400), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2817024187, 'North Entrance (Left)', vector3(2642.1567, -1285.4188, 51.2460), false, { perm = 'SDBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 2089945615 }),
    door(2817192481, 'Office Door', vector3(-817.8111, -1277.6685, 42.6519), true, { perm = 'BWBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(2977782592, 'Stable Back Door', vector3(359.5815, 1510.4863, 179.1641), true, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3088209306, 'Front Door 1 (Right)', vector3(1294.5957, -1297.5837, 76.0396), false, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 3317756151 }),
    door(3093514944, 'Front Gate 1 (Right)', vector3(360.2287, 1465.9957, 178.7266), false, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true, twin = 385812466 }),
    door(3142122679, 'Back Door', vector3(1278.8560, -1310.4031, 76.0396), true, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3158090902, 'Front Gate 1', vector3(3349.9089, -645.2471, 44.3546), false, { perm = 'Sisika', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3317756151, 'Front Door 1 (Left)', vector3(1296.2720, -1299.0121, 76.0396), false, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 3088209306 }),
    door(3365520707, 'Cell Door 3', vector3(2498.5000, -1307.8560, 47.9533), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3410720590, 'Front Door 1 (Right)', vector3(-757.0424, -1268.4854, 43.0686), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 1988748538 }),
    door(3439738919, 'Iron Door 2', vector3(-281.0743, 815.2378, 118.4159), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3444471262, 'Side Door', vector3(-389.5800, 1730.2190, 215.4147), true, {  }),
    door(3483244267, 'Vault Door', vector3(1282.5364, -1309.3159, 76.0364), true, { perm = 'RhoBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3489664864, '2th Office Door', vector3(337.1710, 1501.4639, 180.9113), false, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3544613794, 'Back Door', vector3(1111.4659, -1297.5782, 65.4183), true, {  }),
    door(3588026089, 'Front Door', vector3(-282.8080, 803.9548, 118.3932), false, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3718620420, 'Door Behind Tellers', vector3(-311.0598, 770.1240, 117.7022), true, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3723126486, 'Front Door 1', vector3(2715.9944, -1230.2333, 49.3713), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(3821185084, 'Front Door 1 (Left)', vector3(-757.0424, -1269.9233, 43.0686), true, { perm = 'PoliceDoors', lockpick = 'lockpick', tries = 3, alert = true, twin = 3410720590 }),
    door(3886827663, 'Front Door 1 (Right)', vector3(-306.8853, 780.1154, 117.7299), false, { perm = 'ValBank', lockpick = 'lockpick', tries = 3, alert = true, twin = 2642457609 }),
    door(3921310299, 'Front Door', vector3(1115.8678, -1989.7192, 54.3763), true, {  }),
    door(3929468747, 'Front Door', vector3(1136.9983, -977.4539, 68.3859), true, {  }),
    door(3984556459, 'Back Gate 2 (Left)', vector3(3331.8154, -700.0859, 43.0685), true, { perm = 'Sisika', lockpick = 'lockpick', tries = 3, alert = true, twin = 906662604 }),
    door(4016307508, 'Cell Door 1', vector3(-3620.9932, -2600.2490, -14.3516), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(4067537969, 'Front Door 2', vector3(-286.6420, 809.7845, 118.4212), true, { perm = 'Doctor', lockpick = 'lockpick', tries = 3, alert = true }),
    door(4070066247, 'Front Door', vector3(-398.6430, 1722.3650, 215.4293), true, {  }),
    door(4123766266, 'Front Door', vector3(778.9694, 849.5260, 117.9156), true, {  }),
    door(4235597664, 'Cell Door 2', vector3(-3619.1482, -2604.2065, -14.3516), true, { lockpick = 'lockpick', tries = 3, alert = true }),
    door(4248740658, 'Cell Door', vector3(346.2372, 1468.9340, 178.7269), true, { perm = 'FortWallace', lockpick = 'lockpick', tries = 3, alert = true }),
    door(4276865168, 'Room 1 Door', vector3(1115.0217, -1302.5012, 65.4184), true, {  }),
    door(4288310487, 'Back Door', vector3(-1348.2998, 2447.0854, 307.4806), true, {  }),
}

-- jobs that may use a door: job name = lowest grade
Config.Permissions = {
    BWBank = { Police = 1 },
    Doctor = { doctor = 0 },
    FortWallace = { Police = 1 },
    PoliceDoors = { Police = 2 },
    RhoBank = { Police = 1 },
    SDBank = { Police = 1 },
    Sisika = { Police = 1 },
    ValBank = { Police = 1 },
}

-- characters (by id) that may use a door, whatever their job
Config.Unique = {
    location = { 147 },
}
