// ===================================================================
// JRS CORE | Loading Screen Content & Showcase
// Copyright (C) 2026 JRS TEAM | All Rights Reserved
// ===================================================================

const SERVER = {
    SIDE_FEEDS: {
        TEAM: {
            ENABLE: true,
            INTERVAL: 4200,
        },
        RULES: {
            ENABLE: true,
            INTERVAL: 5200,
        },
        NEWS: {
            ENABLE: true,
            INTERVAL: 5000,
        },
        HINTS: {
            ENABLE: true,
            INTERVAL: 4600,
        },
    },

    CARDS: [
        {
            NAME: "JRS CORE",
            NAME_AR: "JRS CORE",
            DESCRIPTION: "A complete roleplay framework built for the highest performance and stability on the frontier.",
            DESCRIPTION_AR: "فريمورك رول بلاي متكامل تم تطويره لتقديم أقصى درجات الاستقرار والأداء العالي.",
            IMAGE: "assets/images/image_1.jpg",
            ROLE: "FRAMEWORK",
            ROLE_AR: "الفريمورك",
        },
        {
            NAME: "ADMINISTRATION",
            NAME_AR: "الإدارة",
            DESCRIPTION: "Staff members are dedicated to supporting players and ensuring a fair environment.",
            DESCRIPTION_AR: "فريق الإدارة متواجد دائماً لمساعدة اللاعبين وضمان بيئة لعب عادلة.",
            IMAGE: "assets/images/image_2.jpg",
            ROLE: "STAFF",
            ROLE_AR: "طاقم الإدارة",
        },
        {
            NAME: "DEVELOPMENT",
            NAME_AR: "فريق التطوير",
            DESCRIPTION: "Continuous development, custom features, and framework updates powered by JRS.",
            DESCRIPTION_AR: "تطوير مستمر وميزات حصرية وتحديثات مستمرة بدعم من JRS.",
            IMAGE: "assets/images/image_3.jpg",
            ROLE: "JRS TEAM",
            ROLE_AR: "فريق JRS",
        },
    ],

    HINTS: [
        {
            NAME: "INVENTORY",
            NAME_AR: "الحقيبة",
            DESCRIPTION: "Press I to open your inventory. You can manage items and weapons, use the category filters, and search for specific items. Equip weapons from the inventory before using them.",
            DESCRIPTION_AR: "اضغط على زر (I) لفتح حقيبتك. يمكنك إدارة الأغراض والأسلحة، واستخدام فلاتر الفئات، والبحث عن غرض معيّن. جهّز أسلحتك من الحقيبة قبل استخدامها.",
            IMAGE: "assets/images/image_1.jpg",
        },
        {
            NAME: "HORSES",
            NAME_AR: "الخيول",
            DESCRIPTION: "Hold H to call your horse when it is available. Feed, brush, and care for your horse regularly to maintain a strong bond.",
            DESCRIPTION_AR: "اضغط مطوّلاً على زر (H) لاستدعاء حصانك عندما يكون متاحاً. احرص على إطعامه وتنظيفه والاعتناء به دائماً للحفاظ على رابط قوي معه.",
            IMAGE: "assets/images/image_2.jpg",
        },
        {
            NAME: "JOBS & ECONOMY",
            NAME_AR: "الوظائف والاقتصاد",
            DESCRIPTION: "Visit job locations around the map to earn money. Each profession offers different activities, progression, and opportunities.",
            DESCRIPTION_AR: "توجّه إلى مواقع الوظائف على الخريطة لكسب المال. كل مهنة تقدّم أنشطة وتطوّراً وفرصاً مختلفة.",
            IMAGE: "assets/images/image_3.jpg",
        },
        {
            NAME: "WEAPON WHEEL",
            NAME_AR: "عجلة الأسلحة",
            DESCRIPTION: "Hold TAB to open the weapon wheel. Make sure your weapons are equipped from your inventory first.",
            DESCRIPTION_AR: "اضغط مطوّلاً على زر (TAB) لفتح عجلة الأسلحة. تأكد أولاً من تجهيز أسلحتك من داخل الحقيبة.",
            IMAGE: "assets/images/image_4.jpg",
        },
        {
            NAME: "VOICE CHAT",
            NAME_AR: "المحادثة الصوتية",
            DESCRIPTION: "Use N for voice chat and the configured voice controls to change your speaking range. Be aware that nearby players may hear you through walls depending on distance.",
            DESCRIPTION_AR: "استخدم زر (N) للمحادثة الصوتية وأزرار الصوت المخصّصة لتغيير مدى صوتك. انتبه إلى أن اللاعبين القريبين قد يسمعونك عبر الجدران حسب المسافة.",
            IMAGE: "assets/images/image_5.jpg",
        },
    ],

    NEWS: [
        {
            TITLE: "GRAND OPENING",
            TITLE_AR: "الافتتاح الكبير",
            DESCRIPTION: "The frontier is officially open. Months of custom development are now live, welcome to the server.",
            DESCRIPTION_AR: "الحدود مفتوحة الآن رسمياً. أشهر من التطوير المخصص أصبحت متاحة أمامكم، أهلاً بكم في السيرفر.",
            IMAGE: "assets/images/image_1.jpg",
        },
        {
            TITLE: "CUSTOM JOBS & ECONOMY",
            TITLE_AR: "وظائف واقتصاد مخصّص",
            DESCRIPTION: "Mining, lumberjacking, farming, and more, a full custom economy built from the ground up for real roleplay.",
            DESCRIPTION_AR: "التعدين وقطع الأشجار والزراعة وغيرها، اقتصاد مخصّص بالكامل بُني من الصفر لخدمة تمثيل الأدوار الحقيقي.",
            IMAGE: "assets/images/image_2.jpg",
        },
        {
            TITLE: "HOUSING & STABLES",
            TITLE_AR: "المنازل والإسطبلات",
            DESCRIPTION: "Own your own home and raise your own horses. Furnish, decorate, and build the life your character deserves.",
            DESCRIPTION_AR: "امتلك منزلك الخاص واعتنِ بخيولك. أثّث وزيّن وابنِ الحياة التي تستحقها شخصيتك.",
            IMAGE: "assets/images/image_3.jpg",
        },
        {
            TITLE: "LAW, ORDER & HONOR",
            TITLE_AR: "القانون والنظام والشرف",
            DESCRIPTION: "Deep police and doctor roleplay systems paired with a living honor system that reacts to every choice you make.",
            DESCRIPTION_AR: "أنظمة متكاملة للشرطة والأطباء إلى جانب نظام شرف حي يتفاعل مع كل قرار تتخذه.",
            IMAGE: "assets/images/image_4.jpg",
        },
        {
            TITLE: "MORE TO COME",
            TITLE_AR: "المزيد في الطريق",
            DESCRIPTION: "This is only the beginning. New features, jobs, and frontier experiences are in active development, stay tuned.",
            DESCRIPTION_AR: "هذه مجرد البداية. ميزات ووظائف وتجارب جديدة قيد التطوير المستمر، ترقّبوا القادم.",
            IMAGE: "assets/images/image_5.jpg",
        },
    ],

    RULES: [
        {
            TITLE: "GENERAL RULES",
            TITLE_AR: "القوانين العامة",
            DESCRIPTION: "Random Deathmatch (RDM), Vehicle Deathmatch (VDM), metagaming, exploiting, and disruptive behavior are not allowed. Stay in character and respect other players.",
            DESCRIPTION_AR: "يمنع القتل العشوائي [RDM] والدهس العشوائي [VDM] والميتاجيمنغ واستغلال الثغرات والسلوك التخريبي. التزم بشخصيتك واحترم بقية اللاعبين دائماً.",
        },
        {
            TITLE: "ROLEPLAY RULES",
            TITLE_AR: "قوانين تمثيل الأدوار",
            DESCRIPTION: "Roleplay every situation and value your character's life. Go out of character only when staff specifically asks you to explain a situation. Do not quote server rules during active roleplay. Medical injuries should be roleplayed properly. Do not use AFK, logout, self-revive, or other methods to avoid consequences or escape an active scenario. Use common sense and avoid unrealistic power-gaming.",
            DESCRIPTION_AR: "مثّل كل موقف بواقعية وقدّر حياة شخصيتك. لا تخرج عن الشخصية إلا بطلب من الإدارة لتوضيح موقف. مثّل الإصابات الطبية بشكل صحيح وتجنّب استغلال الخروج من اللعبة أو التوقف للهروب من الموقف.",
        },
        {
            TITLE: "COMBAT RULES",
            TITLE_AR: "قوانين القتال",
            DESCRIPTION: "Do not attack or kill another player without a valid roleplay reason and prior interaction. RDM, VDM, and metagaming are prohibited. Any use of vehicles or weapons must make sense within the active roleplay scenario.",
            DESCRIPTION_AR: "يمنع مهاجمة أو قتل أي لاعب دون سبب تمثيلي مقنع وتفاعل مسبق. يجب أن يكون استخدام الأسلحة أو المركبات منطقياً ضمن سيناريو تمثيل الأدوار القائم.",
        },
        {
            TITLE: "ROBBERY RULES",
            TITLE_AR: "قوانين السرقة",
            DESCRIPTION: "Robberies must be driven by roleplay and character motivation. Do not rob players only for entertainment or without a reasonable in-character purpose.",
            DESCRIPTION_AR: "يجب أن تكون السرقات مدفوعة بالتمثيل وبدافع مقنع من الشخصية. يمنع سرقة اللاعبين لمجرد التسلية دون هدف منطقي للشخصية.",
        },
        {
            TITLE: "GANG RULES",
            TITLE_AR: "قوانين العصابات",
            DESCRIPTION: "Joining or creating a gang requires staff approval when required by server policy. Gang activity must be supported by roleplay and meaningful character motivation.",
            DESCRIPTION_AR: "الانضمام إلى عصابة أو إنشاؤها يتطلب موافقة الإدارة وفقاً لقوانين السيرفر. يجب أن يكون نشاط العصابة مدعوماً بالتمثيل ودوافع شخصية حقيقية.",
        },
    ],
};

export default SERVER;
