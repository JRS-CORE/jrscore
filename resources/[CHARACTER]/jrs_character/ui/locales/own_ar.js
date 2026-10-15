// JRS Character Creator - Arabic translation
// Same shape as en.js. Anything missing here falls back to English through
// locale-helper.js, so a key added to en.js never shows as a raw path.
const Locale_ar = {
    // Language step (character screen)
    language: {
        title: "اختر لغتك",
        change: "اللغة",
        confirm: "متابعة",
    },

    // General UI
    ui: {
        cancel: "إلغاء",
        accept: "موافق",
        save: "حفظ",
        back: "رجوع",
        continue: "متابعة",
        delete: "حذف",
        create: "إنشاء",
        edit: "تعديل",
        close: "إغلاق",
        reset: "إعادة ضبط",
        confirm: "تأكيد",
        yes: "نعم",
        no: "لا",
        play: "لعب",
        spawn: "دخول",
        loading: "جارٍ التحميل...",
        style: "النمط",
        colour: "اللون",
        variation: "التنويع",
        advanced: "خيارات متقدمة",
    },

    // Character Selection
    charSelect: {
        title: "قائمة اختيار الشخصية",
        createNew: "إنشاء شخصية جديدة",
        selectCharacter: "اختيار الشخصية",
        deleteWarning: "تحذير!",
        deleteMessage: "هل أنت متأكد من حذف هذه الشخصية؟",
        cancelDeletion: "إلغاء",
        confirmDeletion: "حذف",
        characterInfo: "معلومات الشخصية",
        sexe: "الجنس",
        male: "ذكر",
        female: "أنثى",
        lore: "قصة الشخصية",
        birthday: "تاريخ الميلاد",
        day: "اليوم",
        month: "الشهر",
        year: "السنة",
        noLore: "لا توجد قصة",
    },

    // Flat character selection details & UI keys
    character_money: "نقود",
    character_gold: "ذهب",
    character_dirty_money: "أموال قذرة",
    character_characters: "الشخصيات",
    character_job: "الوظيفة",
    character_last_location: "آخر موقع",
    character_date_of_birth: "تاريخ الميلاد",
    character_age: "العمر",
    character_height: "الطول",
    character_unemployed: "عاطـل",
    character_unknown: "غير معروف",
    character_char_name: "اسم الشخصية",
    character_character: "الشخصية",
    character_edit_apparence: "تعديل المظهر",
    character_view_controls: "أزرار العرض",
    character_next: "التالي",
    character_back: "رجوع",

    // Character Creation
    charCreation: {
        title: "إنشاء شخصية",
        editTitle: "تعديل الشخصية",
        firstname: "الاسم الأول",
        lastname: "اسم العائلة",
        characterLore: "قصة الشخصية...",
        playAsAPed: "اللعب بشخصية جاهزة",
        selectPed: "اختيار الشخصية الجاهزة",
        cancelCreation: "إلغاء الإنشاء",
        cancelWarning: "ستفقد كل التغييرات، هل أنت متأكد؟",
        cancelStop: "إلغاء",
        confirmStop: "متابعة",
        birthDay: "اليوم...",
        birthMonth: "الشهر...",
        birthYear: "السنة...",
    },

    // Appearance Editor
    appearance: {
        title: "تعديل المظهر",
        globalSettings: "الإعدادات العامة",
        skinSettings: "إعدادات البشرة",
        eyeSettings: "إعدادات العينين",
        height: "الطول",
        headSize: "حجم الرأس",
        body: "الجسم",
        waist: "الخصر",
        legs: "الساقان",
        upperBody: "الجزء العلوي",
        lowerBody: "الجزء السفلي",
        teeth: "الأسنان",
        eyes: "العينان",
        skinColour: "لون البشرة",
        eyeColour: "لون العينين",
        cancel: "إلغاء",
        undress: "خلع الملابس",
        reset: "إعادة ضبط",
        resetWarning: "هل أنت متأكد من إعادة ضبط كل التغييرات؟",
        resetConfirm: "إعادة ضبط",
        resetCancel: "إلغاء",
    },

    // Outfit Menu
    outfit: {
        title: "الزي",
        myOutfit: "زيّي",
        createOutfit: "إنشاء زي جديد",
        mannequinOutfit: "إنشاء زي باستخدام المجسّم",
        clothes: "الملابس",
        skin: "البشرة",
        saveOutfit: "حفظ",
        backToList: "العودة للقائمة",
    },

    // Variation Menu
    variation: {
        title: "إعدادات التنويع",
        cameraTitle: "موضع الكاميرا",
        tintSettings: "إعدادات الصبغة/اللون",
        opacity: "الشفافية",
        palette: "لوحة الألوان",
    },

    // Spawn Menu
    spawn: {
        title: "اختر مكان الظهور",
        spawn: "دخول",
    },

    // Camera
    camera: {
        title: "موضع الكاميرا",
        zoom: "التقريب (Z)",
        rotation: "الدوران (R)",
    },

    // Body Parts and Facial Features
    bodyParts: {
        head: "الرأس",
        headShape: "شكل الرأس",
        headWidth: "عرض الرأس",
        faceWidth: "عرض الوجه",
        faceDepth: "عمق الوجه",
        foreheadSize: "حجم الجبهة",

        neck: "الرقبة",
        neckWidth: "عرض الرقبة",
        neckDepth: "عمق الرقبة",

        eyes: "العينان",
        eyesDepth: "عمق العينين",
        eyesAngle: "زاوية العينين",
        eyesDistance: "المسافة بين العينين",
        eyesHeight: "ارتفاع العينين",

        eyebrows: "الحاجبان",
        browsHeight: "ارتفاع الحاجبين",
        browsWidth: "عرض الحاجبين",
        browsDepth: "عمق الحاجبين",

        eyelid: "الجفن",
        eyelidHeight: "ارتفاع الجفن",
        eyelidWidth: "عرض الجفن",
        eyelidLeftOpen: "فتح/إغلاق الجفن الأيسر",
        eyelidRightOpen: "فتح/إغلاق الجفن الأيمن",

        ears: "الأذنان",
        earsWidth: "عرض الأذنين",
        earsAngle: "زاوية الأذنين",
        earsHeight: "ارتفاع الأذنين",
        earsDepth: "عمق الأذنين",

        cheekbone: "عظمة الخد",
        cheekboneHeight: "ارتفاع عظمة الخد",
        cheekboneWidth: "عرض عظمة الخد",
        cheekboneDepth: "عمق عظمة الخد",

        jaw: "الفك",
        jawHeight: "ارتفاع الفك",
        jawWidth: "عرض الفك",
        jawDepth: "عمق الفك",

        chin: "الذقن",
        chinHeight: "ارتفاع الذقن",
        chinWidth: "عرض الذقن",
        chinDepth: "عمق الذقن",

        nose: "الأنف",
        noseWidth: "عرض الأنف",
        noseSize: "حجم الأنف",
        noseHeight: "ارتفاع الأنف",
        noseAngle: "زاوية الأنف",
        noseCurvature: "انحناء الأنف",
        noseDistance: "بروز الأنف",

        mouth: "الفم",
        mouthWidth: "عرض الفم",
        mouthDepth: "عمق الفم",
        mouthX: "موضع الفم الأفقي",
        mouthY: "موضع الفم العمودي",

        lips: "الشفتان",
        lipUpperHeight: "ارتفاع الشفة العليا",
        lipUpperWidth: "عرض الشفة العليا",
        lipUpperDepth: "عمق الشفة العليا",
        lipLowerHeight: "ارتفاع الشفة السفلى",
        lipLowerWidth: "عرض الشفة السفلى",
        lipLowerDepth: "عمق الشفة السفلى",

        mouthCorner: "زوايا الفم",
        mouthCornerLeftWidth: "عرض الزاوية اليسرى",
        mouthCornerRightWidth: "عرض الزاوية اليمنى",
        mouthCornerLeftDepth: "عمق الزاوية اليسرى",
        mouthCornerRightDepth: "عمق الزاوية اليمنى",
        mouthCornerLeftHeight: "ارتفاع الزاوية اليسرى",
        mouthCornerRightHeight: "ارتفاع الزاوية اليمنى",

        shoulders: "الكتفان",
        shouldersSize: "حجم الكتفين",
        shouldersThickness: "سماكة الكتفين",
        backMuscles: "عضلات الظهر",

        arms: "الذراعان",
        armsSize: "حجم الذراعين",

        chest: "الصدر",
        chestSize: "حجم الصدر",

        waist: "الخصر",
        waistWidth: "عرض الخصر",

        hips: "الوركان",
        hipsSize: "حجم الوركين",

        legs: "الساقان",
        thightsSize: "حجم الفخذين",
        calvesSize: "حجم الساقين",
    },

    // Measurement Descriptors
    descriptors: {
        narrow: "ضيّق",
        wide: "واسع",
        large: "كبير",
        small: "صغير",
        high: "مرتفع",
        low: "منخفض",
        left: "يسار",
        right: "يمين",
        up: "أعلى",
        down: "أسفل",
        open: "مفتوح",
        close: "مغلق",
        far: "بعيد",
        near: "قريب",
        extruded: "بارز",
        retracted: "غائر",
        raised: "مرفوع",
        lowered: "منخفض",
        detached: "منفصل",
        stuck: "ملتصق",
    },

    // Categories (Barber and Makeup)
    categories: {
        hair: "الشعر",
        hairBonnet: "غطاء الشعر",
        beard: "اللحية",
        beardComplete: "لحية كاملة",
        beardMustache: "الشارب",
        beardChops: "السوالف",
        beardChin: "شعر الذقن",
        eyeliners: "كحل العينين",
        eyebrows: "الحاجبان",
        scars: "ندوب 1",
        scars2: "ندوب 2",
        scars3: "ندوب 3",
        lipsticks: "أحمر الشفاه",
        acne: "حبّ الشباب",
        shadows: "ظلال العيون",
        beardStabble: "لحية خفيفة",
        paintedMasks: "أقنعة مرسومة",
        ageing: "علامات التقدّم في السن",
        blush: "أحمر الخدود",
        blush2: "أحمر الخدود 2",
        complex: "لون البشرة",
        disc: "تصبّغات",
        foundation: "كريم الأساس",
        freckles: "النمش",
        grime: "الأوساخ",
        hairStabble: "شعر خفيف",
        moles: "الشامات",
        spots: "البقع",
    },

    // Notifications and Warnings
    notifications: {
        pedWarning: "أنت تستخدم شخصية جاهزة، وستحتاج إلى تخصيص تسريحة الشعر والملابس بشكل منفصل. لن تتوفر تفاصيل المكياج والبشرة.",
        characterCreated: "تم إنشاء الشخصية بنجاح!",
        characterUpdated: "تم تحديث الشخصية بنجاح!",
        characterDeleted: "تم حذف الشخصية بنجاح!",
        actionInProgress: "الإجراء قيد التنفيذ، يرجى الانتظار...",
        dataNotLoaded: "لم يتم تحميل البيانات بعد، جارٍ إعادة المحاولة...",
        errorOccurred: "حدث خطأ، يرجى المحاولة مرة أخرى.",
        selectionInProgress: "جارٍ اختيار الشخصية، يرجى الانتظار...",
    },

    // Ped Selection
    pedSelection: {
        title: "اختيار الشخصية الجاهزة",
        search: "بحث...",
        cancel: "إلغاء",
        select: "اختيار",
    },

    // Placeholders
    placeholders: {
        name: "الاسم...",
        surname: "اسم العائلة...",
        characterLore: "قصة الشخصية...",
        day: "اليوم...",
        month: "الشهر...",
        year: "السنة...",
        searchPed: "ابحث عن شخصية جاهزة...",
    },
};

// Export for global use
if (typeof window !== 'undefined') {
    window.LocaleTables = window.LocaleTables || {};
    window.LocaleTables.ar = Locale_ar;
}
