-- jrs_railroad | server: only one client at a time may run the ambient train
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local taken = false

JRS.Callback('jrs_railroad:shouldSpawnAmbient', function()
    if taken then return false end
    taken = true
    return true
end)

RegisterNetEvent('jrs_railroad:ambientDespawned', function() taken = false end)
