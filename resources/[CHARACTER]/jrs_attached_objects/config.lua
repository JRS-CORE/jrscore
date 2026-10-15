-- ==========================================================================
--  JRS CORE  |  jrs_attached_objects  |  config.lua
--  attached objects - wearable props from items (shield, arrow pouch, miner lamp)
-- ==========================================================================

Config = {}

Config.Debug = false

---------------------------------------------------------------
--[[ General Settings ]]--
---------------------------------------------------------------

Config.DeleteAllAttached = { 
    Command = 'deleteallattachedprops', 
    Description = 'Execute this command to remove all attached props from your player ped.'
}

-- Clear all player ped attached objects - props if the player has been respawned (not revived).
Config.DeleteAllOnPlayerRespawn = true

---------------------------------------------------------------
--[[ Item Sets ]]--
---------------------------------------------------------------

Config.AttachedItemSets = {


    ["natives_backshield"] = { -- ITEM NAME
        {EntityObject = "p_spookynative05x",          Attachment = "CP_Back",     x = -1.16, y= -0.03, z= -0.33999999999999, xRot = -67.0, yRot = 0, zRot = -83.0},
    },

    ['natives_arrow_pouch_bag'] = { -- ITEM NAME
        {EntityObject = "p_arrowbundle01x",           Attachment = "CP_Back",     x = -0.12999999999999, y= -0.04, z= 0.04, xRot = -7.0, yRot = -375.0, zRot = 79.0},
    },
    
    ["miner_hat"] = { -- ITEM NAME
        {EntityObject = "s_hat_miner01x",             Attachment = "HairScale_B", x = 0, y= -0.03, z= 0.01, xRot= -9.0, yRot= 4.0, zRot= 0},
        {EntityObject = "s_movieprojection01x",       Attachment = "HairScale_B", x = 0.00999999999999, y= -0.070, z= 0.09, xRot= -80.0, yRot= 16.0, zRot= 4.0},
    },

}
