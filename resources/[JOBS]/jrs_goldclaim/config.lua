-- ==========================================================================
--  JRS CORE  |  jrs_goldclaim  |  config.lua
--  gold claims - gold rockers, paydirt, water and licensed claims
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'
Config.PlayerProps = {} -- populated at runtime by the server, do not edit

Config.Debug = false

Config.NotifyDuration = 10000 -- default notification duration (ms)

---------------------------------------------
-- general settings (gold rocker / claims)
---------------------------------------------
Config.EnableVegModifier    = true                   -- clears vegetation around placed rockers
Config.GoldRocker           = `p_goldcradlestand01x` -- prop used for gold rocker
Config.MaxGoldRockers       = 4                      -- maximum gold rockers per character
Config.DegradeChance        = 5                      -- % chance (per rocker) of losing 1% quality each cron cycle
Config.DegradeEvery         = 30                     -- minutes between degradation rolls
Config.RepairWoodAmount     = 5                      -- amount of wood needed to repair
Config.LeoJobs              = { police = true, sheriff = true, marshal = true } -- jobs allowed to destroy unlicensed claims
Config.OwnerOnlyProcessing  = true                   -- only the owner can start processing (and receives the output)
Config.LicenseItem          = 'goldclaim_license' -- consumed on placement to make the claim licensed

---------------------------------------------
-- distances (server-side anti-exploit checks)
---------------------------------------------
Config.InteractDistance     = 5.0                    -- max distance from a rocker to interact with it
Config.PickupDistance       = 10.0                   -- max distance from a rocker to pick up its output
Config.PlaceMaxDistance     = 6.0                    -- max distance between player and placed rocker
Config.MinRockerSpacing     = 4.0                    -- min distance between two rockers
Config.PropDrawDistance     = 60.0                   -- distance at which rocker props are streamed in

---------------------------------------------
-- processing settings
---------------------------------------------
Config.ProcessingTime       = 60000                  -- time in ms per processing cycle
Config.GoldChance           = 50                     -- % chance of gold vs paydirt return
Config.AddPaydirtTime       = 10000                  -- time in ms to add paydirt to rocker
Config.AddWaterTime         = 10000                  -- time in ms to add water to rocker
Config.MaxPaydirt           = 5                      -- max paydirt units a rocker can hold
Config.MaxWater             = 5                      -- max water units a rocker can hold
Config.RepairTime           = 10000                  -- time in ms to repair
Config.PackUpTime           = 10000                  -- time in ms to pack up
Config.PlaceTime            = 10000                  -- time in ms to set up a rocker
Config.DestroyTime          = 10000                  -- time in ms for LEO to destroy an illegal claim
Config.PickupTime           = 3000                   -- time in ms to pick up an output prop

---------------------------------------------
-- gold ore output (random amount per gold pickup)
---------------------------------------------
Config.GoldOreItem   = 'goldnugget'
Config.GoldOreAmount = { min = 1, max = 5 }

---------------------------------------------
-- gathering settings (shovel / bucket)
---------------------------------------------
Config.ShovelDigTime        = 10000                  -- time in ms to dig paydirt
Config.BucketFillTime       = 8000                   -- time in ms to fill bucket

---------------------------------------------
-- prop models
---------------------------------------------
Config.GoldProp             = `p_goldstack01x`                -- gold output prop
Config.PaydirtProp          = `mp005_p_dirtpile_sca02_buried` -- paydirt output prop
Config.PropSpawnOffset      = 1.5                             -- distance to side of rocker to spawn output prop

---------------------------------------------
-- shovel prop (attached to hand during dig)
---------------------------------------------
Config.ShovelProp = {
    model  = `p_shovel02x`,
    bone   = 'SKEL_R_Hand',
    offset = { 0.0, -0.19, -0.089, 274.1899, 483.89, 378.40 },
}

-- dirt pile spawned in front of the player after a successful dig (cosmetic, local only)
Config.DigDirtPile = {
    enabled  = true,
    model    = `mp005_p_dirtpile_tall_unburied`,
    offset   = 0.6,    -- distance in front of the player
    lifetime = 30000,  -- ms before it is removed
}

---------------------------------------------
-- animations
---------------------------------------------
Config.Anims = {
    dig = {
        dict = 'amb_work@world_human_gravedig@working@male_b@base',
        name = 'base',
    },
    crouch_inspect = `WORLD_HUMAN_CROUCH_INSPECT`,  -- scenario
    add_paydirt    = `WORLD_HUMAN_FEED_PIGS`,       -- scenario used when adding paydirt
    add_water      = `WORLD_HUMAN_BUCKET_POUR_LOW`, -- scenario used when adding water
}

---------------------------------------------
-- claim zone / blip settings
---------------------------------------------
Config.ClaimZoneRadius = 20.0
Config.MaxClaimNameLength = 50
Config.ClaimBlip = {
    blipSprite = 'blip_gold',
    blipScale  = 0.2,
    blipColour = 'BLIP_MODIFIER_MP_COLOR_6',
}

---------------------------------------------
-- placement
---------------------------------------------
Config.ForwardDistance = 2.0
