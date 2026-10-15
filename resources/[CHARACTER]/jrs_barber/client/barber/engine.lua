-- Wait for the authoritative skin tone without allowing a failed callback to
-- freeze the barber forever. The fallback matches the server adapter defaults.
function WaitForBarberAlbedo(ped, timeoutMs)
    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 5000)

    while BarberActualAlbedo == nil and GetGameTimer() < deadline do
        Wait(50)
    end

    local albedo = tonumber(BarberActualAlbedo)
    if not albedo or albedo == 0 then
        albedo = GetHashKey(IsPedMale(ped)
            and "mp_head_mr1_sc08_c0_000_ab"
            or "mp_head_fr1_sc08_c0_000_ab")
        BarberActualAlbedo = albedo
    end

    return albedo
end

---- CAMERA (ported from jrs_character appearance/camera.lua) ----
BarberCamHeight = 0.0
BarberCamDistance = 0.7
BarberCamFov = 30.0
-- jrs_barber head framing: 0.7m from the skel_head bone, 40 degree FOV.
BarberHeadCamFov = 40.0
BarberCamera = nil
BarberBaseHeading = nil
BarberAngleOffset = nil
BarberCurrentH, BarberCurrentZ, BarberCurrentR = 180, 217, 180

BarberActiveCam = 0
BarberCam1 = nil
BarberCam2 = nil
BarberCurrentCamDestination = ""
BarberCamCoords = {}
BarberViewBaseHeading = nil
BarberViewFov = nil
BarberViewPedHandle = nil
BarberBaseCamFov = 30.0
BarberCurrentTargetCoords = nil

local function GetBarberCameraPed()
    local ped = BarberMannequinPed or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then ped = PlayerPedId() end
    return ped
end

local function BarberGetActiveCamera()
    if BarberCamera and DoesCamExist(BarberCamera) then return BarberCamera end
    if BarberActiveCam == 1 and BarberCam1 and DoesCamExist(BarberCam1) then return BarberCam1 end
    if BarberActiveCam == 2 and BarberCam2 and DoesCamExist(BarberCam2) then return BarberCam2 end
    return nil
end

local DEFAULT_BARBER_LATERAL_RATIO = 0.065
local barberViewPanRatio = 0.0
local barberCurrentRawCamCoords = nil
local barberCurrentRawCamTarget = nil

local function ApplyBarberCameraLateralOffset(rawCoords, rawTarget)
    if not rawCoords or not rawTarget then return rawCoords, rawTarget end
    local fwd = rawTarget - rawCoords
    local fwdLen = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
    if fwdLen < 0.001 then return rawCoords, rawTarget end
    local dist = #(rawCoords - rawTarget)
    local totalRatio = DEFAULT_BARBER_LATERAL_RATIO + barberViewPanRatio
    local lateralDist = dist * totalRatio
    local ux = fwd.x / fwdLen
    local uy = fwd.y / fwdLen
    local shiftX = -uy * lateralDist
    local shiftY = ux * lateralDist
    local newCoords = vector3(rawCoords.x + shiftX, rawCoords.y + shiftY, rawCoords.z)
    local newTarget = vector3(rawTarget.x + shiftX, rawTarget.y + shiftY, rawTarget.z)
    return newCoords, newTarget
end

local function UpdateBarberActiveCameraPosition()
    local cam = BarberGetActiveCamera()
    if not cam or not barberCurrentRawCamCoords or not barberCurrentRawCamTarget then return end
    local coords, target = ApplyBarberCameraLateralOffset(barberCurrentRawCamCoords, barberCurrentRawCamTarget)
    SetCamCoord(cam, coords)
    PointCamAtCoord(cam, target)
end

local function BarberBuildCameraDestinations(ped)
    if BarberCamCoords[ped] then return end
    BarberCamCoords[ped] = {
        default = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.3),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0), fov = 30.0,
        },
        Body = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.0, 0.5),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.3), fov = 30.0,
        },
        upperbody = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.2),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.2), fov = 30.0,
        },
        lowerbody = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, -0.4),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.4), fov = 30.0,
        },
        waist = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.75, -0.05),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.05), fov = 28.0,
        },
        feet = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, -0.82),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.82), fov = 27.0,
        },
        hands = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.8, 0.0),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0), fov = 31.0,
        },
    }
end

-- Every head destination uses jrs_barber's framing: the camera sits in front
-- of the real skel_head bone (BarberCamDistance, raised by BarberCamHeight) and
-- looks straight at it with a 40 degree FOV. The previous per-category framings
-- (0.82-1.02m at 24-29 FOV, anchored on the entity instead of the bone) were
-- too tight to see a whole hairstyle, and zooming could not fully undo it.
local function BarberBuildHeadDestination(ped, destination)
    local head
    local boneIndex = GetEntityBoneIndexByName(ped, "skel_head")
    if boneIndex and boneIndex ~= -1 then
        head = GetWorldPositionOfEntityBone(ped, boneIndex)
    else
        head = GetPedBoneCoords(ped, 21030, 0.0, 0.0, 0.0)
    end
    local forward = GetEntityForwardVector(ped)
    local distance = tonumber(BarberCamDistance) or 0.7
    local height = tonumber(BarberCamHeight) or 0.0

    BarberCamCoords[ped][destination] = {
        coords = vector3(head.x + forward.x * distance, head.y + forward.y * distance, head.z + height),
        target = vector3(head.x, head.y, head.z),
        fov = BarberHeadCamFov
    }
end

function BarberMoveCam(destination, data, tpcam)
    local ped = GetBarberCameraPed()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    destination = tostring(destination or "head")
    BarberBuildCameraDestinations(ped)

    if destination == "head" or destination == "hair" or destination == "beard"
        or destination == "eyesandbrows" or destination == "facial" or destination == "mouth" then
        BarberBuildHeadDestination(ped, destination)
    end

    if destination == BarberCurrentCamDestination and BarberGetActiveCamera() then return true end
    BarberCurrentCamDestination = destination

    local destinationData = BarberCamCoords[ped][destination]
    local coords, target, fov
    if destinationData then
        coords, target, fov = destinationData.coords, destinationData.target, destinationData.fov
    elseif type(data) == "table" and data.coords and data.target then
        coords, target, fov = data.coords, data.target, tonumber(data.fov) or 30.0
    else
        local fallback = BarberCamCoords[ped].default
        coords, target, fov = fallback.coords, fallback.target, fallback.fov
    end

    barberCurrentRawCamCoords = coords
    barberCurrentRawCamTarget = target
    coords, target = ApplyBarberCameraLateralOffset(coords, target)

    BarberCurrentTargetCoords = target
    BarberCamFov = tonumber(fov) or 30.0
    BarberBaseCamFov = BarberCamFov
    BarberViewFov = BarberCamFov

    if BarberActiveCam == 0 then
        BarberCam1 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(BarberCam1, coords)
        PointCamAtCoord(BarberCam1, target)
        SetCamFov(BarberCam1, BarberCamFov)
        SetCamActive(BarberCam1, true)
        if not tpcam then
            RenderScriptCams(true, true, 1000, true, true)
        else
            RenderScriptCams(true, false, 0, true, true)
        end
        SetCamFocusDistance(BarberCam1, #(GetCamCoord(BarberCam1) - GetEntityCoords(ped)))
        BarberActiveCam = 1
        BarberCamera = BarberCam1
    else
        local from, to
        if BarberActiveCam == 1 then
            if not BarberCam2 or not DoesCamExist(BarberCam2) then BarberCam2 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true) end
            from, to = BarberCam1, BarberCam2
            BarberActiveCam = 2
        else
            if not BarberCam1 or not DoesCamExist(BarberCam1) then BarberCam1 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true) end
            from, to = BarberCam2, BarberCam1
            BarberActiveCam = 1
        end
        SetCamCoord(to, coords)
        PointCamAtCoord(to, target)
        SetCamFov(to, BarberCamFov)
        if not tpcam then SetCamActiveWithInterp(to, from, 1000, true, true) else SetCamActive(to, true) end
        SetCamFocusDistance(to, #(GetCamCoord(to) - GetEntityCoords(ped)))
        BarberCamera = to
    end

    TriggerEvent('jrs_hud:busy', 'jrs_barber', true)
    DisplayRadar(false)
    return true
end

-- Legacy API retained for the barber builder.
function BarberCameraUpdate(zoom, offset)
    return BarberMoveCam(BarberCurrentCamDestination ~= "" and BarberCurrentCamDestination or "head")
end

function BarberKillCamera()
    RenderScriptCams(false, true, 350, true, true)
    if BarberCam1 and DoesCamExist(BarberCam1) then DestroyCam(BarberCam1, true) end
    if BarberCam2 and DoesCamExist(BarberCam2) then DestroyCam(BarberCam2, true) end
    if BarberCamera and DoesCamExist(BarberCamera)
        and BarberCamera ~= BarberCam1 and BarberCamera ~= BarberCam2 then
        DestroyCam(BarberCamera, true)
    end
    TriggerEvent('jrs_hud:busy', 'jrs_barber', false)
    pcall(DisplayHud, true)
    DisplayRadar(true)
    BarberActiveCam = 0
    BarberCam1 = nil
    BarberCam2 = nil
    BarberCamera = nil
    BarberCurrentCamDestination = ""
    BarberCurrentTargetCoords = nil
    BarberCamCoords = {}
    BarberViewBaseHeading = nil
    BarberViewFov = nil
    BarberViewPedHandle = nil
    barberCurrentRawCamCoords = nil
    barberCurrentRawCamTarget = nil
    barberViewPanRatio = 0.0
    BarberBaseHeading = nil
    BarberAngleOffset = nil
    BarberCamHeight = 0.0
    BarberCamDistance = 0.7
    BarberCamFov = 30.0
    BarberBaseCamFov = 30.0
    BarberCurrentH, BarberCurrentZ, BarberCurrentR = 180, 217, 180
end

function GetBarberCameraDestination(category, group)
    category = tostring(category or "")
    group = tostring(group or "")
    local hairCategories = { hairstabble = true, hair = true, hair_bonnet = true, hair_stubble = true }
    local beardCategories = {
        beardstabble = true, beard = true, beards_complete = true, beards_chin = true,
        beards_chops = true, beards_mustache = true, stubble = true, full_beard = true,
        chin_hair = true, sideburns = true, mustache = true
    }
    local eyeCategories = { eyes = true, eyebrows = true, eyeliners = true, shadows = true }
    local mouthCategories = { lipsticks = true, lipstick = true }

    if hairCategories[category] or group == "hair" or category == "hair" then return "hair" end
    if beardCategories[category] or group == "beard" or category == "beard" then return "beard" end
    if eyeCategories[category] then return "eyesandbrows" end
    if mouthCategories[category] then return "mouth" end
    if group == "makeup" or group == "lifestyle" or group == "skin" then return "facial" end
    return "head"
end

function FocusBarberCameraCategory(category, group)
    BarberCurrentCamDestination = ""
    return BarberMoveCam(GetBarberCameraDestination(category, group))
end

local function BarberOrbitActiveCamera(deltaDegrees)
    local cam = BarberGetActiveCamera()
    local target = BarberCurrentTargetCoords
    if not cam or not DoesCamExist(cam) or not target then return false end

    local camCoords = GetCamCoord(cam)
    local dx = camCoords.x - target.x
    local dy = camCoords.y - target.y
    local radius = math.sqrt((dx * dx) + (dy * dy))
    if radius < 0.05 then return false end

    local angle = math.atan(dy, dx) + math.rad(tonumber(deltaDegrees) or 0.0)
    local nextX = target.x + math.cos(angle) * radius
    local nextY = target.y + math.sin(angle) * radius
    SetCamCoord(cam, nextX, nextY, camCoords.z)
    PointCamAtCoord(cam, target)
    SetCamFocusDistance(cam, #(vector3(nextX, nextY, camCoords.z) - GetEntityCoords(GetBarberCameraPed())))
    -- Orbit the un-panned base too, otherwise the next pan press rebuilds the
    -- camera from the pre-orbit spot and snaps the view back.
    local rawC, rawT = barberCurrentRawCamCoords, barberCurrentRawCamTarget
    if rawC and rawT then
        local rdx, rdy = rawC.x - rawT.x, rawC.y - rawT.y
        local rr = math.sqrt((rdx * rdx) + (rdy * rdy))
        local ra = math.atan(rdy, rdx) + math.rad(tonumber(deltaDegrees) or 0.0)
        barberCurrentRawCamCoords = vector3(rawT.x + math.cos(ra) * rr, rawT.y + math.sin(ra) * rr, rawC.z)
    end
    return true
end

function HandleBarberViewControl(data)
    data = type(data) == "table" and data or {}
    local action = tostring(data.action or "")
    local focusTarget = tostring(data.target or "")
    local ped = GetBarberCameraPed()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return { ok = false, reason = "invalid_ped" } end

    if BarberViewPedHandle ~= ped then
        BarberViewPedHandle = ped
        BarberViewBaseHeading = GetEntityHeading(ped)
        BarberViewFov = nil
    elseif BarberViewBaseHeading == nil then
        BarberViewBaseHeading = GetEntityHeading(ped)
    end

    local function applyFocus(destination)
        if not destination or destination == "" then return false end
        BarberCurrentCamDestination = ""
        BarberMoveCam(destination)
        local cam = BarberGetActiveCamera()
        if cam then
            BarberViewFov = tonumber(GetCamFov(cam)) or BarberViewFov
            BarberCamFov = BarberViewFov or BarberCamFov
        end
        return true
    end

    local focusMap = {
        fullbody = "Body", body = "Body", head = "head", face = "facial", torso = "upperbody",
        upperbody = "upperbody", hands = "hands", waist = "waist", legs = "lowerbody",
        lowerbody = "lowerbody", boots = "feet", feet = "feet"
    }
    local downSequence = {
        head = "upperbody", hair = "upperbody", beard = "upperbody", eyesandbrows = "upperbody", mouth = "upperbody",
        facial = "upperbody", upperbody = "hands", hands = "waist", waist = "lowerbody",
        lowerbody = "feet", feet = "Body", Body = "lowerbody", [""] = "lowerbody"
    }
    local upSequence = {
        feet = "lowerbody", lowerbody = "waist", waist = "hands", hands = "upperbody",
        upperbody = "head", facial = "head", mouth = "head", eyesandbrows = "head",
        beard = "head", hair = "head", Body = "head", [""] = "head"
    }

    if action == "rotateLeft" or action == "rotateRight" then
        local step = 7.5
        if type(BarberIsSeatActive) == "function" and BarberIsSeatActive() then
            -- A seated barber client must never rotate the ped itself: changing
            -- entity heading breaks PROP_PLAYER_BARBER_SEAT and makes them stand.
            BarberOrbitActiveCamera(action == "rotateLeft" and step or -step)
        else
            local heading = GetEntityHeading(ped)
            heading = heading + (action == "rotateLeft" and step or -step)
            SetEntityHeading(ped, heading % 360.0)
        end
    elseif action == "zoomIn" or action == "zoomOut" then
        local cam = BarberGetActiveCamera()
        if cam then
            local current = tonumber(GetCamFov(cam)) or tonumber(BarberViewFov) or tonumber(BarberBaseCamFov) or 30.0
            local nextFov = current + (action == "zoomIn" and -1.25 or 1.25)
            nextFov = math.max(16.0, math.min(55.0, nextFov))
            BarberViewFov = nextFov
            BarberCamFov = nextFov
            SetCamFov(cam, nextFov)
        end
    elseif action == "moveDown" then
        applyFocus(downSequence[BarberCurrentCamDestination or ""] or "lowerbody")
    elseif action == "moveUp" then
        applyFocus(upSequence[BarberCurrentCamDestination or ""] or "head")
    elseif action == "focus" then
        local mapped = focusMap[string.lower(focusTarget)]
        if not mapped or not applyFocus(mapped) then return { ok = false, reason = "invalid_focus_target" } end
    elseif action == "panRight" then
        -- 0.007 per press was sub-centimetre on the head cam: buttons looked dead.
        barberViewPanRatio = math.min(0.35, barberViewPanRatio + 0.035)
        UpdateBarberActiveCameraPosition()
    elseif action == "panLeft" then
        barberViewPanRatio = math.max(-0.35, barberViewPanRatio - 0.035)
        UpdateBarberActiveCameraPosition()
    elseif action == "centerView" then
        barberViewPanRatio = 0.0
        UpdateBarberActiveCameraPosition()
    elseif action == "reset" then
        barberViewPanRatio = 0.0
        if not (type(BarberIsSeatActive) == "function" and BarberIsSeatActive()) then
            if BarberViewBaseHeading ~= nil then SetEntityHeading(ped, BarberViewBaseHeading) end
        end
        applyFocus("head")
        local cam = BarberGetActiveCamera()
        if cam then
            local resetFov = tonumber(BarberBaseCamFov) or 29.0
            BarberViewFov = resetFov
            BarberCamFov = resetFov
            SetCamFov(cam, resetFov)
        end
    else
        return { ok = false, reason = "invalid_action" }
    end

    return { ok = true, heading = GetEntityHeading(ped), fov = BarberViewFov, current = BarberCurrentCamDestination }
end

BarberCreatorLight = false

function play_anim(dict, name, time, flag, ikflag)
    RequestAnimDict(dict)
    local animDeadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < animDeadline do
        Citizen.Wait(50)
    end
    if not HasAnimDictLoaded(dict) then return false end
    if ikflag == nil then
        ikflag = 0
    end
    TaskPlayAnim(PlayerPedId(), dict, name, 1.0, 1.0, time, flag, 0, true, ikflag, false, 0, false)
end

function BarberPlaySound(action, soundset)
    PlaySoundFrontend(action, soundset, true, 0)
end

function BarberScale(value, oldMin, oldMax, newMin, newMax)
    return (((value - oldMin) * (newMax - newMin)) / (oldMax - oldMin)) + newMin
end

function CaptureBarberHeadwear(ped)
    ped = ped or PlayerPedId()
    local snapshot = {}
    local categories = { 'hats', 'hat_accessories' }
    for _, name in ipairs(categories) do
        local categoryHash = BarberGetHashFromString(name)
        local index = BarberGetComponentIndexByCategory(ped, categoryHash)
        if index and index >= 0 then
            local shopHash = GetShopItemComponentAtIndex(ped, index, true)
            local drawable, albedo, normal, material = BarberGetMetaPedAssetGuids(ped, index)
            local palette, tint0, tint1, tint2 = BarberGetMetaPedAssetTint(ped, index)
            snapshot[#snapshot + 1] = {
                category = name,
                shopHash = tonumber(shopHash) or 0,
                drawable = tonumber(drawable) or 0,
                albedo = tonumber(albedo) or 0,
                normal = tonumber(normal) or 0,
                material = tonumber(material) or 0,
                palette = tonumber(palette) or 0,
                tint0 = tonumber(tint0) or 0,
                tint1 = tonumber(tint1) or 0,
                tint2 = tonumber(tint2) or 0,
            }
        end
    end
    return snapshot
end

function RestoreBarberHeadwear(ped, snapshot)
    ped = ped or PlayerPedId()
    if type(snapshot) ~= 'table' or #snapshot == 0 then return true end
    for _, item in ipairs(snapshot) do
        if tonumber(item.shopHash) and tonumber(item.shopHash) ~= 0 then
            BarberNativeSetPedComponentEnabled(ped, tonumber(item.shopHash), false, true)
        elseif tonumber(item.drawable) and tonumber(item.drawable) ~= 0 then
            BarberSetMetaPedTag(
                ped,
                tonumber(item.drawable) or 0,
                tonumber(item.albedo) or 0,
                tonumber(item.normal) or 0,
                tonumber(item.material) or 0,
                tonumber(item.palette) or 0,
                tonumber(item.tint0) or 0,
                tonumber(item.tint1) or 0,
                tonumber(item.tint2) or 0
            )
        end
    end
    BarberNativeUpdatePedVariation(ped)
    return true
end

function RemoveAllBarber(ped, removeHeadwear)
    local equipped = BarberGetCategoriesEquipped(ped)
    local toremove = {
        hair = true,
        beard = true,
        beards_chin = true,
        beards_chops = true,
        beards_mustache = true,
        beards_complete = true,
        hair_bonnet = true,
    }
    if removeHeadwear == true then
        toremove.hats = true
        toremove.hat_accessories = true
    end

    for category in pairs(equipped) do
        for name in pairs(toremove) do
            if category == BarberGetHashFromString(name) then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, category, 0)
                break
            end
        end
    end

    BarberNativeUpdatePedVariation(ped)
end

local lastanim = 0
function ChangehairstyleAnim()
    -- The chair scenario owns the player's animation. Layering TaskPlayAnim on
    -- top of it ejects the ped from the barber seat, so only use these legacy
    -- showcase animations in creator/mannequin mode.
    if not BarberMannequinPed and type(BarberIsSeatActive) == "function" and BarberIsSeatActive() then
        return true
    end
    RequestAnimDict("script_common@barber_shop@hair_cut")
    local animDeadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded("script_common@barber_shop@hair_cut") and GetGameTimer() < animDeadline do
        Citizen.Wait(0)
    end
    if not HasAnimDictLoaded("script_common@barber_shop@hair_cut") then return false end
    local anim
    if IsPedMale(PlayerPedId()) then
        anim = { "idle_alittle_more_plyr", "idle_approve_plyr", "idle_cut_n_shave_plyr", "idle_shaved_plyr",
            "idle_ok_plyr", "idle_checkout_short_plyr" }
    else
        anim = { "idle_alittle_more_plyr", "idle_approve_plyr", "idle_cut_n_shave_plyr", "idle_ok_plyr",
            "idle_checkout_short_plyr" }
    end
    local selectedanim = math.random(1, #anim)
    lastanim = selectedanim
    repeat selectedanim = math.random(1, #anim) until selectedanim ~= lastanim
    local timer = GetAnimDuration("script_common@barber_shop@hair_cut", anim[selectedanim])
    if BarberCreatorLight == false then
        return
    end
    TaskPlayAnim(PlayerPedId(), "script_common@barber_shop@hair_cut", anim[selectedanim], 1.0, 1.0, -1, 25, 0, true, 15,
        0)
    Wait(timer * 1000 * 2)
    return true
end

local lastidle = 0
function BarberIdleAnim()
    if not BarberMannequinPed and type(BarberIsSeatActive) == "function" and BarberIsSeatActive() then
        return true
    end
    local ped = BarberMannequinPed or PlayerPedId()
    if BarberOutfitMenuOpen == false then return end
    RequestAnimDict("script_common@barber_shop@hair_cut")
    local animDeadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded("script_common@barber_shop@hair_cut") and GetGameTimer() < animDeadline do
        Citizen.Wait(0)
    end
    if not HasAnimDictLoaded("script_common@barber_shop@hair_cut") then return false end
    local idle = { "idle_plyr", "idle_plyr" }
    -- Alternate deterministically; the old repeat/random loop spun (and would
    -- hang forever if the list were ever cut to a single entry).
    local selectedidle = (lastidle % #idle) + 1
    lastidle = selectedidle
    if BarberCreatorLight == false then
        return
    end
    TaskPlayAnim(ped, "script_common@barber_shop@hair_cut", idle[selectedidle], 1.0, 1.0, -1, 25, 0, true, 15, 0)
end

local function BarberUsesHairTintPalette(category)
    category = tostring(category or "")
    return category == "hair" or category == "hairstabble" or category == "hair_bonnet"
        or category == "beard" or category == "beardstabble" or category == "beards_complete"
        or category == "beards_chin" or category == "beards_chops" or category == "beards_mustache"
end

function BarberChange(id, category, change_type, value)
    id = tonumber(id) or 0
    local ped = BarberMannequinPed or PlayerPedId()
    local gender = IsPedMale(ped) and "male" or "female"

    if not BarberHairCache then BarberHairCache = {} end
    if type(BarberHairCache[category]) ~= "table" then
        BarberHairCache[category] = { model = 0, texture = 0 }
    end

    if id < 1 then
        if category == "cloaks" or category == "ponchos" or category == "capes" then
            local categories = { "cloaks", "ponchos", "capes" }
            for k, v in pairs(categories) do
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, v, 0)
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(v), 0)
                local hexHash = tostring(v):match("0x[%x]+")
                local decimalHash = tonumber(hexHash)
                if decimalHash then Citizen.InvokeNative(0xD710A5007C2AC539, ped, decimalHash, 0) end
                if hexHash then Citizen.InvokeNative(0xD710A5007C2AC539, ped, hexHash, true) end
                BarberNativeUpdatePedVariation(ped)
            end
        elseif category == "beard" then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF8016BCA, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF7FE5F2A, 0)
            BarberNativeUpdatePedVariation(ped)
        elseif category == "hair" then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x864B03AE, 0)
            BarberNativeUpdatePedVariation(ped)
        else
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, category, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
            local hexHash = tostring(category):match("0x[%x]+")
            local decimalHash = tonumber(hexHash)
            if decimalHash then Citizen.InvokeNative(0xD710A5007C2AC539, ped, decimalHash, 0) end
            if hexHash then Citizen.InvokeNative(0xD710A5007C2AC539, ped, hexHash, true) end
            BarberNativeUpdatePedVariation(ped)
        end
        BarberHairCache[category].model = 0
        BarberHairCache[category].texture = 0
        return true
    end

    local genderAssets = BarberAssets and BarberAssets[gender]
    local categoryAssets = genderAssets and genderAssets[category]
    local asset = categoryAssets and categoryAssets[id]
    if not asset then return false end

    if change_type == "model" then
        BarberHairCache[category].model = id
        if asset.drawable then
            if category == "beard" then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF7FE5F2A, 0)
            end
            local variants = type(asset.variants) == "table" and asset.variants or {}
            local firstVariant = variants[1] or {}
            local drawable = asset.drawable
            local albedo = firstVariant.albedo
            local normal = firstVariant.normal
            local material = firstVariant.material
            local palette = firstVariant.palette
            local vt = type(firstVariant.tint) == "table" and firstVariant.tint or {}
            local tint0 = tonumber(firstVariant.tint0 or vt[1]) or 0
            local tint1 = tonumber(firstVariant.tint1 or vt[2]) or 0
            local tint2 = tonumber(firstVariant.tint2 or vt[3]) or 0

            if BarberUsesHairTintPalette(category) then
                palette = `metaped_tint_hair`
                tint1 = tint0
                tint2 = tint0
            end

            BarberHairCache[category].texture = {
                palette = 1,
                tint0 = tint0,
                tint1 = tint1,
                tint2 = tint2,
            }

            UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)

        else
            if category == "beard" then
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF8016BCA, 0)
            end
            BarberHairCache[category].texture = 1
            local firstVariant = asset[1]
            if firstVariant and firstVariant.hash then
                BarberNativeSetPedComponentEnabled(ped, firstVariant.hash, false, true, true)
                BarberNativeUpdatePedVariation(ped)
            end
        end
    else
        if asset.drawable then
            local drawable = asset.drawable
            local variants = type(asset.variants) == "table" and asset.variants or {}

            if change_type == "variants" then
                local variantIndex = math.max(1, math.floor(tonumber(value) or 1))
                local selectedVariant = variants[variantIndex] or variants[1]
                if not selectedVariant then return false end

                local vt = type(selectedVariant.tint) == "table" and selectedVariant.tint or {}
                local tint0 = tonumber(selectedVariant.tint0 or vt[1]) or 0
                local tint1 = tonumber(selectedVariant.tint1 or vt[2]) or 0
                local tint2 = tonumber(selectedVariant.tint2 or vt[3]) or 0

                if BarberUsesHairTintPalette(category) then
                    palette = `metaped_tint_hair`
                    tint1 = tint0
                    tint2 = tint0
                end

                if type(BarberHairCache[category].texture) ~= "table" then
                    BarberHairCache[category].texture = {}
                end
                BarberHairCache[category].texture.palette = variantIndex
                BarberHairCache[category].texture.tint0 = tint0
                BarberHairCache[category].texture.tint1 = tint1
                BarberHairCache[category].texture.tint2 = tint2

                local albedo = selectedVariant.albedo
                local normal = selectedVariant.normal
                local material = selectedVariant.material
                local palette = selectedVariant.palette

                if BarberUsesHairTintPalette(category) then
                    palette = `metaped_tint_hair`
                end

                UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            elseif change_type == 1 or change_type == 2 or change_type == 3 then
                if type(BarberHairCache[category].texture) ~= "table" then
                    local defTint = (variants[1] and type(variants[1].tint) == "table" and variants[1].tint) or {}
                    local baseT = tonumber(defTint[1]) or 0
                    BarberHairCache[category].texture = {
                        palette = 1,
                        tint0 = baseT,
                        tint1 = baseT,
                        tint2 = baseT,
                    }
                end

                local curPalette = tonumber(BarberHairCache[category].texture.palette) or 1
                local currentVariant = variants[curPalette] or variants[1] or {}

                local albedo = currentVariant.albedo
                local normal = currentVariant.normal
                local material = currentVariant.material
                local palette = currentVariant.palette

                local val = tonumber(value) or 0
                if change_type == 1 then
                    BarberHairCache[category].texture.tint0 = val
                    if BarberUsesHairTintPalette(category) and not BarberHairCache[category].texture.custom_tint1 then
                        BarberHairCache[category].texture.tint1 = val
                    end
                    if BarberUsesHairTintPalette(category) and not BarberHairCache[category].texture.custom_tint2 then
                        BarberHairCache[category].texture.tint2 = val
                    end
                elseif change_type == 2 then
                    BarberHairCache[category].texture.tint1 = val
                    BarberHairCache[category].texture.custom_tint1 = true
                elseif change_type == 3 then
                    BarberHairCache[category].texture.tint2 = val
                    BarberHairCache[category].texture.custom_tint2 = true
                end

                local tint0 = tonumber(BarberHairCache[category].texture.tint0) or 0
                local tint1 = tonumber(BarberHairCache[category].texture.tint1) or tint0
                local tint2 = tonumber(BarberHairCache[category].texture.tint2) or tint0

                if BarberUsesHairTintPalette(category) then
                    palette = `metaped_tint_hair`
                end

                UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            end
        else
            local catHash = (category == "beard") and -134124598 or (type(category) == "number" and category or joaat(category))

            if change_type == "variants" then
                local variantIndex = math.max(1, math.floor(tonumber(value) or 1))
                if type(BarberHairCache[category].texture) == "table" then
                    BarberHairCache[category].texture.model = variantIndex
                else
                    BarberHairCache[category].texture = variantIndex
                end
                local selectedVariant = asset[variantIndex] or asset[1]
                if selectedVariant and selectedVariant.hash then
                    BarberNativeSetPedComponentEnabled(ped, selectedVariant.hash, false, true, true)
                    BarberNativeUpdatePedVariation(ped)
                end
            elseif change_type == 1 or change_type == 2 or change_type == 3 then
                local componentIndex = BarberGetComponentIndexByCategory(ped, catHash)
                if componentIndex == -1 then return false end

                local drawable, albedo, normal, material = BarberGetMetaPedAssetGuids(ped, componentIndex)
                local palette, tint0, tint1, tint2 = BarberGetMetaPedAssetTint(ped, componentIndex)

                if type(BarberHairCache[category].texture) ~= "table" then
                    local currentVar = tonumber(BarberHairCache[category].texture) or 1
                    BarberHairCache[category].texture = {
                        model = currentVar,
                        tint0 = tint0 or 0,
                        tint1 = tint1 or 0,
                        tint2 = tint2 or 0,
                    }
                end

                local val = tonumber(value) or 0
                if change_type == 1 then
                    BarberHairCache[category].texture.tint0 = val
                elseif change_type == 2 then
                    BarberHairCache[category].texture.tint1 = val
                elseif change_type == 3 then
                    BarberHairCache[category].texture.tint2 = val
                end

                tint0 = tonumber(BarberHairCache[category].texture.tint0) or 0
                tint1 = tonumber(BarberHairCache[category].texture.tint1) or 0
                tint2 = tonumber(BarberHairCache[category].texture.tint2) or 0
                palette = `metaped_tint_hair`

                UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            end
        end
    end
    return true
end

RegisterNetEvent('jrs_barber:clotheitem')
AddEventHandler('jrs_barber:clotheitem', function(hairstyleComponents, outfitid, overlay, target, charid, previewOnly)
    Citizen.CreateThread(function()
        local _Target = target or PlayerPedId()
        local gender
        if IsPedMale(_Target) then gender = "male" else gender = "female" end
        BarberHairCache = type(hairstyleComponents) == "table" and BarberDeepcopy(hairstyleComponents) or {}
        for k, v in pairs(BarberAssets[gender] or {}) do
            if BarberHairCache[k] == nil then
                BarberHairCache[k] = { model = 0, texture = 0 }
            end
        end
        BarberOldHairCache = BarberDeepcopy(BarberHairCache)
        Callback.triggerServer("jrs_barber:GetCurrentOverlays", function(makeup, permanent)
            makeup = type(makeup) == "table" and makeup or {}
            permanent = type(permanent) == "table" and permanent or {}
            BarberActualAlbedo = nil
            Callback.triggerServer("jrs_barber:GetCharSkinTone", function(result)
                BarberActualAlbedo = result
            end, IsPedMale(_Target), charid)
            WaitForBarberAlbedo(_Target, 5000)
            if GetHead(_Target) ~= 0 then
                if overlay == false then
                    RemoveOverlays(_Target)
                    BarberOverlayLayers = BarberDeepcopy(BarberBaseOverlay)
                    for k, v in pairs(BarberOverlayLayers) do
                        for key, value in pairs(makeup) do
                            if v.name == value.name then
                                -- Replace direct assignment with field updates
                                for field, val in pairs(value) do
                                    BarberOverlayLayers[k][field] = val
                                end
                            end
                        end
                        for key, value in pairs(permanent) do
                            if v.name == value.name then
                                -- Replace direct assignment with field updates
                                for field, val in pairs(value) do
                                    BarberOverlayLayers[k][field] = val
                                end
                            end
                        end
                    end
                end
            end
            local canloadhair = false
            for k, v in pairs(BarberHairCache) do
                if type(v) == "table" and (tonumber(v.model) or 0) > 0 then
                    canloadhair = true
                    break
                end
            end
            if canloadhair then
                RemoveAllBarber(_Target)
                ReequipAllhairstyle(_Target, BarberHairCache)
            end

            -- Eye colour is independent of hair: a bald character must still get
            -- their saved eyes back, so this sits outside the canloadhair gate.
            local eyeIndex = BarberResolveEyeIndex(BarberHairCache, _Target)
            if eyeIndex > 0 then BarberApplyEyeColour(_Target, eyeIndex) end

            if GetHead(_Target) ~= 0 then
                for k, v in pairs(BarberOverlayLayers) do
                    if v.visibility > 0 then
                        UpdateOverlay(_Target)
                        break
                    end
                end
            end

            if charid == nil and previewOnly ~= true then
                TriggerServerEvent("jrs_barber:updatehairstyle", BarberHairCache, BarberOverlayLayers, outfitid)
            end
        end, charid)
    end)
end)


-------- OVERLAYS --------
local textureId = -1

function RemoveOverlays(ped)
    Callback.triggerServer("jrs_barber:GetCurrentOverlays", function(makeup, permanent)
        permanent = type(permanent) == "table" and permanent or {}
        BarberOverlayLayers = BarberDeepcopy(BarberBaseOverlay)
        for k, v in pairs(BarberOverlayLayers) do
            for key, value in pairs(permanent) do
                if v.name == value.name then
                    -- Replace direct assignment with field updates
                    for field, val in pairs(value) do
                        BarberOverlayLayers[k][field] = val
                    end
                end
            end
        end
        Wait(200)
        UpdateOverlay(ped)
    end)
end

local BarberOverlayUpdateRunning = false
local BarberOverlayUpdateQueued = false
local BarberOverlayUpdatePed = nil

local function ApplyBarberOverlayTexture(ped)
    if IsPedMale(ped) then
        current_texture_settings = BarberTextureTypes["male"]
    else
        current_texture_settings = BarberTextureTypes["female"]
    end
    local albedo = WaitForBarberAlbedo(ped, 5000)
    current_texture_settings.albedo = albedo
    if textureId ~= -1 then
        Citizen.InvokeNative(0xB63B9178D0F58D82, textureId) -- reset texture
        Citizen.InvokeNative(0x6BEFAA907B076859, textureId) -- remove texture
    end
    textureId = Citizen.InvokeNative(0xC5E7204F322E49EB, current_texture_settings.albedo,
        current_texture_settings.normal, current_texture_settings.material)
    local attempts = 0
    repeat
        attempts = attempts + 1
        Citizen.InvokeNative(0xB63B9178D0F58D82, textureId)
        Citizen.InvokeNative(0x6BEFAA907B076859, textureId)
        textureId = Citizen.InvokeNative(0xC5E7204F322E49EB, current_texture_settings.albedo,
            current_texture_settings.normal, current_texture_settings.material)
        Citizen.Wait(10)
    until textureId ~= -1 or attempts > 20

    if textureId == -1 then return false end

    for _, v in pairs(BarberOverlayLayers) do
        if v.visibility and tonumber(v.visibility) ~= 0 then
            local tx_id = v.tx_id
            local tx_normal = v.tx_normal or 0
            local tx_material = v.tx_material or 0

            if BarberOverlaysInfo and BarberOverlaysInfo[v.name] then
                local info = nil
                if v.tx_id_index and BarberOverlaysInfo[v.name][v.tx_id_index] then
                    info = BarberOverlaysInfo[v.name][v.tx_id_index]
                elseif type(tx_id) == "number" and tx_id > 0 and tx_id <= #BarberOverlaysInfo[v.name] then
                    info = BarberOverlaysInfo[v.name][tx_id]
                else
                    for _, entry in ipairs(BarberOverlaysInfo[v.name]) do
                        if entry.id == tx_id then
                            info = entry
                            break
                        end
                    end
                end

                if info then
                    if info.id and (not tx_id or tx_id == 0 or (type(tx_id) == "number" and tx_id <= #BarberOverlaysInfo[v.name] and tx_id > 0)) then
                        tx_id = info.id
                    end
                    if (tx_normal == 0 or not tx_normal) and info.normal then
                        tx_normal = info.normal
                    end
                    if (tx_material == 0 or not tx_material) and (info.ma or info.material) then
                        tx_material = info.ma or info.material
                    end
                end
            end

            local tx_opacity = tonumber(v.tx_opacity)
            if not tx_opacity or tx_opacity <= 0.0 then tx_opacity = 1.0 end
            local opacity = tonumber(v.opacity)
            if not opacity or opacity <= 0.0 then opacity = 1.0 end

            local overlay_id = Citizen.InvokeNative(0x86BB5FF45F193A02, textureId, tx_id, tx_normal,
                tx_material, v.tx_color_type or 0, tx_opacity, v.tx_unk or 0)
            if (v.tx_color_type or 0) == 0 then
                Citizen.InvokeNative(0x1ED8588524AC9BE1, textureId, overlay_id, v.palette or 0)
                Citizen.InvokeNative(0x2DF59FFE6FFD6044, textureId, overlay_id, v.palette_color_primary or 0,
                    v.palette_color_secondary or 0, v.palette_color_tertiary or 0)
            end
            Citizen.InvokeNative(0x3329AAE2882FC8E4, textureId, overlay_id, v.var or 0)
            Citizen.InvokeNative(0x6C76BC24F8BB709A, textureId, overlay_id, opacity)
        end
    end

    local textureDeadline = GetGameTimer() + 2500
    while not Citizen.InvokeNative(0x31DC8D3F216D8509, textureId) and GetGameTimer() < textureDeadline do
        Citizen.Wait(0)
    end
    if not Citizen.InvokeNative(0x31DC8D3F216D8509, textureId) then
        Citizen.InvokeNative(0x6BEFAA907B076859, textureId)
        textureId = -1
        return false
    end

    Citizen.InvokeNative(0x0B46E25761519058, ped, `heads`, textureId)
    Citizen.InvokeNative(0x92DAABA2C1C10B0E, textureId)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
    -- Texture handle must be kept active on the ped; do NOT delete it here.
    -- Reapply facial expressions after ped variation update
    TriggerEvent('jrs_character:reapplyExpressions', ped)
    return true
end

function UpdateOverlay(ped)
    BarberOverlayUpdatePed = ped or PlayerPedId()
    if BarberOverlayUpdateRunning then
        -- Several colour/opacity sliders can fire while a metaped texture is
        -- still being built. Keep only one extra pass with the newest state.
        BarberOverlayUpdateQueued = true
        return true
    end

    BarberOverlayUpdateRunning = true
    local result = true
    repeat
        BarberOverlayUpdateQueued = false
        local ok, applied = pcall(ApplyBarberOverlayTexture, BarberOverlayUpdatePed)
        if not ok then
            print(('[jrs_barber] barber overlay update failed: %s'):format(tostring(applied)))
            result = false
            break
        end
        if applied == false then result = false end
        Citizen.Wait(0)
    until not BarberOverlayUpdateQueued

    BarberOverlayUpdateRunning = false
    return result
end

------------ NATIVE AND BASICS ----------------

function ReequipAllhairstyle(ped, hairstyleComponents)
    local gender
    if IsPedMale(ped) then gender = "male" else gender = "female" end

    -- Selector preview peds can be loaded at the same time.  Use the supplied
    -- character data when present instead of the shared player editor cache.
    local components = hairstyleComponents or BarberHairCache
    if type(components) ~= "table" then return end

    for category, data in pairs(components) do
        -- Categories that are not barber assets (eye colour, or a stale entry
        -- from an older save) must be skipped instead of indexing nil and
        -- aborting the whole re-equip.
        local categoryAssets = BarberAssets[gender] and BarberAssets[gender][category]
        local modelIndex = type(data) == "table" and tonumber(data.model) or 0
        if modelIndex > 0 and type(categoryAssets) == "table" and categoryAssets[modelIndex] then
            local asset = categoryAssets[modelIndex]
            local drawable = asset.drawable
            if drawable then
                local varIdx = 1
                if type(data.texture) == "table" then
                    varIdx = tonumber(data.texture.palette or data.texture.model) or 1
                else
                    varIdx = tonumber(data.texture) or 1
                end
                if varIdx < 1 then varIdx = 1 end

                local variants = type(asset.variants) == "table" and asset.variants or {}
                local selectedVariant = variants[varIdx] or variants[1]
                if selectedVariant then
                    local albedo = selectedVariant.albedo
                    local normal = selectedVariant.normal
                    local material = selectedVariant.material
                    local palette = selectedVariant.palette
                    local vt = type(selectedVariant.tint) == "table" and selectedVariant.tint or {}
                    local tint0 = 0
                    local tint1 = 0
                    local tint2 = 0

                    if BarberUsesHairTintPalette(category) then
                        palette = `metaped_tint_hair`
                        if type(data.texture) == "table" then
                            local baseTint = tonumber(data.texture.tint0) or tonumber(vt[1]) or 0
                            tint0 = baseTint
                            tint1 = tonumber(data.texture.tint1) or baseTint
                            tint2 = tonumber(data.texture.tint2) or baseTint
                        else
                            local baseTint = tonumber(vt[1]) or 0
                            tint0 = baseTint
                            tint1 = baseTint
                            tint2 = baseTint
                        end
                    else
                        tint0 = tonumber(type(data.texture) == "table" and (data.texture.tint0 or vt[1]) or vt[1]) or 0
                        tint1 = tonumber(type(data.texture) == "table" and (data.texture.tint1 or vt[2]) or vt[2]) or 0
                        tint2 = tonumber(type(data.texture) == "table" and (data.texture.tint2 or vt[3]) or vt[3]) or 0
                    end

                    UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                end
            else
                -- Non-drawable component (e.g. beard hashes)
                local varIdx = 1
                if type(data.texture) == "table" then
                    varIdx = tonumber(data.texture.model or data.texture.palette) or 1
                else
                    varIdx = tonumber(data.texture) or 1
                end
                if varIdx < 1 then varIdx = 1 end

                local selectedVariant = asset[varIdx] or asset[1]
                if selectedVariant and selectedVariant.hash then
                    BarberNativeSetPedComponentEnabled(ped, selectedVariant.hash, false, true, true)
                    BarberNativeUpdatePedVariation(ped)

                    if type(data.texture) == "table" and (data.texture.tint0 or data.texture.tint1 or data.texture.tint2) then
                        local catHash = (category == "beard") and -134124598 or (type(category) == "number" and category or joaat(category))
                        local componentDeadline = GetGameTimer() + 1500
                        local componentIndex = BarberGetComponentIndexByCategory(ped, catHash)
                        while componentIndex == -1 and GetGameTimer() < componentDeadline do
                            Wait(0)
                            componentIndex = BarberGetComponentIndexByCategory(ped, catHash)
                        end
                        if componentIndex ~= -1 then
                            local d, albedo, normal, material = BarberGetMetaPedAssetGuids(ped, componentIndex)
                            local palette = `metaped_tint_hair`
                            local baseTint = tonumber(data.texture.tint0) or 0
                            local tint0 = baseTint
                            local tint1 = tonumber(data.texture.tint1) or baseTint
                            local tint2 = tonumber(data.texture.tint2) or baseTint
                            UpdateCustomhairstyle(ped, d, albedo, normal, material, palette, tint0, tint1, tint2)
                        end
                    end
                end
            end
        end
    end
end

function BarberGetComponentIndexByCategory(ped, category)
    local numComponents = BarberGetNumComponentsInPed(ped)
    for i = 0, numComponents - 1, 1 do
        local componentCategory = BarberGetCategoryOfComponentAtIndex(ped, i)
        if componentCategory == category then
            return i
        end
    end
    return -1
end

function BarberNativeGetPedComponentCategory(isFemale, componentHash)
    return Citizen.InvokeNative(0x5FF9A878C3D115B8, componentHash, isFemale, true)
end

function BarberNativeSetPedComponentEnabled(ped, componentHash, immediately, isMp)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not componentHash then return false end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, immediately == true, isMp ~= false, true)
    BarberNativeFixMeshIssues(ped)
    BarberNativeUpdatePedVariation(ped)
    return true
end

function BarberNativeFixMeshIssues(ped, categoryHash)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, 1)
end

function BarberSetMetaPedTag(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
end

function BarberUpdatePedVariation(ped)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)                           -- UNKNOWN "Fixes outfit"- always paired with _UPDATE_PED_VARIATION
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) -- _UPDATE_PED_VARIATION
end

function BarberGetMetaPedAssetGuids(ped, index)
    return Citizen.InvokeNative(0xA9C28516A6DC9D56, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(),
        Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

function BarberGetMetaPedAssetTint(ped, index)
    return Citizen.InvokeNative(0xE7998FEC53A33BBE, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(),
        Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

GetMetaPedAssetGuids = BarberGetMetaPedAssetGuids
GetMetaPedAssetTint = BarberGetMetaPedAssetTint

-- ---------------------------------------------------------------------------
-- Eye colour
-- The eye colour is a MetaPed shop item hash, not a barber asset, so it does
-- not live in BarberAssets. It is applied with _APPLY_SHOP_ITEM_TO_PED, exactly
-- as jrs_character's creator does, and is carried through BarberHairCache.eyes
-- as a 1-based index into the shared Eyes table so it saves, prices and
-- restores with the rest of the barber data.
-- ---------------------------------------------------------------------------

function BarberEyeList(ped)
    local key = IsPedMale(ped or PlayerPedId()) and "Male" or "Female"
    local list = type(Eyes) == "table" and Eyes[key] or nil
    return type(list) == "table" and list or {}, key
end

function BarberEyeCount(ped)
    return #(BarberEyeList(ped))
end

function BarberClampEyeIndex(value, ped)
    local count = BarberEyeCount(ped)
    if count <= 0 then return 0 end
    value = math.floor(tonumber(value) or 0)
    if value < 1 then return 1 end
    if value > count then return count end
    return value
end

function BarberApplyEyeColour(ped, index)
    ped = ped or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    -- Index 0 means "this character has no stored eye colour". Clamping it up
    -- to 1 here would silently repaint every ped that never chose one.
    if (tonumber(index) or 0) < 1 then return false end

    local list = BarberEyeList(ped)
    local hash = tonumber(list[BarberClampEyeIndex(index, ped)])
    if not hash then return false end

    -- Both passes are required: the first registers the item, the second
    -- commits it to the rendered head.
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, false, false, false)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, hash, false, true, false)
    BarberUpdatePedVariation(ped)
    return true
end

-- Reads the index the player currently has stored, falling back to whatever
-- characters.skinPlayer holds so an existing character keeps their eyes.
function BarberResolveEyeIndex(cache, ped)
    local stored = type(cache) == "table" and type(cache.eyes) == "table"
        and tonumber(cache.eyes.model) or nil
    if stored and stored > 0 then return BarberClampEyeIndex(stored, ped) end
    return 0
end

function BarberSetEyeCache(cache, index)
    if type(cache) ~= "table" then return cache end
    index = BarberClampEyeIndex(index)
    if index <= 0 then
        cache.eyes = nil
    else
        cache.eyes = { model = index, texture = 0 }
    end
    return cache
end

function UpdateCustomhairstyle(playerPed, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    local deadline = GetGameTimer() + 2000
    while not BarberNativeHasPedComponentLoaded(playerPed) and GetGameTimer() < deadline do
        Wait(0)
    end
    -- This only waits for the PREVIOUS component change (if any) to finish
    -- streaming before touching the ped again - it is not a check on whether
    -- THIS drawable can be applied. Bailing out here on a slow/cold cache used
    -- to skip BarberSetMetaPedTag/BarberUpdatePedVariation entirely and just
    -- return false (which every caller discards), so the moustache/beard the
    -- player picked would silently never appear. Proceed regardless, same as
    -- BarberNativeUpdatePedVariation below already does after its own
    -- identical bounded wait.
    local playerPed = playerPed
    local _drawable = tonumber(drawable)
    local _albedo = tonumber(albedo)
    local _normal = tonumber(normal)
    local _material = tonumber(material)
    local _palette = tonumber(palette)
    local _tint0 = tonumber(tint0)
    local _tint1 = tonumber(tint1)
    local _tint2 = tonumber(tint2)
    BarberSetMetaPedTag(playerPed, _drawable, _albedo, _normal, _material, _palette, _tint0, _tint1, _tint2)
    BarberUpdatePedVariation(playerPed)
end

function BarberNativeUpdatePedVariation(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true) -- UNKNOWN "Fixes outfit"- always paired with _UPDATE_PED_VARIATION
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    local deadline = GetGameTimer() + 2000
    while not BarberNativeHasPedComponentLoaded(ped) and GetGameTimer() < deadline do
        Wait(1)
    end
end

function BarberGetNumComponentsInPed(ped)
    return Citizen.InvokeNative(0x90403E8107B60E81, ped, Citizen.ResultAsInteger())
end

function BarberGetCategoryOfComponentAtIndex(ped, componentIndex)
    return Citizen.InvokeNative(0x9b90842304c938a7, ped, componentIndex, 0, Citizen.ResultAsInteger())
end

function BarberNativeHasPedComponentLoaded(ped)
    return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
end

function BarberGetCategoriesEquipped(ped)
    local equiped = {}
    local numComponent = BarberGetNumComponentsInPed(ped) or 0
    for index = 0, numComponent - 1 do
        --Get current component
        local category = BarberGetCategoryOfComponentAtIndex(ped, index)
        equiped[category] = {
            index = index,
        }
        if category == `neckwear` then
            equiped[`neckerchiefs`] = equiped[category]
            equiped[`neckerchiefs`].category = "neckerchiefs"
        elseif category == `neckerchiefs` then
            equiped[`neckwear`] = equiped[category]
            equiped[`neckwear`].category = "neckwear"
        end
    end
    --clear cached value
    local component = equiped
    return component
end

function BarberGetHashFromString(value)
    if type(value) == "string" then
        local number = tonumber(value)
        if number then return number end
        return joaat(value)
    end
    return value
end

function BarberDeepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[BarberDeepcopy(orig_key)] = BarberDeepcopy(orig_value)
        end
        setmetatable(copy, BarberDeepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function GetHead(ped)
    local numComponents = BarberGetNumComponentsInPed(ped)
    for i = 0, numComponents - 1, 1 do
        local componentCategory = BarberGetCategoryOfComponentAtIndex(ped, i)
        if componentCategory == `heads` then
            local shopitem = GetShopItemComponentAtIndex(ped, i, true)
            return shopitem
        end
    end
end

function CaptureCurrentJRSBarber(ped)
    ped = ped or PlayerPedId()
    local gender = IsPedMale(ped) and 'male' or 'female'
    local assets = BarberAssets and BarberAssets[gender]
    if type(assets) ~= 'table' then return {} end

    local captured = {}
    for category, models in pairs(assets) do
        if type(models) == 'table' then
            local categoryHash = category == 'beard' and -134124598 or joaat(category)
            local componentIndex = BarberGetComponentIndexByCategory(ped, categoryHash)
            if componentIndex and componentIndex >= 0 then
                local equippedHash = GetShopItemComponentAtIndex(ped, componentIndex, true)
                local drawable, albedo, normal, material = BarberGetMetaPedAssetGuids(ped, componentIndex)
                for modelIndex, modelData in pairs(models) do
                    if type(modelIndex) == 'number' and type(modelData) == 'table' then
                        if modelData.drawable and tonumber(modelData.drawable) == tonumber(drawable) then
                            for variantIndex, variant in pairs(modelData.variants or {}) do
                                if type(variantIndex) == 'number' and type(variant) == 'table'
                                    and tonumber(variant.albedo) == tonumber(albedo)
                                    and tonumber(variant.normal) == tonumber(normal)
                                    and tonumber(variant.material) == tonumber(material) then
                                    local _, tint0, tint1, tint2 = BarberGetMetaPedAssetTint(ped, componentIndex)
                                    captured[category] = {
                                        model = modelIndex,
                                        texture = { palette = variantIndex, model = variantIndex, tint0 = tint0 or 0, tint1 = tint1 or 0, tint2 = tint2 or 0 }
                                    }
                                    break
                                end
                            end
                        else
                            for textureIndex, variant in pairs(modelData) do
                                if type(textureIndex) == 'number' and type(variant) == 'table'
                                    and tonumber(variant.hash) == tonumber(equippedHash) then
                                    captured[category] = { model = modelIndex, texture = textureIndex }
                                    break
                                end
                            end
                        end
                    end
                    if captured[category] then break end
                end
            end
        end
    end
    return captured
end

function ConvertLegacyJRSOverlays(skin)
    skin = type(skin) == 'table' and skin or {}
    local converted = BarberDeepcopy(BarberBaseOverlay or {})
    for _, layer in pairs(converted) do
        local prefix = tostring(layer.name or '')
        local function take(field, suffix)
            local value = skin[prefix .. suffix]
            if value ~= nil then layer[field] = value end
        end
        take('visibility', '_visibility')
        take('tx_id_index', '_tx_id')
        take('tx_color_type', '_color_type')
        take('palette_color_primary', '_color_1')
        take('palette_color_secondary', '_color_2')
        take('palette_color_tertiary', '_color_3')
        take('var', '_var')
        take('opacity', '_opacity')
    end
    return converted
end

exports('CaptureCurrentBarber', CaptureCurrentJRSBarber)

RegisterNetEvent('jrs_barber:captureCurrent', function(skin)
    CreateThread(function()
        Wait(750)
        TriggerServerEvent(
            'jrs_barber:updatehairstyle',
            CaptureCurrentJRSBarber(PlayerPedId()),
            ConvertLegacyJRSOverlays(skin),
            0
        )
    end)
end)

RegisterNetEvent('jrs_barber:loadbarberoverlay', function()
    Callback.triggerServer('jrs_barber:GetCurrentHairs', function(datatable, outfitid, makeup, permanent, exists, legacySkin)
        if exists ~= true then
            CreateThread(function()
                Wait(2500)
                local captured = CaptureCurrentJRSBarber(PlayerPedId())
                local convertedOverlays = ConvertLegacyJRSOverlays(legacySkin)
                TriggerServerEvent('jrs_barber:updatehairstyle', captured, convertedOverlays, 0)
            end)
            return
        end
        if datatable then
            makeup = type(makeup) == "table" and makeup or {}
            permanent = type(permanent) == "table" and permanent or {}
            BarberOverlayLayers = BarberDeepcopy(BarberBaseOverlay)
            for k, v in pairs(BarberOverlayLayers) do
                for key, value in pairs(makeup) do
                    if v.name == value.name then
                        -- Replace direct assignment with field updates
                        for field, val in pairs(value) do
                            BarberOverlayLayers[k][field] = val
                        end
                    end
                end
                for key, value in pairs(permanent) do
                    if v.name == value.name then
                        -- Replace direct assignment with field updates
                        for field, val in pairs(value) do
                            BarberOverlayLayers[k][field] = val
                        end
                    end
                end
            end
            TriggerEvent("jrs_barber:clotheitem", datatable, outfitid, true, nil, nil, true)
        end
    end)
end)

RegisterNetEvent('jrs_barber:loadbarberoverlayOnCharacter', function(charid, ped)
    Callback.triggerServer('jrs_barber:GetCurrentHairsOnCharacter', function(datatable, outfitid, makeup, permanent)
        if type(datatable) == 'table' and next(datatable) ~= nil and ped and DoesEntityExist(ped) then
            -- Do not route selector previews through jrs_barber:clotheitem.
            -- That event owns the live player's shared editor cache, so several
            -- preview peds loading together could inherit another character's
            -- hair. Apply this character's saved hair/beard data directly.
            RemoveAllBarber(ped)
            local previewCache = BarberDeepcopy(datatable)
            ReequipAllhairstyle(ped, previewCache)
            BarberApplyEyeColour(ped, BarberResolveEyeIndex(previewCache, ped))
        end
    end, charid)
end)
