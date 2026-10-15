-- jrs_animations | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_animations  |  config.lua
--  Animation catalogue used through the `initiate` export.
-- ==========================================================================

Config = {}

-- Chat commands for placing props (/animdev, /animnudge, /animdump). Leave off on live servers.
Config.DevTools = false

-- Length of the one-shot test in /animdev and of playAnimation() when no time is given (ms)
Config.DefaultPlayTime = 8000

-- ------------------------------------------------------------------ builders
-- A prop is { model, bone, coords = { x, y, z, xr, yr, zr }, subprops = { same shape without bone } }

local function at(x, y, z, xr, yr, zr)
    return { x = x, y = y, z = z, xr = xr, yr = yr, zr = zr }
end

local function clip(dict, name, flag, prop)
    return { type = 'standard', dict = dict, name = name, flag = flag, prop = prop }
end

local function carryBox(model, coords)
    return clip('mech_carry_box', 'idle', 31, { model = model, bone = 'SKEL_L_Hand', coords = coords })
end

-- ------------------------------------------------------------------ catalogue
-- Add your own with exports.jrs_animations:initiate().registerAnimation(name, definition)
-- Definition: { type = 'standard', dict, name, flag, prop? }  or  { type = 'scenario', hash, prop? }

Config.Animations = {
    craft = clip('mech_inventory@crafting@fallbacks', 'full_craft_and_stow', 27),

    spindlecook = clip('amb_camp@world_camp_fire_cooking@male_d@wip_base', 'wip_base', 17, {
        model = 'p_stick04x', bone = 'SKEL_R_Finger13', coords = at(0.2, 0.04, 0.12, 170.0, 50.0, 0.0),
        subprops = { { model = 's_meatbit_chunck_medium01x', coords = at(-0.30, -0.08, -0.30, 0.0, 0.0, 70.0) } },
    }),

    knifecooking = clip('amb_camp@world_player_fire_cook_knife@male_a@wip_base', 'wip_base', 17, {
        model = 'w_melee_knife06', bone = 'SKEL_R_Finger13', coords = at(-0.01, -0.02, 0.02, 190.0, 0.0, 0.0),
        subprops = { { model = 'p_redefleshymeat01xa', coords = at(0.0, 0.02, -0.20, 0.0, 0.0, 0.0) } },
    }),

    campfire  = clip('script_campfire@lighting_fire@male_male', 'light_fire_b_p2_male_b', 17),
    riverwash = clip('amb_misc@world_human_wash_kneel_river@female_a@idle_a', 'idle_c', 17),

    hoeing = clip('amb_work@world_human_farmer_hoe@male_a@base', 'base', 17, {
        model = 'p_rake01x', bone = 'SKEL_L_Hand', coords = at(0.2, 0.3, 0.1, 210.0, -90.0, -186.0),
    }),

    sweeping = clip('amb_work@world_human_farmer_hoe@male_a@base', 'base', 17, {
        model = 'p_broom04x', bone = 'SKEL_L_Hand', coords = at(0.75, 1.1, 0.1, 303.0, -90.0, -186.0),
    }),

    readnewspaper = clip('mech_carry_box', 'idle', 17, {
        model = 'p_cs_newspaper_02x_noanim', bone = 'SKEL_L_Finger12', coords = at(0.15, -0.04, 0.0, 0.0, 0.0, 0.0),
    }),

    gravedigging = clip('amb_work@world_human_gravedig@working@male_b@base', 'base', 17, {
        model = 'p_shovel02x', bone = 'SKEL_R_Hand', coords = at(0.0, -0.09, -0.09, 250.29, 579.19, 373.3),
    }),

    carry_box        = carryBox('p_chair_crate02x',            at(0.1, -0.14, 0.21, 263.29, 619.19, 334.3)),
    carry_sugar      = carryBox('p_cs_sacksugarcornwall01x',   at(-0.05, 0.01, 0.18, 323.69, 705.89, 361.4)),
    carry_barrel     = carryBox('p_barrel010x',                at(-0.05, -0.09, 0.18, 320.69, 714.89, 361.4)),
    carry_moonshine  = carryBox('p_bottlecrate_mil',           at(0.1, -0.14, 0.26, 263.29, 619.19, 334.3)),
    carry_moonshine2 = carryBox('p_bottlecrate_cul',           at(0.1, -0.14, 0.26, 263.29, 619.19, 334.3)),
}
