-- ==========================================================================
--  JRS CORE  |  jrs_passports  |  config.lua
--  passports - register, renew and show identity papers
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

Config.DevMode   = false
Config.Debug     = false

Config.PromptKeys = { 
    ['REGISTER'] = { key = 0x760A9C6F, label = 'Passport Registration'   }, 
    ['RETRIEVE'] = { key = 0xE30CD707, label = 'Retrieve Lost Passport'  },
    ['RENEW']    = { key = 0xCEFD9220, label = 'Renew Existing Passport' },
}

-----------------------------------------------------------
--[[ General Settings  ]]--
-----------------------------------------------------------

Config.Year = 1890

-- The rendering distance for spawning / despawning the npcs.
Config.NPCRenderingSpawnDistance = 20.0

-- @ExpirationDays : (time in days) - every 3 months by default, a passport will be expired automatically by the system.
Config.PassportExpirationDays = 90

-- @param Retrieve : When player lost the passport and has to get it back by paying a cost.
-- @param Renewal  : To renew into a new expiring date your existing passport.
Config.PassportCosts = { Registration = 5, Retrieve = 10, Renewal = 10 }

-- To display the passport to yourself or the closest players by the @Distance parameter.
Config.PassportItem = 'passport'

Config.DisplayPassportCardDistance = 2.0

Config.AutomaticallyClosePassportDelayDuration = 20 -- Time in seconds.

-- (!) jrs_society IS REQUIRED IF YOU WANT THE REGISTRATION OR RETRIEVE COST MONEY TO BE ADDED ON A SOCIETY LEDGER ACCOUNT.
Config.Society = { Enabled = false, Job = 'police' }

-----------------------------------------------------------
--[[ Passport Registration Locations  ]]--
-----------------------------------------------------------

-- Set to false if you don't want the players to register a passport on locations.
Config.EnableRegistrationLocations = true

Config.Locations = {

    ['VALENTINE'] = {

        Coords = { x = -174.356, y = 633.3184, z = 114.08 },

        ActionDistance = 1.5,

        Hours = { Enabled = true, Opening = 7, Closing = 23 },

        BlipData = {
            Enabled = true,
            Sprite = -1636832113,
            Title = "Registrations Office Department",

            OpenBlipModifier = 'BLIP_MODIFIER_MP_COLOR_32',
            DisplayClosedHours = { Enabled = true, Sprite = -1636832113, BlipModifier = "BLIP_MODIFIER_MP_COLOR_2" },
        },

        NPCData = {
            Enabled = false, -- FALSE BY DEFAULT.
            Model   = "", -- THE NPC MODEL NAME.
            Coords  = { x = 0, y = 0, z = 0, h = 0 },
        },
        
    },

    ['RHODES'] = {

        Coords = { x = 1231.482, y = -1299.63, z = 76.903 },

        ActionDistance = 1.5,

        Hours = { Enabled = true, Opening = 7, Closing = 23 },

        BlipData = {
            Enabled = true,
            Sprite = -1636832113,
            Title = "Registrations Office Department",

            OpenBlipModifier = 'BLIP_MODIFIER_MP_COLOR_32',
            DisplayClosedHours = { Enabled = true, Sprite = -1636832113, BlipModifier = "BLIP_MODIFIER_MP_COLOR_2" },
        },

        NPCData = {
            Enabled = false, -- FALSE BY DEFAULT.
            Model   = "", -- THE NPC MODEL NAME.
            Coords  = { x = 0, y = 0, z = 0, h = 0 },
        },
        
    },

    ['BLACKWATER'] = {

        Coords = { x = -875.363, y = -1334.23, z = 43.957, },

        ActionDistance = 1.5,

        Hours = { Enabled = true, Opening = 7, Closing = 23 },

        BlipData = {
            Enabled = true,
            Sprite = -1636832113,
            Title = "Registrations Office Department",

            OpenBlipModifier = 'BLIP_MODIFIER_MP_COLOR_32',
            DisplayClosedHours = { Enabled = true, Sprite = -1636832113, BlipModifier = "BLIP_MODIFIER_MP_COLOR_2" },
        },

        NPCData = {
            Enabled = false, -- FALSE BY DEFAULT.
            Model   = "", -- THE NPC MODEL NAME.
            Coords  = { x = 0, y = 0, z = 0, h = 0 },
        },
        
    },
}

---------------------------------------------------------------
--[[ Webhooks ]]--
---------------------------------------------------------------

-- (!) Checkout jrs_core/server/discord/webhooks.lua to modify the webhook urls.
Config.Webhooks = {

    ['CREATED_PASSPORT'] = { -- When a passport has been created.
        Enabled = false, 
        Color = 10038562,
    },

    ['RETRIEVED_PASSPORT'] = { -- When a passport has been retrieved.
        Enabled = false, 
        Color = 10038562,
    },

    ['RENEWED_PASSPORT'] = { -- When a passport has been renewed.
        Enabled = false, 
        Color = 10038562,
    },
}

-----------------------------------------------------------
--[[ Notification Functions  ]]--
-----------------------------------------------------------

-- @param source : The source always null when called from client.
-- @param type   : returns "error", "success", "info"
-- @param duration : the notification duration in milliseconds
function SendNotification(source, message, type, duration)

	if not duration then
		duration = 3000
	end

    if not source then
        TriggerEvent(GetCurrentResourceName() .. ':notify', message, duration)
    else
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', source, message, duration)
    end
  
end
