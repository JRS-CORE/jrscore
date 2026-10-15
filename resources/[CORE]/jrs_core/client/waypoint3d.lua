if not Config.Waypoint3D.Enabled then return end

local waypoint = nil
local lastWaypointStatus = false
local isEnabled = true
local customDestination = nil
local GetWaypointCoords = GetWaypointCoords
local IsWaypointActive = IsWaypointActive
local GetEntityCoords = GetEntityCoords
local PlayerPedId = PlayerPedId
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord
local GetGroundZFor_3dCoord = GetGroundZFor_3dCoord
local floor = math.floor
local vector3 = vector3
local vector2 = vector2
local DrawSprite = DrawSprite
local SetTextScale = SetTextScale
local SetTextFontForCurrentCommand = SetTextFontForCurrentCommand
local SetTextColor = SetTextColor
local SetTextCentre = SetTextCentre
local SetTextDropshadow = SetTextDropshadow
local DisplayText = DisplayText
local CreateVarString = CreateVarString
local HasStreamedTextureDictLoaded = HasStreamedTextureDictLoaded
local RequestStreamedTextureDict = RequestStreamedTextureDict
local IsPauseMenuActive = IsPauseMenuActive

local cachedGroundZ = {}

local function EnsureTextures()
    if not HasStreamedTextureDictLoaded("generic_textures") then
        RequestStreamedTextureDict("generic_textures", true)
    end
    if not HasStreamedTextureDictLoaded("BLIPS") then
        RequestStreamedTextureDict("BLIPS", true)
    end
end

local function GetCachedGroundZ(x, y)
    local key = string.format("%.1f_%.1f", x, y)
    if cachedGroundZ[key] and cachedGroundZ[key].found then
        return cachedGroundZ[key].z
    end

    local ground, z = GetGroundZFor_3dCoord(x, y, 1000.0, true)
    local heightOffset = (Config.Waypoint3D.display and Config.Waypoint3D.display.heightOffset) or 1.0

    if ground and z and z > -100.0 then
        local finalZ = z + heightOffset
        cachedGroundZ[key] = { found = true, z = finalZ }
        return finalZ
    else
        local playerPed = PlayerPedId()
        local pZ = playerPed and playerPed ~= 0 and GetEntityCoords(playerPed).z or 0.0
        return pZ + heightOffset
    end
end

local function DrawWaypointIndicator(x, y, distance, blipName, blipColor)
    EnsureTextures()
    local r, g, b = table.unpack(blipColor or Config.Waypoint3D.defaultBlip.color)
    DrawSprite("generic_textures", "default_pedshot", x, y, 0.02, 0.035, 0.0, 255, 255, 255, 200, 0)
    local w, h = table.unpack(Config.Waypoint3D.display.spriteSize)
    DrawSprite(
        "BLIPS", 
        blipName or Config.Waypoint3D.defaultBlip.sprite, 
        x, y, 
        w, h,
        0.0, r, g, b, 200, 0
    )
    local text = tostring(floor(distance)) .. "m"
    SetTextScale(Config.Waypoint3D.display.textScale, Config.Waypoint3D.display.textScale)
    SetTextFontForCurrentCommand(Config.Waypoint3D.display.textFont)
    SetTextColor(table.unpack(Config.Waypoint3D.display.textColor))
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 255)
    DisplayText(CreateVarString(10, "LITERAL_STRING", text), x, y + Config.Waypoint3D.display.textOffset)
end

function SetCustomDestination(coords, blipName, blipColor)
    if not coords then return end
    customDestination = {
        coords = vector3(coords.x, coords.y, coords.z or GetCachedGroundZ(coords.x, coords.y)),
        blip = blipName,
        color = blipColor
    }
    return true
end

function RemoveCustomDestination()
    customDestination = nil
    return true
end

RegisterCommand(Config.Waypoint3D.commands.toggle, function()
    isEnabled = not isEnabled
    TriggerEvent(
        'jrsCore:notify',
        _U('system'),
        isEnabled and _U('waypoint_enabled') or _U('waypoint_disabled'),
        'placeholder',
        4000
    )
end, false)

Citizen.CreateThread(function()
    while true do
        if not customDestination then
            local isWaypointActive = IsWaypointActive()
            if isWaypointActive then
                local coords = GetWaypointCoords()
                if coords and coords.x and coords.y and (coords.x ~= 0.0 or coords.y ~= 0.0) then
                    if not waypoint or #(vector2(waypoint.x, waypoint.y) - vector2(coords.x, coords.y)) > 2.0 then
                        waypoint = vector3(coords.x, coords.y, GetCachedGroundZ(coords.x, coords.y))
                    end
                end
            else
                if waypoint ~= nil then
                    waypoint = nil
                    cachedGroundZ = {}
                end
            end
            lastWaypointStatus = isWaypointActive
        end
        Citizen.Wait(250)
    end
end)

Citizen.CreateThread(function()
    EnsureTextures()
    while true do
        local destination = customDestination and customDestination.coords or waypoint
        if isEnabled and destination then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local distance = #(playerCoords - destination)
            local minDistance = (Config.Waypoint3D.display and Config.Waypoint3D.display.minDistance) or 6.0

            if distance <= minDistance then
                -- Reached the destination: turn off waypoint only when close
                if not customDestination and IsWaypointActive() then
                    pcall(SetWaypointOff)
                    waypoint = nil
                    cachedGroundZ = {}
                    lastWaypointStatus = false
                elseif customDestination then
                    customDestination = nil
                end
                Citizen.Wait(250)
            else
                if not IsPauseMenuActive() then
                    EnsureTextures()
                    local currentZ = GetCachedGroundZ(destination.x, destination.y)
                    local isVisible, screenX, screenY = GetScreenCoordFromWorldCoord(
                        destination.x, 
                        destination.y, 
                        currentZ
                    )
                    if isVisible then
                        if customDestination then
                            DrawWaypointIndicator(
                                screenX, screenY, distance, 
                                customDestination.blip, 
                                customDestination.color
                            )
                        else
                            DrawWaypointIndicator(screenX, screenY, distance)
                        end
                    end
                end
                Citizen.Wait(0)
            end
        else
            Citizen.Wait(250)
        end
    end
end)

exports('SetCustomDestination', SetCustomDestination)
exports('RemoveCustomDestination', RemoveCustomDestination)

RegisterNetEvent('jrs_core:waypoint3d:setDestination', function(coords, blipName, blipColor)
    SetCustomDestination(coords, blipName, blipColor)
end)

RegisterNetEvent('jrs_core:waypoint3d:removeDestination', function()
    RemoveCustomDestination()
end)

RegisterNetEvent('3d_waypoint:setWaypoint', function(coords, blipName, blipColor)
    SetCustomDestination(coords, blipName, blipColor)
end)
