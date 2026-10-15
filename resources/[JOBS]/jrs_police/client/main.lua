-- jrs_police | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_police | client
-- Station blips and prompts for officers, menus (duty, teleport, hire/fire), handcuffs and dragging,
-- the call marker, and the prison area. The server checks every action.

local Core = exports.jrs_core:GetCore()
local Menu = exports.jrs_core:GetMenuData()
local Text = Config.Text[Config.Language] or Config.Text.en
local TextEn = Config.Text.en
local Jail = Config.Jail

local group = GetRandomIntInRange(0, 0xffffff)
local prompt
local callBlip, callActive = nil, false
local inJail, jailLoop = false, false
local draggedBy, dragged = -1, false

-- ------------------------------------------------------------------ who am I

local function myRank()
    local info = LocalPlayer.state.Character
    local grades = info and Config.Jobs[info.Job]
    return grades and grades[info.Grade]
end

local function needDuty()
    if LocalPlayer.state.isPoliceDuty then return true end
    Core.NotifyObjective(Text.notOnDuty, 5000)
    return false
end

-- the closest other player within 3 m: ped, player index
local function closestPlayer()
    local here = GetEntityCoords(PlayerPedId())
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() then
            local ped = GetPlayerPed(id)
            if #(here - GetEntityCoords(ped)) < 3.0 then return ped, id end
        end
    end
end

-- the duty badge on the shirt
local function badge(on)
    local ped = PlayerPedId()
    RemoveTagFromMetaPed(ped, 0x3F7F3587, 0)
    UpdatePedVariation(ped, false, true, true, true, false)
    if on then
        ApplyShopItemToPed(ped, IsPedMale(ped) and 0x1FC12C9C or 0x929677D, true, true, true)
        UpdatePedVariation(ped, false, true, true, true, false)
    end
end

-- ------------------------------------------------------------------ menus

local function menuOptions(name, sub, rows, onPick, onBack, first)
    Menu.CloseAll()
    Menu.Open('default', GetCurrentResourceName(), name, {
        title = Text.sheriffMenu, subtext = sub, align = Config.MenuAlign, elements = rows,
        soundOpen = first == true, hideRadar = true, divider = true, fixedHeight = true,
        itemHeight = '4vh', skipOpenEvent = false,
    }, onPick, onBack or function(_, menu) menu.close(true, true) end)
end

local function askPlayerId(header)
    local answer = exports.jrs_core:advancedInput({
        type = 'enableinput', inputType = 'input', button = Text.confirm, placeholder = Text.playerId, style = 'block',
        attributes = { inputHeader = header, type = 'number', pattern = '[0-9]', title = Text.numbersOnly,
                       style = 'border-radius: 10px; border:none;' },
    })
    answer = tonumber(answer)
    return answer and answer > 0 and answer or nil
end

local function teleportMenu(from, first)
    local rows = {}
    for index, station in ipairs(Config.Stations) do
        if index ~= from then
            rows[#rows + 1] = { label = station.name, value = index, desc = Text.teleportTo .. station.name }
        end
    end
    menuOptions('teleports', Text.sub, rows, function(data, menu)
        menu.close(true, true, true)
        local at = Config.Stations[data.current.value].teleport
        local ped = PlayerPedId()
        DoScreenFadeOut(1000)
        while not IsScreenFadedOut() do Wait(0) end
        RequestCollisionAtCoord(at.x, at.y, at.z)
        SetEntityCoords(ped, at.x, at.y, at.z, false, false, false, false)
        while HasCollisionLoadedAroundEntity(ped) ~= 1 do Wait(0) end
        Wait(4000)
        DoScreenFadeIn(1000)
    end, nil, first)
end

local function hireMenu()
    local rows = {}
    for job, grades in pairs(Config.Jobs) do
        for grade, rank in pairs(grades) do
            rows[#rows + 1] = { label = ('%s: %s %d'):format(Text.job, rank.label, grade), value = job, grade = grade,
                                desc = ('%s: %s %d'):format(Text.job, rank.label, grade) }
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)

    menuOptions('hire', Text.sub, rows, function(data, menu)
        menu.close(true, true, true)
        local id = askPlayerId(Text.hirePlayer)
        if id then TriggerServerEvent('jrs_police:server:hirePlayer', id, { job = data.current.value, grade = data.current.grade }) end
    end)
end

local function bossMenu()
    menuOptions('boss', Text.hireFire, {
        { label = Text.hirePlayer, value = 'hire', desc = Text.hirePlayer },
        { label = Text.firePlayer, value = 'fire', desc = Text.firePlayer },
    }, function(data, menu)
        if data.current.value == 'hire' then return hireMenu() end
        menu.close(true, true, true)
        local id = askPlayerId(Text.firePlayer)
        if id then TriggerServerEvent('jrs_police:server:firePlayer', id) end
    end)
end

local function dutyMenu()
    local on = LocalPlayer.state.isPoliceDuty
    local rows = {
        { label = on and Text.offDuty or Text.onDuty, value = 'duty', desc = on and Text.goOff or Text.goOn, footerText = Text.pressEnter },
    }
    if Config.UseTeleportMenu then
        rows[#rows + 1] = { label = Text.teleportTo, value = 'teleports', desc = Text.teleportAll, footerText = Text.pressEnter }
    end

    menuOptions('duty', Text.sub, rows, function(data, menu)
        if data.current.value == 'teleports' then return teleportMenu(nil, true) end
        local nowOn = Core.Callback.TriggerAwait('jrs_police:server:checkDuty')
        Core.NotifyObjective(nowOn and Text.nowOnDuty or Text.notOnDuty, 5000)
        badge(nowOn)
        menu.close(true, true, true)
    end, nil, true)
end

RegisterNetEvent('jrs_police:Client:OpenPoliceMenu', dutyMenu)
RegisterNetEvent('jrs_police:Client:JobUpdate', function() end)           -- stations read the job every second

-- ------------------------------------------------------------------ stations

local blips = {}

local function addBlips()
    local look = Config.Blips.station
    for _, station in ipairs(Config.Stations) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, joaat(look.style), station.boss.x, station.boss.y, station.boss.z)
        SetBlipSprite(blip, joaat(look.sprite), true)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, station.name)
        Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(look.color))
        blips[#blips + 1] = blip
    end
end

local function makePrompt()
    prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, Config.PromptKey)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', TextEn.press))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, prompt, true)
    PromptRegisterEnd(prompt)
end

local function pressed() return Citizen.InvokeNative(0xC92AC953F0A982AE, prompt) end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    addBlips()
    makePrompt()

    while true do
        local wait = 1000
        if myRank() then
            local here = GetEntityCoords(PlayerPedId())
            for index, station in ipairs(Config.Stations) do
                for _, kind in ipairs({ 'boss', 'storage', 'teleport' }) do
                    local reach = kind == 'storage' and 1.5 or Config.Reach
                    if (kind ~= 'teleport' or Config.UseTeleportMenu) and #(here - station[kind]) <= reach then
                        wait = 0
                        local label = kind == 'boss' and station.name or kind == 'storage' and station.storageName or station.name
                        PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', label))

                        if pressed() then
                            if kind == 'boss' then
                                local rank = myRank()
                                if rank and rank.manager then bossMenu() else Core.NotifyObjective(Text.menuDenied, 5000) end
                            elseif kind == 'storage' then
                                if needDuty() then
                                    if closestPlayer() then Core.NotifyObjective(Text.playerNearby, 5000)
                                    else TriggerServerEvent('jrs_police:Server:OpenStorage', index) end
                                end
                            elseif needDuty() then
                                teleportMenu(index, true)
                            end
                            Wait(500)
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ------------------------------------------------------------------ cuffs and dragging

RegisterNetEvent('jrs_police:Client:PlayerCuff', function(action)
    local ped = PlayerPedId()
    if action == 'cuff' then
        CuffPed(ped)
        SetEnableHandcuffs(ped, true, false)
        SetPedCanPlayGestureAnims(ped, false)
        DisplayRadar(false)
    else
        UncuffPed(ped)
        SetEnableHandcuffs(ped, false, false)
        SetPedCanPlayGestureAnims(ped, true)
        DisplayRadar(true)
    end
end)

-- the server asks which player is next to us, and whether they are cuffed
Core.Callback.Register('jrs_police:Client:nearby', function(cb)
    local ped, id = closestPlayer()
    if not ped then
        Core.NotifyObjective(Text.notFound, 5000)
        return cb({ cuffed = false, id = false })
    end
    cb({ cuffed = IsPedCuffed(ped), id = GetPlayerServerId(id) })
end)

local function dragSomeone()
    if not needDuty() then return end
    local ped, id = closestPlayer()
    if ped then TriggerServerEvent('jrs_police:Server:dragPlayer', GetPlayerServerId(id)) end
end

RegisterCommand(Config.DragCommand, function()
    if myRank() then dragSomeone() else Core.NotifyObjective(Text.notOfficer, 5000) end
end, false)

RegisterNetEvent('jrs_police:Client:dragPlayer', function(officer)
    draggedBy = officer
    dragged = not dragged
end)

AddEventHandler('jrs_core:Client:OnPlayerDeath', function() dragged = false end)

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    local attached = false
    while true do
        if dragged then
            local officer = GetPlayerPed(GetPlayerFromServerId(draggedBy))
            AttachEntityToEntity(PlayerPedId(), officer, 4103, 11816, 0.48, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, false, true, false)
            attached = true
        elseif attached then
            attached = false
            DetachEntity(PlayerPedId(), true, false)
        end
        Wait(1000)
    end
end)

-- ------------------------------------------------------------------ emergency call marker

local function clearCall()
    if callBlip then RemoveBlip(callBlip) callBlip = nil end
    callActive = false
    ClearGpsMultiRoute()
end

RegisterNetEvent('jrs_police:Client:AlertPolice', function(at)
    if callActive then return end
    callActive = true

    local look = Config.Blips.call
    callBlip = Citizen.InvokeNative(0x554D9D53F696D002, joaat(look.style), at.x, at.y, at.z)
    SetBlipSprite(callBlip, joaat(look.sprite), true)
    Citizen.InvokeNative(0x9CB1A1623062F402, callBlip, look.name)
    Citizen.InvokeNative(0x662D364ABF16DE2F, callBlip, joaat(look.color))

    StartGpsMultiRoute(joaat(look.color), true, true)
    AddPointToGpsMultiRoute(at.x, at.y, at.z, false)
    SetGpsMultiRouteRender(true)

    while callActive and #(GetEntityCoords(PlayerPedId()) - at) >= 15.0 do Wait(1000) end
    if callActive then
        Core.NotifyObjective(Text.arrived, 5000)
        clearCall()
    end
end)

RegisterNetEvent('jrs_police:Client:RemoveBlip', clearCall)

-- ------------------------------------------------------------------ prison

local function moveTo(at, heading)
    local ped = PlayerPedId()
    DoScreenFadeOut(1000)
    while not IsScreenFadedOut() do Wait(0) end
    RequestCollisionAtCoord(at.x, at.y, at.z)
    SetEntityCoordsAndHeading(ped, at.x, at.y, at.z, heading, false, false, false)
    while HasCollisionLoadedAroundEntity(ped) ~= 1 do Wait(0) end
    Wait(4000)
    DoScreenFadeIn(1000)
    while not IsScreenFadedIn() do Wait(0) end
end

RegisterNetEvent('jrs_police:Client:JailPlayer', function()
    if inJail then return end
    inJail = true
    moveTo(Jail.spawn, Jail.spawnHeading)

    CreateThread(function()                                   -- keep prisoners inside the area
        while inJail do
            if #(GetEntityCoords(PlayerPedId()) - Jail.center) > Jail.radius then
                Core.NotifyObjective(Text.cantLeave, 5000)
                Wait(3000)
                SetEntityCoordsAndHeading(PlayerPedId(), Jail.spawn.x, Jail.spawn.y, Jail.spawn.z, Jail.spawnHeading, false, false, false)
            end
            Wait(500)
        end
    end)

    CreateThread(function()                                   -- no horse or wagon calls from a cell
        while inJail do
            DisableControlAction(0, `INPUT_WHISTLE`, true)
            DisableControlAction(0, `INPUT_OPEN_JOURNAL`, true)
            Wait(0)
        end
    end)

    SetTimeout(5000, function() Core.NotifyObjective(Text.jailHint:format(Jail.commands.check), 5000) end)
end)

RegisterNetEvent('jrs_police:Client:JailFinished', function()
    inJail = false
    moveTo(Jail.release, Jail.releaseHeading)
    SetTimeout(5000, function() Core.NotifyObjective(Text.freed, 5000) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if dragged then DetachEntity(PlayerPedId(), true, false) end
    clearCall()
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)
