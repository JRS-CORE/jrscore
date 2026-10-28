-- ===================================================================
-- JRS CORE | Native Death & Hospital Respawn (Client)
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local DeathConfig = {
    RespawnHoldTime = 4000,
    RespawnCooldown = 8,
    Hospitals = {
        { name = "Valentine Clinic",     coords = vector4(-283.83, 806.40, 119.38, 321.76) },
        { name = "Saint Denis Hospital", coords = vector4(2721.45, -1446.10, 46.23, 321.76) },
        { name = "Blackwater Medical",   coords = vector4(-723.95, -1242.84, 44.73, 321.76) },
        { name = "Rhodes Clinic",        coords = vector4(1229.00, -1306.10, 76.90, 321.76) },
        { name = "Armadillo Clinic",     coords = vector4(-3742.50, -2600.90, -13.23, 321.76) },
        { name = "Strawberry Clinic",    coords = vector4(-1789.20, -384.90, 157.30, 225.00) },
    }
}

local isDead = false
local deathCam = nil
local respawnTimer = 0
local respawnPrompt = nil
local promptGroup = GetRandomIntInRange(0, 0xffffff)

local function getNearestHospital(pos)
    local best = DeathConfig.Hospitals[1]
    local minDst = #(pos - vector3(best.coords.x, best.coords.y, best.coords.z))
    for i = 2, #DeathConfig.Hospitals do
        local h = DeathConfig.Hospitals[i]
        local dst = #(pos - vector3(h.coords.x, h.coords.y, h.coords.z))
        if dst < minDst then
            best = h
            minDst = dst
        end
    end
    return best
end

local function startDeathCam()
    if deathCam then return end
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    deathCam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z + 1.2, -80.0, 0.0, 0.0, 55.0, false, 0)
    SetCamActive(deathCam, true)
    RenderScriptCams(true, true, 1000, true, false, 0)
end

local function stopDeathCam()
    if not deathCam then return end
    ClearFocus()
    RenderScriptCams(false, false, 0, true, false, 0)
    DestroyCam(deathCam, false)
    deathCam = nil
end

local function healPed(ped)
    SetAttributeCoreValue(ped, 0, 100)
    SetEntityHealth(ped, GetEntityMaxHealth(ped), 0)
    SetAttributeCoreValue(ped, 1, 100)
    RestorePedStamina(ped, 100.0)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityCanBeDamaged(ped, true)
end

local function executeRevive()
    local ped = PlayerPedId()
    ResurrectPed(ped)
    Wait(200)
    stopDeathCam()
    isDead = false
    DisplayHud(true)
    DisplayRadar(true)
    healPed(ped)
    TriggerEvent("jrs_core:client:onRevived")
end

local function executeHospitalRespawn()
    local ped = PlayerPedId()
    DoScreenFadeOut(1500)
    Wait(1600)
    ResurrectPed(ped)
    Wait(200)
    stopDeathCam()
    isDead = false

    local pos = GetEntityCoords(ped)
    local hospital = getNearestHospital(pos)
    local hCoords = hospital.coords
    Citizen.InvokeNative(0x203BEFFDBE12E96A, ped, hCoords.x, hCoords.y, hCoords.z, false, false, false)
    SetEntityHeading(ped, hCoords.w)

    Wait(1000)
    healPed(ped)
    DisplayHud(true)
    DisplayRadar(true)
    DoScreenFadeIn(1500)

    TriggerEvent("jrs_character:client:reloadCurrentCharacter")
    TriggerEvent("jrs_core:client:onHospitalRespawn", hospital.name)
    exports.jrs_core:NotifyRightTip(hospital.name, 4000)
end

RegisterNetEvent('jrs_core:death:executeRevive', executeRevive)
RegisterNetEvent('jrs_core:death:executeHospitalRespawn', executeHospitalRespawn)

CreateThread(function()
    respawnPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(respawnPrompt, 0xDFF812F9) -- E key
    UiPromptSetText(respawnPrompt, VarString(10, 'LITERAL_STRING', 'Respawn (Hospital)'))
    UiPromptSetEnabled(respawnPrompt, true)
    UiPromptSetVisible(respawnPrompt, true)
    UiPromptSetHoldMode(respawnPrompt, DeathConfig.RespawnHoldTime)
    UiPromptSetGroup(respawnPrompt, promptGroup, 0)
    UiPromptSetPriority(respawnPrompt, 3)
    UiPromptRegisterEnd(respawnPrompt)

    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if IsPlayerDead(PlayerId()) or IsEntityDead(ped) then
            if not isDead then
                isDead = true
                respawnTimer = DeathConfig.RespawnCooldown
                DisplayRadar(false)
                startDeathCam()

                local killerPed = GetPedSourceOfDeath(ped)
                local killer = 0
                if IsPedAPlayer(killerPed) then
                    local idx = NetworkGetPlayerIndexFromPed(killerPed)
                    if idx then killer = GetPlayerServerId(idx) end
                end
                local cause = GetPedCauseOfDeath(ped)
                TriggerServerEvent('jrs_core:death:playerDied', killer, cause)
                TriggerEvent('jrs_core:client:onDeath', killer, cause)

                CreateThread(function()
                    while isDead and respawnTimer > 0 do
                        Wait(1000)
                        respawnTimer = respawnTimer - 1
                    end
                end)
            end

            sleep = 0
            local label = respawnTimer > 0 and ('Wait ' .. respawnTimer .. 's') or 'Hold to Respawn'
            UiPromptSetActiveGroupThisFrame(promptGroup, VarString(10, 'LITERAL_STRING', label), 0, 0, 0, 0)
            UiPromptSetEnabled(respawnPrompt, respawnTimer <= 0)

            if deathCam then
                local p = GetEntityCoords(ped)
                SetCamCoord(deathCam, p.x, p.y, p.z + 1.2)
            end

            if respawnTimer <= 0 and UiPromptHasHoldModeCompleted(respawnPrompt) then
                TriggerServerEvent('jrs_core:death:requestHospitalRespawn')
                Wait(3000)
            end
        elseif isDead then
            isDead = false
            stopDeathCam()
            DisplayRadar(true)
        end

        Wait(sleep)
    end
end)

-- Client Exports
exports('IsDead', function() return isDead end)
