-- jrs_saloons | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_saloons | client
-- Map blips for every saloon and a "open storage" prompt at the storage point, for the saloon's own staff.

local promptGroup = GetRandomIntInRange(0, 0xffffff)
local prompt

local function makePrompt()
    prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, Config.PromptKey)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', Config.Text.press))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, promptGroup)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, prompt, true)
    PromptRegisterEnd(prompt)
end

local function addBlips()
    if not Config.ShowBlips then return end
    for _, s in ipairs(Config.Saloons) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, s.blip.x, s.blip.y, s.blip.z)
        SetBlipSprite(blip, s.sprite or Config.BlipSprite, true)
        SetBlipScale(blip, 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, 'LITERAL_STRING', s.name))
    end
end

local function myJob()
    local state = LocalPlayer.state
    return state.Character and state.Character.Job
end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(1000) end
    addBlips()
    makePrompt()

    while true do
        local wait = 1000
        local here = GetEntityCoords(PlayerPedId())
        local job = myJob()

        for _, s in ipairs(Config.Saloons) do
            if job == s.job and #(here - s.storage) < Config.UseDistance then
                wait = 0
                PromptSetActiveGroupThisFrame(promptGroup,
                    CreateVarString(10, 'LITERAL_STRING', Config.Text.storage .. s.name))
                if Citizen.InvokeNative(0xC92AC953F0A982AE, prompt) then
                    TriggerServerEvent('jrsSaloon:GetInventory', s.job)
                    Wait(500)
                end
                break
            end
        end

        Wait(wait)
    end
end)
