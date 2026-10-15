-- ==========================================================================
--  JRS CORE  |  jrs_canoe  |  config.lua
--  canoes - rent canoes from riverside carpenters and carry them
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

Config.PromptAction = { Key = 0x760A9C6F, HoldMode = 1000 }

Config.CanoeActionPrompt = { Key = 0x760A9C6F, Label = 'Drop' }

-----------------------------------------------------------
--[[ General Settings ]]--
-----------------------------------------------------------

Config.NPCRenderingSpawnDistance = 50.0

-- Remove stamina while carrying a canoe?
Config.RemoveStaminaWhileCarrying = { Enabled = true, RemoveValue = 0.05 }

Config.SetPedMaxMoveBlendRatio = 0.8 --  0.0 - 1.0

-- The command to pickup the closest canoe.
Config.PickupCommand = 'pickupcanoe'

-- The command to drop the closest canoe.
Config.DropCommand = 'dropcanoe'

-- true = interact through the JRS interaction prompt instead of the classic prompts
Config.UseInteractPrompt = false

-----------------------------------------------------------
--[[ Canoes ]]--
-----------------------------------------------------------

-- Insert all the canoe models here (You might also have custom canoe vehicle object)
-- DO NOT EDIT WITHOUT KNOWLEDGE.
Config.Models = { 'pirogue', 'pirogue2', 'canoetreetrunk', 'canoe' }

-- The target options are for the JRS interaction prompt support only when targetting a canoe from Config.Models
Config.ModelsTargetOptions = {

    {
        label = 'Pickup Canoe',
        icon = 'fa-solid fa-canoe-person',
        distance = 1.5,

        onSelect = function(data)
            PickupClosestCanoe() -- this is located on client/functions.lua
        end,

        description = ""
    }
}

-----------------------------------------------------------
--[[ Store Locations ]]--
-----------------------------------------------------------

Config.Stores = {

    ['RoanokeValley'] = {
        PromptName = "Canoe Renting", -- same for target
        City = "Roanoke Valley",

        Coords = {x = 2495.163, y = 1801.524, z = 85.494}, -- prompt
        DistanceOpenStore = 2.8, -- prompt

        Hours = { Allowed = true, Opening = 7, Closing = 23 },

        BlipData = { 
            Allowed = true,
            Name    = "Canoe Renting",
            Sprite  = 2005921736,

            OpenBlipModifier = 'BLIP_MODIFIER_MP_COLOR_32',
            DisplayClosedHours = { Enabled = true, Sprite = 2005921736, BlipModifier = "BLIP_MODIFIER_MP_COLOR_2" },
        },

        NPCData = {
            Allowed = true,
            Model = "u_m_m_nbxriverboattarget_01",
            Coords = { x = 2495.163, y =  1801.524, z = 85.494, h = 350.66 },
        },

        -- The coords to spawn the built object of the canoe for the npc to build the canoe.
        -- This will not be functional if NPC is set to false.
        SpawnCoords = { x = 2495.359, y = 1802.518, z = 86.46930694580078, h = 76.73},

        TargetIcon = 'fas fa-box-circle-check',
        TargetDistance = 2.9,

        Canoes = {

            {
                
                Model = 'canoe',

                Title = "Canoe",
                Cost = 2,
                
                DescriptionTitle = "Canoe Rating",
                Description = "⭐⭐⭐",

                ImageBackground = 'canoe.png',
        
            },
        
            {
                Model = "canoeTreeTrunk",

                Title = "Canoe Tree Trunk",
                Cost = 1,

                DescriptionTitle = "Canoe Rating",
                Description = "⭐⭐",
        
                ImageBackground = 'canoetreetrunk.png',
        
            },

        },
        
    },

}

-----------------------------------------------------------
--[[ Notification Functions  ]]--
-----------------------------------------------------------

-- @param source is always null when called from client.
function SendNotification(source, message)
    local duration = 3000

    if not source then
        TriggerEvent(GetCurrentResourceName() .. ':notify', message, duration)
    else
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', source, message, duration)
    end

end
