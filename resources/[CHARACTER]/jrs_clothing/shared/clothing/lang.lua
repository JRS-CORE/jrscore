ClothingLang = {}

ClothingLang.Prompt = {
    open = _UE("tailor_open"),
    title = _UE("tailor_title"),
    interact = _UE("tailor_interact"),
}

ClothingLang.Categories = {
    ["Remove_head"] = "Remove Head Items",
    ["Remove_neck"] = "Remove Neck Items",
    ["Remove_torso"] = "Remove Torso Items",
    ["Remove_shirts"] = "Remove Shirts",
    ["Remove_legs"] = "Remove Leg Items",
    ["Remove_feet"] = "Remove Feet Items",
    ["Remove_hands"] = "Remove Hand Items",
    ["Remove_weapons"] = "Remove Weapons",
    ["Remove_accessories"] = "Remove Accessories",
    
    -- Main Categories
    ["head"] = "Head",
    ["upper"] = "Upper Body",
    ["lower"] = "Lower Body",
    ["feets"] = "Footwear",
    ["accs"] = "Accessories",
    ["weapons"] = "Weapons",
    ["admin"] = "Admin",

    -- Head Subcategories
    ["heads"] = "Heads",
    ["hats"] = "Hats",
    ["masks"] = "Masks",
    ["eyewear"] = "Eyewear",
    ["headwear"] = "Headwear",
    ["face_props"] = "Face Props",
    ["hat_accessories"] = "Hat Accessories",
    ["hair"] = "Hair",
    ["teeth"] = "Teeth",
    ["eyes"] = "Eyes",
    ["beards_complete"] = "Full Beard",
    ["eyecaps"] = "Eyecaps",
    ["eyebrows"] = "Eyebrows",
    ["beards_mustache"] = "Mustache",
    ["eyelashes"] = "Eyelashes",
    ["beards_chops"] = "Sideburns",
    ["beards_chin"] = "Chin Hair",
    ["gore_head"] = "Gore Head",
    ["masks_large"] = "Large Masks",

    -- Upper Body Subcategories
    ["bodies_upper"] = "Upper Body",
    ["coats"] = "Coats",
    ["shirts_full"] = "Shirts",
    ["vests"] = "Vests",
    ["suspenders"] = "Suspenders",
    ["unionsuits_full"] = "Full Unionsuits",
    ["overalls_full"] = "Overalls (Full)",
    ["shirts_full_overpants"] = "Overshirts",
    ["cloaks"] = "Cloaks",
    ["overalls_modular_uppers"] = "Overalls (Upper)",
    ["coats_closed"] = "Closed Coats",
    ["outfits"] = "Full Outfits",
    ["coats_heavy"] = "Heavy Coats",
    ["ponchos"] = "Ponchos",
    ["shawls"] = "Shawls",
    ["corsets"] = "Corsets",
    ["chemises"] = "Chemises",
    ["capes"] = "Capes",

    -- Lower Body Subcategories
    ["bodies_lower"] = "Lower Body",
    ["pants"] = "Pants",
    ["spats"] = "Spats",
    ["overalls_modular_lowers"] = "Overalls (Lower)",
    ["dresses"] = "Dresses",
    ["skirts"] = "Skirts",
    ["unionsuit_legs"] = "Unionsuit Legs",
    ["knickers"] = "Knickers",

    -- Footwear Subcategories
    ["boots"] = "Boots",
    ["boot_accessories"] = "Boot Accessories",

    -- Accessories Subcategories
    ["neckerchiefs"] = "Neckerchiefs",
    ["neckties"] = "Neckties",
    ["gloves"] = "Gloves",
    ["belts"] = "Belts",
    ["accessories"] = "General Accessories",
    ["badges"] = "Badges",
    ["satchels"] = "Satchels",
    ["neckwear"] = "Neckwear",
    ["jewelry_necklaces"] = "Necklaces",
    ["jewelry_rings"] = "Rings",
    ["vest_accessories"] = "Vest Accessories",
    ["hair_accessories"] = "Hair Accessories",
    ["aprons"] = "Aprons",
    ["coat_accessories"] = "Coat Accessories",
    ["chaps"] = "Chaps",
    ["pants_accessories"] = "Pants Accessories",
    ["armor"] = "Armor",
    ["jewelry_bracelets"] = "Bracelets",
    ["wrist_bindings"] = "Wrist Bindings",
    ["gauntlets"] = "Gauntlets",
    ["ankle_bindings"] = "Ankle Bindings",
    ["belt_buckles"] = "Belt Buckles",
    ["jewelry_rings_right"] = "Rings (Right Hand)",
    ["jewelry_rings_left"] = "Rings (Left Hand)",
    ["satchel_straps"] = "Satchel Straps",
    ["jewelry_earrings"] = "Earrings",

    -- Weapons Subcategories
    ["gunbelts"] = "Gun Belts",
    ["holsters_right"] = "Holster (Right)",
    ["holsters_knife"] = "Knife Sheath",
    ["loadouts"] = "Loadouts",
    ["holsters_left"] = "Holster (Left)",
    ["holsters_crossdraw"] = "Holster (Crossdraw)",
    ["holsters_center"] = "Holster (Center)",
    ["gunbelt_accs"] = "Gun Belt Accessories",
    ["holsters_quivers"] = "Quivers",
    ["ammo_pistols"] = "Pistol Ammo",

    -- Admin Categories
    ["gjrbmoma_0xcb39a6f4"] = "Dress Accessories 1",
    ["pnyvpusa_0x44f4c713"] = "Dress Accessories 2",
    ["ogoolgaa_0xecd61654"] = "Dress Accessories 3",
    ["gnuusvra_0x7024af8b"] = "Dress Accessories 4",
    ["oacpqvda_0x41292b6f"] = "Dress Accessories 5",
    ["ywkywwvb_0xe93b9f1b"] = "Dress Accessories 6",
    ["mbbwboia_0x42e8f927"] = "Flowers",
    ["stockings"] = "Stockings",
    ["718708483"] = "Extra Accessory 1",
    ["1080070465"] = "Extra Accessory 2",
    ["tyyeqpea_0x5ad6c8a1"] = "Shirt Collar",
    ["lduvmjua_0x2b388a05"] = "Under Shirt",
    ["hynnzeba_0x534c424e"] = "Arrows",
    ["1572501618"] = "Extra Accessory 6",
    ["xvnliuia_0x625d7b14"] = "Injured Upper",
    ["-822935952"] = "Extra Accessory 8",
    ["idntoqja_0xe85a1a4d"] = "Hands",
    ["-1816970959"] = "Extra Accessory 10",
    ["1816970959"] = "Extra Accessory 10",
    ["rheovufa_0x4a8a0b53"] = "Under Shirt 2",
    ["lputhoya_0x7b78114c"] = "Other Beards",
    ["brhyqiua_0x1af71626"] = "Shirt Sleeve",
    ["sqwapmca_0x5b0f410e"] = "Suit Upper",
    ["jjpzgvmc_0x22d33ac2"] = "Under Shirt 3",
    ["ondqcrka_0xbc4255e3"] = "Aviator Glasses",
    ["arbhwiba_0x2f725b6c"] = "Right Arm",
    ["dlzdyqba_0xd82c8dd3"] = "Severed Head",
    ["jmwhzgaa_0x106fe11f"] = "Injured Left Foot",
    ["-801920077"] = "Extra Accessory 20",
    ["801920077"] = "Extra Accessory 20",
    ["-363708904"] = "Extra Accessory 21",
    ["363708904"] = "Extra Accessory 21",
    ["lvpmxtsa_0xb57244a4"] = "Right Shirt Sleeve",
    ["najrjqia_0x37b57629"] = "Extra Accessory 23",
    ["bctrhzba_0xcb350942"] = "Extra Accessory 24",
    ["-87047232"] = "Extra Accessory 25",
    ["87047232"] = "Extra Accessory 25",
    ["916904447"] = "Extra Accessory 26",
    ["kpmcfucb_0xeb4b82d1"] = "Upper Body Bandage",
    ["-1373389517"] = "Extra Accessory 28",
    ["1373389517"] = "Extra Accessory 28",
    ["nrpnskza_0x3cadebb7"] = "Extra Accessory 29",
    ["-705203924"] = "Extra Accessory 30",
    ["705203924"] = "Extra Accessory 30",
    ["cgvqvdaa_0xd4968e65"] = "Extra Accessory 31",
    ["wemtvpaa_0xa8fcd30e"] = "Extra Accessory 32",
    ["vfnqsfba_0x95ad5e2a"] = "Extra Accessory 33",
    ["464404356"] = "Extra Accessory 34",
    ["-1163401704"] = "Extra Accessory 35",
    ["1163401704"] = "Extra Accessory 35",
    ["2049190526"] = "Extra Accessory 36",
    ["118125201"] = "Extra Accessory 37",
    ["88372018"] = "Extra Accessory 38",
    ["upigupqa_0x5a536e23"] = "Extra Accessory 39",
    ["-1132439862"] = "Extra Accessory 40",
    ["1132439862"] = "Extra Accessory 40",
    ["609538240"] = "Extra Accessory 41",
    ["kqmlmpca_0x294e561e"] = "Extra Accessory 42",
    ["kkawrfba_0x202a8054"] = "Extra Accessory 43",
    ["777116858"] = "Extra Accessory 44",
    ["hyohcica_0xa1071d52"] = "Extra Accessory 45",
    ["ogdexlma_0xe8b5e43d"] = "Extra Accessory 46",
    ["-1783753551"] = "Extra Accessory 47",
    ["1783753551"] = "Extra Accessory 47",
    ["1022160959"] = "Extra Accessory 48",
    ["bloiioka_0x1e9e019b"] = "Extra Accessory 49",
    ["833267460"] = "Upper Body",
    ["-808505712"] = "Extra Accessory 51",
    ["808505712"] = "Extra Accessory 51",
    ["-234263672"] = "Extra Accessory 52",
    ["234263672"] = "Extra Accessory 52",
    ["885415775"] = "Extra Accessory 53",
    ["2101323755"] = "Extra Accessory 54",
    ["-818624178"] = "Extra Accessory 55",
    ["818624178"] = "Extra Accessory 55",
    ["-343684413"] = "Extra Accessory 56",
    ["343684413"] = "Extra Accessory 56",
    ["2099925833"] = "Extra Accessory 57",
    ["-272917581"] = "Extra Accessory 58",
    ["272917581"] = "Extra Accessory 58",
    ["-1434819954"] = "Extra Accessory 59",
    ["1434819954"] = "Extra Accessory 59",
    ["cnvfyaba_0xd7ae0d03"] = "Shoulder Dresses",
    ["-851097716"] = "Extra Accessory 61",
    ["851097716"] = "Extra Accessory 61",
    ["-419539457"] = "Extra Accessory 62",
    ["419539457"] = "Extra Accessory 62",
    ["-853084561"] = "Extra Accessory 63",
    ["853084561"] = "Extra Accessory 63",
    ["-328758153"] = "Extra Accessory 64",
    ["328758153"] = "Extra Accessory 64",
    ["nbtudvja_0x53b67599"] = "Sleeveless Shirt",
    ["1038525765"] = "Extra Accessory 66",
    ["758729615"] = "Extra Accessory 67",
    ["1314832239"] = "Extra Accessory 68",
    ["1557299516"] = "Extra Accessory 69",
    ["-94776482"] = "Extra Accessory 70",
    ["94776482"] = "Extra Accessory 70",
    ["-2050673586"] = "Extra Accessory 71",
    ["2050673586"] = "Extra Accessory 71",
    ["-1191653202"] = "Extra Accessory 72",
    ["1191653202"] = "Extra Accessory 72",
    ["-347650877"] = "Extra Accessory 73",
    ["347650877"] = "Extra Accessory 73",
    ["-1690877284"] = "Extra Accessory 74",
    ["1690877284"] = "Extra Accessory 74",
    ["-1018339117"] = "Extra Accessory 75",
    ["1018339117"] = "Extra Accessory 75",
    ["1356593691"] = "Extra Accessory 76",
    ["1382278837"] = "Extra Accessory 77",
    ["-1680267930"] = "Extra Accessory 78",
    ["1680267930"] = "Extra Accessory 78",
    ["-1362238266"] = "Extra Accessory 79",
    ["1362238266"] = "Extra Accessory 79",
    ["-1301348568"] = "Extra Accessory 80",
    ["1301348568"] = "Extra Accessory 80",
    ["913841068"] = "Extra Accessory 81",
    ["870137449"] = "Extra Accessory 82",
    ["358502875"] = "Extra Accessory 83",
    ["2044677326"] = "Extra Accessory 84"
}

-- Category names follow the reader's language at the moment a menu is built
-- (client _U resolves against the local player's current language). The table
-- above stays as the English source and the fallback for any id the locale
-- files do not carry; the admin extra accessory slots share one pattern key.
function ClothingLang.Label(cat)
    if not cat or cat == "" then return _U('clothing_cat_accessory') end
    local id = tostring(cat)
    local key = 'clothing_cat_' .. id
    local text = _U(key)
    if text ~= key and text ~= "" then return text end

    -- Signed / Unsigned 32-bit normalization for numeric IDs
    local num = tonumber(id)
    local english = ClothingLang.Categories[cat] or ClothingLang.Categories[id]
    if not english and num then
        local altNum = (num < 0) and (num + 4294967296) or (num - 4294967296)
        local altId = tostring(altNum)
        local altKey = 'clothing_cat_' .. altId
        local altText = _U(altKey)
        if altText ~= altKey and altText ~= "" then return altText end
        english = ClothingLang.Categories[altId] or ClothingLang.Categories[altNum]
    end

    local n = english and (english:match('^Extra Accessory (%d+)$') or english:match('^Unknown (%d+)$'))
    if n then
        return _U('clothing_cat_extra_accessory_n', tonumber(n))
    end

    if english then
        local engKey = 'clothing_cat_' .. english:lower():gsub('%s+', '_')
        local tr = _U(engKey)
        if tr ~= engKey and tr ~= "" then return tr end
        return english
    end

    -- If it's a numeric hash, never expose raw numbers to the player!
    if id:match('^%-?%d+$') then
        return _U('clothing_cat_accessory')
    end

    return id
end
