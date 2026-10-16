-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | client
-- Rental shops: a clerk and blip per store, open during the store's hours. Standing at the clerk (or the
-- counter) opens the rental menu.

local state = { IsBusy = false, Loaded = false, LocationIndex = nil }

function GetPlayerData() return state end

-- is the store open at the current game hour? (closing before opening means it runs past midnight)
local function isOpen(store)
    local hours = store.Hours
    if not hours.Allowed then return true end
    local now = GetClockHours()
    if hours.Opening < hours.Closing then return now >= hours.Opening and now < hours.Closing end
    return now >= hours.Opening or now < hours.Closing
end

local function dropClerk(store)
    JRS.RemoveEntity(store.NPC, joaat(store.NPCData.Model))
    store.NPC = nil
end

-- keeps the blip in line with the opening hours
local function updateBlip(id, store, open)
    if not store.BlipData.Allowed then return end
    local closedLook = store.BlipData.DisplayClosedHours

    if open ~= store.IsAllowed and store.BlipHandle then
        RemoveBlip(store.BlipHandle)
        store.BlipHandle, store.IsAllowed = nil, open
    end
    if not store.BlipHandle and (open or (closedLook and closedLook.Enabled)) then
        AddBlip(id, open and 'OPEN' or 'CLOSED')
        store.IsAllowed = open
    end
end

CreateThread(function()
    CreatePromptRegistration()

    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local dead = IsEntityDead(ped)

        if dead and state.IsBusy then
            TriggerEvent('jrs_canoe:client:close')
            if state.LocationIndex then TriggerServerEvent('jrs_canoe:server:setBusyState', state.LocationIndex, false) end
        end

        if not state.IsBusy and not dead then
            local here = GetEntityCoords(ped)

            for id, store in pairs(Config.Stores) do
                local away = #(here - vector3(store.Coords.x, store.Coords.y, store.Coords.z))
                if store.NPC and away > Config.NPCRenderingSpawnDistance then dropClerk(store) end

                local open = isOpen(store)
                updateBlip(id, store, open)
                if store.NPC and not open then dropClerk(store) end

                if open then
                    if not store.NPC and store.NPCData.Allowed and away <= Config.NPCRenderingSpawnDistance then SpawnNPC(id) end

                    if away <= store.DistanceOpenStore and (not store.useInteractPrompt or not store.NPC) then
                        wait = 0
                        local group, prompt = GetPromptData()
                        PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', store.PromptName))
                        if PromptHasHoldModeCompleted(prompt) then
                            OpenCanoeRentingShop(id, store.City)
                            Wait(1000)
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)
