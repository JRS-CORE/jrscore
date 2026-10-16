-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_stables  |  config/wagons.lua
--  Wagon catalogue. Add a wagon by adding one line to a category below.
--  Written by the JRS TEAM.
-- ==========================================================================

-- Settings every wagon starts with. A single wagon line can override any of these keys
-- (cash, gold, cargo, job, distance, repair, wear, wearEvery).
local Base = {
    distance  = 5,      -- metres from the wagon to show prompts and open the menu
    cargo     = 100,    -- cargo slots
    weapons   = true,   -- weapons may be stored in the cargo
    shared    = true,   -- anyone nearby may use the cargo (false = owner only)
    repair    = 25,     -- condition restored by one repair hammer
    wear      = 1,      -- condition lost every `wearEvery` seconds
    wearEvery = 60,
    maxHealth = 100,    -- full condition
    job       = {},     -- e.g. { 'wainwright' } = only these jobs can buy it
}

-- Category list. Each entry: { model, label, cash, gold [, overrides] }
local Catalogue = {
    { name = 'Buggies', cargo = 40, wagons = {
        { 'buggy01', 'Buggy 1', 140, 7 },
        { 'buggy02', 'Buggy 2', 190, 9 },
        { 'buggy03', 'Buggy 3', 240, 12 },
    } },
    { name = 'Coaches', cargo = 60, wagons = {
        { 'coach4', 'Coach 4', 310, 16 },
        { 'coach5', 'Coach 5', 360, 18 },
        { 'coach3', 'Coach 3', 420, 21 },
        { 'coach6', 'Coach 6', 480, 24 },
    } },
    { name = 'Carts', cargo = 120, wagons = {
        { 'cart01', 'Cart 1', 90, 5 },
        { 'cart02', 'Cart 2', 110, 6 },
        { 'cart03', 'Cart 3', 130, 7 },
        { 'cart04', 'Cart 4', 150, 8 },
        { 'cart06', 'Cart 6', 170, 9 },
        { 'cart07', 'Cart 7', 190, 10 },
        { 'cart08', 'Cart 8', 210, 11 },
        { 'huntercart01', 'Hunter Cart', 260, 13 },
    } },
    { name = 'Wagons', cargo = 260, wagons = {
        { 'supplywagon', 'Supply Wagon', 380, 19 },
        { 'wagontraveller01x', 'Travel Wagon', 450, 23 },
        { 'wagon02x', 'Wagon 2', 520, 26 },
        { 'wagon03x', 'Wagon 3', 560, 28 },
        { 'wagon04x', 'Wagon 4', 600, 30 },
        { 'wagon05x', 'Wagon 5', 640, 32 },
        { 'wagon06x', 'Wagon 6', 700, 35 },
        { 'chuckwagon000x', 'Chuck Wagon 1', 760, 38 },
        { 'chuckwagon002x', 'Chuck Wagon 2', 820, 41 },
    } },
}

local function pick(over, cat, key)
    if over and over[key] ~= nil then return over[key] end
    if cat[key] ~= nil then return cat[key] end
    return Base[key]
end

-- Expands one catalogue line into the full table the stable code reads.
local function expand(cat, line)
    local over = line[5]
    return {
        label     = line[2],
        distance  = pick(over, cat, 'distance'),
        cashPrice = line[3],
        goldPrice = line[4],
        brakeSet  = false,
        blip      = { enabled = true, sprite = 'blip_mp_player_wagon' },
        gamerTag  = { enabled = false, distance = 15 },
        condition = {
            enabled       = true,
            maxAmount     = pick(over, cat, 'maxHealth'),
            decreaseValue = pick(over, cat, 'wear'),
            decreaseTime  = pick(over, cat, 'wearEvery'),
            repairValue   = pick(over, cat, 'repair'),
        },
        inventory = {
            enabled = true,
            limit   = pick(over, cat, 'cargo'),
            weapons = pick(over, cat, 'weapons'),
            shared  = pick(over, cat, 'shared'),
            whitelistWeapons = false,  weaponsLimitWhiteList = {},
            useBlackList = false,      itemsBlackList = {},
            useWhiteList = false,      itemsLimitWhiteList = {},
            ignoreItemStackLimit = true,
            usePermissions = false,
            permissions = { allowedJobsTakeFrom = {}, allowedJobsMoveTo = {} },
        },
        job = pick(over, cat, 'job'),
    }
end

StableWagons = {}
for _, cat in ipairs(Catalogue) do
    local types = {}
    for _, line in ipairs(cat.wagons) do
        types[line[1]] = expand(cat, line)
    end
    StableWagons[#StableWagons + 1] = { name = cat.name, types = types }
end
