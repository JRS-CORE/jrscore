-- jrs_attached_objects | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_attached_objects | client commands

local cmd = Config.DeleteAllAttached
TriggerEvent('chat:addSuggestion', '/' .. cmd.Command, cmd.Description)
RegisterCommand(cmd.Command, function() ClearAllPlayerPedAttachedProps() end, false)
