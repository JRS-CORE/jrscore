-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | the teleport section

local T = Translation.Current()
local followWaypoint = false         -- "auto teleport to marker" is running
local returnFromGuarma = nil

-- ------------------------------------------------------------------ moving the admin

local function inGuarma()
    local zone = GetMapZoneAtCoords(GetEntityCoords(PlayerPedId()), 10)
    return Config.GuamarmaCoords.GuarmaAreaHashes[zone] == true
end

-- the world and minimap switch between the mainland and Guarma
local function guarmaWorld(entering)
    Citizen.InvokeNative(0x74E2261D2A66849A, entering)
    Citizen.InvokeNative(0xE8770EE02AEE45C2, entering and 1 or 0)
    Citizen.InvokeNative(0xA657EC9DBC6CC900, entering and 1935063277 or -1868977180)
end

local function jumpTo(ped, at)
    DoScreenFadeOut(500)
    RequestCollisionAtCoord(at.x, at.y, at.z)
    Wait(1000)
    SetEntityCoords(ped, at.x, at.y, at.z, false, false, false, false)
    local limit = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < limit do Wait(10) end
    Wait(1000)
    DoScreenFadeIn(650)
end

-- "x y z", "vector3(x, y, z)" and "{x = 1, y = 2, z = 3}" all end up as three numbers
local function readCoords(text)
    local digits = text:gsub('vector[34]', ''):gsub(',', ' '):gsub('[^%d%. -]', '')
    local n = {}
    for token in digits:gmatch('%S+') do n[#n + 1] = tonumber(token) end
    if n[1] and n[2] and n[3] then return n[1], n[2], n[3] end
end

-- ------------------------------------------------------------------ the actions

local function toWaypoint()
    if not IsWaypointActive() then return JRS.NotifyObjective(T.Notify.noWaypoint, 5000) end
    TriggerServerEvent('jrs:teleportWayPoint', '', GetEntityCoords(PlayerPedId()), GetWaypointCoords())
end

local function toggleFollow()
    followWaypoint = not followWaypoint
    TriggerEvent('jrs:TipRight', followWaypoint and T.Notify.switchedOn or T.Notify.switchedOff, 3000)
    if not followWaypoint then return end
    CreateThread(function()
        while followWaypoint do
            Wait(2000)
            if followWaypoint then TriggerServerEvent('jrs:teleportWayPoint') end
        end
    end)
end

local function toTypedCoords()
    local spec = T.Menus.MainTeleportOptions.InsertCoordsInput
    local before = GetEntityCoords(PlayerPedId())
    Kit.ask(spec, '.{5,100}', function(text)
        local x, y, z = readCoords(text)
        if not x then return JRS.NotifyObjective(T.Notify.missingArgument, 4000) end
        MenuData.CloseAll()
        jumpTo(PlayerPedId(), { x = x, y = y, z = z })
        TriggerServerEvent('jrs_admin:tptocoords', before, x, y, z)
    end)
end

-- asks for a server id and hands it to `done`; `onEmpty` decides what an empty answer says
local function withPlayerId(done, emptyNotice)
    AdminSimpleInput(T.Menus.DefaultsInputs.confirm, T.Menus.DefaultsInputs.serverID, function(answer)
        if answer ~= '' then done(answer) else emptyNotice() end
    end)
end

local function noticeEmpty() JRS.NotifyObjective(T.Notify.empty, 5000) end

local function toGuarmaAndBack()
    local ped = PlayerPedId()
    MenuData.CloseAll()
    if inGuarma() then
        guarmaWorld(false)
        jumpTo(ped, returnFromGuarma or Config.GuamarmaCoords.MainLandCoords)
        returnFromGuarma = nil
    else
        returnFromGuarma = GetEntityCoords(ped)
        guarmaWorld(true)
        jumpTo(ped, Config.GuamarmaCoords.GuarmaCoords)
    end
end

-- ------------------------------------------------------------------ the menu

function Teleport()
    local O = T.Menus.MainTeleportOptions
    Kit.open('Teleport', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleTeleport,
        back = 'OpenMenu',
        items = {
            { label = O.tpmAuto, value = 'autotpm', desc = O.tpmAuto_desc, go = toggleFollow },
            { label = O.tpmToMarker, value = 'tpm', desc = O.tpmToMarker_desc, go = toWaypoint },
            { label = O.tpToCoords, value = 'tptocoords', gate = 'tp_to_coords', desc = O.tpToCoords_desc, go = toTypedCoords },
            { label = O.tpToPlayer, value = 'tptoplayer', desc = O.tpToPlayer_desc, go = function()
                withPlayerId(function(id) TriggerServerEvent('jrs_admin:TpToPlayer', id) end, noticeEmpty)
            end },
            { label = O.adminGoBackLastLocation, value = 'admingoback', desc = O.adminGoBackLastLocation_desc,
              go = function() TriggerServerEvent('jrs_admin:sendAdminBack') end },
            { label = O.bringPlayer, value = 'bringplayer', desc = O.bringPlayer_desc, go = function()
                withPlayerId(function(id)
                    TriggerServerEvent('jrs_admin:Bring', id, GetEntityCoords(PlayerPedId()), '', nil, id)
                end, noticeEmpty)
            end },
            { label = O.sendPlayerToLastLocation, value = 'sendback', desc = O.sendPlayerToLastLocation_desc, go = function()
                withPlayerId(function(id) TriggerServerEvent('jrs_admin:TeleportPlayerBack', id) end,
                    function() TriggerEvent('jrs:TipRight', T.Notify.goToPlayerFirst, 4000) end)
            end },
            { label = O.teleportToGuarma, value = 'tptoguarma', gate = 'teleport_to_guarma', desc = O.teleportToGuarma_desc, go = toGuarmaAndBack },
        },
    })
end
