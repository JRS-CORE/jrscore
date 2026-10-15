-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | shared functions and the main menu

local T = Translation.Current()

function Closem()
    MenuData.CloseAll()
    Inmenu = false
end

function GetPlayers()
    return JRS.Callback.TriggerAwait('jrs_admin:Callback:getplayersinfo', { search = 'all' }) or {}
end

-- the ped of a player (by server id); waits up to five seconds for the player to stream in
function GetPlayersClient(serverId)
    local deadline = GetGameTimer() + 5000
    repeat
        local player = GetPlayerFromServerId(tonumber(serverId) or -1)
        local ped = player ~= -1 and GetPlayerPed(player) or 0
        if ped ~= 0 and DoesEntityExist(ped) then return ped end
        Wait(50)
    until GetGameTimer() >= deadline
    return nil
end

-- description of a text box shown by the admin UI
function Inputs(kind, button, placeholder, header, inputType, errorMessage, pattern)
    return {
        type = 'enableinput',
        inputType = kind,
        button = button,
        placeholder = placeholder,
        style = 'block',
        attributes = {
            inputHeader = header,
            type = inputType,
            pattern = pattern,
            title = errorMessage,
            style = 'border-radius: 10px; background-color: ; border:none;',
        },
    }
end

-- ------------------------------------------------------------------ main menu

local sections = {
    { key = 'administration', gate = 'admin_menu',     open = function() Admin() end },
    { key = 'booster',        gate = 'boosters_menu',  open = function() Boost() end,        value = 'boost' },
    { key = 'database',       gate = 'database_menu',  open = function() DataBase() end },
    { key = 'teleport',       gate = 'teleport_menu',  open = function() Teleport() end },
    { key = 'devTools',       gate = 'devtools_menu',  open = function() OpenDevTools() end, value = 'devtools' },
}

function OpenMenu()
    local O = T.Menus.MainMenuOptions
    local items = {}
    for _, section in ipairs(sections) do
        items[#items + 1] = {
            label = O[section.key],
            desc = O[section.key .. '_desc'],
            value = section.value or section.key,
            gate = section.gate,
            go = section.open,
        }
    end
    Kit.open('menuapi', { sub = T.Menus.DefaultsMenusTitle.menuSubTitle, items = items })
end

-- ------------------------------------------------------------------ position helpers

local function trim2(n) return tonumber(('%.2f'):format(n)) end

local copyFormats = {
    v2 = function(x, y, z) return ('{x = %s, y = %s, z = %s}'):format(x, y, z) end,
    v3 = function(x, y, z) return ('vector3(%s, %s, %s)'):format(x, y, z) end,
    v4 = function(x, y, z, h) return ('vector4(%s, %s, %s, %s)'):format(x, y, z, h) end,
    heading = function(_, _, _, h) return h end,
}

-- puts the position (or heading) of the admin in the clipboard, via the page
function CopyToClipboard(kind)
    local format = copyFormats[kind]
    if not format then return end
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    SendNUIMessage({ string = format(trim2(at.x), trim2(at.y), trim2(at.z), trim2(GetEntityHeading(ped))) })
    TriggerEvent('jrs:TipRight', T.Notify.copied, 3000)
end

-- the object nearest to `coords` (default: the admin) and its distance
function GetClosestObject(coords)
    coords = coords or GetEntityCoords(PlayerPedId())
    local best, bestDistance = -1, -1
    for _, object in ipairs(GetGamePool('CObject')) do
        local distance = #(GetEntityCoords(object) - coords)
        if bestDistance == -1 or distance < bestDistance then best, bestDistance = object, distance end
    end
    return best, bestDistance
end
