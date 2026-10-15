-- ==========================================================================
--  JRS CORE  |  jrs_inventory  |  config/weapons.lua
--  JRS Inventory unified resource: inventory + weapons + storage + ground + robbery + transactional trade
-- ==========================================================================


RECORDSW = {
    {
        item = "WEAPON_MELEE_KNIFE_TRADER",
        label = "Tradders Knife"
    },
    {
        item = "WEAPON_MELEE_KNIFE",
        label = "Knife"
    }, 
    {
        item = "WEAPON_MELEE_KNIFE_JAWBONE",
        label = "JawBone Knife"
    },
	    {
        item = "WEAPON_MELEE_MACHETE",
        label = "Machete"
    },
    {
        item = "WEAPON_MELEE_CLEAVER",
        label = "Melee cleaver"
    },
    {
        item = "WEAPON_MELEE_HATCHET_HUNTER",
        label = "Hatchet hunter"
    },
    {
        item = "WEAPON_MELEE_MACHETE_COLLECTOR",
        label = "Machete collector"
    },
    {
        item = "WEAPON_BOW_IMPROVED",
        label = "Bow improved"
    },
    {
        item = "WEAPON_BOW",
        label = "Bow"
    },
    {
        item = "WEAPON_KIT_METAL_DETECTOR",
        label = "Metal Detector"
    },
    {
        item = "WEAPON_RIFLE_ELEPHANT",
        label = "Rifle elephant"
    },
    {
        item = "WEAPON_RIFLE_VARMINT",
        label = "Rifle varmint"
    },
    {
        item = "WEAPON_SNIPERRIFLE_ROLLINGBLOCK",
        label = "Sniperrifle rollingblock"
    },
    {
        item = "WEAPON_SNIPERRIFLE_CARCANO",
        label = "Sniperrifle carcano"
    },
    {
        item = "WEAPON_RIFLE_SPRINGFIELD",
        label = "Rifle springfield"
    },
    {
        item = "WEAPON_RIFLE_BOLTACTION",
        label = "Rifle boltaction"
    },
    {
        item = "WEAPON_REPEATER_WINCHESTER",
        label = "Repeater winchester"
    },
    {
        item = "WEAPON_REPEATER_HENRY",
        label = "Repeater henry"
    },
    {
        item = "WEAPON_REPEATER_EVANS",
        label = "Repeater evans"
    },
    {
        item = "WEAPON_REPEATER_CARBINE",
        label = "Repeater carbine"
    },
    {
        item = "WEAPON_PISTOL_SEMIAUTO",
        label = "Pistol semiauto"
    },
    {
        item = "WEAPON_PISTOL_MAUSER",
        label = "Pistol mauser"
    },
    {
        item = "WEAPON_PISTOL_VOLCANIC",
        label = "Pistol volcanic"
    },
    {
        item = "WEAPON_PISTOL_M1899",
        label = "Pistol m1899"
    },
    {
        item = "WEAPON_REVOLVER_SCHOFIELD",
        label = "Revolver schofield"
    },
    {
        item = "WEAPON_REVOLVER_LEMAT",
        label = "Revolver lemat"
    },
    {
        item = "WEAPON_REVOLVER_DOUBLEACTION",
        label = "Revolver doubleaction"
    },
    {
        item = "WEAPON_REVOLVER_CATTLEMAN",
        label = "Revolver cattleman"
    },
    {
        item = "WEAPON_REVOLVER_NAVY",
        label = "Revolver navy"
    },
    {
        item = "WEAPON_THROWN_TOMAHAWK",
        label = "Thrown tomahawk"
    },
    {
        item = "WEAPON_THROWN_THROWING_KNIVES",
        label = "Throwing knives"
    },
    {
        item = "WEAPON_THROWN_POISONBOTTLE",
        label = "Thrown Poison bottle"
    },
    {
        item = "WEAPON_THROWN_BOLAS",
        label = "Thrown bolas"
    },
    {
        item = "WEAPON_THROWN_DYNAMITE",
        label = "Thrown dynamite"
    },
    {
        item = "WEAPON_THROWN_MOLOTOV",
        label = "Thrown molotov"
    },
    {
        item = "WEAPON_SHOTGUN_SEMIAUTO",
        label = "Shotgun semiauto"
    },
    {
        item = "WEAPON_SHOTGUN_SAWEDOFF",
        label = "Weapon Shotgun"
    },
    {
        item = "WEAPON_SHOTGUN_REPEATING",
        label = "Shotgun repeater"
    },
    {
        item = "WEAPON_SHOTGUN_PUMP",
        label = "Shotgun pump"
    },
    {
        item = "WEAPON_SHOTGUN_DOUBLEBARREL",
        label = "Shotgun doublebarrel"
    },
    {
        item = "WEAPON_LASSO",
        label = "Lasso"
    },
    {
        item = "WEAPON_LASSO_REINFORCED",
        label = "Lasso reinforced"
    },
    {
        item = "WEAPON_KIT_BINOCULARS_IMPROVED",
        label = "Improved binoculars"
    },
    {
        item = "WEAPON_KIT_BINOCULARS",
        label = "Binoculars"
    },
    {
        item = "WEAPON_FISHINGROD",
        label = "Fishing rod"
    },
    {
        item = "WEAPON_KIT_CAMERA",
        label = "Camera"
    },
    {
        item = "WEAPON_KIT_CAMERA_ADVANCED",
        label = "Camera advanced"
    },
    {
        item = "WEAPON_MELEE_LANTERN",
        label = "Melee lantern"
    },
    {
        item = "WEAPON_MELEE_DAVY_LANTERN",
        label = "Davy lantern"
    },
    {
        item = "WEAPON_MELEE_LANTERN_HALLOWEEN",
        label = "Lucerna Horor"
    },
    {
        item = "WEAPON_MELEE_MACHETE_HORROR",
        label = "Machette Horor"
    },
    {
        item = "WEAPON_MELEE_KNIFE_HORROR",
        label = "Scissors"
    },
    {
        item = "WEAPON_MELEE_HAMMER",
        label = "Hammer"
    },
    {
        item = "WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC",
        label = "Exotic Doublebarrel"
    },
    {
        item = "WEAPON_REVOLVER_CATTLEMAN_MEXICAN",
        label = "Mexican Cattleman"
    },
    {
        item = "WEAPON_REVOLVER_NAVY_CROSSOVER",
        label = "Navy Crossover"
    },

    -- 2026-09-15: the rest of the game's weapon list, so every weapon
    -- jrs_weapons sells can actually be created (createWeapon rejects any
    -- name missing from this table). WEAPON_MELEE_HATCHET was already on sale
    -- in the gunsmith catalogue but missing here.
    { item = "WEAPON_MELEE_HATCHET", label = "Hatchet" },
    { item = "WEAPON_MELEE_HATCHET_HUNTER_RUSTED", label = "Rusted Hunter Hatchet" },
    { item = "WEAPON_MELEE_HATCHET_DOUBLE_BIT", label = "Double Bit Hatchet" },
    { item = "WEAPON_MELEE_HATCHET_DOUBLE_BIT_RUSTED", label = "Rusted Double Bit Hatchet" },
    { item = "WEAPON_MELEE_HATCHET_HEWING", label = "Hewing Hatchet" },
    { item = "WEAPON_MELEE_HATCHET_VIKING", label = "Viking Hatchet" },
    { item = "WEAPON_MELEE_ANCIENT_HATCHET", label = "Ancient Hatchet" },
    { item = "WEAPON_MELEE_KNIFE_CIVIL_WAR", label = "Civil War Knife" },
    { item = "WEAPON_MELEE_KNIFE_MINER", label = "Miner Knife" },
    { item = "WEAPON_MELEE_KNIFE_VAMPIRE", label = "Vampire Knife" },
    { item = "WEAPON_MELEE_KNIFE_RUSTIC", label = "Rustic Knife" },
    { item = "WEAPON_MELEE_KNIFE_BEAR", label = "Bear Claw Knife" },
    { item = "WEAPON_MELEE_KNIFE_JOHN", label = "John's Knife" },
    { item = "WEAPON_MELEE_BROKEN_SWORD", label = "Broken Sword" },
    { item = "WEAPON_MELEE_TORCH", label = "Torch" },
    { item = "WEAPON_MELEE_LANTERN_ELECTRIC", label = "Electric Lantern" },
    { item = "WEAPON_REVOLVER_CATTLEMAN_JOHN", label = "John's Cattleman" },
    { item = "WEAPON_REVOLVER_CATTLEMAN_PIG", label = "Cattleman Pig" },
    { item = "WEAPON_REVOLVER_DOUBLEACTION_EXOTIC", label = "Exotic Double Action" },
    { item = "WEAPON_REVOLVER_DOUBLEACTION_GAMBLER", label = "Gambler Double Action" },
    { item = "WEAPON_REVOLVER_DOUBLEACTION_MICAH", label = "Micah's Double Action" },
    { item = "WEAPON_REVOLVER_SCHOFIELD_CALLOWAY", label = "Calloway's Schofield" },
    { item = "WEAPON_REVOLVER_SCHOFIELD_GOLDEN", label = "Golden Schofield" },
    { item = "WEAPON_PISTOL_MAUSER_DRUNK", label = "Drunk Mauser" },
    { item = "WEAPON_REPEATER_LANCASTER", label = "Lancaster Repeater" },
    { item = "WEAPON_SNIPERRIFLE_ROLLINGBLOCK_EXOTIC", label = "Exotic Rolling Block" },
    { item = "WEAPON_THROWN_TOMAHAWK_ANCIENT", label = "Ancient Tomahawk" },
    { item = "WEAPON_THROWN_BOLAS_HAWKMOTH", label = "Hawkmoth Bolas" },
    { item = "WEAPON_THROWN_BOLAS_INTERTWINED", label = "Intertwined Bolas" },
    { item = "WEAPON_THROWN_BOLAS_IRONSPIKED", label = "Ironspiked Bolas" },
    { item = "WEAPON_MOONSHINEJUG_MP", label = "Moonshine Jug" }
}

