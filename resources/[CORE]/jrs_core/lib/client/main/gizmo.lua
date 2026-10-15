local usingGizmo = false
local editingStop = false
local cam = nil
local isRadarActive = false

local function toggleNuiFrame(bool)
    usingGizmo = bool
    JRSExtLibFocus(bool, bool)
end

local function startScriptedCam()
    isRadarActive = IsRadarHidden() == 1 and false or true

    DisplayRadar(false)
    if cam then
        DestroyCam(cam, false)
        cam = nil
    end

    local coords = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local fov = GetGameplayCamFov()

    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(cam, coords.x, coords.y, coords.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true, 0)

    return {
        position = coords,
        rotation = rot,
    }
end

local function stopScriptedCam()
    if not cam then
        return
    end

    RenderScriptCams(false, true, 500, true, true, 0)
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    cam = nil
end

---@param data? { lang?: table, dist?: { min?: number, max?: number } }
--- lang keys: controlsTitle, cameraTitle, transform, rotate, placeOnGround, apply, cancel,
--- zoomIn, zoomOut, rotateLeft, rotateRight, raise, lower, focusEntity
local function useGizmo(handle, alpha, placeOnGround, deleteOnStop, createCam, data)
    local initialCamera = nil

    if createCam then
        initialCamera = startScriptedCam()
    end

    if alpha then
        SetEntityAlpha(handle, alpha, true)
    end

    if placeOnGround then
        PlaceEntityOnGroundProperly(handle, true)
    end

    FreezeEntityPosition(handle, true)

    if data then
        JRSExtLibNUI({
            action = 'addData',
            data = data,
        })
    end

    JRSExtLibNUI({
        action = 'setGizmoEntity',
        data = {
            handle = handle,
            position = GetEntityCoords(handle),
            rotation = GetEntityRotation(handle),
        },
    })

    if createCam and initialCamera then
        JRSExtLibNUI({
            action = 'setCameraMode',
            data = {
                enabled = true,
                position = initialCamera.position,
                rotation = initialCamera.rotation,
            },
        })
    end

    toggleNuiFrame(true)

    while usingGizmo do
        JRSExtLibNUI({
            action = 'setCameraPosition',
            data = {
                position = GetFinalRenderedCamCoord(),
                rotation = GetFinalRenderedCamRot(0),
            },
        })
        Wait(0)
    end

    FreezeEntityPosition(handle, false)

    local _data = {
        handle = handle,
        position = GetEntityCoords(handle),
        rotation = GetEntityRotation(handle),
    }

    SetTimeout(1000, function()
        editingStop = false
    end)

    if deleteOnStop then
        DeleteEntity(handle)
    end

    if createCam then
        JRSExtLibNUI({
            action = 'setCameraMode',
            data = { enabled = false },
        })
        stopScriptedCam()
    end

    DisplayRadar(isRadarActive)
    SetGameplayCamInitialHeading(0)

    return not editingStop and _data or nil
end

RegisterNUICallback('extlib_moveEntity', function(data, cb)
    local entity = data.handle
    local position = data.position
    local rotation = data.rotation

    SetEntityCoords(entity, position.x, position.y, position.z, false, false, false, false)
    SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 0, false)
    cb('ok')
end)

RegisterNUICallback('extlib_placeOnGround', function(data, cb)
    local entity = data.handle
    PlaceObjectOnGroundProperly(entity, false)

    JRSExtLibNUI({
        action = 'setGizmoEntity',
        data = {
            handle = entity,
            position = GetEntityCoords(entity),
            rotation = GetEntityRotation(entity),
        },
    })

    cb('ok')
end)

RegisterNUICallback('extlib_syncScriptedCam', function(data, cb)
    if not cam then
        cb('ok')
        return
    end

    local position = data.position
    local rotation = data.rotation

    if position then
        SetCamCoord(cam, position.x, position.y, position.z)
    end

    if rotation then
        SetCamRot(cam, rotation.x, rotation.y, rotation.z, 2)
    end

    cb('ok')
end)

RegisterNUICallback('extlib_finishEdit', function(_, cb)
    toggleNuiFrame(false)
    JRSExtLibNUI({
        action = 'setGizmoEntity',
        data = {
            handle = nil,
        },
    })
    cb('ok')
end)


RegisterNUICallback('extlib_stopEditing', function(_, cb)
    toggleNuiFrame(false)
    editingStop = true
    JRSExtLibNUI({
        action = 'setGizmoEntity',
        data = {
            handle = nil,
        },
    })
    cb('ok')
end)

exports('StartGizmo', useGizmo)

exports('StopGizmo', function()
    toggleNuiFrame(false)
    editingStop = true
    JRSExtLibNUI({
        action = 'setGizmoEntity',
        data = { handle = nil },
    })
end)

