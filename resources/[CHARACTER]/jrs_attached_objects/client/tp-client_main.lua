-- jrs_attached_objects | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_attached_objects | client
-- Using an item attaches a set of props to the ped's bones; using it again (or /command) takes them off.

local worn = {}                    -- list of { type = set name, entities = { { entity, model }, ... } }

local function wornSet(setName)
    for _, set in ipairs(worn) do
        if set.type == setName then return set end
    end
end

local function stopTasks(ped)
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
end

local function removeSet(set, pause)
    for _, prop in ipairs(set.entities) do
        if pause then Wait(pause) end
        RemoveEntityProperly(prop.entity, joaat(prop.model))
    end
end

local function takeOff(setName)
    local set = wornSet(setName)
    if not set then return end
    removeSet(set, 100)
    Wait(1000)
    for i = #worn, 1, -1 do
        if worn[i] == set then table.remove(worn, i) end
    end
end

local function putOn(setName, parts)
    local ped = PlayerPedId()
    stopTasks(ped)
    Citizen.InvokeNative(0xFCCC886EDE3C63EC, ped, 2, 1)          -- holster whatever the ped holds

    local at = GetEntityCoords(ped)
    local made = {}
    for _, part in pairs(parts) do
        LoadModel(part.EntityObject)
        local prop = CreateObject(part.EntityObject, at.x, at.y, at.z, 0.2, true, true, false, false, true)
        made[#made + 1] = { entity = prop, model = part.EntityObject }

        local bone = GetEntityBoneIndexByName(ped, part.Attachment)
        AttachEntityToEntity(prop, ped, bone, part.x, part.y, part.z, part.xRot, part.yRot, part.zRot, true, true, false, true, 1, true)
        Wait(100)
    end
    worn[#worn + 1] = { type = setName, entities = made }
end

local function toggle(setName)
    Wait(1000)
    local parts = Config.AttachedItemSets[setName]
    if not parts then
        return print(('This attached prop item set type (%s) does not exist'):format(setName))
    end
    if wornSet(setName) then
        stopTasks(PlayerPedId())
        takeOff(setName)
    else
        putOn(setName, parts)
    end
end

function ClearAllPlayerPedAttachedProps()
    if #worn == 0 then return end
    for _, set in ipairs(worn) do removeSet(set) end
    stopTasks(PlayerPedId())
    worn = {}
end

RegisterNetEvent('jrs_attached_objects:client:attach', toggle)

RegisterNetEvent('jrs_core:Client:OnPlayerSpawned', function()
    if Config.DeleteAllOnPlayerRespawn then ClearAllPlayerPedAttachedProps() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then ClearAllPlayerPedAttachedProps() end
end)
