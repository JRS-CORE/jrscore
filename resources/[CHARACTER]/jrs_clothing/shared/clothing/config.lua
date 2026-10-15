-- ==========================================================================
--  JRS CORE  |  jrs_clothing  |  shared/clothing/config.lua
--  Free - clothing store (pieces + colours)
-- ==========================================================================

ClothingConfig = {}

ClothingConfig.framework = "jrs_core"

-- G at a tailor opens the store. Set to nil to disable the command.
ClothingConfig.MenuCommand = nil          -- e.g. "clothing"
ClothingConfig.LoadClothesCommand = "loadclothes"
ClothingConfig.NativePrompt = true

-- Law-enforcement clothing (sheriff/marshal/army/badges).
-- false = hidden from the store.
ClothingConfig.LawClothing = {
    Enabled = false,
    BlockedCategories = { "badges" },
    PedKeywords = {
        "police", "sheriff", "sherriff", "deput", "marshal", "marshall", "ambientlaw", "dispatchlaw",
        "lawman", "lawtarget", "lawcamp_", "_law_", "pinlaw", "leadofficer", "revenueagent", "pinkerton",
        "edgarross", "miltonandrews", "archerfordham", "agent_hixon", "captainmonroe", "exconfed",
        "army", "soldier", "military", "cavalry",
    },
    PedExceptions = { "prisoner" },
    HashNameKeywords = {
        "STDPOLICE", "_BADGE_", "SHERIFF", "DEPUTY", "MARSHAL", "MARSHALL", "ARMY", "SOLDIER",
        "MILITARY", "CAVALRY", "KEPI",
    },
}

ClothingConfig.Shops = {
    ["Saint Denis Tailor"] = { shopCoords = vector3(2554.636, -1170.411, 53.68349) },
    ["Blackwater Tailor"]  = { shopCoords = vector3(-761.98, -1292.61, 43.885) },
    ["Tumbleweed Tailor"]  = { shopCoords = vector3(-5514.65, -2965.27, -0.61) },
    ["Rhodes Tailor"]      = { shopCoords = vector3(1322.520, -1291.683, 77.024) },
    ["Valentine Tailor"]   = { shopCoords = vector3(-328.16, 774.82, 117.64) },
    ["Strawberry Tailor"]  = { shopCoords = vector3(-1791.30, -390.90, 160.33) },
    ["Annesburg Tailor"]   = { shopCoords = vector3(2944.82, 1329.72, 44.25) },
    ["Armadillo Tailor"]   = { shopCoords = vector3(-3658.21, -2625.20, -13.55) },
}

-- Price per piece (a new piece or a new colour of a piece).
ClothingConfig.Price = {
    hats = 1.25, masks = 2.50, eyewear = 0.75, headwear = 1.00, face_props = 0.50, hat_accessories = 0.35,
    masks_large = 3.00,
    coats = 3.50, shirts_full = 1.20, lduvmjua_0x2b388a05 = 1.20, vests = 1.00, suspenders = 0.40,
    unionsuits_full = 1.10, overalls_full = 1.50, shirts_full_overpants = 1.30, cloaks = 2.50,
    overalls_modular_uppers = 1.30, coats_closed = 3.50, outfits = 4.50, coats_heavy = 4.50, ponchos = 2.00,
    pants = 1.50, overalls_modular_lowers = 1.20, dresses = 2.50, skirts = 1.80, unionsuit_legs = 1.10,
    boots = 2.25, boot_accessories = 0.50, spats = 0.75,
    neckerchiefs = 0.40, neckties = 0.50, gloves = 0.75, belts = 1.20, accessories = 0.60, badges = 0.50,
    satchels = 2.00, neckwear = 0.50, jewelry_necklaces = 3.50, jewelry_rings = 2.50, vest_accessories = 0.50,
    hair_accessories = 0.40, aprons = 0.75, coat_accessories = 0.50, chaps = 1.75, pants_accessories = 0.50,
    armor = 5.00, jewelry_bracelets = 2.00, wrist_bindings = 0.50, gauntlets = 1.25, ankle_bindings = 0.50,
    belt_buckles = 0.85, jewelry_rings_right = 2.50, jewelry_rings_left = 2.50, satchel_straps = 0.75,
    jewelry_earrings = 1.80,
    gunbelts = 2.75, holsters_right = 1.50, holsters_knife = 1.00, loadouts = 4.00, holsters_left = 1.50,
    holsters_crossdraw = 1.50, holsters_center = 1.50, gunbelt_accs = 0.75, holsters_quivers = 1.75,
    ammo_pistols = 1.25,
    capes = 2.50, shawls = 1.20, corsets = 1.80, chemises = 1.10, knickers = 0.65, stockings = 0.40,
    nbtudvja_0x53b67599 = 1.20, cnvfyaba_0xd7ae0d03 = 1.50, gjrbmoma_0xcb39a6f4 = 1.50,
    pnyvpusa_0x44f4c713 = 1.50, ogoolgaa_0xecd61654 = 1.50, gnuusvra_0x7024af8b = 1.50,
    oacpqvda_0x41292b6f = 1.50, ywkywwvb_0xe93b9f1b = 1.50, mbbwboia_0x42e8f927 = 0.65,
}

--- !!!! Do not change: categories that are never removed when clothes change !!!! ---
ClothingConfig.EssentialsCategories = {
    "bodies_upper", "bodies_lower", "heads", "hair", "hair_bonnet", "beard", "teeth", "eyes",
    "beards_chin", "beards_chops", "beards_mustache", "beards_complete",
}
