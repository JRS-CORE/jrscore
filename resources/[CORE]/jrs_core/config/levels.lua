-- ==========================================================================
--  JRS CORE  |  Levels and perks
--  jrs_core configuration
-- ==========================================================================
Config = Config or {}


-- --------------------------------------------------------------------------
--  Levels
-- --------------------------------------------------------------------------
do
-- JRS XP / Level configuration
-- Config.Levels[level] is the XP required to advance from that level
-- to the next one. Level 100 is the maximum level and therefore uses 0.

Config.XpTable = "jrs_characters_level" -- Database table used for character XP and calculated level.
Config.MaxLevel = 100

-- Per-script (per-job) levels. Every job/script keeps its OWN level 1..100 using
-- the SAME medium Config.Levels curve below (so all jobs are balanced against
-- each other and share one medium difficulty). On top of its own job level, each
-- award also feeds a balanced fixed share of the XP into the global core level,
-- so every script contributes to the core equally per XP earned.
Config.JobXP = {
    Enabled = true,
    Table = 'jrs_job_levels',       -- charidentifier + job + xp
    MaxLevel = 100,                 -- each job level runs 1..100 (uses Config.Levels)
    CoreShare = 0.25,               -- default: 25% of each job's XP also goes to the global core level
    -- Per-job overrides of CoreShare, keyed by normalized job name (lowercase, a-z0-9_).
    -- A job not listed here uses the default CoreShare above. Admins can also set/clear
    -- these live from jrs_admin (SERVER > LEVEL), which persists to `jrs_job_xp_shares`
    -- and takes priority over this static table.
    CoreShareByJob = {
        randomquests = 0.25,
    },
}

-- 1899 / Red Dead Online style economy. Money is meant to be hard to earn, so
-- gameplay money REWARDS are scaled down by RewardMultiplier. Only income routed
-- through getCoreApi().AddReward(...) is scaled - player transfers, refunds,
-- admin gives and banking are NOT affected. Lower RewardMultiplier = harder.
Config.Economy = {
    Enabled = true,
    RewardMultiplier = 0.35,  -- 1899 realism: everyday pay in small cents/dollars (hard to reach wealth, balanced necessities)
    GoldMultiplier = 0.5,     -- gold rewards scale separately (gold is rare and precious)
    MinReward = 0.05,         -- floor minimum for fractional earnings (5 cents)
}
Config.AllowClientXpCallbacks = false -- Keep false. XP should be awarded from server scripts only.
Config.LevelUpNotification = true -- Enable Red Dead Online Rank Up notifications
Config.XpGainNotification = true -- Send a "+XP" right-tip notification whenever XP is added by any script
Config.XpNotificationDuration = 4500

Config.Levels = {
    -- Official Red Dead Online XP progression curve (Ranks 1 - 100)
    -- Total XP required to reach Rank 100: 446,525 XP
    [1] = 200,
    [2] = 350,
    [3] = 500,
    [4] = 675,
    [5] = 850,
    [6] = 1050,
    [7] = 1250,
    [8] = 1450,
    [9] = 1650,
    [10] = 1875,
    [11] = 2100,
    [12] = 2325,
    [13] = 2575,
    [14] = 2825,
    [15] = 3050,
    [16] = 3300,
    [17] = 3575,
    [18] = 3825,
    [19] = 4100,
    [20] = 4125,
    [21] = 4150,
    [22] = 4175,
    [23] = 4200,
    [24] = 4225,
    [25] = 4250,
    [26] = 4275,
    [27] = 4300,
    [28] = 4325,
    [29] = 4350,
    [30] = 4375,
    [31] = 4400,
    [32] = 4425,
    [33] = 4450,
    [34] = 4475,
    [35] = 4500,
    [36] = 4525,
    [37] = 4550,
    [38] = 4575,
    [39] = 4600,
    [40] = 4625,
    [41] = 4650,
    [42] = 4675,
    [43] = 4700,
    [44] = 4725,
    [45] = 4750,
    [46] = 4775,
    [47] = 4800,
    [48] = 4825,
    [49] = 4850,
    [50] = 4875,
    [51] = 4900,
    [52] = 4925,
    [53] = 4950,
    [54] = 4975,
    [55] = 5000,
    [56] = 5025,
    [57] = 5050,
    [58] = 5075,
    [59] = 5100,
    [60] = 5125,
    [61] = 5150,
    [62] = 5175,
    [63] = 5200,
    [64] = 5225,
    [65] = 5250,
    [66] = 5275,
    [67] = 5300,
    [68] = 5325,
    [69] = 5350,
    [70] = 5375,
    [71] = 5400,
    [72] = 5425,
    [73] = 5450,
    [74] = 5475,
    [75] = 5500,
    [76] = 5525,
    [77] = 5550,
    [78] = 5575,
    [79] = 5600,
    [80] = 5625,
    [81] = 5650,
    [82] = 5675,
    [83] = 5700,
    [84] = 5725,
    [85] = 5750,
    [86] = 5775,
    [87] = 5800,
    [88] = 5825,
    [89] = 5850,
    [90] = 5875,
    [91] = 5900,
    [92] = 5925,
    [93] = 5950,
    [94] = 5975,
    [95] = 6000,
    [96] = 6025,
    [97] = 6050,
    [98] = 6075,
    [99] = 6100,
}

-- Official Red Dead Online Role XP progression (Bounty Hunter, Trader, Collector, Naturalist, Moonshiner)
-- 20 Ranks per role, 2,000 XP per rank, with 4 Title Tiers and Role Tokens.
Config.RoleMaxLevel = 20
Config.RoleRankXP = 2000
Config.RoleTiers = {
    { min = 1, max = 5, name = "Novice", tokens = 1 },
    { min = 6, max = 10, name = "Promising", tokens = 2 },
    { min = 11, max = 15, name = "Established", tokens = 2 },
    { min = 16, max = 20, name = "Distinguished", tokens = 3 },
}


-- RED DEAD ONLINE CHARACTER & ROLE PERK TREES

Config.CharacterPerks = {
    [1] = { title = "مبتدئ البرية (Frontier Rookie)", desc = "سعة حقيبة أولية 25 كغ واسترجاع طاقة أساسي", icon = "🎒" },
    [5] = { title = "عداء المسارات (Trail Runner)", desc = "تقليل استنزاف طاقة الركض السريع بنسبة 10%", icon = "🏃" },
    [10] = { title = "عين الصقر الحادة (Keen Sight)", desc = "زيادة مدى ومدة رؤية عين الصقر Eagle Eye بنسبة 15%", icon = "👁️" },
    [15] = { title = "حقيبة السفر المعززة (Reinforced Pack)", desc = "ترقية سعة حقيبة الظهر إلى 35 كغ", icon = "📦" },
    [20] = { title = "رابطة الخيل الأصيلة (Equine Bond)", desc = "تسريع كسب نقاط ترابط الحصان Bonding بنسبة 25%", icon = "🐎" },
    [25] = { title = "إعفاء ضريبي جزئي (Tax Exemption)", desc = "خصم 5% على رسوم المعاملات البنكية والضرائب العقارية", icon = "📜" },
    [30] = { title = "العزيمة الفولاذية (Iron Will)", desc = "تقليل استنزاف دوائر الصحة والطاقة في الطقس القاسي 15%", icon = "🛡️" },
    [35] = { title = "دبلوماسي المتاجر (Merchant Diplomat)", desc = "خصم تجاري دائم 5% في جميع المتاجر العامة", icon = "🏷️" },
    [40] = { title = "ناقل الحمولات الثقيلة (Heavy Cargo)", desc = "ترقية سعة حقيبة الظهر إلى 45 كغ", icon = "🎒" },
    [50] = { title = "محارب البرية المخضرم (Frontier Veteran)", desc = "+10% سعة إضافية لدوائر الصحة + إبزيم الحزام الذهبي المرموق", icon = "⭐" },
    [60] = { title = "إتقان الرماية وتلقيم السلاح (Deadeye Mastery)", desc = "تسريع سرعة تلقيم وإعادة حشو الأسلحة بنسبة 20%", icon = "🎯" },
    [75] = { title = "أسطورة الغرب الأمريكي (Legend of the West)", desc = "بونص إضافي 15% على مبيعات السلع والجلود والمحاصيل", icon = "👑" },
    [100] = { title = "خالد البرية (Frontier Immortal)", desc = "إتقان تام لكافة الإحصائيات، سعة 50 كغ كاملة، وسام الرتبة الذهبية 100", icon = "🏆" }
}

Config.RolePerks = {
    bountyhunter = {
        label = "صياد الجوائز (Bounty Hunter)",
        [5]  = { name = "تتبع الأثر الحاد (Focus Tracking)", desc = "إبراز مسار الهدف باللون الأحمر في عين الصقر حتى في المطر والضباب", tier = "Novice" },
        [10] = { name = "عقدة الوهق المقوى (Reinforced Knot)", desc = "زيادة وقت محاولة هروب الهدف المربوط بنسبة 40%", tier = "Promising" },
        [15] = { name = "المراوغة السريعة (Duck and Weave)", desc = "تقليل ضرر طلقات الأعداء 15% أثناء الركض في مهمة باونتي", tier = "Established" },
        [20] = { name = "محقق العدالة الأعظم (Master Inquisitor)", desc = "بونص 25% كاش و 0.08 ذهب عند تسليم المطلوبين أحياء للعدالة", tier = "Distinguished" },
    },
    delivery = {
        label = "التاجر وتوصيل البضائع (Trader & Delivery)",
        [5]  = { name = "نوابض العربة المقواة (Sturdy Suspension)", desc = "تقليل ضرر العربة من الطرق الوعرة والصخور بنسبة 30%", tier = "Novice" },
        [10] = { name = "سعة الشحن الموسعة (Bulk Hauler)", desc = "إضافة خانات تخزين إضافية بنسبة 20% لحمولة العربة التجارية", tier = "Promising" },
        [15] = { name = "مسارات القوافل السريعة (Efficiency Route)", desc = "تقليل استنزاف طاقة خيول العربة التجارية بنسبة 20%", tier = "Established" },
        [20] = { name = "احتكار التجارة الإقليمية (Monopoly Guild)", desc = "بونص 25% على عقود التوصيل الكبرى بعيدة المدى بين الأقاليم", tier = "Distinguished" },
    },
    collector = {
        label = "الجامع والمستكشف (Collector & Relics)",
        [5]  = { name = "حاسة الاستشعار (Divining Sense)", desc = "اهتزاز وتوهج شاشة خفيف عند الاقتراب من الكنوز والبطاقات المدفونة", tier = "Novice" },
        [10] = { name = "مجرفة الآثار المحسنة (Archaeologist Shovel)", desc = "تسريع أنيميشن استخراج وحفر الآثار والكنوز بنسبة 50%", tier = "Promising" },
        [15] = { name = "تقييم الخبير النادر (Antiquities Appraisal)", desc = "زيادة سعر بيع مجموعات البطاقات والتحف لمادام نزار بنسبة 20%", tier = "Established" },
        [20] = { name = "مكتشف الثروات الأسطورية (Fortune Seeker)", desc = "فرصة مضاعفة للعثور على شذرات الذهب والخواتم الثمينة بالصناديق", tier = "Distinguished" },
    },
    moonshine = {
        label = "المقطر والمهرب (Moonshiner)",
        [5]  = { name = "التخمير النقي المتسارع (Quality Fermentation)", desc = "تسريع دورة طبخ وتخمير المونشاين بنسبة 15%", tier = "Novice" },
        [10] = { name = "خلطات النكهات الحصرية (Flavored Recipes)", desc = "فتح وصفات تقطير نادرة 3 نجوم تطلبها حانات خاصة بأعلى سعر", tier = "Promising" },
        [15] = { name = "براميل امتصاص الصدمات (Shock Absorbing Casks)", desc = "حماية زجاج المونشاين في العربة من الكسر بنسبة 50% على المنعطفات", tier = "Established" },
        [20] = { name = "بارون الحانات الخاصة (Bar Baron)", desc = "زيادة أرباح وسمعة الحانة السرية بنسبة 30% من الزبائن المحليين", tier = "Distinguished" },
    },
    hunting = {
        label = "عالم الطبيعة والصياد (Naturalist & Hunter)",
        [5]  = { name = "المطارد الصامت (Silent Stalker)", desc = "تقليل حساسية الحيوانات للرائحة ووقع الخطوات بنسبة 25%", tier = "Novice" },
        [10] = { name = "الحفاظ على جلود 3 نجوم (Clean Pelts)", desc = "زيادة فرصة الحصول على جلد مثالي 3 نجوم بنسبة 35% عند القتل بالقوس", tier = "Promising" },
        [15] = { name = "طُعم الفرمونات النادرة (Pheromone Lure)", desc = "جذب الحيوانات النادرة والمفترسة إلى مناطق الصيد المعينة", tier = "Established" },
        [20] = { name = "خبير السلخ والتشريح (Master Skinner)", desc = "مضاعفة حصاد اللحوم والدهون وأنياب الحيوانات المفترسة عند السلخ", tier = "Distinguished" },
    },
    mining = {
        label = "عامل المناجم والتعدين (Mining)",
        [5]  = { name = "فأس التعدين المقسى (Tempered Pickaxe)", desc = "تقليل استهلاك ومتانة فأس التعدين بنسبة 30%", tier = "Novice" },
        [10] = { name = "كاشف العروق المعدنية (Vein Prospector)", desc = "زيادة كمية استخراج الفحم والحديد والفضة الخام بنسبة 20%", tier = "Promising" },
        [15] = { name = "صهر الخامات المتقدم (Forge Smelter)", desc = "تسريع وقت صهر المعادن وتجهيز السبائك في الفرن بنسبة 35%", tier = "Established" },
        [20] = { name = "الضربة الذهبية (Golden Strike)", desc = "فرصة استخراج شذرات ذهبية حقيقية Gold Nuggets من عروق الصخور العميقة", tier = "Distinguished" },
    },
    lumberjack = {
        label = "الحطاب وتقطيع الأخشاب (Lumberjack)",
        [5]  = { name = "خطوة الحطاب السريعة (Lumberjack Stride)", desc = "الحفاظ على سرعة المشي الطبيعية أثناء حمل الجذوع والألواح الثقيلة", tier = "Novice" },
        [10] = { name = "خبير منشار الجذوع (Crosscut Master)", desc = "تسريع لعبة شق وقص الأخشاب بنسبة 30%", tier = "Promising" },
        [15] = { name = "أخشاب الأرز الفاخرة (Cedar Selection)", desc = "استخراج ألواح خشب صلب معالج عالي القيمة للبناء والأثاث", tier = "Established" },
        [20] = { name = "كبير حطابي الغابات (Forester Guildmaster)", desc = "بونص 25% على شحنات الأخشاب التجارية المسلمة لمستودعات النجارة", tier = "Distinguished" },
    },
    farming = {
        label = "المزارع والفلاح (Farming)",
        [5]  = { name = "اليد الخضراء (Green Thumb)", desc = "زيادة فترة رطوبة التربة بعد الري بنسبة 50% قبل الجفاف", tier = "Novice" },
        [10] = { name = "المحصول الوفير (Bountiful Harvest)", desc = "زيادة إنتاجية المحاصيل المحصودة (قمح، ذرة، بطاطا، تبغ) بنسبة 25%", tier = "Promising" },
        [15] = { name = "مقاومة الآفات الزراعية (Pest Resistance)", desc = "حماية المحاصيل من الذبول والتعفن طوال دورة النمو", tier = "Established" },
        [20] = { name = "كبير المهندسين الزراعيين (Master Agronomist)", desc = "فتح بذور المحاصيل الهجينة الذهبية التي تباع بأعلى عائد للمطاحن", tier = "Distinguished" },
    },
    doctor = {
        label = "الطبيب والمسعف (Doctors & Medics)",
        [5]  = { name = "سرعة الاستجابة الطارئة (Triage Responder)", desc = "زيادة سرعة الركض بنسبة 15% عند الاستجابة لبلاغ مريض حرج", tier = "Novice" },
        [10] = { name = "تضميد معقم فوري (Sterile Bandages)", desc = "الضمادات تشفي 50% صحة إضافية وتوقف النزيف فوراً", tier = "Promising" },
        [15] = { name = "صيدلي الأعشاب الطبية (Apothecary Crafter)", desc = "تصنيع العلاجات واللقاحات باستهلاك أعشاب برية أقل بنسبة 30%", tier = "Established" },
        [20] = { name = "جراح الدولة العام (Surgeon General)", desc = "زيادة أجر الراتب الدوري 25% وضمان نجاح عمليات الإنعاش المعقدة", tier = "Distinguished" },
    },
    police = {
        label = "ضابط القانون والمارشال (Law & Sheriff)",
        [5]  = { name = "هيبة القانون السريعة (Authority Presence)", desc = "تسريع تقييد واعتقال المجرمين والأصفاد بنسبة 30%", tier = "Novice" },
        [10] = { name = "دورية الخيالة السريعة (Mounted Patrol)", desc = "استرجاع طاقة خيل الشرطة بنسبة 25% أسرع أثناء المطاردات", tier = "Promising" },
        [15] = { name = "خبير المقذوفات والدقة (Ballistics Expert)", desc = "ثبات السلاح وتقليل الارتداد بنسبة 15% أثناء أداء الواجب الرسمي", tier = "Established" },
        [20] = { name = "رئيس المارشالات الإقليمي (Chief Marshal)", desc = "فتح ترسانة أسلحة المارشال التكتيكية وصلاحيات القيادة الميدانية", tier = "Distinguished" },
    },
    blacksmith = {
        label = "الحداد وصانع الأسلحة (Weaponsmith)",
        [5]  = { name = "زيت صيانة الأسلحة الفاخر (Gunsmith Oil)", desc = "الأسلحة المنظفة تظل بحالة ممتازة لفترة أطول بنسبة 50%", tier = "Novice" },
        [10] = { name = "حفر وتوسيع السبطانة (Barrel Rifling)", desc = "توسيع سبطانة السلاح يزيد المدى الفعال ودقة الرصاص 15%", tier = "Promising" },
        [15] = { name = "نقوش المعادن الفضية (Metal Engraver)", desc = "خصم 30% على تكلفة النقوش الجمالية والطلاء المعدني للأسلحة", tier = "Established" },
        [20] = { name = "كبير صناع السلاح (Master Armorer)", desc = "الذخائر المصنوعة تزيد قوة الإصابة 10% والأسلحة لا تتعطل أبداً", tier = "Distinguished" },
    },
    fisherman = {
        label = "صياد الأسماك (Fisherman)",
        [5]  = { name = "قارئ التيارات النهرية (River Reader)", desc = "الأسماك تعض الطُعم أسرع بنسبة 30% في الأنهار والبحيرات", tier = "Novice" },
        [10] = { name = "خيط الصيد المضفر (Braided Line)", desc = "تقليل احتمالية انقطاع خيط الصنارة أمام الأسماك الضخمة بنسبة 50%", tier = "Promising" },
        [15] = { name = "طعوم الصيد الاحترافية (Special Lures)", desc = "فتح الطعوم الخاصة للبحيرات والمستنقعات لصيد أسماك السلمون والتروت", tier = "Established" },
        [20] = { name = "صياد الأسماك الأسطوري (Legendary Angler)", desc = "فرصة اصطياد أسماك عملاقة وأسطورية تباع بضعف السعر في المتاجر", tier = "Distinguished" },
    },
    train = {
        label = "سائق وقائد القطار (Train Conductor)",
        [5]  = { name = "توفير فحم الغلاية (Coal Efficiency)", desc = "تقليل استهلاك فحم القاطرة بنسبة 25% لكل كيلومتر", tier = "Novice" },
        [10] = { name = "فرامل البخار الدقيقة (Smooth Braking)", desc = "تقليل مسافة توقف القطار عند الأرصفة والمحطات بنسبة 35%", tier = "Promising" },
        [15] = { name = "الجدول السريع العابر (Express Schedule)", desc = "فتح سرعات تشغيل أعلى على المسارات الطويلة بين المحافظات", tier = "Established" },
        [20] = { name = "قطب السكك الحديدية (Iron Road Tycoon)", desc = "زيادة عوائد تذاكر الركاب وعقود شحن البضائع بالقطار بنسبة 30%", tier = "Distinguished" },
    },
    boats = {
        label = "قبطان المراكب والسفن (Boat Captain)",
        [5]  = { name = "دفة التوجيه الثابتة (Steady Rudder)", desc = "تحسين استجابة وانعطاف القوارب والمراكب في المياه بنسبة 25%", tier = "Novice" },
        [10] = { name = "ملاح الأنهار الضحلة (River Navigator)", desc = "هيكل القارب يتحمل صدمات الصخور والرمال الضحلة بنسبة 40% أفضل", tier = "Promising" },
        [15] = { name = "محرك البخار النفاث (Steam Boiler Tuning)", desc = "تسريع قوة دفع القارب البخاري بنسبة 20% ضد تيارات المياه القوية", tier = "Established" },
        [20] = { name = "عميد الموانئ المائية (Harbor Commodore)", desc = "بونص 25% على شحنات النقل والتجارة النهرية والبحرية", tier = "Distinguished" },
    },
    rancher = {
        label = "صاحب الرنش والخيول (Rancher & Stable)",
        [5]  = { name = "مروّض الماشية (Cattle Whisperer)", desc = "القطيع يتبع الخيل بسلاسة وتقل مسافة شرود الأبقار والأغنام", tier = "Novice" },
        [10] = { name = "الأعلاف المغذية المحسنة (Nutritious Feed)", desc = "نمو الماشية وإنتاجها للحليب والصوف والبيض أسرع بنسبة 25%", tier = "Promising" },
        [15] = { name = "سلالات الخيل الأصيلة (Equine Pedigree)", desc = "المهرات المولودة لديها فرصة 30% لوراثة سرعة وتحمل أعلى", tier = "Established" },
        [20] = { name = "بارون السهول الغربية (Baron of the Plains)", desc = "خصم 25% على ضرائب الرنش ومبيعات الجملة تدر 20% أرباحاً إضافية", tier = "Distinguished" },
    },
    crafting = {
        label = "الحِرفة والصناعة اليدوية (Artisan & Crafter)",
        [5]  = { name = "التجميع الاقتصادي (Efficient Assembly)", desc = "فرصة 15% لاسترجاع المواد الخام عند تصنيع الأدوات والمعدات", tier = "Novice" },
        [10] = { name = "النجارة المعمرة (Sturdy Joinery)", desc = "الأثاث والمعدات المصنوعة تمتلك متانة وقوة تحمل إضافية 40%", tier = "Promising" },
        [15] = { name = "وصفات الحرفي النادرة (Artisan Recipes)", desc = "فتح مخططات صناديق التخزين الموسعة وتجهيزات المخيم الفاخرة", tier = "Established" },
        [20] = { name = "المعلم الحرفي الكبير (Master Artisan)", desc = "تسريع وقت الصناعة 50% وزيادة القيمة السوقية لجميع المصنوعات 20%", tier = "Distinguished" },
    },
    fighter = {
        label = "الملاكم ومقاتل الحلبات (Brawler & Fighter)",
        [5]  = { name = "الفك الفولاذي (Iron Jaw)", desc = "تقليل ضرر اللكمات والضربات الجسدية المباشرة بنسبة 15%", tier = "Novice" },
        [10] = { name = "اللكمة القاضية (Haymaker)", desc = "اللكمات الثقيلة تسبب إرباكاً وخصماً أقوى لطاقة الخصم بنسبة 25%", tier = "Promising" },
        [15] = { name = "النَفَس الثاني (Second Wind)", desc = "استرجاع فوري لـ 40% من الطاقة عندما تنخفض الصحة إلى أقل من 30%", tier = "Established" },
        [20] = { name = "بطل الحلبات الذي لا يُقهر (Undefeated Champion)", desc = "زيادة جوائز المراهنات وبطولات الملاكمة في سانت دنيس بنسبة 30%", tier = "Distinguished" },
    },
    freelance = {
        label = "المهام الحرة والخدمات (Freelance & Services)",
        [5]  = { name = "خفة منظف المداخن (Chimney Sweep Agility)", desc = "تسريع تنظيف وكنس المداخن وسحب السخام بنسبة 25%", tier = "Novice" },
        [10] = { name = "رجل المهام المتعددة (Jack of All Trades)", desc = "فتح عقود صيانة وإصلاح منشآت ومرافق البلدة المحلية", tier = "Promising" },
        [15] = { name = "عامل المدينة المعتمد (Trusty Handyman)", desc = "إكراميات إضافية Tips من سكان المدن والزبائن بنسبة 30%", tier = "Established" },
        [20] = { name = "ركيزة المدينة (Town Pillar)", desc = "بونص 25% على كافة أجور الأعمال والخدمات الحرة بالمدينة", tier = "Distinguished" },
    },
}
end


-- --------------------------------------------------------------------------
--  Level perks
-- --------------------------------------------------------------------------
do
-- JRS level perks
-- ---------------------------------------------------------------------------
-- What the global core level (characters_level) unlocks for a character.
-- Loaded on BOTH client and server so the numbers can never disagree.
--
-- Server is the authority: server/level_perks.lua computes the perks from the
-- cached character level and publishes them on the replicated player state bag
-- `jrsPerks`. Other resources read that bag (or the exports) - they never
-- calculate perks themselves.
--
-- Consumers:
--   jrs_inventory : carry capacity (kg), weapon slots, weight -> run speed
--   jrs_stores    : shop discount (buy), sell bonus (sell)
--   jrs_banking   : bank fee reduction
--   jrs_core      : tax reduction (TaxEngine), job pay bonus (AddReward)
--
-- Milestone tables: { [level] = value } - the highest milestone at or below the
-- player's level wins. Values for discounts/bonuses are fractions (0.05 = 5%).
-- ---------------------------------------------------------------------------

Config = Config or {}

Config.LevelPerks = {
    Enabled = true,

    -- Backpack capacity grows linearly from MinKg at level 1 to MaxKg at
    -- MaxAtLevel, rounded down to RoundToKg so the number reads cleanly.
    Carry = {
        MinKg = 50,
        MaxKg = 300,
        MaxAtLevel = 100,
        RoundToKg = 5,
    },

    -- Weapon slots. Job overrides in jrs_inventory Config.WeaponLimitByJob
    -- (police/sheriff/admin) still apply when they are HIGHER than this.
    WeaponSlots = {
        [1]  = 4,
        [20] = 5,
        [45] = 6,
        [75] = 7,
    },

    -- Carried weight vs movement.
    -- Below FreeRunLevel the bag slows you down based on how FULL it is
    -- (percent of your own capacity, so a bigger bag is not a heavier penalty).
    -- Every level before FreeRunLevel softens the penalty a little
    -- (up to MaxRelief of the gap back to full speed at FreeRunLevel - 1).
    -- From FreeRunLevel on, the weight never slows you.
    -- speed = RedM max move blend ratio: 1.0 walk, 2.0 run, 3.0 sprint.
    Movement = {
        FreeRunLevel = 40,
        MaxRelief = 0.5,
        Tiers = {
            { percent = 60,  speed = 2.40 },  -- can't fully sprint
            { percent = 75,  speed = 2.10 },  -- run only
            { percent = 90,  speed = 1.85 },
            { percent = 100, speed = 1.60 },  -- full bag: slow jog
            { percent = 115, speed = 1.20 },  -- overloaded (old items above capacity)
        },
    },

    -- Discount on NPC store purchases (jrs_stores static/custom stores; player
    -- owned stores are NOT discounted so owners keep their revenue).
    ShopDiscount = {
        [10]  = 0.02,
        [25]  = 0.04,
        [50]  = 0.07,
        [75]  = 0.10,
        [100] = 0.15,
    },

    -- Extra payout when selling to NPC stores.
    SellBonus = {
        [15]  = 0.02,
        [35]  = 0.04,
        [60]  = 0.07,
        [100] = 0.10,
    },

    -- Fraction of every tax removed (jrs_core TaxEngine).
    TaxReduction = {
        [15] = 0.10,
        [30] = 0.20,
        [60] = 0.35,
        [90] = 0.50,
    },

    -- Fraction of bank fees removed (deposit/withdraw/transfer fees in jrs_banking).
    BankFeeReduction = {
        [20] = 0.10,
        [45] = 0.25,
        [80] = 0.50,
    },

    -- Extra job pay on gameplay rewards routed through getCoreApi().AddReward
    -- (money only, applied after the economy RewardMultiplier).
    RewardBonus = {
        [25]  = 0.03,
        [50]  = 0.06,
        [75]  = 0.10,
        [100] = 0.15,
    },

    -- Fraction of medical and doctor fees removed (treatment / revive bills).
    DoctorFeeReduction = {
        [20] = 0.15,
        [50] = 0.30,
        [85] = 0.50,
    },

    -- Fraction of stable care and stall fees removed.
    StableFeeReduction = {
        [25] = 0.10,
        [55] = 0.25,
        [85] = 0.40,
    },

    -- Discount on train tickets and fast travel carriage fares.
    TravelDiscount = {
        [15] = 0.15,
        [40] = 0.30,
        [75] = 0.50,
    },

    -- Sprint stamina drain reduction fraction (metabolism / endurance).
    StaminaDrainReduction = {
        [20] = 0.10,
        [45] = 0.20,
        [75] = 0.35,
        [95] = 0.50,
    },

    -- Notify the player which perks improved when they level up.
    NotifyOnLevelUp = true,
    -- Tell the player how much a perk saved them (store discount, sell bonus).
    NotifySavings = true,
    -- /perks prints the current perks and the next milestone.
    Command = 'perks',
}
end


-- --------------------------------------------------------------------------
--  Job perks
-- --------------------------------------------------------------------------
do
-- JRS Per-Job Perks Configuration
-- ---------------------------------------------------------------------------
-- Dedicated progression perks for all 21 tracked job scripts.
-- Levels run 1..100 using the unified Config.Levels curve.
-- Split into:
--   1) Business & Commercial Enterprises (شجرة الأعمال والتجارة)
--   2) Activities, Roles & Public Services (شجرة المهن والأنشطة العامة)
-- ---------------------------------------------------------------------------

Config = Config or {}

Config.JobPerks = {
    Enabled = true,

    Jobs = {
        -- ===================================================================
        -- BUSINESS & ENTERPRISE JOBS (شجرة الأعمال والاستثمار)
        -- ===================================================================

        business = {
            label = 'Business',
            label_ar = 'الأعمال والتجارة',
            perks = {
                {
                    key = 'order_revenue',
                    name = 'ORDER REVENUE',
                    name_ar = 'أرباح طلبيات البزنس',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [35] = 0.10, [65] = 0.18, [90] = 0.25 },
                },
                {
                    key = 'supply_discount',
                    name = 'SUPPLY DISCOUNT',
                    name_ar = 'خصم شراء المواد الخام',
                    kind = 'percent',
                    milestones = { [20] = 0.05, [50] = 0.12, [80] = 0.20 },
                },
                {
                    key = 'shipping_speed',
                    name = 'EXPRESS FULFILLMENT',
                    name_ar = 'سرعة وصول الشحنات',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.45 },
                },
                {
                    key = 'customer_retention',
                    name = 'WHOLESALE MARGIN',
                    name_ar = 'هوامش مبيعات الجملة',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [40] = 0.12, [70] = 0.20, [95] = 0.30 },
                },
            },
        },

        moonshiner = {
            label = 'Moonshiner',
            label_ar = 'صناعة المونشاين',
            perks = {
                {
                    key = 'batch_payout',
                    name = 'MOONSHINE BATCH PAYOUT',
                    name_ar = 'أرباح تسليم شحنات المونشاين',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'brew_speed',
                    name = 'DISTILLATION SPEED',
                    name_ar = 'سرعة التقطير والتخمير',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'mash_efficiency',
                    name = 'MASH INGREDIENT SAVING',
                    name_ar = 'توفير مكونات التخمير',
                    kind = 'percent',
                    milestones = { [15] = 0.08, [40] = 0.18, [70] = 0.28, [90] = 0.40 },
                },
                {
                    key = 'bottle_durability',
                    name = 'BOTTLE INTEGRITY',
                    name_ar = 'حماية الزجاجات من الكسر',
                    kind = 'percent',
                    milestones = { [10] = 0.15, [35] = 0.30, [65] = 0.50, [85] = 0.70 },
                },
            },
        },

        farming = {
            label = 'Farming',
            label_ar = 'الزراعة والحصاد',
            perks = {
                {
                    key = 'crop_yield',
                    name = 'CROP HARVEST YIELD',
                    name_ar = 'زيادة محصول الحصاد',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [75] = 0.35 },
                },
                {
                    key = 'water_efficiency',
                    name = 'SOIL WATER RETENTION',
                    name_ar = 'كفاءة ري التربة والماء',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.25, [80] = 0.40 },
                },
                {
                    key = 'fertilizer_boost',
                    name = 'FERTILIZER POTENCY',
                    name_ar = 'فعالية تسريع النمو',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.40 },
                },
                {
                    key = 'market_produce',
                    name = 'PRODUCE MARKET VALUE',
                    name_ar = 'قيمة بيع المحاصيل',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [35] = 0.10, [65] = 0.18, [90] = 0.25 },
                },
            },
        },

        stable = {
            label = 'Stable Hand',
            label_ar = 'مربي وخبير الخيول والمزارع',
            perks = {
                {
                    key = 'horse_bonding',
                    name = 'HORSE BONDING SPEED',
                    name_ar = 'سرعة ترويض وترابط الخيل',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [45] = 0.30, [80] = 0.50 },
                },
                {
                    key = 'horse_sale',
                    name = 'HORSE TRADE VALUE',
                    name_ar = 'قيمة بيع وتجارة الخيول',
                    kind = 'percent',
                    milestones = { [20] = 0.05, [50] = 0.12, [80] = 0.20 },
                },
                {
                    key = 'stable_maintenance',
                    name = 'GROOMING SUSTENANCE',
                    name_ar = 'تقليل تكاليف العناية بالخيل',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.45 },
                },
                {
                    key = 'stamina_coaching',
                    name = 'MOUNT STAMINA TRAINING',
                    name_ar = 'تدريب سرعة وتحمل الخيول',
                    kind = 'percent',
                    milestones = { [15] = 0.08, [45] = 0.18, [75] = 0.30 },
                },
            },
        },

        crafting = {
            label = 'Crafting',
            label_ar = 'الحِرفة والورش والتصنيع',
            perks = {
                {
                    key = 'mat_save',
                    name = 'MATERIAL SAVING',
                    name_ar = 'توفير المواد أثناء الصنع',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [40] = 0.10, [70] = 0.18, [95] = 0.25 },
                },
                {
                    key = 'craft_speed',
                    name = 'CRAFTING SPEED',
                    name_ar = 'سرعة التصنيع والتحضير',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'masterwork_chance',
                    name = 'MASTERWORK FINISH',
                    name_ar = 'جودة صنع متقنة',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [30] = 0.12, [60] = 0.20, [85] = 0.30 },
                },
                {
                    key = 'tool_durability',
                    name = 'ARTISAN PRESERVATION',
                    name_ar = 'صيانة أدوات الحرفة',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [45] = 0.25, [75] = 0.40 },
                },
            },
        },

        delivery = {
            label = 'Delivery Rider',
            label_ar = 'شحن وتوصيل البضائع',
            perks = {
                {
                    key = 'tip_bonus',
                    name = 'COURIER TIP BONUS',
                    name_ar = 'بونص إكراميات التوصيل',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [30] = 0.12, [60] = 0.20, [85] = 0.30 },
                },
                {
                    key = 'cargo_safety',
                    name = 'CARGO PROTECTION',
                    name_ar = 'حماية البضائع من التلف',
                    kind = 'percent',
                    milestones = { [20] = 0.15, [50] = 0.30, [80] = 0.50 },
                },
                {
                    key = 'wagon_wear',
                    name = 'CARRIAGE RESILIENCE',
                    name_ar = 'متانة عجلات وهيكل العربة',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [70] = 0.35, [90] = 0.50 },
                },
                {
                    key = 'express_rush',
                    name = 'EXPRESS DELIVERY PAY',
                    name_ar = 'بونص التوصيل السريع للمسافات',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [30] = 0.12, [60] = 0.20, [80] = 0.30 },
                },
            },
        },

        mining = {
            label = 'Mining',
            label_ar = 'التعدين والمناجم',
            perks = {
                {
                    key = 'ore_yield',
                    name = 'ORE VEIN YIELD',
                    name_ar = 'كمية استخراج المعادن',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [75] = 0.35 },
                },
                {
                    key = 'gem_chance',
                    name = 'GEMSTONE DISCOVERY',
                    name_ar = 'فرصة العثور على أحجار كريمة',
                    kind = 'percent',
                    milestones = { [20] = 0.05, [50] = 0.12, [80] = 0.25 },
                },
                {
                    key = 'pickaxe_longevity',
                    name = 'PICKAXE RESILIENCE',
                    name_ar = 'صلابة معول التعدين',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [45] = 0.30, [75] = 0.45 },
                },
                {
                    key = 'gold_nugget_payout',
                    name = 'PRECIOUS VEIN PURITY',
                    name_ar = 'نقاوة شذرات الذهب',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [30] = 0.12, [60] = 0.20, [85] = 0.30 },
                },
            },
        },

        lumberjack = {
            label = 'Lumberjack',
            label_ar = 'قطع وتجارة الأخشاب',
            perks = {
                {
                    key = 'wood_yield',
                    name = 'TIMBER YIELD',
                    name_ar = 'زيادة محصول قطع الخشب',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [75] = 0.35 },
                },
                {
                    key = 'sawmill_bonus',
                    name = 'SAWMILL CONTRACT BONUS',
                    name_ar = 'أجر عقود بيع الأخشاب',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'axe_durability',
                    name = 'AXE BLADE TEMPER',
                    name_ar = 'صلابة نصل الفأس',
                    kind = 'percent',
                    milestones = { [15] = 0.12, [40] = 0.25, [70] = 0.40, [90] = 0.55 },
                },
                {
                    key = 'hardwood_chance',
                    name = 'HARDWOOD EXTRACTION',
                    name_ar = 'استخراج أخشاب صلبة نادرة',
                    kind = 'percent',
                    milestones = { [10] = 0.08, [35] = 0.18, [65] = 0.28, [85] = 0.40 },
                },
            },
        },

        beekeeping = {
            label = 'Beekeeping',
            label_ar = 'تربية النحل وإنتاج العسل',
            perks = {
                {
                    key = 'honey_yield',
                    name = 'HONEY YIELD',
                    name_ar = 'إنتاج العسل والشمع',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'sting_resist',
                    name = 'STING RESISTANCE',
                    name_ar = 'مقاومة لدغات النحل',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [45] = 0.30, [75] = 0.50 },
                },
                {
                    key = 'queen_bee_chance',
                    name = 'QUEEN BEE BREEDING',
                    name_ar = 'استيلاد ملكات نادرة',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.12, [50] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'royal_jelly_payout',
                    name = 'ROYAL JELLY VALUE',
                    name_ar = 'قيمة الغذاء الملكي',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [35] = 0.10, [65] = 0.18, [85] = 0.25 },
                },
            },
        },

        organizations = {
            label = 'Organizations',
            label_ar = 'العصابات والمنظمات التجارية',
            perks = {
                {
                    key = 'turf_income',
                    name = 'TURF REVENUE BONUS',
                    name_ar = 'عائدات السيطرة على المناطق',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [35] = 0.10, [65] = 0.18, [90] = 0.25 },
                },
                {
                    key = 'syndicate_discount',
                    name = 'SYNDICATE SUPPLY DISCOUNT',
                    name_ar = 'خصم مشتريات عتاد المنظمة',
                    kind = 'percent',
                    milestones = { [20] = 0.05, [50] = 0.12, [80] = 0.20 },
                },
                {
                    key = 'influence_gain',
                    name = 'RESPECT ACCUMULATION',
                    name_ar = 'معدل كسب نفوذ العصابة',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.40 },
                },
                {
                    key = 'safehouse_cut',
                    name = 'SAFEHOUSE RETURN',
                    name_ar = 'عائدات غسيل الخزينة',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [40] = 0.12, [70] = 0.20, [95] = 0.30 },
                },
            },
        },

        -- ===================================================================
        -- ACTIVITIES, ROLES & PUBLIC SERVICES (شجرة المهن والأنشطة العامة)
        -- ===================================================================

        hunting = {
            label = 'Hunting',
            label_ar = 'الصيد والسلخ',
            perks = {
                {
                    key = 'pelt_quality',
                    name = 'PRISTINE PELT CHANCE',
                    name_ar = 'فرصة الحصول على جلود نقية',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [45] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'butcher_bonus',
                    name = 'BUTCHER SELL BONUS',
                    name_ar = 'بونص بيع الطرائد واللحوم',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'tracking_eagle_eye',
                    name = 'TRACKING EAGLE EYE',
                    name_ar = 'دقة التتبع وعين الصقر',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [70] = 0.35, [90] = 0.50 },
                },
                {
                    key = 'carcass_yield',
                    name = 'CARCASS MEAT HARVEST',
                    name_ar = 'محصول اللحوم والقرون',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.40 },
                },
            },
        },

        fishing = {
            label = 'Fishing',
            label_ar = 'صيد الأسماك',
            perks = {
                {
                    key = 'fish_sell',
                    name = 'FRESH FISH VALUE',
                    name_ar = 'قيمة بيع الأسماك الطازجة',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'rare_catch',
                    name = 'TROPHY CATCH CHANCE',
                    name_ar = 'فرصة صيد أسماك نادرة',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'line_strength',
                    name = 'LINE INTEGRITY',
                    name_ar = 'صلابة خيط السنارة',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [40] = 0.30, [70] = 0.45, [90] = 0.60 },
                },
                {
                    key = 'bait_efficiency',
                    name = 'SPECIAL BAIT LURE',
                    name_ar = 'كفاءة جذب الطعوم',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [55] = 0.30, [80] = 0.40 },
                },
            },
        },

        herbs = {
            label = 'Herbalism',
            label_ar = 'جمع الأعشاب والطبابة',
            perks = {
                {
                    key = 'herb_double',
                    name = 'DOUBLE FORAGE CHANCE',
                    name_ar = 'فرصة قطف أعشاب مضاعفة',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [45] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'apothecary_bonus',
                    name = 'HERBAL PAYOUT BONUS',
                    name_ar = 'قيمة بيع الأعشاب للطبابة',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [30] = 0.12, [60] = 0.20, [85] = 0.25 },
                },
                {
                    key = 'remedy_potency',
                    name = 'TINCTURE STRENGTH',
                    name_ar = 'فاعلية الترياقات المصنوعة',
                    kind = 'percent',
                    milestones = { [15] = 0.08, [40] = 0.16, [70] = 0.25, [90] = 0.35 },
                },
                {
                    key = 'rare_flora',
                    name = 'RARE FLORA DISCOVERY',
                    name_ar = 'اكتشاف الأعشاب النادرة',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.45 },
                },
            },
        },

        metal_detector = {
            label = 'Metal Detecting',
            label_ar = 'كاشف المعادن والآثار',
            perks = {
                {
                    key = 'artifact_value',
                    name = 'ARTIFACT SELL VALUE',
                    name_ar = 'قيمة بيع القطع الأثرية',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'detector_range',
                    name = 'DETECTOR SENSITIVITY',
                    name_ar = 'حساسية ومدى الكاشف',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'coin_discovery',
                    name = 'RARE COIN FIND',
                    name_ar = 'اكتشاف عملات نادرة',
                    kind = 'percent',
                    milestones = { [10] = 0.08, [30] = 0.16, [60] = 0.25, [85] = 0.35 },
                },
                {
                    key = 'shovel_speed',
                    name = 'EXCAVATION RAPIDITY',
                    name_ar = 'سرعة الحفر والاستخراج',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [45] = 0.25, [75] = 0.40 },
                },
            },
        },

        fight = {
            label = 'Fight Club',
            label_ar = 'نادي القتال',
            perks = {
                {
                    key = 'purse_bonus',
                    name = 'ARENA PRIZE PURSE',
                    name_ar = 'جائزة النزالات والمراهنات',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'brawl_defense',
                    name = 'BRAWL RESILIENCE',
                    name_ar = 'تحمل ضربات القتال اليدوي',
                    kind = 'percent',
                    milestones = { [20] = 0.05, [50] = 0.12, [80] = 0.20 },
                },
                {
                    key = 'heavy_hook',
                    name = 'MELEE IMPACT',
                    name_ar = 'قوة اللكمات والضربات',
                    kind = 'percent',
                    milestones = { [15] = 0.08, [40] = 0.15, [70] = 0.25, [90] = 0.35 },
                },
                {
                    key = 'adrenaline_recovery',
                    name = 'STAMINA RECOVERY',
                    name_ar = 'سرعة استعادة اللياقة',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [35] = 0.20, [65] = 0.35, [85] = 0.50 },
                },
            },
        },

        surfacecleaner = {
            label = 'Surface Cleaner',
            label_ar = 'تنظيف الأسطح والمداخن',
            perks = {
                {
                    key = 'sweep_pay',
                    name = 'SWEEP PAY BONUS',
                    name_ar = 'بونص أجر تنظيف الأسطح',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'soot_bonus',
                    name = 'TRINKET DISCOVERY',
                    name_ar = 'العثور على قطع ثمينة',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [40] = 0.12, [75] = 0.25 },
                },
                {
                    key = 'ladder_agility',
                    name = 'ROOF AGILITY',
                    name_ar = 'سرعة حركة الأسطح',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [35] = 0.20, [65] = 0.30, [85] = 0.40 },
                },
                {
                    key = 'chimney_hazard',
                    name = 'SOOT RESISTANCE',
                    name_ar = 'مقاومة غبار وأوساخ الأسطح',
                    kind = 'percent',
                    milestones = { [20] = 0.15, [50] = 0.30, [80] = 0.50 },
                },
            },
        },

        chimneysweep = {
            label = 'Chimney Sweep',
            label_ar = 'تنظيف الأسطح والمداخن',
            perks = {
                {
                    key = 'sweep_pay',
                    name = 'SWEEP PAY BONUS',
                    name_ar = 'بونص أجر تنظيف الأسطح والمداخن',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'soot_bonus',
                    name = 'TRINKET DISCOVERY',
                    name_ar = 'العثور على قطع ثمينة',
                    kind = 'percent',
                    milestones = { [15] = 0.05, [40] = 0.12, [75] = 0.25 },
                },
                {
                    key = 'ladder_agility',
                    name = 'ROOF AGILITY',
                    name_ar = 'سرعة حركة الأسطح',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [35] = 0.20, [65] = 0.30, [85] = 0.40 },
                },
                {
                    key = 'chimney_hazard',
                    name = 'SOOT RESISTANCE',
                    name_ar = 'مقاومة دخان المداخن',
                    kind = 'percent',
                    milestones = { [20] = 0.15, [50] = 0.30, [80] = 0.50 },
                },
            },
        },

        trash = {
            label = 'Trash Collector',
            label_ar = 'جامع النفايات والخردة',
            perks = {
                {
                    key = 'trash_pay',
                    name = 'COLLECTION PAY BONUS',
                    name_ar = 'بونص أجر جمع النفايات',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'scrap_find',
                    name = 'VALUABLE SCRAP CHANCE',
                    name_ar = 'فرصة العثور على خردوات ثمينة',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [45] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'salvage_efficiency',
                    name = 'RECYCLING RECOVERY',
                    name_ar = 'استرجاع مواد صالحة',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [70] = 0.35, [90] = 0.45 },
                },
                {
                    key = 'sanitation_hazard',
                    name = 'IMMUNITY RESISTANCE',
                    name_ar = 'مقاومة الأوبئة والروائح',
                    kind = 'percent',
                    milestones = { [10] = 0.15, [35] = 0.30, [65] = 0.50, [85] = 0.70 },
                },
            },
        },

        boats = {
            label = 'Boat Captain',
            label_ar = 'قبطان القوارب والملاحة',
            perks = {
                {
                    key = 'voyage_pay',
                    name = 'CHARTER PAYOUT',
                    name_ar = 'أجر رحلات النقل والملاحة',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'fuel_saving',
                    name = 'VESSEL EFFICIENCY',
                    name_ar = 'توفير صيانة القارب',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.20, [80] = 0.35 },
                },
                {
                    key = 'cargo_capacity',
                    name = 'CARGO DECK HOLD',
                    name_ar = 'حمولة بضائع إضافية',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [70] = 0.30, [90] = 0.40 },
                },
                {
                    key = 'storm_navigation',
                    name = 'STORM STABILITY',
                    name_ar = 'ثبات ملاحة العواصف',
                    kind = 'percent',
                    milestones = { [10] = 0.08, [30] = 0.15, [55] = 0.25, [80] = 0.35 },
                },
            },
        },

        train = {
            label = 'Train Conductor',
            label_ar = 'سائق وقائد القطار',
            perks = {
                {
                    key = 'rail_pay',
                    name = 'EXPRESS RUN REWARD',
                    name_ar = 'أجر رحلات السكة الحديدية',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'fuel_burn',
                    name = 'COAL BURN EFFICIENCY',
                    name_ar = 'كفاءة واقتصاد حرق الفحم',
                    kind = 'percent',
                    milestones = { [15] = 0.12, [40] = 0.25, [70] = 0.38, [90] = 0.50 },
                },
                {
                    key = 'freight_haul',
                    name = 'FREIGHT CAPACITY',
                    name_ar = 'سعة مقطورات الشحن التجاري',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.45 },
                },
                {
                    key = 'braking_control',
                    name = 'EMERGENCY BRAKING',
                    name_ar = 'كفاءة المكابح وسلامة القطار',
                    kind = 'percent',
                    milestones = { [20] = 0.15, [50] = 0.30, [80] = 0.50 },
                },
            },
        },

        bounty = {
            label = 'Bounty Hunter',
            label_ar = 'صياد الجوائز والمطلوبين',
            perks = {
                {
                    key = 'bounty_pay',
                    name = 'ALIVE BOUNTY REWARD',
                    name_ar = 'أجر تسليم المطلوبين أحياء',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.12, [50] = 0.20, [80] = 0.30 },
                },
                {
                    key = 'lasso_strength',
                    name = 'REINFORCED LASSO',
                    name_ar = 'عقدة الوهق ومقاومة الهروب',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [45] = 0.30, [75] = 0.50 },
                },
                {
                    key = 'eagle_eye_track',
                    name = 'EAGLE EYE TRACKING',
                    name_ar = 'تتبع أثر الهدف بعين الصقر',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.35, [85] = 0.50 },
                },
                {
                    key = 'body_armor_evasion',
                    name = 'DUCK AND WEAVE',
                    name_ar = 'المراوغة وتقليل ضرر الرصاص',
                    kind = 'percent',
                    milestones = { [20] = 0.05, [50] = 0.12, [80] = 0.25 },
                },
            },
        },

        police = {
            label = 'Lawman & Sheriff',
            label_ar = 'الشرطة والأمن وحفظ النظام',
            perks = {
                {
                    key = 'patrol_salary',
                    name = 'LAW SERVICE STIPEND',
                    name_ar = 'علاوة خدمة الأمن والدورية',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.10, [50] = 0.18, [80] = 0.25 },
                },
                {
                    key = 'cuff_speed',
                    name = 'TACTICAL APPREHENSION',
                    name_ar = 'سرعة السيطرة والتقييد',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [40] = 0.30, [70] = 0.45, [90] = 0.60 },
                },
                {
                    key = 'investigation_sense',
                    name = 'CLUE PERCEPTION',
                    name_ar = 'كشف مسرح الجريمة والأدلة',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.30, [85] = 0.45 },
                },
                {
                    key = 'suppression_fire',
                    name = 'TACTICAL RECOIL',
                    name_ar = 'ثبات السلاح أثناء إطلاق النار',
                    kind = 'percent',
                    milestones = { [20] = 0.08, [50] = 0.15, [80] = 0.25 },
                },
            },
        },

        doctor = {
            label = 'Doctor & Medic',
            label_ar = 'الطبيب والمسعف',
            perks = {
                {
                    key = 'healing_pay',
                    name = 'TREATMENT HONORARIUM',
                    name_ar = 'أجر علاج وإنعاش المصابين',
                    kind = 'percent',
                    milestones = { [10] = 0.05, [25] = 0.12, [50] = 0.20, [80] = 0.30 },
                },
                {
                    key = 'bandage_speed',
                    name = 'FIRST AID RAPIDITY',
                    name_ar = 'سرعة التضميد والإنعاش',
                    kind = 'percent',
                    milestones = { [15] = 0.15, [40] = 0.30, [70] = 0.45, [90] = 0.60 },
                },
                {
                    key = 'medicine_efficiency',
                    name = 'PHARMACY PRESERVATION',
                    name_ar = 'توفير استهلاك الأدوية',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [35] = 0.20, [65] = 0.35, [85] = 0.50 },
                },
                {
                    key = 'revive_health_boost',
                    name = 'RESUSCITATION SURGE',
                    name_ar = 'استعادة صحة المصاب بعد الإنعاش',
                    kind = 'percent',
                    milestones = { [20] = 0.10, [50] = 0.25, [80] = 0.40 },
                },
            },
        },

        hunting = {
            label = 'Hunter',
            label_ar = 'الصياد',
            perks = {
                {
                    key = 'butcher_bonus',
                    name = 'BUTCHER COMMERCE',
                    name_ar = 'أرباح بيع الجزار',
                    kind = 'percent',
                    milestones = { [5] = 0.05, [20] = 0.12, [50] = 0.22, [80] = 0.35 },
                },
                {
                    key = 'pelt_quality',
                    name = 'PRISTINE HARVEST',
                    name_ar = 'جودة وغنائم السلخ',
                    kind = 'percent',
                    milestones = { [10] = 0.08, [30] = 0.18, [60] = 0.30, [85] = 0.45 },
                },
                {
                    key = 'tracking_instinct',
                    name = 'HUNTER INSTINCT',
                    name_ar = 'غريزة التتبع والمسح',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [25] = 0.20, [55] = 0.35, [80] = 0.50 },
                },
                {
                    key = 'predator_defense',
                    name = 'WILD BEAST RESILIENCE',
                    name_ar = 'مقاومة هجمات المفترسات',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.20, [70] = 0.35, [90] = 0.50 },
                },
            },
        },

        randomquests = {
            label = 'Stranger Missions & Quests',
            label_ar = 'مهام الغرباء والمهام العشوائية',
            perks = {
                {
                    key = 'quest_payout',
                    name = 'QUEST PAYOUT BONUS',
                    name_ar = 'زيادة مكافآت المهام العشوائية',
                    kind = 'percent',
                    milestones = { [5] = 0.05, [20] = 0.12, [50] = 0.22, [80] = 0.35 },
                },
                {
                    key = 'gold_bonus',
                    name = 'GOLD EXPLORER',
                    name_ar = 'مكافآت سبائك الذهب الإضافية',
                    kind = 'percent',
                    milestones = { [10] = 0.10, [30] = 0.20, [60] = 0.35, [85] = 0.50 },
                },
                {
                    key = 'honor_surge',
                    name = 'FRONTIER REPUTATION',
                    name_ar = 'اكتساب السمعة والخبرة السريعة',
                    kind = 'percent',
                    milestones = { [15] = 0.10, [40] = 0.25, [70] = 0.40 },
                },
                {
                    key = 'escort_resilience',
                    name = 'ESCORT VANGUARD',
                    name_ar = 'حماية ومناعة مرافق المهام',
                    kind = 'percent',
                    milestones = { [10] = 0.15, [35] = 0.30, [65] = 0.50, [90] = 0.75 },
                },
            },
        },
    },
}
end
