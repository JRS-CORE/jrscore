-- ==========================================================================
--  JRS CORE  |  jrs_character  |  config/config.lua
--  jrs core Character System
-- ==========================================================================

-- JRS Character configuration
-- All editable settings are kept in this file.

Config = {}
Config.Debug = false

-- Character aging system.
-- In playtime mode, the character keeps the age calculated from the date of
-- birth when it is created. Every HoursPerYear hours played with that specific
-- character adds one year. Time is saved per character in the database.
Config.AgingMode = 'playtime'

-- 24 hours played = 1 year aged. A character created at the minimum age
-- reaches the first "Early Grey" stage (30) after 288 hours played and
-- "Elder" (60) after 1008 hours - a slow background effect that stays
-- reachable over a real character's active lifetime instead of never
-- showing up. The previous value (100) needed 1200+ hours just to see the
-- first grey hair.
Config.HoursPerYear = 24
Config.AgingSaveIntervalMinutes = 5

-- No character may be created younger than this. Enforced both client-side
-- (immediate feedback in the creator) and server-side (authoritative).
Config.MinimumAge = 18

-- The world's own date. Red Dead Redemption 2's story runs through 1899, so a
-- character's age is measured from this date and NOT from the real-world clock.
--
-- Before this existed, ages were computed against os.date(), which is why the
-- live database holds birth years like 2008 and 1990 - a player had to type a
-- modern date to pass the minimum-age check, and the ID card then printed a
-- year that could not exist in this setting.
--
-- Changing the year re-dates the whole server: every age is (WorldDate.year -
-- birth year), so raising it ages everyone by the difference. Birth years are
-- stored as entered and are never rewritten.
Config.WorldDate = {
    year  = 1899,
    month = 6,
    day   = 1,
}

-- Nobody may claim to have been born before this. Purely a sanity bound for the
-- creator's date picker and the server's validation; it also stops a birth year
-- of 0001 producing an 1898-year-old character.
Config.EarliestBirthYear = 1790

-- Character vitals applied after selecting or respawning a character.
-- The creator changes the player model while loading appearance, and RedM can
-- leave the new ped with the temporary selector ped's low health/stamina.
Config.SpawnVitals = {
    Enabled = true,

    -- Fill both the outer bars and the inner cores.
    FillHealth = true,
    FillHealthCore = true,
    FillStamina = true,
    FillStaminaCore = true,

    Health = 600,
    HealthCore = 100,
    Stamina = 100.0,
    StaminaCore = 100,

    -- Repeat briefly because appearance/metabolism resources may finish loading
    -- during the first second after the ready event.
    ReapplyDelaysMs = { 0, 200, 700, 1200 },

    ApplyOnCharacterSelect = true,
    ApplyAfterDeathRespawn = true,

    -- Some death scripts fire their respawn event just before the replacement
    -- ped becomes alive. Wait only for a real living ped; never revive a corpse.
    DeathRespawnAliveWaitMs = 15000,
    DeathRespawnPollMs = 100,
}


-- Wake-up animation played when a living character enters the game world.
-- It is skipped for characters that are still dead.
Config.SpawnAnimation = {
    Enabled = true,

    Dictionary = 'script_rc@bch2@leadout@rsc_6',
    Name = 'wakeup_slow_charles',
    Duration = -1,
    Flag = 0,

    BlendInSpeed = 1.0,
    BlendOutSpeed = 1.0,
    LoadTimeoutMs = 10000,

    -- Existing and newly-created characters both use the same final spawn path.
    ApplyOnCharacterSelect = true,

    -- The built-in JRS revive routes already use this wake-up animation too.
    ApplyAfterDeathRespawn = true,

    -- Time the character spends in the sleeping/wake-up animation before controls are returned.
    -- Gives ample time for low-end PCs (slow HDDs/CPUs) to stream all textures, face and clothes.
    WakeUpTimeMs = 7000,
    FadeInDelayMs = 2000,
    EnsureComponentsTimeoutMs = 12000,
}


-- New-character city selection book.
-- Each city can be enabled or disabled independently with Enabled = true/false.
-- Keep at least one city enabled so a new character always has a valid spawn.
Config.SpawnBook = {
    Title = 'Choose Your Beginning',
    Subtitle = 'Every trail begins somewhere.',
    SelectLabel = 'Begin in %s',
    PageLabel = 'Page %s of %s',

    -- Arabic copy for the book. Any field left out falls back to the English.
    -- Each city below carries its own Ar block the same way.
    Ar = {
        Title = 'اختر بدايتك',
        Subtitle = 'كل دربٍ يبدأ من مكانٍ ما.',
        SelectLabel = 'ابدأ في %s',
        PageLabel = 'صفحة %s من %s',
    },

    -- The book already contains a city image for every page. Enable this only
    -- when you also want the game camera to move to the city while browsing.
    PreviewWorld = false,

    Cities = {
        {
            Enabled = true,
            Key = 'rhodes',
            Name = 'Rhodes',
            Tagline = 'A warm southern town surrounded by red soil and fields.',
            Region = 'Lemoyne',
            Climate = 'Warm and humid',
            Economy = 'Farming and commerce',
            Danger = 'Moderate',
            Description = 'Rhodes sits between farms, plantations and long country roads. It suits characters who prefer a quieter town with easy routes toward Saint Denis, the bayou and the eastern frontier.',
            Image = 'img/spawn_cities/rhodes.png',
            Ar = {
                Name = 'رودز',
                Tagline = 'بلدة جنوبية دافئة تحيط بها التربة الحمراء والحقول.',
                Region = 'ليموين',
                Climate = 'دافئ ورطب',
                Economy = 'الزراعة والتجارة',
                Danger = 'متوسطة',
                Description = 'تقع رودز بين المزارع والحقول الواسعة والطرق الريفية الطويلة. تناسب من يفضّل بلدة أهدأ مع طرق سهلة نحو سانت دينيس والمستنقعات والحدود الشرقية.',
            },
            CameraCoords = vector3(1302.20, -1298.40, 91.50),
            CameraTarget = vector3(1231.80, -1276.50, 76.00),
            CameraFov = 45.0,
            SpawnCoords = vector3(1231.84, -1276.56, 76.02),
            SpawnHeading = 145.0,
        },
        {
            Enabled = true,
            Key = 'saint_denis',
            Name = 'Saint Denis',
            Tagline = 'A crowded industrial port where fortunes rise and fall.',
            Region = 'Lemoyne',
            Climate = 'Humid city coast',
            Economy = 'Industry and shipping',
            Danger = 'High',
            Description = 'Saint Denis is the largest and most developed city in the region. Its docks, factories, markets and crowded streets offer opportunity, but crime and social inequality are never far away.',
            Image = 'img/spawn_cities/saint_denis.png',
            Ar = {
                Name = 'سانت دينيس',
                Tagline = 'ميناء صناعي مزدحم تُصنع فيه الثروات وتضيع.',
                Region = 'ليموين',
                Climate = 'ساحل مدينة رطب',
                Economy = 'الصناعة والشحن',
                Danger = 'عالية',
                Description = 'سانت دينيس أكبر مدن المنطقة وأكثرها تطوراً. أرصفتها ومصانعها وأسواقها وشوارعها المزدحمة مليئة بالفرص، لكن الجريمة والتفاوت الاجتماعي ليسا بعيدين أبداً.',
            },
            CameraCoords = vector3(2561.39, -1196.94, 55.27),
            CameraTarget = vector3(2575.39, -1199.94, 57.27),
            CameraFov = 50.0,
            SpawnCoords = vector3(2562.541, -1202.153, 52.91567),
            SpawnHeading = 88.36,
        },
        {
            Enabled = true,
            Key = 'blackwater',
            Name = 'Blackwater',
            Tagline = 'A prosperous lakeside city standing between two eras.',
            Region = 'West Elizabeth',
            Climate = 'Mild lakeside',
            Economy = 'Banking and commerce',
            Danger = 'Low',
            Description = 'Blackwater is orderly, wealthy and rapidly modernizing. It is a strong starting point for merchants, professionals and travelers who want access to the Great Plains and western trade routes.',
            Image = 'img/spawn_cities/blackwater.png',
            Ar = {
                Name = 'بلاك ووتر',
                Tagline = 'مدينة مزدهرة على ضفاف البحيرة تقف بين عصرين.',
                Region = 'ويست إليزابيث',
                Climate = 'معتدل على ضفاف البحيرة',
                Economy = 'المصارف والتجارة',
                Danger = 'منخفضة',
                Description = 'بلاك ووتر مدينة منظمة وثرية تتطور بسرعة. نقطة بداية قوية للتجار وأصحاب المهن والمسافرين الراغبين في الوصول إلى السهول الكبرى وطرق التجارة الغربية.',
            },
            CameraCoords = vector3(-796.39, -1329.94, 44.27),
            CameraTarget = vector3(-804.02, -1260.20, 45.79),
            CameraFov = 44.0,
            SpawnCoords = vector3(-793.4255, -1330.698, 42.64374),
            SpawnHeading = 91.10,
        },
        {
            Enabled = true,
            Key = 'armadillo',
            Name = 'Armadillo',
            Tagline = 'A harsh desert settlement built for stubborn survivors.',
            Region = 'New Austin',
            Climate = 'Hot and dry',
            Economy = 'Frontier trade',
            Danger = 'High',
            Description = 'Armadillo is isolated, dusty and unforgiving. Its streets carry the feeling of the old frontier, making it suitable for outlaws, drifters and characters seeking a difficult beginning far from civilization.',
            Image = 'img/spawn_cities/armadillo.png',
            Ar = {
                Name = 'أرماديلو',
                Tagline = 'مستوطنة صحراوية قاسية بُنيت للناجين العنيدين.',
                Region = 'نيو أوستن',
                Climate = 'حار وجاف',
                Economy = 'تجارة الحدود',
                Danger = 'عالية',
                Description = 'أرماديلو معزولة ومغبرة ولا ترحم. تحمل شوارعها روح الحدود القديمة، مما يجعلها مناسبة للخارجين عن القانون والرحّالة ومن يبحث عن بداية صعبة بعيداً عن الحضارة.',
            },
            CameraCoords = vector3(-3646.41, -2619.23, -12.62),
            CameraTarget = vector3(-3666.02, -2602.20, -12.79),
            CameraFov = 70.0,
            SpawnCoords = vector3(-3647.277, -2618.289, -14.57223),
            SpawnHeading = 8.36,
        },
        {
            Enabled = true,
            Key = 'strawberry',
            Name = 'Strawberry',
            Tagline = 'A secluded mountain town of timber, rivers and cold air.',
            Region = 'West Elizabeth',
            Climate = 'Cool mountain valley',
            Economy = 'Logging and tourism',
            Danger = 'Low',
            Description = 'Strawberry is a small settlement hidden among forests and steep mountains. It offers a peaceful beginning for hunters, lumber workers and travelers who prefer wilderness over crowded streets.',
            Image = 'img/spawn_cities/strawberry.png',
            Ar = {
                Name = 'ستروبيري',
                Tagline = 'بلدة جبلية منعزلة من الأخشاب والأنهار والهواء البارد.',
                Region = 'ويست إليزابيث',
                Climate = 'وادٍ جبلي بارد',
                Economy = 'قطع الأخشاب والسياحة',
                Danger = 'منخفضة',
                Description = 'ستروبيري مستوطنة صغيرة مخبأة بين الغابات والجبال الشاهقة. تقدّم بداية هادئة للصيادين وعمّال الأخشاب والمسافرين الذين يفضّلون البرية على الشوارع المزدحمة.',
            },
            CameraCoords = vector3(-1786.40, -385.20, 180.20),
            CameraTarget = vector3(-1815.80, -418.20, 159.50),
            CameraFov = 45.0,
            SpawnCoords = vector3(-1815.78, -418.17, 159.53),
            SpawnHeading = 61.0,
        },
    }
}


-- Optional automatic visual and movement effects based on the character's
-- playtime age. These effects are runtime-only: the player's original hair,
-- beard and face selections are never overwritten in the database.
Config.AgingEffects = {
    Enabled = true,

    -- Show the automatic grey hair / wrinkles on selector preview peds too.
    PreviewInCharacterSelector = true,

    -- Some dependent resources reload the saved barber appearance immediately
    -- after the character-ready event. During this short window, verify the
    -- equipped hair tint and repair it without waiting for the playtime save.
    RuntimeEnforcement = {
        Enabled = true,
        SpawnDurationMs = 5000,
        CheckIntervalMs = 500,
    },

    -- Each effect can be disabled independently.
    Hair = {
        Enabled = true,
        Categories = {
            hair = true,
            hairstabble = true,
            hair_bonnet = true,
        }
    },

    Beard = {
        Enabled = true,
        Categories = {
            beard = true,
            beardstabble = true,
            beards_complete = true,
            beards_chin = true,
            beards_chops = true,
            beards_mustache = true,
        }
    },

    Wrinkles = {
        Enabled = true,
    },

    Movement = {
        Enabled = true,
        -- When false, the movement penalty is suspended while mounted or in a vehicle.
        ApplyWhileMounted = false,
    },

    -- Ranges must not overlap. Hair/beard tint values use the RedM hair palette.
    -- Pure white and silver/grey shades only:
    -- 160 = Aged Gray / Silver-White (رمادي مسنّ مشيب)
    -- 161 = Pure White (أبيض ناصع)
    -- Characters below age 50 keep their 100% natural chosen hair and beard color.
    Stages = {
        {
            Label = 'Grey Hair',
            MinAge = 50,
            MaxAge = 59,
            HairTint = 160,
            BeardTint = 160,
            WrinkleTexture = 5,
            WrinkleOpacity = 0.35,
            MovementRate = 0.95,
        },
        {
            Label = 'Elder White',
            MinAge = 60,
            MaxAge = nil,
            HairTint = 161,
            BeardTint = 161,
            WrinkleTexture = 12,
            WrinkleOpacity = 0.65,
            MovementRate = 0.88,
        },
    }
}

Config.startScale = true

-- Character re-selection is intentionally admin-only.
-- Normal players have no command or keybind that can unload the active character.
Config.CharacterSwitch = {
	enabled = false,
	command = nil
}

Config.SteamIds = {
	[1] = {
		OwnerID = 'steam:110000xxxxxxxxx',
		OwnerCharId = 5,
		height = 1.20
	},
}

Config.spawnGroups = {
	{
		playerPos = {x = 1086.067, y = 1720.671, z = 381.985},
		char1 = {x = 1072.090, y = 1719.825, z = 380.288, h = 267.333},
		char2 = {x = 1072.830, y = 1722.740, z = 380.327, h = 260.172},
		char3 = {x = 1073.194, y = 1725.436, z = 380.288, h = 247.672},
		char4 = {x = 1074.259, y = 1727.795, z = 380.287, h = 239.175},
		camStart = {x = 1080.800, y = 1722.200, z = 382.100, h = 85.0, f = 44.0},
		camSwitch = {
			[1] = {x = 1076.980, y = 1720.360, z = 381.920, h = 90.195},
			[2] = {x = 1077.814, y = 1721.645, z = 382.006, h = 78.192},
			[3] = {x = 1077.187, y = 1723.270, z = 381.948, h = 60.121},
			[4] = {x = 1077.931, y = 1725.059, z = 381.910, h = 50.252}
		}
	}
}

Config.TimeToRespawn = 50 -- Second
Config.RespawnCoords = {
	[1] = {x = -284.560, y = 805.924, z = 119.286}, -- Valentine
	[2] = {x = 2722.40, y = -1233.59, z = 51.14}, -- Saint Denis
	[3] = {x = 2943.74, y = 1334.19, z = 43.19}, -- Annesburg
	[4] = {x = -1803.78, y = -430.77, z = 159.72}, -- Strawberry
	[5] = {x = -870.71, y = -1283.67, z = 45.24}, -- Blackwater
	[6] = {x = -3664.89, y = -2618.44, z = -14.00}, -- Armandillo
	[7] = {x = 1370.02, y = -1310.32, z = 78.31}, -- Rhodes
	[8] = {x = -1318.50, y = 2463.07, z = 310.48}, -- SnowLoc
	[9] = {x = 1335.76, y = -7025.03, z = 53.60}, -- Guarma
	[10] = {x = 366.85, y = 1464.64, z = 179.61}, -- Fort Wallace
}


Config.ModelNames = {
	male = "mp_male",
	female = "mp_female"
}

Config.CreatorCam = {
	heading = -83.32,
	z = 121.305,
	zoom = 50.0,
	start = {x = 1620.171, y = 835.350, z = 122.302, heading = 61.874},
	pitch = -10.0,
	rotateStep = 6.0,
	zoomStep = 5.0,
	zMin = 119.100,
	zMax = 123.300,
	zStep = 0.05,
}


-- Integrated creator and selector settings.
Config.Creator = {}

Config.Creator.framework = 'jrs_core'
Config.Creator.jrs_clothing = true
Config.Creator.LoadSkinCommand = "mc" -- Reload the saved JRS creator appearance
Config.Creator.DevMode = false -- Disabled: developer selector shortcuts are not exposed to players
Config.UseCharSelectRoom = true -- When true, uses the modern Moonshine Saloon interior (interior 78337) with preconfigured ped slots & lighting instead of outdoor spawnGroups

-- Dynamic player lighting for Character Creator & Clothing/Barber menus (same concept as jrs_pets)
Config.Creator.Lighting = {
    enabled = true,
    color = { r = 255, g = 230, b = 195 }, -- Natural warm studio tone (RGB)
    intensity = 2.0,        -- Central omnidirectional light on player (same as pets script: 1.0 - 2.5)
    frontIntensity = 1.4,   -- Front key light for face (under hat brim), chest, and clothing
    range = 4.5,            -- Light sphere radius in meters around the player
    heightOffset = 1.0,     -- Height above player feet (torso/chest level)
    frontOffset = 0.6,      -- Distance in front of player for direct clothing illumination
    selectorIntensity = 15.0, -- Character selection scene light (for selectorLampObj)
}

function CreatorDebug(...)
    if Config.Debug == true then
        print(...)
    end
end

-- Character Selector & Creator Room Settings
Config.Creator.CharSelect = {
    interior = 78337,
    playerSpawn = {
        coords = vector3(-2785.515, -3058.224, -12.34043),
        heading = 349.0,
    },
    imaps = {
        "MP006_A4SUPP_MOONSHINE03",
        "MP006_A4SUPP_MOONSHINE03_PLUG",
    },
    interior_sets = {
        "mp006_mshine_band2",
        "mp006_mshine_theme_goth",
    },
    camera = {
        coords = vector3(-2781.93, -3050.32, -11.65),
        target = vector3(-2781.13, -3053.62, -11.70),
        fov = 40.0,
    },
    pedslots = {
        [1] = { coords = vector3(-2780.148, -3058.581, -13.34043), heading = 0.0, scenariopoint = "PROP_HUMAN_SEAT_CHAIR_TABLE_DRINKING_MOONSHINE" },
        [2] = { coords = vector3(-2782.359, -3058.382, -13.34042), heading = -10.0, scenariopoint = "PROP_HUMAN_SEAT_CHAIR_TABLE_DRINKING_MOONSHINE" },
        [3] = { coords = vector3(-2779.928, -3055.968, -13.34043), heading = 95.82, scenario = "WORLD_HUMAN_SMOKE_NERVOUS_STRESSED" },
        [4] = { coords = vector3(-2780.274, -3053.504, -13.34042), heading = 41.82, scenario = "WORLD_HUMAN_LEAN_BACK_WALL_SMOKING" },
        [5] = { coords = vector3(-2782.446, -3052.998, -13.34043), heading = 292.65, scenario = "WORLD_HUMAN_LEAN_WALL_LEFT" },
        [6] = { coords = vector3(-2784.195, -3061.677, -13.34044), heading = 337.10, scenario = "WORLD_HUMAN_BARTENDER_CLEAN_GLASS" },
    },
}

-- How many characters a player may create.
--
-- Resolved in this order, each step overriding the one before it:
--   1. default                      - the number every player starts with
--   2. users.chars from jrs_core    - only while useCoreLimit is true
--   3. role[<group>]                - per rank
--   4. identifier[<steam:...>]      - per player, wins over everything
-- The result is never below 1.
--
-- default and jrs_core's Config.Char_Count are deliberately kept at the same
-- number. With useCoreLimit = true jrs_core supplies the live value, so that is
-- the one players actually get; default is what applies if the jrs_core user
-- object is not available yet. Change BOTH together, or they will disagree the
-- first time a player connects before jrs_core has loaded them.
--
-- Lowering the number never deletes anything: a player who already has more
-- characters than the limit keeps them and simply cannot create another.
--
-- Granting one player an extra slot: run  addchar <playerId> 2  in the console.
-- That is stored in users.chars_override and survives changes to the default,
-- and it only works while useCoreLimit is true. Set useCoreLimit = false to
-- ignore jrs_core entirely and drive everything from this file instead - then
-- extra slots go in role/identifier below and addchar stops applying.
Config.Creator.Slots = {
    useCoreLimit = true, -- Use users.chars/chars_override managed by jrs_core
    default = 1,         -- Characters a player starts with (match jrs_core Config.Char_Count)

    -- Per-rank slot counts. Empty = every rank uses the value above.
    -- Every account, including staff, is capped at one character.
    --   role = { owner = 3, admin = 2 },
    role = {
    },

    -- Per-player slot counts. Wins over role and default.
    --   identifier = { ['steam:110000xxxxxxxxx'] = 2 },
    identifier = {
    }
}

Config.Creator.PedPermission = {
    default = false,  -- true = access to ped models, false = no access
    
    role = {
        superadmin = false,
        admin = false,
    },
    
    identifier = {
    }
}

Config.Creator.CharacterDeletion = {
    enabled = true,           -- true = deletion enabled, false = no one can delete
    restrictToRoles = false,  -- false = everyone can delete, true = only allowed roles/identifiers
    
    -- If restrictToRoles = true, only these roles can delete characters
    role = {
        owner = true,
        superadmin = true,
        admin = true,
        mod = true,
        server_owner = true,
        full_access = true,
    },
    
    -- Specific players who can always delete (overrides role)
    identifier = {
    }
}

Config.Creator.Commands = {
    deleteCharacter = {
        enabled = true,              -- Enable/disable the command
        command = "deletechar",       -- Command name: /deletechar [charidentifier]
        allowedRoles = {
            "owner",
            "superadmin",
            "admin",
            "mod",
            "server_owner",
            "full_access",
        },
        allowedIdentifiers = {
        }
    },
    
    -- "Second Chance" command - Reopen character customization menu for a player
    secondChance = {
        enabled = true,
        command = "secondchance",     -- Command name: /secondchance [playerid]
        allowedRoles = {
            "owner",
            "superadmin",
            "admin",
            "mod",
            "server_owner",
            "full_access",
        },
        allowedIdentifiers = {
        }
    }
}

-- Studio Lighting Setup for Character Creator / Customization
Config.Creator.Lighting = {
    enabled = true,
    color = { r = 255, g = 248, b = 240 }, -- Crisp neutral-warm studio tone (RGB)
    intensity = 7.5,                         -- Overall body ambient illumination
    frontIntensity = 6.5,                    -- Upper body & face key light
    lowerIntensity = 5.5,                    -- Lower body & legs/boots fill light
    range = 6.5,                             -- Light reach in meters
    heightOffset = 0.85,                     -- Main light height offset
    frontOffset = 0.9,                       -- Front light distance in meters
}

-- Compatibility alias used by the existing runtime code.
CreatorConfig = Config.Creator
