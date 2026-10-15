-- jrs_mailbox | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_mailbox | client
-- Post office clerks with blips, a prompt next to them, and the page. The page does the writing;
-- the server stores, charges and checks.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local group = GetRandomIntInRange(0, 0xffffff)
local readPrompt, shoutPrompt
local isOpen = false
local clerks, blips = {}, {}

-- ------------------------------------------------------------------ small helpers

local function tip(line, ms)
    if line and #line > 0 then TriggerEvent('jrs:Tip', line, ms) end
end

local function fill(line, vars)
    for key, value in pairs(vars) do line = line:gsub('{' .. key .. '}', (tostring(value):gsub('%%', '%%%%'))) end
    return line
end

local function makePrompt(key, label)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, key)
    PromptSetText(p, CreateVarString(10, 'LITERAL_STRING', label))
    PromptSetEnabled(p, true)
    PromptSetVisible(p, true)
    PromptSetStandardMode(p, true)
    PromptSetGroup(p, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, p, true)
    PromptRegisterEnd(p)
    return p
end

local function pressed(p) return Citizen.InvokeNative(0xC92AC953F0A982AE, p) end

-- ------------------------------------------------------------------ the page

local function open(mode)
    if isOpen then return end
    isOpen = true

    local inbox, people = {}, {}
    if mode == 'inbox' then
        inbox = Core.Callback.TriggerAwait('jrs_mailbox:inbox') or {}
        people = Core.Callback.TriggerAwait('jrs_mailbox:directory') or {}
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open', mode = mode, text = Text, rtl = Config.Language == 'ar',
        letters = inbox, people = people,
    })
end

RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    isOpen = false
    cb('ok')
end)

RegisterNUICallback('update', function(data, cb)
    TriggerServerEvent('jrs_mailbox:update', { delete = data.delete, read = data.read })
    cb('ok')
end)

RegisterNUICallback('send', function(data, cb)
    cb(Core.Callback.TriggerAwait('jrs_mailbox:send', data.to, data.message) == true)
end)

RegisterNUICallback('shout', function(data, cb)
    cb(Core.Callback.TriggerAwait('jrs_mailbox:shout', data.message) == true)
end)

-- ------------------------------------------------------------------ messages from the server

RegisterNetEvent('jrs_mailbox:got', function(name)
    tip(fill(Text.received, { name = name }), 5000)
end)

RegisterNetEvent('jrs_mailbox:shouted', function(name, message)
    tip(fill(Text.shouted, { name = name, message = message }), 20000)
end)

-- ------------------------------------------------------------------ clerks and blips

local function nearOffice(here)
    for _, office in ipairs(Config.Offices) do
        if #(here - vector3(office.at.x, office.at.y, office.at.z)) < Config.UseDistance then return true end
    end
end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(500) end
    Wait(300)

    local model = joaat(Config.ClerkModel)
    if not IsModelValid(model) then
        print(('[jrs_mailbox] model %s is not valid, using the player model'):format(Config.ClerkModel))
        model = GetEntityModel(PlayerPedId())
    end
    RequestModel(model, false)
    while not HasModelLoaded(model) do Wait(50) end

    for _, office in ipairs(Config.Offices) do
        local at = office.at
        local ped = CreatePed(model, at.x, at.y, at.z - 1.0, at.w, false, false, false, false)
        repeat Wait(100) until DoesEntityExist(ped)
        Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
        PlaceEntityOnGroundProperly(ped)
        SetEntityCanBeDamaged(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        SetPedCanRagdoll(ped, false)
        clerks[#clerks + 1] = ped

        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, at.x, at.y, at.z)
        Citizen.InvokeNative(0x74F74D3207ED525C, blip, Config.BlipSprite, 1)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, Config.BlipName)
        blips[#blips + 1] = blip
    end
    SetModelAsNoLongerNeeded(model)

    readPrompt = makePrompt(Config.ReadKey, Text.read)
    shoutPrompt = makePrompt(Config.BroadcastKey, Text.shout)

    while true do
        local wait = 1000
        if not isOpen and nearOffice(GetEntityCoords(PlayerPedId())) then
            wait = 0
            PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', Text.prompt))
            if pressed(readPrompt) then
                CreateThread(function() open('inbox') end)
                Wait(300)
            elseif pressed(shoutPrompt) then
                CreateThread(function() open('shout') end)
                Wait(300)
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    for _, ped in ipairs(clerks) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    for _, blip in ipairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
end)
