-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | developer tools: spawning, object inspection, the aim laser

local T = Translation.Current()

local aiming = false              -- the aim laser is on
local laserRunning = false
local watchScenario = false

local ADJUST_VARIATION = 0x77FF8D35EEC6BBC4
local AIM_COPY_INFO, AIM_COPY_COORDS = 0x24978A28, 0x760A9C6F       -- H and G

local function ahead(distance)
    return GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, distance or 5.0, 0.0)
end

local function placePed(model, fromList)
    local hash = AdminLoadModel(model)
    if not hash then return end
    local at = ahead()
    local ped = CreatePed(hash, at.x, at.y, at.z, 0.0, true, true, not fromList, false)
    if not AdminWaitEntity(ped) then return end
    Citizen.InvokeNative(ADJUST_VARIATION, ped, true, 0)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function placeWagon(model)
    local hash = AdminLoadModel(model)
    if not hash then return end
    local at = ahead()
    local wagon = CreateVehicle(hash, at.x, at.y, at.z, 0.0, true, true)
    if not AdminWaitEntity(wagon) then return end
    Citizen.InvokeNative(ADJUST_VARIATION, wagon, true, 0)
    SetPedIntoVehicle(PlayerPedId(), wagon, -1)
    SetModelAsNoLongerNeeded(hash)
    return wagon
end

local function toggleScenarioWatch()
    watchScenario = not watchScenario
    CreateThread(function()
        while watchScenario do
            Wait(1000)
            local ped = PlayerPedId()
            if IsPedUsingAnyScenario(ped) then print('scenario Hash', Citizen.InvokeNative(0x569F1E1237508DEB, ped)) end
        end
    end)
end

-- ------------------------------------------------------------------ the menu

function OpenDevTools()
    local O = T.Menus.MainDevToolsOptions
    MenuData.CloseAll(true, true, true)

    Kit.open('OpenDevTools', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleDevTools,
        back = 'OpenMenu',
        items = {
            { label = O.spawnPedWithList, value = 'pedlist', desc = O.spawnPedWithList_desc, go = function() SpawnPeds('peds') end },
            { label = O.spawnPedWithInput, value = 'spawnped', desc = O.spawnPedWithInput_desc, go = function()
                MenuData.CloseAll(true, true, true)
                Kit.ask(O.SpawnPedInput, '[A-Za-z0-9_ \\-]{5,60}', function(model) placePed(model) end, { empty = 3000 })
            end },
            { label = O.coordsMenu, value = 'getcoords', desc = O.coordsMenu_desc, go = function() OpenCoordsMenu() end },
            { label = O.spawnWagonWithInput, value = 'spawnwagon', desc = O.spawnWagonWithInput_desc, go = function()
                MenuData.CloseAll(true, true, true)
                Kit.ask(O.SpawnWagonInput, '[A-Za-z0-9_ \\-]{5,60}', function(model) placeWagon(model) end, { empty = 3000 })
            end },
            { label = O.spawnWagonWithList, value = 'wagonlist', desc = O.spawnWagonWithList_desc, go = function() SpawnPeds('wagons') end },
            { label = O.objectMenu, value = 'delobject', desc = O.objectMenu_desc, go = function() OpenObjMenu() end },
            { label = O.imapViwer, value = 'imap', desc = O.imapViwer_desc, go = function() ExecuteCommand('imapview') end },
            { label = O.scenarioHashViwer, value = 'scenario', desc = O.scenarioHashViwer_desc, go = toggleScenarioWatch },
            { label = O.interiorId, value = 'interiorid', desc = O.interiorId_desc,
              go = function() print('interiorId', GetInteriorFromEntity(PlayerPedId())) end },
        },
    })
end

-- a list of every ped model, or every wagon model, to spawn with one click
function SpawnPeds(kind)
    local O = T.Menus.MainDevToolsOptions
    local source, hint = Peds, O.spawnPeds_desc
    if kind == 'wagons' then source, hint = Vehicles, O.spawnVehicle_desc end

    local rows = {}
    for _, model in ipairs(source) do
        rows[#rows + 1] = {
            label = model, value = model, desc = hint,
            go = function(row)
                if kind == 'wagons' then placeWagon(row.value) else placePed(row.value, true) end
            end,
        }
    end
    Kit.open('SpawnPeds', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleDevTools, back = 'OpenDevTools', items = rows })
end

local function toggleLaser()
    aiming = not aiming
    TriggerEvent('jrs:TipRight', aiming and T.Notify.laserOn or T.Notify.laserOff, aiming and 3000 or 2500)
    if aiming then StartDevLaserLoop() end
end

function OpenObjMenu()
    local O = T.Menus.SubDevToolsOptions
    Kit.open('OpenObjMenu', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleDevTools,
        back = 'Actions',
        items = {
            { label = O.printModel, value = 'print', desc = O.printModel_desc, go = function()
                local object = GetClosestObject()
                local text = T.Notify.closesObject .. ' ' .. GetEntityModel(object)
                print(text, GetEntityCoords(object))
                TriggerEvent('jrs:TipRight', text, 6000)
            end },
            { label = O.deleteModel, value = 'del', desc = O.deleteModel_desc, go = function()
                local object = GetClosestObject()
                TriggerEvent('jrs:TipRight', T.Notify.closesObject .. ' ' .. object, 4000)
                DeleteObject(object)
            end },
            { label = O.coordsMenu, value = 'getcoords', desc = O.coordsMenu_desc, go = function() OpenCoordsMenu() end },
            { label = O.devtoolOn, value = 'devlaser', desc = O.devtool_desc, go = function()
                toggleLaser()
                MenuData.CloseAll()
            end },
        },
    })
end

-- ------------------------------------------------------------------ aim laser
-- A red line from the head, a small box where it lands and the facts about what it hits.
--   H copies the information, G copies the point as vector3.

local hit = { at = nil, entity = nil }

local function nameIndex(list)
    local by = {}
    for _, name in ipairs(list or {}) do by[joaat(name:lower())] = name end
    return by
end
local pedNames, propNames = nameIndex(Peds), nameIndex(Props)

local function write(text, x, y, scale, r, g, b)
    SetTextFontForCurrentCommand(0)
    SetTextScale(scale, scale)
    SetTextColor(r, g, b, 235)
    SetTextCentre(true)
    DisplayText(CreateVarString(10, 'LITERAL_STRING', text), x, y)
end

local function direction(rotation)
    local z, x = math.rad(rotation.z), math.rad(rotation.x)
    local flat = math.cos(x)
    return vector3(-math.sin(z) * flat, math.cos(z) * flat, math.sin(x))
end

local function copy(text)
    if pcall(SendNUIMessage, { string = text }) then
        TriggerEvent('jrs:TipRight', T.Notify.copied, 2000)
    else
        TriggerEvent('chat:addMessage', { args = { '^2COPY', text } })
        TriggerEvent('jrs:TipRight', T.Notify.copiedConsole, 2500)
        print(text)
    end
end

function StartDevLaserLoop()
    if laserRunning then return end
    laserRunning = true

    CreateThread(function()
        local L = T.Menus.Inspect
        while aiming do
            Wait(0)
            local ped = PlayerPedId()
            local from = GetPedBoneCoords(ped, 21030, 0.0, 0.05, 0.02)
            local to = from + direction(GetGameplayCamRot(2)) * 60.0
            DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, 255, 25, 25, 255)

            local _, touched, point, _, entity = GetShapeTestResult(StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, ped, 0))
            hit.at, hit.entity = point, nil
            local info = (L.coords .. ': %.2f, %.2f, %.2f'):format(point.x, point.y, point.z)

            if touched == 1 and entity ~= 0 and DoesEntityExist(entity) then
                hit.entity = entity
                local model = GetEntityModel(entity)
                local c, r = GetEntityCoords(entity), GetEntityRotation(entity)
                info = ('%s: %.2f, %.2f, %.2f\n%s: %s\n%s: %s\n%s: %.2f\n%s: %.2f, %.2f, %.2f'):format(
                    L.coords, c.x, c.y, c.z, L.hash, tostring(model), L.model, pedNames[model] or propNames[model] or L.unknown,
                    L.heading, GetEntityHeading(entity), L.rotation, r.x, r.y, r.z)
                DrawBox(point.x - 0.03, point.y - 0.03, point.z - 0.03, point.x + 0.03, point.y + 0.03, point.z + 0.03, 255, 50, 50, 200)
            end

            write(info, 0.5, 0.80, 0.40, 255, 255, 255)
            write(L.copyHelp, 0.5, 0.92, 0.36, 255, 200, 200)

            if IsControlJustPressed(0, AIM_COPY_INFO) and hit.entity then copy(info) end
            if IsControlJustPressed(0, AIM_COPY_COORDS) and hit.at then
                copy(('vector3(%.2f, %.2f, %.2f)'):format(hit.at.x, hit.at.y, hit.at.z))
            end
        end
        laserRunning = false
        hit.at, hit.entity = nil, nil
    end)
end
