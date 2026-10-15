-- JRS - player disconnect marker
-- Lightweight client-side renderer for recent player disconnect locations.

local activeSigns = {}
local localEntities = {}
local lastSyncRequest = 0

local function cfg()
    return Config and Config.PlayerDropped or nil
end

local function enabled()
    local c = cfg()
    return c and c.Enabled == true
end

local function safeNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function isCharacterReady()
    if LocalPlayer and LocalPlayer.state then
        return LocalPlayer.state.CharacterReady == true
    end
    return true
end

local function requestModelSafe(modelHash, timeoutMs)
    if not modelHash or modelHash == 0 then return false end
    RequestModel(modelHash)
    local deadline = GetGameTimer() + (timeoutMs or 5000)
    while not HasModelLoaded(modelHash) and GetGameTimer() < deadline do
        Wait(25)
    end
    return HasModelLoaded(modelHash)
end

local function deleteLocalEntity(signId)
    local entry = localEntities[signId]
    if not entry then return end

    if entry.prop and DoesEntityExist(entry.prop) then
        DeleteEntity(entry.prop)
    end
    if entry.ped and DoesEntityExist(entry.ped) then
        DeleteEntity(entry.ped)
    end

    localEntities[signId] = nil
end

local function clearAllLocalEntities()
    for signId in pairs(localEntities) do
        deleteLocalEntity(signId)
    end
end

local function buildText(data)
    local c = cfg() or {}
    local lines = {}

    lines[#lines + 1] = tostring(data.name or 'Unknown')

    local ids = {}
    if c.ShowServerId ~= false and data.serverId ~= nil then
        ids[#ids + 1] = ('ID: %s'):format(tostring(data.serverId))
    end
    if c.ShowCharacterId == true and data.charId ~= nil then
        ids[#ids + 1] = ('Character: %s'):format(tostring(data.charId))
    end
    if #ids > 0 then
        lines[#lines + 1] = table.concat(ids, '  |  ')
    end

    if c.ShowReason == true and data.reason and data.reason ~= '' then
        lines[#lines + 1] = ('Reason: %s'):format(tostring(data.reason))
    end
    if c.ShowDisconnectTime == true and data.timeText and data.timeText ~= '' then
        lines[#lines + 1] = ('Left: %s'):format(tostring(data.timeText))
    end

    return table.concat(lines, '\n')
end

local function drawText3D(x, y, z, text)
    local c = cfg() or {}
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end

    local str = CreateVarString(10, 'LITERAL_STRING', tostring(text or ''))
    SetTextScale(safeNumber(c.TextScale, 0.30), safeNumber(c.TextScale, 0.30))
    SetTextFontForCurrentCommand(math.floor(safeNumber(c.TextFont, 25)))
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(1)
    DisplayText(str, sx, sy)
end

local function attachBoard(ped, coords)
    local c = cfg() or {}
    if c.UseBoard ~= true then return nil end

    local boardHash = joaat(c.BoardModel or 'P_BOARD01X')
    if not requestModelSafe(boardHash, safeNumber(c.ModelLoadTimeout, 5000)) then
        return nil
    end

    local prop = CreateObject(boardHash, coords.x, coords.y, coords.z, false, true, true, true)
    if not prop or not DoesEntityExist(prop) then
        SetModelAsNoLongerNeeded(boardHash)
        return nil
    end

    local boneIndex = safeNumber(c.BoardBoneIndex, 0x49D9)
    if GetPedBoneIndex then
        local ok, result = pcall(GetPedBoneIndex, ped, math.floor(safeNumber(c.BoardPedBone, 18905)))
        if ok and result and result ~= 0 then
            boneIndex = result
        end
    end

    local off = c.BoardOffset or {}
    local rot = c.BoardRotation or {}
    AttachEntityToEntity(
        prop,
        ped,
        boneIndex,
        safeNumber(off.x, 0.0), safeNumber(off.y, 0.0), safeNumber(off.z, 0.0),
        safeNumber(rot.x, 0.0), safeNumber(rot.y, 0.0), safeNumber(rot.z, 0.0),
        false, false, false, false, 2, true
    )

    SetModelAsNoLongerNeeded(boardHash)
    return prop
end

local function spawnLocalEntity(signId, data)
    if localEntities[signId] then return end

    local c = cfg() or {}
    if c.UsePed == false then
        localEntities[signId] = { ped = nil, prop = nil }
        return
    end

    local model = tonumber(data.model)
    if not model or model == 0 then
        model = joaat(c.PedModel or 'mp_male')
    end

    if not requestModelSafe(model, safeNumber(c.ModelLoadTimeout, 5000)) then
        local fallback = joaat(c.PedModel or 'mp_male')
        if fallback == model or not requestModelSafe(fallback, safeNumber(c.ModelLoadTimeout, 5000)) then
            return
        end
        model = fallback
    end

    local coords = data.coords
    local ped = CreatePed(model, coords.x, coords.y, coords.z, safeNumber(data.heading, 0.0), false, true, true, true)
    if not ped or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(model)
        return
    end

    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCollision(ped, c.PedCollision == true, c.PedCollision == true)

    local prop = attachBoard(ped, coords)
    localEntities[signId] = { ped = ped, prop = prop }
    SetModelAsNoLongerNeeded(model)
end

local function addOrUpdateSign(data)
    if not enabled() or type(data) ~= 'table' then return end
    local signId = tonumber(data.id)
    local coords = data.coords
    if not signId or type(coords) ~= 'table' then return end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end

    data.coords = { x = x, y = y, z = z }
    local remaining = math.max(1, tonumber(data.remaining) or tonumber(data.lifetime) or 300)
    data.expiresGameTimer = GetGameTimer() + math.floor(remaining * 1000)
    activeSigns[signId] = data
end

RegisterNetEvent('jrs_core:playerDropped:add', function(data)
    addOrUpdateSign(data)
end)

RegisterNetEvent('jrs_core:playerDropped:sync', function(signs)
    if not enabled() then return end
    activeSigns = {}
    clearAllLocalEntities()
    if type(signs) ~= 'table' then return end
    for _, data in pairs(signs) do
        addOrUpdateSign(data)
    end
end)

RegisterNetEvent('jrs_core:playerDropped:remove', function(signId)
    signId = tonumber(signId)
    if not signId then return end
    activeSigns[signId] = nil
    deleteLocalEntity(signId)
end)

local function requestSync()
    if not enabled() then return end
    local now = GetGameTimer()
    if now - lastSyncRequest < 1000 then return end
    lastSyncRequest = now
    TriggerServerEvent('jrs_core:playerDropped:requestSync')
end

RegisterNetEvent('jrs_core:client:characterReady', function()
    requestSync()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1500)
        requestSync()
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearAllLocalEntities()
end)

-- Send only position/model data. Character name and IDs are resolved on the server.
CreateThread(function()
    while true do
        local c = cfg()
        local interval = c and math.max(1000, math.floor(safeNumber(c.UpdateInterval, 10000))) or 10000

        if enabled() and isCharacterReady() then
            local ped = PlayerPedId()
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('jrs_core:playerDropped:update', {
                    coords = { x = coords.x, y = coords.y, z = coords.z },
                    heading = GetEntityHeading(ped),
                    model = GetEntityModel(ped)
                })
            end
        end

        Wait(interval)
    end
end)

-- One lightweight manager thread for all active disconnect markers.
CreateThread(function()
    while true do
        if not enabled() then
            if next(activeSigns) ~= nil then activeSigns = {} end
            if next(localEntities) ~= nil then clearAllLocalEntities() end
            Wait(1000)
        else
            local c = cfg() or {}
            local playerPed = PlayerPedId()
            local playerCoords = playerPed ~= 0 and GetEntityCoords(playerPed) or nil
            local spawnDistance = safeNumber(c.SpawnDistance, 80.0)
            local drawDistance = safeNumber(c.DrawDistance, 25.0)
            local textHeight = safeNumber(c.TextHeight, 1.15)
            local nowTimer = GetGameTimer()
            local nearAnyText = false

            for signId, data in pairs(activeSigns) do
                local expiresGameTimer = tonumber(data.expiresGameTimer)
                if expiresGameTimer and expiresGameTimer <= nowTimer then
                    activeSigns[signId] = nil
                    deleteLocalEntity(signId)
                elseif playerCoords and data.coords then
                    local dx = playerCoords.x - data.coords.x
                    local dy = playerCoords.y - data.coords.y
                    local dz = playerCoords.z - data.coords.z
                    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                    if distance <= spawnDistance then
                        spawnLocalEntity(signId, data)
                    else
                        deleteLocalEntity(signId)
                    end

                    if distance <= drawDistance then
                        nearAnyText = true
                        local z = data.coords.z + textHeight
                        local entity = localEntities[signId]
                        if entity and entity.ped and DoesEntityExist(entity.ped) then
                            local pcoords = GetEntityCoords(entity.ped)
                            z = pcoords.z + textHeight
                        end
                        drawText3D(data.coords.x, data.coords.y, z, buildText(data))
                    end
                end
            end

            Wait(nearAnyText and 0 or math.max(100, math.floor(safeNumber(c.ManagerInterval, 250))))
        end
    end
end)
