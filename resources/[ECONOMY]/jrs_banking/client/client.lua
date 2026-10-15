-- jrs_banking | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_banking | client: banks on the map
-- Blips (greyed out while a bank is shut), the clerk NPC that appears when you come near, and the prompt
-- that opens the bank page (BankUI, see nui.lua). Opening hours follow the in-game clock.

local Core = exports.jrs_core:GetCore()
local T = BankTranslation.For()

local openGroup  = GetRandomIntInRange(0, 0xffffff)
local closedGroup = GetRandomIntInRange(0, 0xffffff)
local openPrompt, closedPrompt

local blip, clerk = {}, {}            -- bank key -> blip handle / clerk ped

local OPEN_COLOUR   = joaat('BLIP_MODIFIER_MP_COLOR_32')
local CLOSED_COLOUR = joaat('BLIP_MODIFIER_MP_COLOR_10')

-- ------------------------------------------------------------------ small helpers

local function placeOf(bank)
    local p = bank.BankLocation
    return vector3(p.x, p.y, p.z)
end

local function isOpen(bank)
    if not bank.StoreHoursAllowed then return true end
    local hour = GetClockHours()
    return hour >= bank.StoreOpen and hour < bank.StoreClose
end

local function makePrompt(group, label)
    local p = UiPromptRegisterBegin()
    UiPromptSetControlAction(p, Config.Key)
    UiPromptSetText(p, VarString(10, 'LITERAL_STRING', label))
    UiPromptSetEnabled(p, true)
    UiPromptSetVisible(p, true)
    UiPromptSetStandardMode(p, true)
    UiPromptSetGroup(p, group, 0)
    UiPromptRegisterEnd(p)
    return p
end

-- ------------------------------------------------------------------ blip and clerk

local function showBlip(key, bank, open)
    if not bank.blipAllowed then return end
    if not blip[key] then
        local at = placeOf(bank)
        blip[key] = BlipAddForCoords(1664425300, at.x, at.y, at.z)
        SetBlipSprite(blip[key], bank.blipsprite, true)
        SetBlipScale(blip[key], 0.2)
        SetBlipName(blip[key], bank.name)
    end
    BlipAddModifier(blip[key], open and OPEN_COLOUR or CLOSED_COLOUR)
end

local function removeClerk(key)
    local ped = clerk[key]
    if not ped then return end
    SetEntityAsNoLongerNeeded(ped)
    DeleteEntity(ped)
    clerk[key] = nil
end

local function spawnClerk(key, bank)
    local model = joaat(bank.NpcModel)
    RequestModel(model, false)
    while not HasModelLoaded(model) do Wait(0) end

    local at = bank.NpcPosition
    local ped = CreatePed(model, at.x, at.y, at.z, at.h, false, false, false, false)
    repeat Wait(0) until DoesEntityExist(ped)
    PlaceEntityOnGroundProperly(ped, true)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    Wait(1000)
    TaskStandStill(ped, -1)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetModelAsNoLongerNeeded(model)
    clerk[key] = ped
end

-- a clerk stands behind the counter while the bank is open and the player is within 40 m
local function tendClerk(key, bank, distance, open)
    if not bank.NpcAllowed then return end
    if open and distance <= 40.0 then
        if not clerk[key] then spawnClerk(key, bank) end
    else
        removeClerk(key)
    end
end

-- ------------------------------------------------------------------ main loop

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    openPrompt = makePrompt(openGroup, T.openmenu)
    closedPrompt = makePrompt(closedGroup, T.closemenu)

    while true do
        local wait = 1000

        if not BankUI.IsOpen() and not IsEntityDead(PlayerPedId()) then
            local here = GetEntityCoords(PlayerPedId())

            for key, bank in pairs(Config.banks) do
                local open = isOpen(bank)
                local distance = #(here - placeOf(bank))

                showBlip(key, bank, open)
                tendClerk(key, bank, distance, open)

                if distance <= bank.distOpen then
                    wait = 0
                    if open then
                        UiPromptSetActiveGroupThisFrame(openGroup, VarString(10, 'LITERAL_STRING', T.bank .. ' ' .. bank.name), 0, 0, 0, 0)
                        if UiPromptHasStandardModeCompleted(openPrompt, 0) then
                            CreateThread(function() BankUI.Open(bank.city) end)
                        end
                    else
                        local hours = ('%s %d%s - %d%s'):format(T.openHours, bank.StoreOpen, T.amTimeZone, bank.StoreClose, T.pmTimeZone)
                        UiPromptSetActiveGroupThisFrame(closedGroup, VarString(10, 'LITERAL_STRING', hours), 0, 0, 0, 0)
                        if UiPromptHasStandardModeCompleted(closedPrompt, 0) then
                            Wait(1000)
                            Core.NotifyRightTip(T.closed, 4000)
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('jrs_core:language:changed', function()
    T = BankTranslation.For()
    if openPrompt then UiPromptSetText(openPrompt, VarString(10, 'LITERAL_STRING', T.openmenu)) end
    if closedPrompt then UiPromptSetText(closedPrompt, VarString(10, 'LITERAL_STRING', T.closemenu)) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(clerk) do removeClerk(key) end
    for _, handle in pairs(blip) do RemoveBlip(handle) end
    BankUI.Close()
    if openPrompt then UiPromptDelete(openPrompt) end
    if closedPrompt then UiPromptDelete(closedPrompt) end
end)
