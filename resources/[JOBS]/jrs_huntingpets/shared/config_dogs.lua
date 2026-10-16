-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_huntingpets  |  shared/config_dogs.lua
--  hunting pets - hunting dogs and birds with training, tracking and scavenging
-- ==========================================================================

---------------------------------
-- Dog Configuration
---------------------------------

Config.DogKeyBind = 'E'

Config.DogTrackingJob = "Police" -- job allowed to use dog tracking (jrs_police job name)
Config.CallDogKey = true
Config.DogTriggerKeys = {
    CallDog = 'U',
}

-- Attack command: send your dog to attack a locked-on target
Config.AttackCommand = true
Config.AttackOnlyPlayers = true
Config.AttackOnlyAnimals = true
Config.AttackOnlyNPC = true

-- Track command: send your dog to follow a locked-on target
Config.TrackCommand = true
Config.TrackOnlyPlayers = true
Config.TrackOnlyAnimals = true
Config.TrackOnlyNPC = true

Config.DefensiveMode = true         -- Pets hostile to anything you are in combat with
Config.NoFear = true                -- Prevents horses from fearing your pet

Config.DogSearchRadius = 50.0       -- How far the dog searches for hunted animals
Config.DogFeedInterval = 1800       -- 1800 = 30 min, seconds between feeds

Config.RaiseAnimal = true           -- Feed to gain XP and grow
Config.DogFullGrownXp = 1000        -- XP to be fully grown
Config.DogXpPerFeed = 20            -- XP gained per feed
Config.NotifyWhenHungry = true
Config.DogPetSearchDatabase = true
Config.DogAllowedSearchTables = {'player_outlawbench', 'player_cocainedry', 'player_cannabisdry', 'cannabis_plants', 'cocaine_plants'}

Config.DogPetAttributes = {
    FollowDistance = 5,
    Invincible = false,
    SpawnLimiter = 0,               -- 0 = disabled
    DeathCooldown = 300,            -- Seconds before respawn after death
}

---------------------------------
-- Dog Breeds (for shop)
---------------------------------
Config.Dogs = {
    {
        Text = "$200 - Husky",
        SubText = "",
        Desc = L('dogdesc_husky'),
        Name = L('dogname_husky'),
        img = 'animal_dog_husky.png',
        Param = {
            Price = 200,
            Model = "A_C_DogHusky_01",
            Level = 1
        }
    },
    {
        Text = "$50 - Mutt",
        SubText = "",
        Desc = L('dogdesc_mutt'),
        Name = L('dogname_mutt'),
        img = 'animal_dog_catahoularcur.png',
        Param = {
            Price = 50,
            Model = "A_C_DogCatahoulaCur_01",
            Level = 1
        }
    },
    {
        Text = "$100 - Labrador Retriever",
        SubText = "",
        Desc = L('dogdesc_labrador'),
        Name = L('dogname_labrador'),
        img = 'animal_dog_lab.png',
        Param = {
            Price = 100,
            Model = "A_C_DogLab_01",
            Level = 1
        }
    },
    {
        Text = "$100 - Chesapeake Bay Retriever",
        SubText = "",
        Desc = L('dogdesc_rufus'),
        Name = L('dogname_rufus'),
        img = 'animal_dog_chesbayretriever.png',
        Param = {
            Price = 100,
            Model = "A_C_DogRufus_01",
            Level = 1
        }
    },
    {
        Text = "$150 - Blue Tick Coon Hound",
        SubText = "",
        Desc = L('dogdesc_coonhound'),
        Name = L('dogname_coonhound'),
        img = 'animal_dog_bluetickcoonhound.png',
        Param = {
            Price = 150,
            Model = "A_C_DogBluetickCoonhound_01",
            Level = 1
        }
    },
    {
        Text = "$150 - Hound Dog",
        SubText = "",
        Desc = L('dogdesc_hound'),
        Name = L('dogname_hound'),
        img = 'animal_dog_hound.png',
        Param = {
            Price = 150,
            Model = "A_C_DogHound_01",
            Level = 1
        }
    },
    {
        Text = "$200 - Border Collie",
        SubText = "",
        Desc = L('dogdesc_collie'),
        Name = L('dogname_collie'),
        img = 'animal_dog_collie.png',
        Param = {
            Price = 200,
            Model = "A_C_DogCollie_01",
            Level = 1
        }
    },
    {
        Text = "$200 - Poodle",
        SubText = "",
        Desc = L('dogdesc_poodle'),
        Name = L('dogname_poodle'),
        img = 'animal_dog_poodle.png',
        Param = {
            Price = 200,
            Model = "A_C_DogPoodle_01",
            Level = 1
        }
    },
    {
        Text = "$100 - American Fox Hound",
        SubText = "",
        Desc = L('dogdesc_foxhound'),
        Name = L('dogname_foxhound'),
        img = 'animal_dog_americanfoxhound.png',
        Param = {
            Price = 100,
            Model = "A_C_DogAmericanFoxhound_01",
            Level = 1
        }
    },
    {
        Text = "$100 - Australian Shepherd",
        SubText = "",
        Desc = L('dogdesc_aussie'),
        Name = L('dogname_aussie'),
        img = 'animal_dog_australianshepherd.png',
        Param = {
            Price = 100,
            Model = "A_C_DogAustralianSheperd_01",
            Level = 1
        }
    },
    {
        Text = "$75 - Street Dog",
        SubText = "",
        Desc = L('dogdesc_streetdog'),
        Name = L('dogname_streetdog'),
        img = 'animal_dog_street.png',
        Param = {
            Price = 75,
            Model = "A_C_DogHobo_01",
            Level = 1
        }
    },
}

---------------------------------
-- Animals dogs can retrieve (hunt mode)
---------------------------------
Config.DogRetrievableAnimals = {
    -- Big game mammals
    [1110710183]  = {["name"] = "Deer"},
    [-1437898800] = {["name"] = "Deer"},
    [-1667609490] = {["name"] = "Deer"},
    [-2032656150] = {["name"] = "Deer"},
    [-2021043433] = {["name"] = "Elk"},
    [-1098441944] = {["name"] = "Moose"},
    [-1427753735] = {["name"] = "Bison"},
    [1556473961]  = {["name"] = "Buffalo"},
    [-2137407627] = {["name"] = "Black Bear"},
    [-1088132500] = {["name"] = "Grizzly Bear"},
    [2023809075]  = {["name"] = "Polar Bear"},
    [-249305323]  = {["name"] = "Cougar"},
    [-2029832225] = {["name"] = "Panther"},
    [2075325674]  = {["name"] = "Wild Boar"},
    [1383236440]  = {["name"] = "Peccary"},
    [195700131]   = {["name"] = "Bull"},
    [1700211906]  = {["name"] = "Cow"},
    [788053982]   = {["name"] = "Cow"},
    [40345436]    = {["name"] = "Sheep"},
    [-1255771871] = {["name"] = "Pig"},
    [-753902995]  = {["name"] = "Goat"},
    [-2091538496] = {["name"] = "Ram"},
    [-1851177881] = {["name"] = "Ram"},
    [1755643085]  = {["name"] = "Pronghorn"},
    [1381945409]  = {["name"] = "Pronghorn"},
    -- Predators
    [1864338716]  = {["name"] = "Wolf"},
    [-665854081]  = {["name"] = "Wolf"},
    [252669332]   = {["name"] = "Fox"},
    [480688259]   = {["name"] = "Coyote"},
    [734582471]   = {["name"] = "Coyote"},
    -- Small game
    [-541762431]  = {["name"] = "Rabbit"},
    [1553815115]  = {["name"] = "Rabbit"},
    [-1211566332] = {["name"] = "Skunk"},
    [1458540991]  = {["name"] = "Raccoon"},
    [-203109469]  = {["name"] = "Raccoon"},
    [-1170118274] = {["name"] = "Badger"},
    [-1797625440] = {["name"] = "Armadillo"},
    [68584579]    = {["name"] = "Opossum"},
    [-1134449699] = {["name"] = "Muskrat"},
    [989669666]   = {["name"] = "Rat"},
    [1465438313]  = {["name"] = "Squirrel"},
    [1785067139]  = {["name"] = "Squirrel"},
    [-710876114]  = {["name"] = "Black Squirrel"},
    [-117890714]  = {["name"] = "Gray Squirrel"},
    -- Game birds
    [-1003616053] = {["name"] = "Duck"},
    [-646237339]  = {["name"] = "Duck"},
    [1459778951]  = {["name"] = "Eagle"},
    [-164963696]  = {["name"] = "Herring Seagull"},
    [-1104697660] = {["name"] = "Vulture"},
    [-466054788]  = {["name"] = "Wild Turkey"},
    [-2011226991] = {["name"] = "Wild Turkey"},
    [-166054593]  = {["name"] = "Wild Turkey"},
    [-1076508705] = {["name"] = "Roseate Spoonbill"},
    [-466687768]  = {["name"] = "Red-Footed Booby"},
    [-575340245]  = {["name"] = "Western Raven"},
    [1416324601]  = {["name"] = "Ring-Necked Pheasant"},
    [1265966684]  = {["name"] = "American White Pelican"},
    [-1797450568] = {["name"] = "Blue And Yellow Macaw"},
    [-2073130256] = {["name"] = "Double-Crested Cormorant"},
    [-564099192]  = {["name"] = "Whooping Crane"},
    [723190474]   = {["name"] = "Canada Goose"},
    [1652376302]  = {["name"] = "Canadian Goose"},
    [1353981788]  = {["name"] = "Canadian Goose"},
    [-2145890973] = {["name"] = "Ferruginous Hawk"},
    [1095117488]  = {["name"] = "Great Blue Heron"},
    [386506078]   = {["name"] = "Common Loon"},
    [-861544272]  = {["name"] = "Great Horned Owl"},
    [-2063183075] = {["name"] = "Chicken"},
    [2023522846]  = {["name"] = "Rooster"},
    [1093853729]  = {["name"] = "Wild Grouse"},
    [1525077198]  = {["name"] = "Pigeon"},
    [-578821898]  = {["name"] = "Blackbird"},
    [98537260]    = {["name"] = "Crow"},
    [-1197044581] = {["name"] = "Condor"},
    [1582986780]  = {["name"] = "Blue Jay"},
    [1784941179]  = {["name"] = "Cardinal"},
    [-1302821723] = {["name"] = "Oriole"},
    [-1210546580] = {["name"] = "Robin"},
    [2105463796]  = {["name"] = "Quail"},
    [1253481500]  = {["name"] = "Grouse"},
    [-393435863]  = {["name"] = "Lark"},
    [-1849659473] = {["name"] = "Rat Snake"},
}

---------------------------------
-- Key Hashes
---------------------------------
Config.DogKeys = {
    ['G'] = 0x760A9C6F,
    ['B'] = 0x4CC0E2FE,
    ['S'] = 0xD27782E3,
    ['W'] = 0x8FD015D8,
    ['H'] = 0x24978A28,
    ['U'] = 0xD8F73058,
    ['R'] = 0x0D55A0F0,
    ['ENTER'] = 0xC7B5340A,
    ['E'] = 0xDFF812F9,
    ['J'] = 0xF3830D8E,
    ['7'] = 0xB03A913B,
    ['8'] = 0x42385422,
}
