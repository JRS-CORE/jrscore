-- ==========================================================================
--  JRS CORE  |  jrs_crafting  |  config.lua
--  crafting stations, campfires and recipe categories (recipes: config/recipes.lua)
-- ==========================================================================

Config = {}

Config.defaultlang = "en_lang"   -- "en_lang" or "ar_lang"
Config.DevMode     = false

-- ─── Crafting ──────────────────────────────────────────────────────────────
Config.CraftTime         = 15000   -- progress bar length (ms)
Config.MaxCraftAmount    = 30      -- highest amount crafted in one go
Config.KneelingAnimation = false   -- kneel while the crafting menu is open

-- ─── Controls / distances ──────────────────────────────────────────────────
Config.Keys      = { G = 0x760A9C6F }
Config.Distances = { campfire = 1.5, locations = 2.5 }

-- ─── Campfire item ─────────────────────────────────────────────────────────
Config.CampFireItem      = "campfire"
Config.PlaceableCampfire = "p_campfire05x"
Config.CampfireJobLock   = 0        -- 0 = everyone, or { "job" }

-- /campfire places a fire without the item (keep false: use the "campfire" item)
Config.Commands = { campfire = false, extinguish = true }

-- ─── Station types: which categories a station can craft ───────────────────
Config.StationTypes = {
    cooking    = { "food", "provisions" },
    survival   = { "field_kit", "beekeeping" },
    jewelry    = { "jewelry" },
    forge      = { "meleeweapons", "armor", "weapon_parts", "prospecting" },
    workshop   = { "firearms", "weapons", "weapon_parts" },
    ammo       = { "ammo" },
    explosives = { "explosives" },
}

-- ─── Stations (a prop is placed at each one) ───────────────────────────────
-- name is also the prompt title and blip label (the game font has no Arabic)
Config.Locations = {
    { name = 'Valentine Camp Kitchen',      id = 'valentine',  StationType = 'cooking',  Job = 0,
      x = -195.80,  y = 502.40,   z = 105.00, prop = { model = 'p_campfire05x',  heading = 0.0 },
      Blip = { enable = true, Hash = 'blip_campfire',          Color = 'BLIP_MODIFIER_MP_COLOR_8' } },

    { name = 'Strawberry Apothecary Bench', id = 'strawberry', StationType = 'survival', Job = 0,
      x = -1991.50, y = -415.90,  z = 168.87, prop = { model = 'p_tablework02x', heading = 110.0 },
      Blip = { enable = true, Hash = 'blip_ambient_herbalist', Color = 'BLIP_MODIFIER_MP_COLOR_21' } },

    { name = 'Saint Denis Jeweler Bench',   id = 'saintdenis', StationType = 'jewelry',  Job = 0,
      x = 2269.70,  y = -723.80,  z = 43.03,  prop = { model = 'p_tablework02x', heading = 90.0 },
      Blip = { enable = true, Hash = 'blip_shop_fence',        Color = 'BLIP_MODIFIER_MP_COLOR_32' } },

    { name = 'Blackwater Blacksmith Forge', id = 'blackwater', StationType = 'forge',    Job = 0,
      x = -1042.90, y = -1122.10, z = 62.01,  prop = { model = 'p_anvil01x',     heading = 270.0 },
      Blip = { enable = true, Hash = 'blip_shop_blacksmith',   Color = 'BLIP_MODIFIER_MP_COLOR_4' } },

    { name = 'Rhodes Weaponsmith Bench',    id = 'rhodes',     StationType = 'workshop', Job = 0,
      x = 1462.30,  y = -1148.00, z = 69.70,  prop = { model = 'p_workbench02x', heading = 180.0 },
      Blip = { enable = true, Hash = 'blip_shop_gunsmith',     Color = 'BLIP_MODIFIER_MP_COLOR_10' } },

    { name = 'Armadillo Ammunition Table',  id = 'armadillo',  StationType = 'ammo',     Job = 0,
      x = -3747.80, y = -2802.00, z = -13.87, prop = { model = 'p_tablework02x', heading = 90.0 },
      Blip = { enable = true, Hash = 'blip_supplies_ammo',     Color = 'BLIP_MODIFIER_MP_COLOR_5' } },
}

-- ─── World props you can cook / craft at (scanned near the player) ─────────
Config.CraftingPropsEnabled = true
Config.CraftingProps = {
    { title = "Campfire Cooking", StationType = "cooking", prop = { "p_campfire01x", "p_campfire05x" } },
    { title = "Cooking Oven",     StationType = "cooking", prop = "p_furnace01x" },
}

-- ─── Categories (ident = recipe Category) ──────────────────────────────────
Config.Categories = {
    { ident = 'food',         text = 'Food & Drinks',          text_ar = 'أطعمة ومشروبات',        Location = 0, Job = 0 },
    { ident = 'provisions',   text = 'Provisions & Cooking',   text_ar = 'المؤن والطبخ',          Location = 0, Job = 0 },
    { ident = 'field_kit',    text = 'Field Kit',              text_ar = 'عدة النجاة',            Location = 0, Job = 0 },
    { ident = 'beekeeping',   text = 'Bee Products',           text_ar = 'منتجات النحل',          Location = 0, Job = 0 },
    { ident = 'firearms',     text = 'Firearms',               text_ar = 'الأسلحة النارية',       Location = 0, Job = 0 },
    { ident = 'weapons',      text = 'Survival Weapons',       text_ar = 'أسلحة النجاة',          Location = 0, Job = 0 },
    { ident = 'meleeweapons', text = 'Melee Weapons',          text_ar = 'الأسلحة اليدوية',       Location = 0, Job = 0 },
    { ident = 'ammo',         text = 'Ammunition',             text_ar = 'الذخائر',               Location = 0, Job = 0 },
    { ident = 'weapon_parts', text = 'Weapon Parts',           text_ar = 'قطع الأسلحة',           Location = 0, Job = 0 },
    { ident = 'armor',        text = 'Armor',                  text_ar = 'الدروع',                Location = 0, Job = 0 },
    { ident = 'explosives',   text = 'Explosives',             text_ar = 'المتفجرات',             Location = 0, Job = { 'explosives_expert' } },
    { ident = 'jewelry',      text = 'Goldsmith & Jewelry',    text_ar = 'صياغة الذهب والمجوهرات', Location = 0, Job = 0 },
    { ident = 'prospecting',  text = 'Prospecting & Mining',   text_ar = 'معدات التنقيب والمناجم', Location = 0, Job = 0 },
}
