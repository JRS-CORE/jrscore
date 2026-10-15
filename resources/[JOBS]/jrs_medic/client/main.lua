-- jrs_medic | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_medic | client
-- Station blips and prompts for doctors, the menus (duty, teleport, hire/fire), healing animations and
-- the map marker for an emergency call. The server checks every action.

local Core = exports.jrs_core:GetCore()
local Menu = exports.jrs_core:GetMenuData()
local Text = Config.Text[Config.Language] or Config.Text.en
local TextEn = Config.Text.en

local group = GetRandomIntInRange(0, 0xffffff)
local prompt
local callBlip, callActive = nil, false

-- ------------------------------------------------------------------ who am I

local function myRank()
    local info = LocalPlayer.state.Character
    local grades = info and Config.Jobs[info.Job]
    return grades and grades[info.Grade]
end

local function needDuty()
    if LocalPlayer.state.isMedicDuty then return true end
    Core.NotifyObjective(Text.notOnDuty, 5000)
    return false
end

local function anyoneClose()
    local here = GetEntityCoords(PlayerPedId())
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() and #(here - GetEntityCoords(GetPlayerPed(id))) < 3.0 then return true end
    end
    return false
end

-- ------------------------------------------------------------------ menus

local function menuOptions(title, sub, rows, onPick, onBack, first)
    Menu.CloseAll()
    Menu.Open('default', GetCurrentResourceName(), title, {
        title = Text.doctorMenu, subtext = sub, align = Config.MenuAlign, elements = rows,
        soundOpen = first == true, hideRadar = true, divider = true, fixedHeight = true,
        itemHeight = '4vh', skipOpenEvent = first ~= true,
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
            rows[#rows + 1] = { label = station.name, value = index, desc = Text.teleportTo .. ': ' .. station.name }
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
        DoScreenFadeIn(1000)
    end, nil, first)
end

local function hireMenu()
    local rows = {}
    for job, grades in pairs(Config.Jobs) do
        for grade, rank in pairs(grades) do
            rows[#rows + 1] = { label = Text.job .. ': ' .. rank.label, value = job, grade = grade, desc = Text.job .. ' ' .. rank.label }
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)

    menuOptions('hire', Text.sub, rows, function(data, menu)
        menu.close(true, true, true)
        local id = askPlayerId(Text.hirePlayer)
        if id then TriggerServerEvent('jrs_medic:server:hirePlayer', id, data.current.value, data.current.grade) end
    end)
end

local function bossMenu()
    menuOptions('boss', Text.hireFire, {
        { label = Text.hirePlayer, value = 'hire', desc = Text.hirePlayer },
        { label = Text.firePlayer, value = 'fire', desc = Text.firePlayer },
    }, function(data, menu)
        if data.current.value == 'hire' then
            hireMenu()
        else
            menu.close(true, true, true)
            local id = askPlayerId(Text.firePlayer)
            if id then TriggerServerEvent('jrs_medic:server:firePlayer', id) end
        end
    end, nil, true)
end

local function dutyMenu()
    local on = LocalPlayer.state.isMedicDuty
    local rows = {
        { label = on and Text.offDuty or Text.onDuty, value = 'duty', desc = on and Text.goOff or Text.goOn, footerText = Text.pressEnter },
    }
    if Config.UseTeleportMenu then
        rows[#rows + 1] = { label = Text.teleportTo, value = 'teleports', desc = Text.teleportAll, footerText = Text.pressEnter }
    end

    menuOptions('duty', Text.sub, rows, function(data, menu)
        if data.current.value == 'teleports' then return teleportMenu() end
        local nowOn = Core.Callback.TriggerAwait('jrs_medic:server:checkDuty')
        Core.NotifyObjective(nowOn and Text.nowOnDuty or Text.notOnDuty, 5000)
        menu.close(true, true, true)
    end, nil, true)
end

RegisterNetEvent('jrs_medic:Client:OpenMedicMenu', dutyMenu)

-- ------------------------------------------------------------------ stations: blips and prompts

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
                    if (kind ~= 'teleport' or Config.UseTeleportMenu) and #(here - station[kind]) <= (kind == 'storage' and 1.5 or Config.Reach) then
                        wait = 0
                        local label = kind == 'boss' and 'Boss Menu' or kind == 'storage' and 'Medical storage' or 'Teleport'
                        PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', label))

                        if pressed() then
                            if kind == 'boss' then
                                local rank = myRank()
                                if rank and rank.manager then bossMenu() else Core.NotifyObjective(Text.menuDenied, 5000) end
                            elseif kind == 'storage' then
                                if needDuty() then
                                    if anyoneClose() then Core.NotifyObjective(Text.playerNearby, 5000)
                                    else TriggerServerEvent('jrs_medic:Server:OpenStorage', index) end
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

RegisterNetEvent('jrs_medic:Client:JobUpdate', function() end)    -- the loop above reads the job every second

-- ------------------------------------------------------------------ healing

local function play(dict, clip)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do Wait(0) end
    end
    TaskPlayAnim(PlayerPedId(), dict, clip, 8.0, 8.0, 2000, 1, 0, false, false, false)
end

RegisterNetEvent('jrs_medic:Client:HealAnim', function() play('script_mp@player@healing', 'healing_male') end)
RegisterNetEvent('jrs_medic:Client:ReviveAnim', function() play('mech_revive@unapproved', 'revive') end)

RegisterNetEvent('jrs_medic:Client:HealPlayer', function(health, stamina)
    local ped = PlayerPedId()
    if health and health > 0 then
        local core = GetAttributeCoreValue(ped, 0)
        if core > 99 then
            SetEntityHealth(ped, math.floor(GetPlayerHealth(PlayerId())) + 100 + health, 0)
        else
            SetAttributeCoreValue(ped, 0, core + health)
        end
    end
    if stamina and stamina > 0 then
        local core = GetAttributeCoreValue(ped, 1)
        if core > 99 then ChangePedStamina(ped, stamina + 0.0) else SetAttributeCoreValue(ped, 1, core + stamina) end
    end
end)

-- ------------------------------------------------------------------ emergency call marker

local function clearCall()
    if callBlip then RemoveBlip(callBlip) callBlip = nil end
    callActive = false
    ClearGpsMultiRoute()
end

RegisterNetEvent('jrs_medic:Client:AlertDoctor', function(at)
    if callActive then return end                                   -- one call at a time
    callActive = true

    local look = Config.Blips.call
    callBlip = Citizen.InvokeNative(0x554D9D53F696D002, joaat(look.style), at.x, at.y, at.z)
    SetBlipSprite(callBlip, joaat(look.sprite), true)
    Citizen.InvokeNative(0x9CB1A1623062F402, callBlip, TextEn.callName)
    Citizen.InvokeNative(0x662D364ABF16DE2F, callBlip, joaat(look.color))

    StartGpsMultiRoute(joaat('COLOR_RED'), true, true)
    AddPointToGpsMultiRoute(at.x, at.y, at.z, false)
    SetGpsMultiRouteRender(true)

    while callActive and #(GetEntityCoords(PlayerPedId()) - at) >= 15.0 do Wait(1000) end
    if callActive then
        Core.NotifyObjective(Text.arrived, 5000)
        clearCall()
    end
end)

RegisterNetEvent('jrs_medic:Client:RemoveBlip', clearCall)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearCall()
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)
