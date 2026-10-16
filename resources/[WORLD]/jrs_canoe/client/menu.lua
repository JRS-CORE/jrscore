-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | client: the rental menu. Renting a canoe makes the clerk build it, which takes a while.

local MenuData = exports.jrs_core:GetMenuData()

local BUILD_MS <const> = 22000

local function leave(index)
    local state = GetPlayerData()
    MenuData.CloseAll()
    state.IsBusy, state.LocationIndex = false, nil
    TaskStandStill(PlayerPedId(), 1)
    if index then TriggerServerEvent('jrs_canoe:server:setBusyState', index, false) end
end

local function rent(pick)
    local store = GetPlayerData().LocationIndex
    local ok = JRS.Await('jrs_canoe:canRentSelectedBoat', { model = pick.model, name = pick.name, index = store, vehicle_index = pick.index })
    if not ok then return end

    local spawn = Config.Stores[store].SpawnCoords
    TriggerServerEvent('jrs_canoe:server:start_building', store)
    Wait(BUILD_MS)

    LoadModel(pick.model)
    local boat = CreateVehicle(pick.model, spawn.x, spawn.y, spawn.z, spawn.h, true, false)
    Citizen.InvokeNative(0x283978A15512B2FE, boat, true)
    SetModelAsNoLongerNeeded(pick.model)

    TriggerServerEvent('jrs_canoe:server:setBusyState', store, false)
    SendNotification(nil, Locales['CANOE_READY'])
end

function OpenCanoeRentingShop(index, title)
    MenuData.CloseAll()
    local store = Config.Stores[index]

    if JRS.Await('jrs_canoe:getStoreStatus', { index = index }) then
        return SendNotification(nil, Locales['STORE_BUSY'])
    end

    -- a canoe is still standing where the new one would be built
    local waiting = GetClosestVehicle(store.SpawnCoords)
    if IsModelCanoe(GetEntityModel(waiting)) then
        return SendNotification(nil, Locales['STORE_PICKUP'])
    end

    local state = GetPlayerData()
    state.IsBusy, state.LocationIndex = true, index
    TaskStandStill(PlayerPedId(), -1)
    TriggerServerEvent('jrs_canoe:server:setBusyState', index, true)
    TriggerEvent('jrs_canoe:client:menu_tasks')

    local rows = {}
    for key, canoe in pairs(store.Canoes) do
        rows[#rows + 1] = {
            label = canoe.Title, rightLabel = '$' .. tostring(canoe.Cost),
            image = 'nui://jrs_canoe/html/img/' .. canoe.ImageBackground,
            desc = ('%s: %s'):format(canoe.DescriptionTitle, canoe.Description),
            value = key, index = key, model = canoe.Model, name = canoe.Title,
        }
    end
    rows[#rows + 1] = { value = 'exit', label = Locales['MENU_EXIT'], desc = '' }

    MenuData.Open('default', GetCurrentResourceName(), 'canoes',
        { title = title, subtext = '', align = 'top-left', elements = rows, lastmenu = 'notMenu' },
        function(data, menu)
            if data.current == 'backup' or data.current.value == 'exit' then
                menu.close()
                return leave(index)
            end
            local pick = data.current
            CreateThread(function() rent(pick) end)
        end,
        function(_, menu)
            menu.close()
            leave(index)
        end)
end

RegisterNetEvent('jrs_canoe:client:close', function() leave() end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and GetPlayerData().IsBusy then MenuData.CloseAll() end
end)

-- everybody near the store sees the clerk hammer a half-built canoe together
RegisterNetEvent('jrs_canoe:client:start_building', function(data)
    local store = Config.Stores[data.index]
    local frame = 'p_canoeconst01x'
    local dict, anim = 'amb_work@world_human_hammer@table@male_a@idle_b', 'idle_e'

    LoadModel(frame)
    local spawn = store.SpawnCoords
    local unfinished = CreateObject(frame, spawn.x, spawn.y, spawn.z, false, false)
    SetEntityHeading(unfinished, spawn.h)
    Wait(250)
    FreezeEntityPosition(unfinished, true)

    JRS.PlayAnimation(store.NPC, { dict = dict, name = anim, blendInSpeed = 1.0, blendOutSpeed = 1.0, duration = -1, flag = 31, playbackRate = 0.0 })
    Wait(19000)
    JRS.RemoveEntity(unfinished, joaat(frame))
    Wait(1000)
    StopAnimTask(store.NPC, dict, anim, 31)
end)

-- the radar stays off while the menu is up
AddEventHandler('jrs_canoe:client:menu_tasks', function()
    CreateThread(function()
        while GetPlayerData().IsBusy do
            Wait(1)
            DisplayRadar(false)
        end
    end)
end)
