---------------------------------------------------------------
-- TRACK SWITCHING - Simple global toggle
-- Toggles ALL junctions across all track models between
-- default routes (OFF) and alternate routes (ON)
---------------------------------------------------------------
local switchState = false

local trackModels = {
    'FREIGHT_GROUP',
    'TRAINS3',
    'BRAITHWAITES2_TRACK_CONFIG',
    'TRAINS_OLD_WEST01',
    'TRAINS_OLD_WEST03',
    'TRAINS_NB1',
    'TRAINS_INTERSECTION1_ANN',
}

---------------------------------------------------------------
-- TOGGLE ALL TRACK SWITCHES
---------------------------------------------------------------
function ToggleTrackSwitches()
    switchState = not switchState

    local counter = 0
    repeat
        for _, modelName in ipairs(trackModels) do
            local trackHash = joaat(modelName)
            Citizen.InvokeNative(0xE6C5E2125EB210C1, trackHash, counter, switchState)
            Citizen.InvokeNative(0x3ABFA128F5BF5A70, trackHash, counter, switchState)
        end
        counter = counter + 1
    until counter >= 25

    if switchState then
        Notify(L('switches_alternate'), 'success', 5000)
    else
        Notify(L('switches_default'), 'inform', 5000)
    end
end

---------------------------------------------------------------
---------------------------------------------------------------
-- SILENT TOGGLE (for ambient trains - no notification)
---------------------------------------------------------------
function ToggleAmbientTrackSwitches()
    switchState = not switchState

    local counter = 0
    repeat
        for _, modelName in ipairs(trackModels) do
            local trackHash = joaat(modelName)
            Citizen.InvokeNative(0xE6C5E2125EB210C1, trackHash, counter, switchState)
            Citizen.InvokeNative(0x3ABFA128F5BF5A70, trackHash, counter, switchState)
        end
        counter = counter + 1
    until counter >= 25
end

-- GET SWITCH STATE (for HUD)
---------------------------------------------------------------
function GetSwitchState()
    return switchState and 'ALT' or 'MAIN'
end

function GetNearestJunctionInfo()
    return { dist = 0, state = switchState and 1 or 0 }
end

---------------------------------------------------------------
-- Q KEY: Toggle switches (works in or out of driver seat)
---------------------------------------------------------------
local SwitchKey = 0xA5BDCD3C -- ] RIGHTBRACKET key

CreateThread(function()
    while true do
        Wait(0)
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            if IsControlJustPressed(0, SwitchKey) then
                ToggleTrackSwitches()
            end
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------
-- TRACK SWITCH POINT BLIPS
---------------------------------------------------------------
Config.SwitchPoints = {
    { coords = vector3(-281.13, -319.66, 89.02),  label = 'Flatneck Junction' },
    { coords = vector3(357.96, 596.37, 115.68),   label = 'Valentine Junction' },
    { coords = vector3(1481.54, 648.33, 92.31),   label = 'Emerald Junction' },
    { coords = vector3(2464.55, -1475.74, 46.15), label = 'Saint Denis South' },
    { coords = vector3(2654.03, -1477.15, 45.76), label = 'Saint Denis East' },
    { coords = vector3(2659.79, -435.71, 43.39),  label = 'Van Horn Junction' },
    { coords = vector3(610.36, 1661.90, 187.39),  label = 'Bacchus East' },
    { coords = vector3(556.65, 1726.0, 187.80),   label = 'Bacchus West' },
    { coords = vector3(2588.54, -1482.19, 46.05), label = 'Saint Denis West' },
	{ coords = vector3(-4921.73, -3000.57, -18.48), label = 'Armadillo' },
   
}

local switchBlips = {}

CreateThread(function()
    Wait(2000)
    for _, sp in ipairs(Config.SwitchPoints) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, sp.coords.x, sp.coords.y, sp.coords.z)
        SetBlipSprite(blip, Config.Blips.switch.hash, true)
        SetBlipScale(blip, Config.Blips.switch.scale)
        Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat('BLIP_MODIFIER_MP_COLOR_6'))
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, sp.label)
        table.insert(switchBlips, blip)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, blip in ipairs(switchBlips) do
            RemoveBlip(blip)
        end
    end
end)
