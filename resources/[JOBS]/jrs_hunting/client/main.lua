-- jrs_hunting | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_hunting | client
-- Butcher NPCs and menu, stowing pelts on the horse, and reporting animals the player skins in the field.
-- Everything is paid by the server; this file only finds out what the player is carrying.

local Core = exports.jrs_core:GetCore()
local Menu = exports.jrs_core:GetMenuData()
local Game <const> = Import 'events'

local Text, TextEn = Config.Text[Config.Language] or Config.Text.en, Config.Text.en
local group = GetRandomIntInRange(0, 0xffffff)
local prompt
local busy = false                 -- a menu or a sale is in progress
local stowed = {}                  -- pelts this player has put on the horse (count matters, not content)

-- ------------------------------------------------------------------ what is carried / ridden

local function carrying(ped) return Citizen.InvokeNative(0xD806CD2A4F2C2996, ped) end     -- entity or false
local function quality(entity) return Citizen.InvokeNative(0x31FEF6A20F00B963, entity) end  -- carriable quality hash
local function lastHorse(ped) return Citizen.InvokeNative(0x4C8B59171957BCF7, ped) end

local function ownHorse(ped)
    local horse = lastHorse(ped)
    if horse and horse ~= 0 and DoesEntityExist(horse) and NetworkGetEntityOwner(horse) == PlayerId() then
        return horse
    end
end

-- finds which animal a pelt of this quality belongs to
local function peltModel(q)
    for _, def in ipairs(Config.Butchered) do
        local k = def.quality
        if q == k.poor or q == k.good or q == k.perfect then return def.model end
    end
end

local byModel = {}
for _, def in ipairs(Config.Butchered) do byModel[def.model] = def end
local skinnable = {}
for _, def in ipairs(Config.Skinnable) do skinnable[def.model] = def end

-- ------------------------------------------------------------------ selling

local function sell(kind, data)
    return Core.Callback.TriggerAwait('jrs_hunting:sell', kind, data) == true
end

local function sellCarried(ped)
    local entity = carrying(ped)
    if not entity then return false, 'nothing' end

    local model = GetEntityModel(entity)
    if byModel[model] then                                       -- a whole animal
        SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(entity), true)
        if not NetworkHasControlOfEntity(entity) then NetworkRequestControlOfEntity(entity) end
        return sell('carcass', { model = model, netid = NetworkGetNetworkIdFromEntity(entity) }) and true or false, 'carcass'
    end

    local q = quality(entity)                                    -- a pelt
    local pelt = q and peltModel(q)
    if pelt and sell('pelt', { model = pelt, quality = q }) then
        DeleteEntity(entity)
        return true, 'pelt'
    end
    return false, 'wont'
end

local function sellHorsePelts(ped)
    local horse = ownHorse(ped)
    local sold = false
    if not horse then return false end

    -- a pelt or animal the horse is carrying right now
    local onHorse = Citizen.InvokeNative(0xA911EE21EDF69DAF, horse) and carrying(horse)
    if onHorse then
        local model = GetEntityModel(onHorse)
        if byModel[model] then
            sold = sell('carcass', { model = model, netid = NetworkGetNetworkIdFromEntity(onHorse) }) or sold
        else
            local q = quality(onHorse)
            local pelt = q and peltModel(q)
            if pelt and sell('pelt', { model = pelt, quality = q }) then
                DeleteEntity(onHorse)
                sold = true
            end
        end
    end

    -- the pelts stowed on the saddle, last one first
    for slot = #stowed, 1, -1 do
        local q = Citizen.InvokeNative(0x0CEEB6F4780B1F2F, horse, slot - 1)
        local pelt = q and peltModel(q)
        if pelt and sell('pelt', { model = pelt, quality = q }) then
            Citizen.InvokeNative(0x627F7F3A0C4C51FF, horse, q)           -- take it off the horse
            sold = true
        end
        table.remove(stowed, slot)
    end
    return sold
end

local function runSale(mode)
    local ped = PlayerPedId()
    local sold, why = false, nil

    if mode == 'hand' then
        sold, why = sellCarried(ped)
    else
        sold = sellHorsePelts(ped)
    end

    if not sold then
        Core.NotifyObjective(why == 'wont' and Text.wontBuy or Text.nothingToSell, 4000)
    end
    SetTimeout(5000, function() busy = false end)
end

-- ------------------------------------------------------------------ butcher menu

local function openMenu(shop)
    Menu.CloseAll()
    Menu.Open('default', GetCurrentResourceName(), 'butcher', {
        title = Text.menuTitle,
        subtext = shop.name,
        align = 'top-left',
        elements = {
            { label = Text.sellCarried, value = 'hand',  desc = Text.sellCarriedDesc },
            { label = Text.sellHorse,   value = 'horse', desc = Text.sellHorseDesc },
            { label = Text.close,       value = 'close', desc = '' },
        },
    }, function(data, menu)
        local pick = data.current and data.current.value
        menu.close()
        if pick == 'hand' or pick == 'horse' then
            CreateThread(function() runSale(pick) end)
        else
            busy = false
        end
    end, function(_, menu)
        menu.close()
        busy = false
    end)
end

-- ------------------------------------------------------------------ butcher NPCs and blips

local shown = {}      -- shop index -> { ped, blip }

local function startShops()
    for i, shop in ipairs(Config.Butchers) do
        local entry = {}
        if Config.ButcherPeds and shop.ped ~= '' then
            local model = joaat(shop.ped)
            if IsModelValid(model) then
                RequestModel(model, false)
                while not HasModelLoaded(model) do Wait(50) end
                local ped = CreatePed(model, shop.at.x, shop.at.y, shop.at.z, shop.heading, false, false, false, false)
                repeat Wait(0) until DoesEntityExist(ped)
                Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
                PlaceEntityOnGroundProperly(ped, true)
                SetEntityCanBeDamaged(ped, false)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                Wait(500)
                FreezeEntityPosition(ped, true)
                entry.ped = ped
            else
                print(('[jrs_hunting] %s is not a valid model'):format(shop.ped))
            end
        end
        if shop.blip then
            entry.blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, shop.at)
            SetBlipSprite(entry.blip, Config.BlipSprite, true)
            Citizen.InvokeNative(0x9CB1A1623062F402, entry.blip, shop.name)
        end
        shown[i] = entry
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, entry in pairs(shown) do
        if entry.ped then DeleteEntity(entry.ped) end
        if entry.blip then RemoveBlip(entry.blip) end
    end
end)

-- ------------------------------------------------------------------ prompt

local function makePrompt()
    prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, Config.PromptKey)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', TextEn.press))   -- game font: English only
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetStandardMode(prompt, true)
    PromptSetHoldMode(prompt, true)
    PromptSetGroup(prompt, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, prompt, true)
    PromptRegisterEnd(prompt)
end

local function pressed() return Citizen.InvokeNative(0xC92AC953F0A982AE, prompt) end
local function title(text) PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', text)) end

-- at a butcher: open the menu
CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(1000) end
    makePrompt()
    if not Config.UseButchers then return end
    startShops()

    while true do
        local wait = 1000
        local here = GetEntityCoords(PlayerPedId())
        for _, shop in ipairs(Config.Butchers) do
            if #(here - shop.at) <= shop.radius then
                wait = 0
                title(shop.name ~= '' and shop.name or TextEn.butcher)
                if pressed() and not busy then
                    busy = true
                    if not Config.JobLocked or Core.Callback.TriggerAwait('jrs_hunting:GetPlayerJob') == shop.job then
                        openMenu(shop)
                    else
                        Core.NotifyObjective(Text.wrongJob, 4000)
                        busy = false
                    end
                end
                break
            end
        end
        Wait(wait)
    end
end)

-- next to the horse holding a pelt: stow it
CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(1000) end
    Citizen.InvokeNative(0x39363DFD04E91496, PlayerId(), true)          -- mercy kills on

    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local horse = lastHorse(ped)
        local item = horse and horse ~= 0 and carrying(ped)

        if item and #(GetEntityCoords(ped) - GetEntityCoords(horse)) < 2.0
           and not byModel[GetEntityModel(item)] and #stowed < Config.MaxPeltsOnHorse then
            wait = 0
            title(TextEn.stow)
            if pressed() then
                TaskPlaceCarriedEntityOnMount(ped, item, horse, 1)
                stowed[#stowed + 1] = { quality = quality(item) }
                Wait(500)
            end
        end
        Wait(wait)
    end
end)

-- ------------------------------------------------------------------ skinning in the field

local watcher = Game.Events:Register('EVENT_LOOT_COMPLETE', 0, function(args)
    local looter, animal, finished = args[1], args[2], args[3]
    if finished ~= 1 or looter ~= PlayerPedId() then return end

    local model = GetEntityModel(animal)
    local def = model and skinnable[model]
    if not def then return end

    CreateThread(function()                                              -- this callback must not wait
        if def.deletePelt then
            Wait(1000)
            local held = carrying(PlayerPedId())
            if held and GetIsCarriablePelt(held) == 1 and GetIsAnimal(held) ~= 1 then
                SetEntityAsMissionEntity(held, true, true)
                DeleteEntity(held)
            end
        end
        Core.Callback.TriggerAwait('jrs_hunting:sell', 'skinned', { model = model })
    end)
end, false)

RegisterNetEvent('jrs:SelectedCharacter', function() watcher:Start() end)
AddEventHandler('jrs_core:Client:OnPlayerDeath', function() watcher:Pause() end)
RegisterNetEvent('jrs_core:Client:OnPlayerRevive', function() watcher:Resume() end)

-- ------------------------------------------------------------------ developer helpers

if Config.DevMode then
    RegisterCommand('animal', function()                                 -- what am I holding?
        local ped = PlayerPedId()
        local held = carrying(ped)
        print('holding', held, 'model', held and GetEntityModel(held), 'quality', held and quality(held))
    end, false)

    RegisterCommand('hunt', function(_, args)                            -- /hunt [model] [freeze ms]
        local name = args[1] or 'a_c_goat_01'
        local model = joaat(name)
        RequestModel(model, false)
        while not HasModelLoaded(model) do Wait(10) end
        local here = GetEntityCoords(PlayerPedId())
        local animal = CreatePed(model, here.x, here.y, here.z, 0.0, true, false, false, false)
        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, animal, 1, 0)
        Wait(tonumber(args[2]) or 2000)
        FreezeEntityPosition(animal, true)
    end, false)
end
