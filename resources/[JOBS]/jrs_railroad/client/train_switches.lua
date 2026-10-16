-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: track switches
-- One switch flips every junction of every track set between its main and its alternate route. Junction
-- blips show where the junctions are. ] flips the switches while a train is out.

local alternate = false

local TRACKS <const> = {
    'FREIGHT_GROUP', 'TRAINS3', 'BRAITHWAITES2_TRACK_CONFIG', 'TRAINS_OLD_WEST01', 'TRAINS_OLD_WEST03', 'TRAINS_NB1', 'TRAINS_INTERSECTION1_ANN',
}
local JUNCTIONS <const> = 25

local function applySwitches()
    for junction = 0, JUNCTIONS - 1 do
        for _, name in ipairs(TRACKS) do
            local track = joaat(name)
            Citizen.InvokeNative(0xE6C5E2125EB210C1, track, junction, alternate)
            Citizen.InvokeNative(0x3ABFA128F5BF5A70, track, junction, alternate)
        end
    end
end

function ToggleTrackSwitches()
    alternate = not alternate
    applySwitches()
    if alternate then Notify(L('switches_alternate'), 'success', 5000) else Notify(L('switches_default'), 'inform', 5000) end
end

-- the same, without a message (the ambient trains use it)
function ToggleAmbientTrackSwitches()
    alternate = not alternate
    applySwitches()
end

function GetSwitchState() return alternate and 'ALT' or 'MAIN' end
function GetNearestJunctionInfo() return { dist = 0, state = alternate and 1 or 0 } end

CreateThread(function()
    while true do
        Wait(0)
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            if IsControlJustPressed(0, 0xA5BDCD3C) then ToggleTrackSwitches() end
        else
            Wait(500)
        end
    end
end)

Config.SwitchPoints = {
    { coords = vector3(-281.13, -319.66, 89.02), label = 'Flatneck Junction' },
    { coords = vector3(357.96, 596.37, 115.68), label = 'Valentine Junction' },
    { coords = vector3(1481.54, 648.33, 92.31), label = 'Emerald Junction' },
    { coords = vector3(2464.55, -1475.74, 46.15), label = 'Saint Denis South' },
    { coords = vector3(2654.03, -1477.15, 45.76), label = 'Saint Denis East' },
    { coords = vector3(2659.79, -435.71, 43.39), label = 'Van Horn Junction' },
    { coords = vector3(610.36, 1661.90, 187.39), label = 'Bacchus East' },
    { coords = vector3(556.65, 1726.0, 187.80), label = 'Bacchus West' },
    { coords = vector3(2588.54, -1482.19, 46.05), label = 'Saint Denis West' },
    { coords = vector3(-4921.73, -3000.57, -18.48), label = 'Armadillo' },
}

local blips = {}

CreateThread(function()
    Wait(2000)
    for _, point in ipairs(Config.SwitchPoints) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, point.coords.x, point.coords.y, point.coords.z)
        SetBlipSprite(blip, Config.Blips.switch.hash, true)
        SetBlipScale(blip, Config.Blips.switch.scale)
        Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat('BLIP_MODIFIER_MP_COLOR_6'))
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, point.label)
        blips[#blips + 1] = blip
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)
