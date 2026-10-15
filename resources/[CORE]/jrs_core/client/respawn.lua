-- Death / respawn / heal for extra scripts on JRS Core (client).
-- Death / respawn handling.

local Config = {
    RespawnTime = 10,            -- seconds before the respawn prompt unlocks
    RespawnKey = 0xDFF812F9,     -- E
    RespawnKeyTime = 5000,       -- hold time (ms)
    RagdollOnResurrection = true,
    -- off when a full doctor/death script (jrs_doctors) is running
    UseDeathHandler = GetResourceState('jrs_doctors') ~= 'started',
    Hospitals = {
        { name = "Valentine",   pos = vector4(-283.83, 806.4, 119.38, 321.76) },
        { name = "Saint Denis", pos = vector4(2721.4562, -1446.0975, 46.2303, 321.76) },
        { name = "Armadillo",   pos = vector4(-3742.5, -2600.9, -13.23, 321.76) },
        { name = "Blackwater",  pos = vector4(-723.9527, -1242.8358, 44.7341, 321.76) },
        { name = "Rhodes",      pos = vector4(1229.0, -1306.1, 76.9, 321.76) },
    },
}

local TEXT = {
    en = { respawnIn = "Respawn in ", seconds = " seconds", ready = "Hold E to respawn", carried = "You are being carried", prompt = "Respawn", woke = "You woke up" },
    ar = { respawnIn = "الرسبون بعد ", seconds = " ثانية", ready = "اضغط مطولاً E للرسبون", carried = "شخص يحملك", prompt = "رسبون", woke = "صحيت" },
}
local function T(key)
    local lang = 'en'
    pcall(function() lang = exports.jrs_core:GetLanguage() or 'en' end)
    return (TEXT[lang] or TEXT.en)[key]
end

local setDead, TimeToRespawn, cam, prompt, PressKey = false, 0, nil, nil, false
local prompts = GetRandomIntInRange(0, 0xffffff)
local keepdown = false

local function Label()
    if IsEntityAttachedToAnyPed(PlayerPedId()) then return VarString(10, 'LITERAL_STRING', T('carried')) end
    if TimeToRespawn > 0 then
        return VarString(10, 'LITERAL_STRING', T('respawnIn') .. TimeToRespawn .. T('seconds'))
    end
    return VarString(10, 'LITERAL_STRING', T('ready'))
end

local function RespawnTimer()
    TimeToRespawn = Config.RespawnTime
    CreateThread(function()
        while setDead and TimeToRespawn > 0 do
            Wait(1000)
            TimeToRespawn = TimeToRespawn - 1
        end
    end)
end

local function StartDeathCam()
    ClearFocus()
    local pos = GetEntityCoords(PlayerPedId())
    cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z, 0, 0, 0, GetGameplayCamFov(), false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 1000, true, false, 0)
end

local function UpdateDeathCam()
    if not cam then return end
    local p = GetEntityCoords(PlayerPedId())
    SetCamCoord(cam, p.x, p.y, p.z + 1.0)
    SetCamRot(cam, -80.0, 0.0, 0.0, 1)
    SetCamFov(cam, 50.0)
end

local function EndDeathCam()
    ClearFocus()
    RenderScriptCams(false, false, 0, true, false, 0)
    if cam then DestroyCam(cam, false) end
    cam = nil
end

local function Heal()
    local player = PlayerPedId()
    if IsEntityDead(player) then return end
    SetAttributeCoreValue(player, 0, 100)
    SetEntityHealth(player, GetEntityMaxHealth(player), 0)
    SetAttributeCoreValue(player, 1, 100)
    RestorePedStamina(player, 100.0)
    FreezeEntityPosition(player, false)
    SetEntityVisible(player, true)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityCanBeDamaged(player, true)
    TriggerEvent('jrs_core:healPlayer')
end

local function Resurrect(coords, name, justRevive)
    local player = PlayerPedId()
    ResurrectPed(player)
    Wait(200)
    EndDeathCam()
    TriggerServerEvent("jrs:ImDead", false)
    setDead = false
    DisplayHud(true)
    DisplayRadar(true)
    TriggerEvent("jrscharacter:reloadafterdeath")
    TriggerEvent("jrs_character:client:reloadCurrentCharacter")
    Wait(500)
    if coords then
        Citizen.InvokeNative(0x203BEFFDBE12E96A, player, coords, false, false, false)
    end
    Wait(2000)
    Heal()
    if Config.RagdollOnResurrection and not justRevive then
        keepdown = true
        CreateThread(function()
            while keepdown do
                Wait(0)
                SetPedToRagdoll(player, 4000, 4000, 0, false, false, false)
                ResetPedRagdollTimer(player)
                DisablePedPainAudio(player, true)
            end
        end)
        AnimpostfxPlay("Title_Gen_FewHoursLater")
        Wait(3000)
        DoScreenFadeIn(2000)
        AnimpostfxPlay("PlayerWakeUpInterrogation")
        Wait(19000)
        keepdown = false
        pcall(function() exports.jrs_core:NotifyLeft(name or "", T('woke'), "minigames_hud", "five_finger_burnout", 6000, "COLOR_PURE_WHITE") end)
    else
        DoScreenFadeIn(2000)
    end
end

local function RespawnAtHospital()
    TriggerEvent("jrs:PlayerForceRespawn")
    local ped = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, math.huge
    for _, h in ipairs(Config.Hospitals) do
        local d = #(ped - vector3(h.pos.x, h.pos.y, h.pos.z))
        if d < bestDist then best, bestDist = h, d end
    end
    TriggerEvent("jrsmetabolism:changeValue", "Thirst", 1000)
    TriggerEvent("jrsmetabolism:changeValue", "Hunger", 1000)
    Resurrect(best and best.pos, best and best.name, false)
end

RegisterNetEvent('jrs_core:Client:OnPlayerHeal', Heal)
RegisterNetEvent('jrs_core:Client:OnPlayerRespawn', function() RespawnAtHospital() end)
RegisterNetEvent('jrs_core:Client:OnPlayerRevive', function() Resurrect(nil, nil, true) end)
RegisterNetEvent('jrs:Heal', Heal)
RegisterNetEvent('jrs_core:Client:AddTimeToRespawn', function(time)
    TimeToRespawn = TimeToRespawn + (tonumber(time) or 0)
end)

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, Config.RespawnKey)
    UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', T('prompt')))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    UiPromptSetHoldMode(prompt, Config.RespawnKeyTime)
    UiPromptSetGroup(prompt, prompts, 0)
    UiPromptSetPriority(prompt, 3)
    UiPromptRegisterEnd(prompt)

    while Config.UseDeathHandler do
        local sleep = 1000
        if IsPlayerDead(PlayerId()) then
            if not setDead then
                setDead = true
                PressKey = false
                TriggerServerEvent("jrs:ImDead", true)
                local killerPed = GetPedSourceOfDeath(PlayerPedId())
                local killer = 0
                if IsPedAPlayer(killerPed) then
                    local idx = NetworkGetPlayerIndexFromPed(killerPed)
                    if idx then killer = GetPlayerServerId(idx) end
                end
                local cause = GetPedCauseOfDeath(PlayerPedId())
                TriggerServerEvent("jrs_core:Server:OnPlayerDeath", killer, cause)
                TriggerEvent("jrs_core:Client:OnPlayerDeath", killer, cause)
                DisplayRadar(false)
                RespawnTimer()
                StartDeathCam()
            end
            if not PressKey then
                sleep = 0
                UiPromptSetActiveGroupThisFrame(prompts, Label(), 0, 0, 0, 0)
                UiPromptSetEnabled(prompt, TimeToRespawn <= 0 and not IsEntityAttachedToAnyPed(PlayerPedId()))
                UpdateDeathCam()
                if TimeToRespawn <= 0 and UiPromptHasHoldModeCompleted(prompt) then
                    PressKey = true
                    DoScreenFadeOut(3000)
                    Wait(3000)
                    TriggerServerEvent("jrs_core:PlayerRespawnInternal", true)
                end
            end
        elseif setDead then
            -- Revived by something else (admin / doctor script).
            setDead = false
            EndDeathCam()
            TriggerServerEvent("jrs:ImDead", false)
            DisplayRadar(true)
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and cam then EndDeathCam() end
end)
