-- If BarberLang variable is not defined, define it as an empty table
BarberLang = BarberLang or {}

-- Define categories for barber and makeup
BarberLang.Categories = {
    -- Barber
    ["hair"] = "الشعر",
    ["hair_bonnet"] = "غطاء الشعر",
    ["beard"] = "اللحية",
    ["beards_complete"] = "لحية كاملة",
    ["beards_mustache"] = "الشارب",
    ["beards_chops"] = "السوالف",
    ["beards_chin"] = "لحية الذقن",
    ["eyes"] = "لون العينين",

    -- Makeup
    ["eyeliners"] = "كحل العين",
    ["eyebrows"] = "الحواجب",
    ["scars"] = "الندوب 1",
    ["scars2"] = "الندوب 2",
    ["scars3"] = "الندوب 3",
    ["lipsticks"] = "أحمر الشفاه",
    ["acne"] = "حب الشباب",
    ["shadows"] = "ظلال العين",
    ["beardstabble"] = "شعر لحية خفيف",
    ["paintedmasks"] = "أقنعة مرسومة",
    ["ageing"] = "علامات التقدم في العمر",
    ["blush"] = "أحمر الخدود",
    ["blush2"] = "أحمر الخدود 2",
    ["complex"] = "البشرة",
    ["disc"] = "البقع",
    ["foundation"] = "كريم الأساس",
    ["freckles"] = "النمش",
    ["grime"] = "الأوساخ",
    ["hairstabble"] = "شعر رأس خفيف",
    ["moles"] = "الشامات",
    ["spots"] = "العيوب",
}

-- Category names follow the reader's language at the moment a menu is built
-- (client _U resolves against the local player's current language). The table
-- above stays as the English source and fallback.
function BarberLang.Label(cat)
    local id = tostring(cat)
    local key = 'barber_cat_' .. id
    local text = _U(key)
    if text ~= key then return text end
    return BarberLang.Categories[cat] or BarberLang.Categories[id] or id
end

-- Value label used by the eye-colour selector ("Colour 1", "Colour 2", ...).
BarberLang.EyeColourLabel = _U("barber_eye_colour")
