-- jrs_stores | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_stores | client: the shops on the map
-- Blips, the clerk NPC near each shop, the "open shop" prompt (with the job and opening-hours rules),
-- and the live price/location refresh pushed by the server. The page itself is StoresUI (nui.lua).

local Core = exports.jrs_core:GetCore()
local T = setmetatable({}, { __index = function(_, key) return StoresShared.Text(nil, key) end })

local prompt, group = nil, GetRandomIntInRange(0, 0xffffff)
local OPEN_COLOUR, CLOSED_COLOUR = joaat('BLIP_MODIFIER_MP_COLOR_32'), joaat('BLIP_MODIFIER_MP_COLOR_2')

-- ------------------------------------------------------------------ rules

-- may this player use the shop (no job list = everybody)
local function jobAllows(shop)
    if not next(shop.AllowedJobs) then return true end
    local who = LocalPlayer.state.Character or {}
    local job = who.Job or who.job
    local grade = tonumber(who.Grade or who.jobGrade or who.grade) or 0
    for _, allowed in ipairs(shop.AllowedJobs) do
        if allowed == job and grade >= shop.JobGrade then return true end
    end
    return false
end

-- shops that close after midnight (open 18, close 4) are handled too
local function isClosed(shop)
    local hour = GetClockHours()
    local open, close = shop.StoreOpen, shop.StoreClose
    if close < open then return not (hour >= open or hour < close) end
    return not (hour >= open and hour < close)
end

-- ------------------------------------------------------------------ blip and clerk

local function placeBlip(shop)
    local at = shop.Blip.Pos
    local handle = BlipAddForCoords(1664425300, at.x, at.y, at.z)
    SetBlipSprite(handle, shop.Blip.sprite, false)
    BlipAddModifier(handle, OPEN_COLOUR)
    SetBlipName(handle, shop.Blip.Name)
    shop.Blip.BlipHandle = handle
end

local function spawnClerk(id, shop)
    local model = shop.Npc.Model
    if not IsModelValid(model) then
        return print(('Invalid npc model for %s (%s).'):format(id, tostring(model)))
    end
    RequestModel(model, false)
    while not HasModelLoaded(model) do Wait(100) end

    local at = shop.Npc.Pos
    local ped = CreatePed(model, at.x, at.y, at.z, at.w, false, false, false, false)
    repeat Wait(100) until DoesEntityExist(ped)
    SetRandomOutfitVariation(ped, true)
    PlaceEntityOnGroundProperly(ped)
    SetEntityCanBeDamaged(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    shop.Npc.NpcHandle = ped
end

local function removeClerk(shop)
    if shop.Npc.NpcHandle then
        DeleteEntity(shop.Npc.NpcHandle)
        shop.Npc.NpcHandle = nil
    end
end

-- ------------------------------------------------------------------ prompt

local function makePrompt()
    prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, Config.Key)
    UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', T.SubPrompt))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    UiPromptSetStandardMode(prompt, true)
    UiPromptSetGroup(prompt, group, 0)
    UiPromptRegisterEnd(prompt)
end

-- shows the prompt for one shop; true when the player pressed it
local function offer(label)
    UiPromptSetActiveGroupThisFrame(group, VarString(10, 'LITERAL_STRING', label), 0, 0, 0, 0)
    if UiPromptHasStandardModeCompleted(prompt, 0) then
        Wait(100)
        return true
    end
    return false
end

-- ------------------------------------------------------------------ one shop, one pass of the loop

-- returns true while the player stands close enough that the loop must run every frame
local function tend(id, shop, closed)
    local distance = #(GetEntityCoords(PlayerPedId()) - shop.Blip.Pos)

    if shop.Blip.Allowed then
        if not shop.Blip.BlipHandle then placeBlip(shop) end
        BlipAddModifier(shop.Blip.BlipHandle, closed and CLOSED_COLOUR or OPEN_COLOUR)
    end

    if shop.Npc.Allowed then
        if not closed and distance < shop.Npc.distanceRemoveNpc then
            if not shop.Npc.NpcHandle then spawnClerk(id, shop) end
        else
            removeClerk(shop)
        end
    end

    local near = distance <= shop.distanceOpenStore
    if not near then return false end

    if closed then
        UiPromptSetEnabled(prompt, false)
        return true
    end
    UiPromptSetEnabled(prompt, true)

    if jobAllows(shop) and offer(shop.PromptName) then
        StoresUI.Open(id)
    end
    return true
end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(2000) end
    makePrompt()

    while true do
        local wait = 1000
        if not IsEntityDead(PlayerPedId()) and not StoresUI.IsOpen() then
            for id, shop in pairs(Config.Stores) do
                if not shop.isDeactivated then
                    local closed = shop.StoreHoursAllowed and isClosed(shop)
                    if tend(id, shop, closed) then wait = 0 end
                end
            end
        end
        Wait(wait)
    end
end)

-- ------------------------------------------------------------------ events for other resources and the server

-- switch a shop on or off, e.g. from a command
RegisterNetEvent('jrs_stores:Server:ChangeStoreStatus', function(id, status)
    if not Config.Stores[id] then return print('Store not found in jrs stores configs') end
    Config.Stores[id].isDeactivated = status
end)

-- open a shop from another script (the player must stand at it: the server checks)
AddEventHandler('jrs_stores:Client:OpenShop', function(id) StoresUI.Open(id) end)

-- fresh prices and shop locations from the server; keep the blip and clerk handles we already hold
RegisterNetEvent('jrs_stores:RefreshStorePrices', function(packed)
    if type(packed) ~= 'table' then return end
    if type(packed.sell) == 'table' then Config.SellItems = packed.sell end
    if type(packed.buy) == 'table' then Config.BuyItems = packed.buy end

    for id, fresh in pairs(packed.stores or {}) do
        local old = Config.Stores[id]
        if old then
            fresh.Blip.BlipHandle = old.Blip.BlipHandle
            fresh.Npc.NpcHandle = old.Npc.NpcHandle
            Config.Stores[id] = fresh
        end
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(1000)
    TriggerServerEvent('jrs_stores:GetRefreshedPrices')
end)

AddEventHandler('jrs_core:language:changed', function()
    if prompt then UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', T.SubPrompt)) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if prompt then UiPromptDelete(prompt) end
    for _, shop in pairs(Config.Stores) do
        removeClerk(shop)
        if shop.Blip.BlipHandle then RemoveBlip(shop.Blip.BlipHandle) end
    end
end)
