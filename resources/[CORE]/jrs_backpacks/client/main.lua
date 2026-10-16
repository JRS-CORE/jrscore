-- jrs_backpacks | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local worn, wornItem = nil, nil

local function removeProp()
    if worn and DoesEntityExist(worn) then
        -- delete while still attached (a detached prop that fails to delete stays in the world)
        DeleteObject(worn)
        if DoesEntityExist(worn) then DeleteEntity(worn) end
    end
    worn, wornItem = nil, nil
end

local function wear(item)
    if wornItem == item and worn and DoesEntityExist(worn) then return end
    removeProp()
    local cfg = item and Config.ByItem[item]
    if not cfg or not JRS.LoadModel(cfg.model) then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local model = joaat(cfg.model)
    local prop = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, ped, GetEntityBoneIndexByName(ped, 'CP_Back'),
        cfg.position.x, cfg.position.y, cfg.position.z, cfg.rotation.x, cfg.rotation.y, cfg.rotation.z,
        true, true, false, true, 1, true)
    worn, wornItem = prop, item
end

RegisterNetEvent('jrs_backpacks:client:wear', wear)

CreateThread(function()
    Wait(5000)
    while true do
        local ped = PlayerPedId()
        if IsEntityDead(ped) then
            removeProp()
        else
            local item = JRS.Await('jrs_backpacks:carried')
            if item then wear(item) else removeProp() end
        end
        Wait(Config.WearCheck * 1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then removeProp() end
end)
