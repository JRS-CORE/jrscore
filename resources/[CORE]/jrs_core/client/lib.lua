-- ---------------------------------------------------------------------------
-- jrs_lib -> jrs_core : client helper library
-- ---------------------------------------------------------------------------
-- Ported wholesale from the standalone jrs_lib resource. The behaviour is
-- unchanged; what did change is scoping, because this file now shares a Lua
-- state with the rest of jrs_core:
--
--   * every helper that used to be a bare global (spawnNPC, getPlayers,
--     deleteObj, RayCastGamePlayCamera, ...) is a local here,
--   * the settings moved from Config.* to Config.Lib.*,
--   * the NUI ids and callback names are prefixed so the dialogs can live on
--     jrs_core's single ui_page next to the HUD.
--
-- The public surface is unchanged: the jrs_lib export and the
-- 'jrs_lib:getApi' event both still answer, now from jrs_core.
-- ---------------------------------------------------------------------------

local hit, coords, entity, coordsTarget = 0, 0, 0, nil

-- Kept global on purpose: client/lib_exports.lua wraps it, and the
-- 'jrs_lib:getApi' event hands it out to callers exactly as jrs_lib did.
JrsLib = {}
dataApi = JrsLib -- legacy name anything written against jrs_lib may look for

local buttons = {}
local allNPCData = {}
local allNPCSpawned = {}
local allNPCChecker = {}
local allBlips = {}
local allPrompts = {}
local allButtonsPrompts = {}
local npcSpawnCode = nil
local lastVehicle = 0

local targetEnable = false
local points = {}
local inPolyCreator = false

local notifyTable = {}
local send_value = nil
local answer_value = nil

-- The raycast used to run every 100ms for every player, forever. Inside
-- jrs_core that is a per-player cost the whole server pays, so the loop now
-- idles unless something actually wants the result: a dev command is on, a
-- polygon is being traced, or getTarget() was called recently.
local lastTargetRequest = 0
local TARGET_KEEPALIVE = 2000

local function libConfig()
    return (Config and Config.Lib) or {}
end

local function RotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    return {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
end

local function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = {
        x = cameraCoord.x + direction.x * distance,
        y = cameraCoord.y + direction.y * distance,
        z = cameraCoord.z + direction.z * distance
    }
    if targetEnable then
        JrsLib.drawMe(destination.x, destination.y, destination.z, ".", 10.0)
    end
    local _, b, c, _, e = GetShapeTestResult(StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z,
        destination.x, destination.y, destination.z, -1, PlayerPedId(), 1))
    return b, c, e, vector3(destination.x, destination.y, destination.z)
end

local function getLocalPlayers()
    local players = {}
    for i = 0, 32 do
        if NetworkIsPlayerActive(i) then
            table.insert(players, i)
        end
    end
    return players
end

local function modelRequest(model)
    Citizen.CreateThread(function()
        RequestModel(model)
    end)
end

-- Delete helper used by the NPC pool. 'check' clears the spawn guard so the
-- same NPC definition can respawn once the player walks back into range.
local function deleteSpawned(obj, check)
    local timeout = 0
    if DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, false, true)
        NetworkRequestControlOfEntity(obj)
        while not NetworkHasControlOfEntity(obj) do
            timeout = timeout + 1
            if timeout > 10 then break end
            if not DoesEntityExist(obj) then break end
            Wait(100)
        end
        DeleteEntity(obj)
        allNPCSpawned[obj] = nil
        allNPCChecker[check] = nil
    end
end

local function spawnNPC(model, x, y, z, h, dist, scenario, spawnChecker)
    if allNPCChecker[spawnChecker] ~= nil then return end
    allNPCChecker[spawnChecker] = true

    local npcSpawn = model
    while not HasModelLoaded(GetHashKey(npcSpawn)) do
        Wait(0)
        modelRequest(GetHashKey(npcSpawn))
    end

    npcSpawnCode = CreatePed(GetHashKey(npcSpawn), x, y, z, h, false, false, 0, 0)
    while not DoesEntityExist(npcSpawnCode) do
        Wait(0)
    end

    allNPCSpawned[npcSpawnCode] = { dist, spawnChecker }
    Citizen.InvokeNative(0x283978A15512B2FE, npcSpawnCode, true)
    SetPedAsGroupMember(npcSpawnCode, GetPedGroupIndex(PlayerPedId()))
    SetBlockingOfNonTemporaryEvents(npcSpawnCode, true)
    FreezeEntityPosition(npcSpawnCode, true)
    SetEntityInvincible(npcSpawnCode, true)
    TaskStandStill(npcSpawnCode, -1)
    SetEntityAsMissionEntity(npcSpawnCode, true, true)
    SetModelAsNoLongerNeeded(GetHashKey(npcSpawn))
    ClearPedEnvDirt(npcSpawnCode)
    ClearPedDamageDecalByZone(npcSpawnCode, 10, "ALL")
    ClearPedBloodDamage(npcSpawnCode)
    if scenario ~= nil then
        TaskStartScenarioInPlace(npcSpawnCode, GetHashKey(scenario), 0, 1)
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function JrsLib.getFolder()
    return libConfig().FolderWithIcons
end

function JrsLib.fpsTimer()
    local frameTime = GetFrameTime()
    local frame = 1.0 / frameTime

    local add = 1.0
    local fpsTable = {
        { upperLimit = 30,        value = 15 / 2 },
        { upperLimit = 40,        value = 12.5 / 2 },
        { upperLimit = 50,        value = 10 / 2 },
        { upperLimit = 60,        value = 7.5 / 2 },
        { upperLimit = 80,        value = 5 / 2 },
        { upperLimit = 100,       value = 2.5 / 2 },
        { upperLimit = math.huge, value = 0 }
    }

    for i = 1, #fpsTable do
        local v = fpsTable[i]
        if frame < v.upperLimit then
            add = v.value
            break
        end
    end

    return add
end

function JrsLib.drawMe(x, y, z, text, dist, marker)
    local playerCoords = GetEntityCoords(PlayerPedId())
    if GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, x, y, z, true) < dist then
        local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
        local str = CreateVarString(10, "LITERAL_STRING", text, Citizen.ResultAsLong())
        if onScreen then
            SetTextScale(0.30, 0.30)
            SetTextFontForCurrentCommand(1)
            SetTextColor(180, 180, 240, 205)
            SetTextCentre(1)
            DisplayText(str, _x, _y)
            if marker ~= nil then
                Citizen.InvokeNative(0x2A32FAA57B937173, -1795314153, x, y, z - 1.0, 0, 0, 0, 0, 0, 0, 1.3, 1.3, 0.4,
                    255, 200, 122, 155, 0, 0, 2, 0, 0, 0, 0)
            end
        end
    end
end

function JrsLib.playerNearCoords(x, y, z, dist, mark)
    local inCoords = false
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    if GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, x, y, z, true) < dist
        and GetEntityHealth(ped) ~= 0
        and GetMount(ped) == 0
        and GetVehiclePedIsUsing(ped) == 0 then
        inCoords = true
        if mark then
            Citizen.InvokeNative(0x2A32FAA57B937173, -1795314153, x, y, z - 1.0, 0, 0, 0, 0, 0, 0, dist * 2.0,
                dist * 2.0, 0.4, 255, 200, 122, 155, 0, 0, 2, 0, 0, 0, 0)
        end
    end
    return inCoords
end

function JrsLib.checkPlayersNearEntity(entity, distance)
    local isNearPlayer = false
    local entityCoords = GetEntityCoords(entity)
    for _, v in pairs(getLocalPlayers()) do
        local playerCoords = GetEntityCoords(GetPlayerPed(v))
        if GetDistanceBetweenCoords(entityCoords.x, entityCoords.y, entityCoords.z, playerCoords.x, playerCoords.y,
                playerCoords.z, false) < distance then
            if PlayerPedId() ~= GetPlayerPed(v) then
                isNearPlayer = true
            end
        end
    end
    return isNearPlayer
end

function JrsLib.groundCheck(x, y)
    local retval, whereGround = nil, nil
    for height = 1, 1000 do
        retval, whereGround = GetGroundZAndNormalFor_3dCoord(x, y, height + 0.0)
        if retval then
            return whereGround
        end
    end
    return 0.0
end

-- https://github.com/femga/rdr3_discoveries/tree/master/useful_info_from_rpfs/textures/blips
function JrsLib.createBlip(text, x, y, z, sprite)
    local blip = N_0x554d9d53f696d002(1664425300, x, y, z)
    SetBlipSprite(blip, sprite, 1)
    SetBlipScale(blip, 0.5)
    local safeText = type(JrsLang) == 'table' and JrsLang.SanitizeNativeText and JrsLang.SanitizeNativeText(text) or text
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, safeText)
    table.insert(allBlips, blip)
end

function JrsLib.createVehicle(model, x, y, z, h)
    local modelHash = GetHashKey(model)
    RequestModel(modelHash)
    while not Citizen.InvokeNative(0x1283B8B89DD5D1B6, modelHash, Citizen.ResultAsBoolean) do
        Wait(5)
    end
    local createdVehicle = Citizen.InvokeNative(0xAF35D0D2583051B0, modelHash, x, y, z, h, true, false, 0, 1)
    while not DoesEntityExist(createdVehicle) do
        Citizen.Wait(5)
    end
    SetModelAsNoLongerNeeded(modelHash)
    SetEntityAsMissionEntity(createdVehicle, true, true)
    SetVehicleOnGroundProperly(createdVehicle)
    lastVehicle = createdVehicle
end

function JrsLib.getLastVehicle()
    return lastVehicle
end

-- https://github.com/femga/rdr3_discoveries/tree/master/Controls
-- Hold mode hashes: SHORT_TIMED_EVENT_MP, SHORT_TIMED_EVENT, MEDIUM_TIMED_EVENT,
-- LONG_TIMED_EVENT, RUSTLING_CALM_TIMING, PLAYER_FOCUS_TIMING, PLAYER_REACTION_TIMING
function JrsLib.showPrompt(name, prompt, show)
    if show == false then
        allPrompts[prompt] = false
    else
        allPrompts[prompt] = name
    end
end

function JrsLib.createPrompt(text, key, promptHash, holdMode, event)
    if buttons[text .. promptHash] == nil then
        local buttonPrompt = Citizen.InvokeNative(0x04F97DE45A519419)
        PromptSetControlAction(buttonPrompt, key)
        local safeText = type(JrsLang) == 'table' and JrsLang.SanitizeNativeText and JrsLang.SanitizeNativeText(text) or text
        PromptSetText(buttonPrompt, CreateVarString(10, 'LITERAL_STRING', safeText))
        PromptSetEnabled(buttonPrompt, true)
        PromptSetVisible(buttonPrompt, true)
        if holdMode == false then
            PromptSetHoldMode(buttonPrompt, false)
        else
            PromptSetStandardizedHoldMode(buttonPrompt, GetHashKey(holdMode))
        end
        PromptSetGroup(buttonPrompt, promptHash)
        PromptRegisterEnd(buttonPrompt)
        buttons[text .. promptHash] = buttonPrompt
        if allButtonsPrompts[promptHash] == nil then
            allButtonsPrompts[promptHash] = {}
        end
        table.insert(allButtonsPrompts[promptHash], { buttonPrompt, event, key })
    end
end

function JrsLib.promptDelete(text, promptHash)
    if buttons[text .. promptHash] ~= nil then
        local deleted = buttons[text .. promptHash]
        PromptDelete(deleted)
        buttons[text .. promptHash] = nil
        -- Do not leave a prompt group marked visible after its last button has
        -- been deleted. RedM's group native can fault when called with an empty
        -- group on a later frame.
        local entries = allButtonsPrompts[promptHash]
        if entries then
            for i = #entries, 1, -1 do
                if entries[i] == nil or entries[i][1] == deleted then table.remove(entries, i) end
            end
            if #entries == 0 then
                allButtonsPrompts[promptHash] = nil
                allPrompts[promptHash] = false
            end
        end
    end
end

function JrsLib.setPromptVisible(text, hash, state)
    PromptSetVisible(buttons[text .. hash], state and true or false)
end

function JrsLib.getPrompt(promptHash, text)
    PromptSetActiveGroupThisFrame(promptHash, CreateVarString(10, 'LITERAL_STRING', "" .. text .. ""))
end

function JrsLib.getPromptButton(text, promptHash)
    local isComplete = false
    if Citizen.InvokeNative(0xE0F65F0640EF0617, buttons[text .. promptHash]) then
        isComplete = true
        Citizen.InvokeNative(0xFC094EF26DD153FA, promptHash)
        Citizen.InvokeNative(0xF1622CE88A1946FB)
    end
    return isComplete
end

function JrsLib.setPromptEnable(text, hash, state)
    Citizen.InvokeNative(0x8A0FB4D03A630D21, buttons[text .. hash], state and true or false)
end

function JrsLib.getPromptButtonData(text, promptHash)
    return buttons[text .. promptHash]
end

function JrsLib.getTarget()
    lastTargetRequest = GetGameTimer()
    return coords, entity, coordsTarget
end

function JrsLib.createPed(model, x, y, z, h, dist, scenario)
    local random = math.random(1, 99999999999999)
    table.insert(allNPCData,
        { model = model, dist = dist, x = x, y = y, z = z, h = h, scenario = scenario, spawnChecker = random })
end

function JrsLib.getLastPed()
    return npcSpawnCode
end

function JrsLib.getAllPeds()
    return GetGamePool('CPed')
end

function JrsLib.getAllEntities()
    return GetGamePool('CObject')
end

function JrsLib.getAllVehicles()
    return GetGamePool('CVehicle')
end

function JrsLib.getTime()
    return GetClockHours(), GetClockMinutes()
end

function JrsLib.getPlayers()
    local players = {}
    for i = 0, 32 do
        if NetworkIsPlayerActive(i) then
            table.insert(players, GetPlayerServerId(i))
        end
    end
    return players
end

function JrsLib.playAnim(entity, dict, name, flag, time)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(0)
    end
    TaskPlayAnim(entity, dict, name, 1.0, 1.0, time, flag, 0, true, 0, false, 0, false)
end

function JrsLib.deleteObj(obj)
    if obj and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, false, true)

        if NetworkGetEntityIsNetworked(obj) then
            NetworkRequestControlOfEntity(obj)
            local timeout = 0
            while not NetworkHasControlOfEntity(obj) do
                timeout = timeout + 1
                if timeout > 10 then break end
                Wait(100)
            end
        end

        if NetworkHasControlOfEntity(obj) or not NetworkGetEntityIsNetworked(obj) then
            DeleteEntity(obj)
        end
    end
end

function JrsLib.deletePed(obj)
    if obj and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, false, true)

        if NetworkGetEntityIsNetworked(obj) then
            NetworkRequestControlOfEntity(obj)
            local timeout = 0
            while not NetworkHasControlOfEntity(obj) do
                timeout = timeout + 1
                if timeout > 10 then break end
                Wait(100)
            end
        end

        if NetworkHasControlOfEntity(obj) or not NetworkGetEntityIsNetworked(obj) then
            DeletePed(obj)
        end
    end
end

function JrsLib.IsPlayerInsidePolygon(playerPos, polyPoints, debug, issmall)
    local oddNodes = false
    local x, y = playerPos.x, playerPos.y

    for i = 1, #polyPoints do
        if debug then
            JrsLib.drawMe(polyPoints[i].x, polyPoints[i].y, polyPoints[i].z + 1.0, tostring(i), 4.0)
            Citizen.InvokeNative(0x2A32FAA57B937173, -1795314153, polyPoints[i].x, polyPoints[i].y,
                polyPoints[i].z - 1.0, 0, 0, 0, 0, 0, 0, 0.05, 0.05, 4.0, 255, 255, 255, 100, 0, 0, 2, 0, 0, 0, 0)
        end

        if issmall then
            Citizen.InvokeNative(0x2A32FAA57B937173, -1795314153, polyPoints[i].x, polyPoints[i].y,
                polyPoints[i].z - 1.0, 0, 0, 0, 0, 0, 0, 0.01, 0.01, 4.0, 255, 255, 255, 100, 0, 0, 2, 0, 0, 0, 0)
        end

        local j = i % #polyPoints + 1
        if ((polyPoints[i].y <= y and polyPoints[j].y > y) or (polyPoints[j].y <= y and polyPoints[i].y > y)) then
            if (polyPoints[i].x + (y - polyPoints[i].y) / (polyPoints[j].y - polyPoints[i].y) * (polyPoints[j].x - polyPoints[i].x) < x) then
                oddNodes = not oddNodes
            end
        end
    end

    return oddNodes
end

function JrsLib.calculatePolygonLength(polyPoints)
    local length = 0.0
    local prevPoint = polyPoints[#polyPoints]
    for _, point in ipairs(polyPoints) do
        length = length + #(point - prevPoint)
        prevPoint = point
    end
    return string.format("%.2f", length)
end

-- ---------------------------------------------------------------------------
-- Notifications / dialogs
-- ---------------------------------------------------------------------------

local function show_notification(bool, title_text, subtext_text, icon_text, duration)
    table.insert(notifyTable, { bool, title_text, subtext_text, icon_text, duration })
end

local function delete_show_notification(bool)
    SendNUIMessage({ type = "jrslib:notify", status = bool, folder = libConfig().FolderWithIcons })
end

RegisterNetEvent('jrsCore:notify')
AddEventHandler('jrsCore:notify', function(title, subtext, icon, duration)
    if type(JRSNotifyRender) == 'function' then
        local rendered = JRSNotifyRender({
            title = title,
            text = subtext,
            notifyType = 'info',
            image = icon,
            duration = duration,
            source = GetInvokingResource()
        })
        if rendered then return end
    end
    show_notification(true, title, subtext, icon, duration)
end)

function JrsLib.notify(title, text, img, time)
    TriggerEvent("jrsCore:notify", title, text, img, time)
end

function JrsLib.getAnswer(title, first, second, cb)
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "jrslib:open_answer", status = true, title = title, first = first, second = second })
    while (answer_value == nil) do
        Citizen.Wait(0)
    end
    SendNUIMessage({ type = "jrslib:open_answer", status = false })
    SetNuiFocus(false, false)
    local transfer_ans_value = answer_value
    answer_value = nil
    cb(transfer_ans_value)
end

function JrsLib.getInput(title, subtext, cb)
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "jrslib:open_inputs", status = true, title = subtext, subtext = title })
    while (send_value == nil) do
        Citizen.Wait(0)
    end
    SendNUIMessage({ type = "jrslib:open_inputs", status = false })
    SetNuiFocus(false, false)
    local transfer_value = send_value
    send_value = nil
    cb(transfer_value)
end

RegisterNUICallback('jrslib:close', function(_, cb)
    send_value = "close"
    cb({})
end)

RegisterNUICallback('jrslib:send', function(data, cb)
    send_value = data.text
    cb({})
end)

RegisterNUICallback('jrslib:yes', function(_, cb)
    answer_value = true
    cb({})
end)

RegisterNUICallback('jrslib:no', function(_, cb)
    answer_value = false
    cb({})
end)

Citizen.CreateThread(function()
    while true do
        for a, b in pairs(notifyTable) do
            SendNUIMessage({
                type   = "jrslib:notify",
                status = b[1],
                title  = b[2],
                text   = b[3],
                id     = b[4],
                folder = libConfig().FolderWithIcons
            })
            Citizen.Wait(tonumber(b[5]) or 3000)
            table.remove(notifyTable, a)
            delete_show_notification(false)
        end
        Citizen.Wait(100)
    end
end)

-- ---------------------------------------------------------------------------
-- Threads
-- ---------------------------------------------------------------------------

-- Raycast / polygon tracer. Idles at 500ms unless a dev tool is active or a
-- consumer asked for the target within the last few seconds.
Citizen.CreateThread(function()
    while true do
        local tracing = #points ~= 0
        local wanted = targetEnable or tracing or (GetGameTimer() - lastTargetRequest) < TARGET_KEEPALIVE

        if not wanted then
            Citizen.Wait(500)
        else
            local optimize = 100
            hit, coords, entity, coordsTarget = RayCastGamePlayCamera(5.0)
            if hit and targetEnable then
                optimize = JrsLib.fpsTimer()
            end

            if tracing then
                optimize = JrsLib.fpsTimer()
                local playerCoords = GetEntityCoords(PlayerPedId())
                JrsLib.IsPlayerInsidePolygon(playerCoords, points, true)
                if Citizen.InvokeNative(0x91AEF906BCA88877, 0, 0x07B8BEAF) then
                    table.insert(points, vector3(playerCoords.x, playerCoords.y, playerCoords.z))
                    SendNUIMessage({ type = "jrslib:copyPoly", status = true, points = points })
                end
            end

            Citizen.Wait(optimize)
        end
    end
end)

-- Prompt group driver.
Citizen.CreateThread(function()
    while true do
        local optimize = 200
        for a, b in pairs(allPrompts) do
            if b ~= false then
                local entries = allButtonsPrompts[a]
                local hasLivePrompt = false
                if type(a) == 'number' and a ~= 0 and entries then
                    for _, d in pairs(entries) do
                        if d and d[1] and PromptIsValid(d[1]) then
                            hasLivePrompt = true
                            break
                        end
                    end
                end
                if hasLivePrompt then
                    optimize = JrsLib.fpsTimer()
                    PromptSetActiveGroupThisFrame(a, CreateVarString(10, 'LITERAL_STRING', "" .. b .. ""))
                    for _, d in pairs(entries) do
                        if d ~= nil and d[2] ~= nil
                            and PromptIsValid(d[1])
                            and Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, d[3])
                            and Citizen.InvokeNative(0x0D00EDDFB58B7F28, d[1]) then
                            Citizen.InvokeNative(0x8A0FB4D03A630D21, d[1], false)
                            TriggerEvent(d[2])
                        end
                    end
                end
            end
        end
        Citizen.Wait(optimize)
    end
end)

-- Distance-based NPC pool.
Citizen.CreateThread(function()
    while true do
        for _, b in pairs(allNPCData) do
            if JrsLib.playerNearCoords(b.x, b.y, b.z, b.dist) then
                spawnNPC(b.model, b.x, b.y, b.z, b.h, b.dist, b.scenario, b.spawnChecker)
            end
        end
        for a, b in pairs(allNPCSpawned) do
            local npcCoords = GetEntityCoords(a)
            if not JrsLib.playerNearCoords(npcCoords.x, npcCoords.y, npcCoords.z, b[1]) then
                deleteSpawned(a, b[2])
            end
        end

        Citizen.Wait(1000)
    end
end)

-- ---------------------------------------------------------------------------
-- Developer commands (jrs_lib registered these unconditionally)
-- ---------------------------------------------------------------------------

Citizen.CreateThread(function()
    local cfg = libConfig()
    if cfg.EnableDevCommands == false then return end

    if cfg.PolyPointCommand and cfg.PolyPointCommand ~= '' then
        RegisterCommand(cfg.PolyPointCommand, function()
            local playerPos = GetEntityCoords(PlayerPedId())
            if not inPolyCreator then
                inPolyCreator = true
                table.insert(points, vector3(playerPos.x, playerPos.y, playerPos.z))
            else
                inPolyCreator = false
                points = {}
            end
        end, false)
    end

    if cfg.TargetCommand and cfg.TargetCommand ~= '' then
        RegisterCommand(cfg.TargetCommand, function()
            targetEnable = not targetEnable
        end, false)
    end
end)

-- ---------------------------------------------------------------------------
-- Cross-resource surface (unchanged names, now served by jrs_core)
-- ---------------------------------------------------------------------------

RegisterNetEvent('jrs_lib:getApi')
AddEventHandler('jrs_lib:getApi', function(cb)
    cb(JrsLib)
end)

RegisterNetEvent('jrs_lib:createStash')
AddEventHandler('jrs_lib:createStash', function(id, size)
    TriggerEvent("inventory:client:SetCurrentStash", id)
    TriggerServerEvent("inventoryOpenInventory", "stash", id, { maxweight = size * 1000, slots = invSlots })
end)

RegisterNetEvent('jrs_lib:openStash')
AddEventHandler('jrs_lib:openStash', function(id, size)
    TriggerServerEvent("inventory:server:OpenInventory", "stash", id, { maxweight = size * 1000, slots = invSlots })
end)

-- jrs_lib also fired TriggerServerEvent("jrs_lib:checkLogin") two seconds after
-- 'jrs:isPlayerReady'. Nothing on the server has ever registered that event, so
-- every login sent an unhandled net event. Dropped with the merge.

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for a, b in pairs(allNPCSpawned) do
        deleteSpawned(a, b[2])
    end
    for _, b in pairs(allBlips) do
        RemoveBlip(b)
    end
end)
