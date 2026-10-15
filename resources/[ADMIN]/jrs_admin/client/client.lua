-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | opening the menu, and the events the server sends to the admin or the target

local T = Translation.Current()
Inmenu = false
MenuData = AdminMenuData
JRS = exports.jrs_core:GetCore()

local spectating = false
local spectate = nil                 -- what to restore when spectating ends
local previousSpot = nil             -- where the admin was before going to a player / being brought

-- ------------------------------------------------------------------ opening

local function openMenu()
    if not IsAdminAllowed('open_menu') then return false end
    OpenMenu()
    return true
end

-- admins get the staff menu, everybody else the users menu
local function openForMe()
    if not openMenu() and Config.UseUsersMenu then OpenUsersMenu() end
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() or not Config.DevMode then return end
    Wait(100)
    TriggerServerEvent('jrs_admin:getStaffInfo', GetPlayerServerId(PlayerId()))
end)

CreateThread(function()
    repeat Wait(500) until LocalPlayer.state.CharacterReady or LocalPlayer.state.jrsCharacterReady or LocalPlayer.state.IsInSession

    if Config.useAdminCommand then
        TriggerEvent('chat:addSuggestion', '/' .. Config.commandAdmin, T.Notify.adminHelp, { {} })
        RegisterCommand(Config.commandAdmin, openMenu, false)
    end

    while true do
        Wait(0)
        if IsControlJustPressed(0, Config.Key) and not Inmenu
            and (Config.CanOpenMenuWhenDead or not IsPedDeadOrDying(PlayerPedId(), false)) then
            openForMe()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Closem()
    AdminStopSpectate()
    AdminResetBoosters()
end)

-- ------------------------------------------------------------------ effects on this player

RegisterNetEvent('jrs_admin:Freezeplayer', function(state)
    FreezeEntityPosition(PlayerPedId(), state)
end)

RegisterNetEvent('jrs_admin:respawn', function()
    Wait(50)
    DoScreenFadeOut(1000)
    repeat Wait(0) until not IsScreenFadingOut()
    FreezeEntityPosition(PlayerPedId(), true)
    Wait(1000)
    DoScreenFadeIn(4000)
    repeat Wait(0) until not IsScreenFadingIn()
    FreezeEntityPosition(PlayerPedId(), false)
    TriggerEvent('jrs:ShowBottomRight', T.Notify.reviseRules, 10000)
end)

RegisterNetEvent('jrs_admin:clearAmmo', function()
    RemoveAllPedWeapons(PlayerPedId(), true, true)
end)

RegisterNetEvent('jrs_admin:getplayerInventory', function(contents)
    OpenInventory(contents)
end)

-- ------------------------------------------------------------------ spectating

function AdminStopSpectate()
    if not spectate then return end
    local ped = PlayerPedId()
    RenderScriptCams(false, false, 0, true, true, 0)
    if Camera then DestroyCam(Camera, true); Camera = nil end
    SetEntityCoords(ped, spectate.coords.x, spectate.coords.y, spectate.coords.z, false, false, false, false)
    SetEntityVisible(ped, spectate.visible)
    SetEntityInvincible(ped, spectate.invincible)
    SetEntityCanBeDamaged(ped, not spectate.invincible)
    spectating, spectate = false, nil
    DoScreenFadeIn(500)
end

RegisterNetEvent('jrs_admin:spectatePlayer', function(target, coords)
    if spectating then return AdminStopSpectate() end
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end

    local ped = PlayerPedId()
    spectate = { coords = GetEntityCoords(ped), visible = IsEntityVisible(ped), invincible = AdminIsInvincible() }

    DoScreenFadeOut(500)
    Wait(500)
    SetEntityVisible(ped, false)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityCoords(ped, coords.x + 15, coords.y + 15, coords.z, false, false, false, false)

    local watched = GetPlayersClient(target)
    if not watched then
        AdminStopSpectate()
        return JRS.NotifyRightTip(T.Notify.userNotExist, 4000)
    end

    Camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    AttachCamToEntity(Camera, watched, 0.0, -2.0, 1.0, false)
    SetCamActive(Camera, true)
    RenderScriptCams(true, true, 250, true, true, 0)
    spectating = true
    AdminUI.Close()
    DoScreenFadeIn(500)

    CreateThread(function()
        while spectating do
            Wait(500)
            if GetPlayerFromServerId(tonumber(target)) == -1 then AdminStopSpectate() end
        end
    end)
end)
RegisterCommand('adminstop', AdminStopSpectate, false)

-- ------------------------------------------------------------------ teleports ordered by the server

local function moveTo(at)
    SetEntityCoords(PlayerPedId(), at.x, at.y, at.z, false, false, false, false)
end

local function goBack()
    if not previousSpot then return JRS.NotifyRightTip(T.Notify.noPreviousLocation, 4000) end
    moveTo(previousSpot)
    previousSpot = nil
end

RegisterNetEvent('jrs_admin:gotoPlayer', function(at)
    AdminUI.Close()
    previousSpot = GetEntityCoords(PlayerPedId())
    moveTo(at)
end)

RegisterNetEvent('jrs_admin:Bring', function(at)
    previousSpot = GetEntityCoords(PlayerPedId())
    moveTo(at)
end)

RegisterNetEvent('jrs_admin:sendAdminBack', goBack)
RegisterNetEvent('jrs_admin:TeleportPlayerBack', goBack)

-- ------------------------------------------------------------------ troll actions

local function onTroll(name, handler) RegisterNetEvent('jrs_admin:' .. name, handler) end

onTroll('ClientTrollKillPlayerHandler', function() SetEntityHealth(PlayerPedId(), 0, 0) end)

onTroll('ClientTrollInvisbleHandler', function()
    local ped = PlayerPedId()
    SetEntityVisible(ped, not IsEntityVisible(ped))
end)

onTroll('ClientTrollLightningStrikePlayerHandler', function(at) ForceLightningFlashAtCoords(at.x, at.y, at.z, -1.0) end)

onTroll('ClientTrollSetPlayerOnFireHandler', function()
    local model = 'p_campfire02xb'
    if not AdminLoadModel(model) then return end
    local fire = CreateObject(joaat(model), 0, 0, 0, false, false, false)
    if not AdminWaitEntity(fire) then return end
    AttachEntityToEntity(fire, PlayerPedId(), 41, 1000, 1000, 10000, 0, 0, 0, false, false, true, false, 1000, false, false, false)
    Wait(5000)
    DeleteObject(fire)
end)

onTroll('ClientTrollTPToHeavenHandler', function()
    local at = GetEntityCoords(PlayerPedId())
    moveTo(vector3(at.x, at.y, at.z + 200))
end)

onTroll('ClientTrollRagdollPlayerHandler', function() SetPedToRagdoll(PlayerPedId(), 5000, 5000, 0, false, false, false) end)

onTroll('ClientDrainPlayerStamHandler', function() Citizen.InvokeNative(0xC3D4B754C0E86B9E, PlayerPedId(), -1000.0) end)

onTroll('ClientHandcuffPlayerHandler', function()
    local ped = PlayerPedId()
    SetEnableHandcuffs(ped, not IsPedCuffed(ped), false)
end)

onTroll('ClientTempHighPlayerHandler', function()
    AnimpostfxPlay('MP_BountyLagrasSwamp')
    Wait(15000)
    AnimpostfxStop('MP_BountyLagrasSwamp')
end)
