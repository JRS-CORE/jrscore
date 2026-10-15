-- ==========================================================================
--  JRS CORE  |  jrs_usable_items  |  config.lua
--  usable items - pipes, cigars, cigarettes and pocket watches with animations
-- ==========================================================================

Config = {}

Config.Debug = false

---------------------------------------------------------------
--[[ General Settings ]]--
---------------------------------------------------------------

Config.UsableItems = {

    ['pipe'] = {

        Type   = 'PIPE',
        Object = 'p_pipe01x',

        RemoveItemOnUse = false,
        RemoveDurabilityOnUse = { Enabled = true, RemoveValue = { min = 15, max = 20 } }, -- (!) THE ITEM MUST BE A NON-STACKABLE ON ITEMS DATABASE OR ITEMS REGISTRATIONS FILE (DEPENDS WHICH ONE YOU USE).

        RequiredItemUse = { Enabled = true, Item = 'matches', Warning = 'You need a match to light it.', Quantity = 1, Remove = true },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = true,  Label = 'Smoke' }, 
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR PIPE.
    },

    ['pipepeace'] = {

        Type   = 'PIPE_OF_PEACE',
        Object = 'p_peacepipe01x',

        RemoveItemOnUse = false,
        RemoveDurabilityOnUse = { Enabled = true, RemoveValue = { min = 15, max = 20 } }, -- (!) THE ITEM MUST BE A NON-STACKABLE ON ITEMS DATABASE OR ITEMS REGISTRATIONS FILE (DEPENDS WHICH ONE YOU USE).

        RequiredItemUse = { Enabled = true, Item = 'matches', Warning = 'You need a match to light it.', Quantity = 1, Remove = true },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = true,  Label = 'Smoke' }, 
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR PIPE OF PEACE.
    },

    ['cigar'] = {

        Type   = 'CIGAR',
        Object = 'p_cigar01x',

        RemoveItemOnUse = false, -- CIGAR NOT REMOVED, WE USE DURABILITY INSTEAD.
        RemoveDurabilityOnUse = { Enabled = true, RemoveValue = { min = 15, max = 20 } }, -- (!) THE ITEM MUST BE A NON-STACKABLE ON ITEMS DATABASE OR ITEMS REGISTRATIONS FILE (DEPENDS WHICH ONE YOU USE).

        RequiredItemUse = { Enabled = true, Item = 'matches', Warning = 'You need a match to light it.', Quantity = 1, Remove = true },

        PutAwayPromptAction = { Enabled = true,  Label = 'Stop Smoking' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR CIGAR.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR CIGAR.
    },

    ['cigarette'] = {

        Type   = 'CIGARETTE',
        Object = 'p_cigarette01x',

        RemoveItemOnUse = true, -- CIGARETTE IS REMOVED ON ITS USE BY DEFAULT
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },

        RequiredItemUse = { Enabled = true, Item = 'matches', Warning = 'You need a match to light it.', Quantity = 1, Remove = true },

        PutAwayPromptAction = { Enabled = true, Label = 'Finish Smoking' }, 
        UsePromptAction     = { Enabled = true, Label = 'Inhale' },
        ChangePromptAction  = { Enabled = false, Label = 'Change Stance' },
    },


    -- hair pomade is left out: the hair look belongs to jrs_clothing / jrs_barber

    -- [ POCKET WATCHES ] --
    ['pocket_watch'] = {

        Type   = 'POCKET_WATCH',
        Object = 's_inv_pocketwatch06x', -- POCKETS REQUIRES OBJECT NAME

        RemoveItemOnUse = false, -- POCKED WATCH SHOULD NOT BE REMOVED
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },
        RequiredItemUse = { Enabled = false, Item = '', Quantity = 0, Warning = '', Remove = false },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
    },

    ['pocket_watch_silver'] = {

        Type   = 'POCKET_WATCH',
        Object = 's_inv_pocketwatch02x', -- POCKETS REQUIRES OBJECT NAME

        RemoveItemOnUse = false, -- POCKED WATCH SHOULD NOT BE REMOVED
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },
        RequiredItemUse = { Enabled = false, Item = '', Quantity = 0, Warning = '', Remove = false },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
    },

    ['pocket_watch_gold'] = {

        Type   = 'POCKET_WATCH',
        Object = 's_inv_pocketwatch03x', -- POCKETS REQUIRES OBJECT NAME

        RemoveItemOnUse = false, -- POCKED WATCH SHOULD NOT BE REMOVED
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },
        RequiredItemUse = { Enabled = false, Item = '', Quantity = 0, Warning = '', Remove = false },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
    },

    ['pocket_watch_platinum'] = {

        Type   = 'POCKET_WATCH',
        Object = 's_inv_pocketwatch01x', -- POCKETS REQUIRES OBJECT NAME

        RemoveItemOnUse = false, -- POCKED WATCH SHOULD NOT BE REMOVED
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },
        RequiredItemUse = { Enabled = false, Item = '', Quantity = 0, Warning = '', Remove = false },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
    },

    ['pocket_watch_antique'] = {

        Type   = 'POCKET_WATCH',
        Object = 's_oldpocketwatch01x', -- POCKETS REQUIRES OBJECT NAME

        RemoveItemOnUse = false, -- POCKED WATCH SHOULD NOT BE REMOVED
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },
        RequiredItemUse = { Enabled = false, Item = '', Quantity = 0, Warning = '', Remove = false },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
    },

    ['pocket_watch_reutlinger'] = {

        Type   = 'POCKET_WATCH',
        Object = 's_pocketwatch_reutlinge', -- POCKETS REQUIRES OBJECT NAME

        RemoveItemOnUse = false, -- POCKED WATCH SHOULD NOT BE REMOVED
        RemoveDurabilityOnUse = { Enabled = false, RemoveValue = { min = 0, max = 0 } },
        RequiredItemUse = { Enabled = false, Item = '', Quantity = 0, Warning = '', Remove = false },

        PutAwayPromptAction = { Enabled = true,  Label = 'Put Away' },
        UsePromptAction     = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
        ChangePromptAction  = { Enabled = false, Label = '' },  -- DISABLED FOR POCKET WATCHES.
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
