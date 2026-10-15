-- ==========================================================================
--  JRS CORE  |  jrs_samples  |  config.lua
--  animal samples - sedate animals, collect samples, leaderboard and milestones
-- ==========================================================================

--------------------------------------------------------------------------------------------
-- JRS SAMPLES — Configuration
-- This file is safe to edit freely. All server-op and designer settings live here.
-- NO escrow protection on this file — make changes without restriction.
--------------------------------------------------------------------------------------------

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'


--------------------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------------------
Config.DebugClient = false   -- Print client-side debug logs to F8 console
Config.DebugServer = false   -- Print server-side debug logs to server console

--------------------------------------------------------------------------------------------
-- Database
--------------------------------------------------------------------------------------------
Config.AutoInstallDB = true  -- create the jrs_samples table automatically on resource start

--------------------------------------------------------------------------------------------
-- Sample Collection
--------------------------------------------------------------------------------------------
Config.StoreSampleData   = true   -- false = no DB writes; collections kept in memory until restart (testing only)
Config.SampleHoldTime    = 4000   -- ms — how long to hold the prompt to collect
Config.AnimalCleanupTime = 90000  -- ms — how long before a sedated animal recovers (90s)
Config.SampleCooldown    = 3000   -- ms — server-side minimum gap between a player's sample submissions (anti-spam/exploit)

--------------------------------------------------------------------------------------------
-- Leaderboard location (prompt)
-- Place this sphere at a naturalist camp, doctor's office, or any RP-fitting location.
-- Adjust coords and heading to match your map layout.
--------------------------------------------------------------------------------------------
Config.LeaderboardLocation = {
    coords  = vector3(-280.45, 758.23, 118.50), -- Example: Valentine area — change to fit your server
    heading = 180.0,
    radius  = 1.5,
}

--------------------------------------------------------------------------------------------
-- Map Blip  (shown at the leaderboard target location)
-- Set Config.ShowBlip = false to hide it entirely.
-- BlipSprite / BlipColor accept RDR3 blip names (joaat'd automatically).
--------------------------------------------------------------------------------------------
Config.ShowBlip   = true
Config.BlipSprite = 'blip_shop_trapper'          -- blip sprite name (or hash)
Config.BlipColor  = 'BLIP_MODIFIER_MP_COLOR_8'   -- blip colour modifier ('' = default)
Config.BlipScale  = 0.2
-- Blip label comes from the 'blip_label' locale key

--------------------------------------------------------------------------------------------
-- Milestone Rewards
-- When a player's personal total sample count hits a key, they receive bonus cash + notify.
-- Keys must be integers (sample counts). Set to {} to disable milestones entirely.
--------------------------------------------------------------------------------------------
Config.MilestoneRewards = {
    [5]  = { bonus = 100,  label = 'Novice Sampler'    },
    [10] = { bonus = 250,  label = 'Field Researcher'   },
    [25] = { bonus = 750,  label = 'Expert Naturalist'  },
    [50] = { bonus = 2000, label = 'Master Biologist'   },
}

--------------------------------------------------------------------------------------------
-- First Discovery Bonus
-- Extra cash awarded to the FIRST player EVER to collect a particular animal sample.
-- Set to 0 to disable.
--------------------------------------------------------------------------------------------
Config.FirstDiscoveryBonus = 500

--------------------------------------------------------------------------------------------
-- Featured Animal
-- The featured animal shows a ⭐ FEATURED BONUS badge in the UI and earns a reward
-- multiplier when sampled. Set FeaturedAnimal = '' (empty) for no featured animal.
-- Admins can change this live with: /setfeatured <animal_name>
-- Admins only (JRS admin group)
--------------------------------------------------------------------------------------------
Config.FeaturedAnimal     = ''  -- e.g. 'bear', 'moose', 'bison' — must match a name in hashToAnimalMap (server/main.lua)
Config.FeaturedMultiplier = 2   -- reward is multiplied by this when sampling the featured animal