local levelHudState = {
    level = 1,
    progress = 0,
    currentXp = 0,
    requiredXp = tonumber(Config.Levels and Config.Levels[1]) or 200,
    isMaxLevel = false,
}

local levelHudVisible = false
local levelPeekHeld = false
local levelPlayerReady = false
local levelHudHasData = false

local function levelHudEnabled()
    return Config.LevelHud and Config.LevelHud.enabled ~= false
end

local function normalizeLevelData(levelData)
    if type(levelData) ~= "table" then return false end

    levelHudState.level = math.max(1, math.floor(tonumber(levelData.level) or levelHudState.level or 1))
    levelHudState.progress = math.max(0, math.min(100, tonumber(levelData.progress) or 0))
    levelHudState.currentXp = math.max(0, math.floor(tonumber(levelData.currentXp) or 0))
    levelHudState.requiredXp = math.max(0, math.floor(tonumber(levelData.requiredXp) or 0))
    levelHudState.isMaxLevel = levelData.isMaxLevel == true
    return true
end

local function buildLevelPayload(action)
    return {
        action = action,
        level = levelHudState.level,
        progress = levelHudState.progress,
        currentXp = levelHudState.currentXp,
        requiredXp = levelHudState.requiredXp,
        isMaxLevel = levelHudState.isMaxLevel,
    }
end

local function isCharacterReady()
    if levelPlayerReady then return true end
    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.jrsCharacterReady == true or LocalPlayer.state.CharacterReady == true then
            return true
        end
    end
    local ped = PlayerPedId()
    if DoesEntityExist(ped) and not IsEntityDead(ped) and not IsScreenFadedOut() then
        return true
    end
    return false
end

local function showLevelHud()
    if not levelHudEnabled() or not isCharacterReady() then return end
    SendNUIMessage(buildLevelPayload('jrsLevel:show'))
    levelHudVisible = true
end

local function updateLevelHud()
    if not levelHudVisible then return end
    SendNUIMessage(buildLevelPayload('jrsLevel:update'))
end

local function hideLevelHud()
    if not levelHudVisible then return end
    levelHudVisible = false
    SendNUIMessage({ action = 'jrsLevel:hide' })
end

local autoShowTimer = 0

local function showLevelHudTemporarily(durationMs)
    if not levelHudEnabled() or not isCharacterReady() then return end
    showLevelHud()
    autoShowTimer = autoShowTimer + 1
    local currentTimer = autoShowTimer
    local waitTime = tonumber(durationMs) or (Config.LevelHud and tonumber(Config.LevelHud.autoShowDurationMs)) or 4500

    SetTimeout(waitTime, function()
        if autoShowTimer == currentTimer and not levelPeekHeld then
            hideLevelHud()
        end
    end)
end

-- This used to also push a bespoke NUI card (SendNUIMessage 'jrsLevel:toast',
-- the shield/arrow banner defined in ui.html/level.js/style.css) alongside the
-- call below, so every level change showed two different notifications at
-- once. The bespoke card is retired; the unified Core Notification below is
-- now the only surface for a level change.
local function showLevelToast(kind, oldLevel, newLevel)
    if not Config.LevelHud or Config.LevelHud.showLevelToast ~= true then return end

    if kind == 'up' then
        pcall(function()
            PlaySoundFrontend("MP_RANK_UP", "HUD_AWARDS", true, 0)
        end)
    end

    -- Trigger authentic Red Dead Online Rank Up banner
    SendNUIMessage({
        action = 'jrsLevel:toast',
        toastType = kind,
        oldLevel = oldLevel,
        newLevel = newLevel,
        duration = tonumber(Config.LevelHud.toastDurationMs) or 4000
    })

    if Config.LevelHud and Config.LevelHud.autoShowOnUpdate == true then
        showLevelHudTemporarily(5000)
    end

    local text = kind == 'down'
        and ('Level decreased: %s -> %s'):format(tostring(oldLevel), tostring(newLevel))
        or ('Level up! %s -> %s'):format(tostring(oldLevel), tostring(newLevel))
    pcall(function()
        exports.jrs_core:Toast(text, kind == 'down' and 'warning' or 'reward',
            tonumber(Config.LevelHud.toastDurationMs) or 3500, 'LEVEL')
    end)
end

-- Fires once, the moment the character crosses into max level, instead of the
-- generic "Level up!" text (XP is already hard-capped server-side, so this
-- never repeats afterward: level stays at Config.MaxLevel with no further change).
local function showLevelMaxToast()
    if not Config.LevelHud or Config.LevelHud.showLevelToast ~= true then return end

    pcall(function()
        PlaySoundFrontend("MP_RANK_UP", "HUD_AWARDS", true, 0)
    end)

    SendNUIMessage({
        action = 'jrsLevel:toast',
        toastType = 'up',
        oldLevel = Config.MaxLevel - 1,
        newLevel = Config.MaxLevel,
        duration = tonumber(Config.LevelHud.toastDurationMs) or 4000
    })

    if Config.LevelHud and Config.LevelHud.autoShowOnUpdate == true then
        showLevelHudTemporarily(5000)
    end

    local text = (type(_U) == 'function' and _U('core_level_max_reached')) or "You've reached the maximum level!"
    pcall(function()
        exports.jrs_core:Toast(text, 'reward', tonumber(Config.LevelHud.toastDurationMs) or 3500, 'LEVEL')
    end)
end

local function requestLevelHudData()
    if not levelHudEnabled() or not isCharacterReady() then return end
    TriggerServerEvent('jrscore:getFrom')
end

local function markLevelPlayerReady()
    levelPlayerReady = true
    SendNUIMessage({ action = 'jrsLevel:init' })
    requestLevelHudData()
end

RegisterNetEvent('jrs:isPlayerready')
AddEventHandler('jrs:isPlayerready', markLevelPlayerReady)

-- Compatibility with resources that use the alternate Ready event casing.
RegisterNetEvent('jrs:isPlayerReady')
AddEventHandler('jrs:isPlayerReady', markLevelPlayerReady)

RegisterNetEvent('jrs_core:client:characterReady', function()
    markLevelPlayerReady()
end)

RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    levelPlayerReady = false
    levelHudHasData = false
    levelPeekHeld = false
    autoShowTimer = autoShowTimer + 1
    hideLevelHud()
end)

RegisterNetEvent('jrscore:sett')
AddEventHandler('jrscore:sett', function(_, _, _, _, _, levelData)
    levelPlayerReady = true
    if normalizeLevelData(levelData) then
        levelHudHasData = true
        if levelPeekHeld then
            if levelHudVisible then
                updateLevelHud()
            else
                showLevelHud()
            end
        end
    end
end)

RegisterNetEvent('jrs_core:xpUpdated')
AddEventHandler('jrs_core:xpUpdated', function(levelData, changedAmount, previousLevel, reason)
    local oldLevel = math.max(1, math.floor(tonumber(previousLevel) or levelHudState.level or 1))
    if not normalizeLevelData(levelData) then return end
    levelHudHasData = true

    -- Show Level HUD smoothly when XP or level changes
    if Config.LevelHud and Config.LevelHud.autoShowOnUpdate == true then
        showLevelHudTemporarily(Config.LevelHud and Config.LevelHud.autoShowDurationMs or 4500)
    end
    updateLevelHud()

    if levelHudState.level > oldLevel then
        if levelHudState.isMaxLevel then
            showLevelMaxToast()
        else
            showLevelToast('up', oldLevel, levelHudState.level)
        end
    elseif levelHudState.level < oldLevel then
        showLevelToast('down', oldLevel, levelHudState.level)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(500)
    SendNUIMessage({ action = 'jrsLevel:init' })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hideLevelHud()
end)

local function isTabHeld()
    local peekHash = Config.LevelHud and Config.LevelHud.peekControlHash
    local ctrl = (type(peekHash) == 'number' and peekHash ~= 0) and peekHash or 0xAC4BD4F1

    return IsControlPressed(0, ctrl)
        or IsDisabledControlPressed(0, ctrl)
        or IsControlPressed(2, ctrl)
        or IsDisabledControlPressed(2, ctrl)
end

local function canShowLevelHud()
    if not levelHudEnabled() then return false end
    if not isCharacterReady() then return false end
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return false end
    if GetResourceState('jrs_doctors') == 'started' then
        local okDoc, dead = pcall(function()
            return exports['jrs_doctors']:IsDeathScreenActive() or exports['jrs_doctors']:IsDead()
        end)
        if okDoc and dead == true then return false end
    end
    return true
end

-- Exclusive TAB watcher thread: shows Level HUD while TAB is held, hides immediately when released
CreateThread(function()
    local isHeld = false

    -- Ensure Level HUD starts hidden
    Wait(500)
    hideLevelHud()

    while true do
        if levelHudEnabled() and isCharacterReady() then
            local held = isTabHeld()

            if held then
                if not isHeld and canShowLevelHud() then
                    isHeld = true
                    levelPeekHeld = true
                    if Config.LevelHud and Config.LevelHud.clearChatOnPeek == true then
                        TriggerEvent('chat:clear')
                    end
                    requestLevelHudData()
                    TriggerEvent('jrs_core:client:requestDoubleXp')
                    showLevelHud()
                end
            else
                if isHeld or levelHudVisible or levelPeekHeld then
                    isHeld = false
                    levelPeekHeld = false
                    hideLevelHud()
                end
            end
            Wait(0)
        else
            if isHeld or levelHudVisible or levelPeekHeld then
                isHeld = false
                levelPeekHeld = false
                hideLevelHud()
            end
            Wait(250)
        end
    end
end)

-- Test / Debug command: /testlevelhud (shows level HUD on top right for 5s & prints diagnostics in F8)
RegisterCommand('testlevelhud', function()
    print('^3[jrs_core:levelHud]^7 Diagnostics:')
    print(('  - enabled: %s'):format(tostring(levelHudEnabled())))
    print(('  - characterReady: %s'):format(tostring(isCharacterReady())))
    print(('  - canShow: %s'):format(tostring(canShowLevelHud())))
    print(('  - isTabHeld: %s'):format(tostring(isTabHeld())))
    print(('  - level: %s | XP: %s / %s | progress: %s%%'):format(
        tostring(levelHudState.level), tostring(levelHudState.currentXp),
        tostring(levelHudState.requiredXp), tostring(levelHudState.progress)
    ))
    requestLevelHudData()
    TriggerEvent('jrs_core:client:requestDoubleXp')
    showLevelHudTemporarily(5000)
    print('^2[jrs_core:levelHud]^7 Display command triggered successfully (5s preview).')
end, false)

-- JRS: Apply stamina drain reduction perk to native sprint depletion
CreateThread(function()
    local lastMultiplier = 1.0
    while true do
        Wait(2500)
        local perks = LocalPlayer and LocalPlayer.state and LocalPlayer.state.jrsPerks
        local reduction = (type(perks) == 'table' and tonumber(perks.staminaDrainReduction)) or 0
        local multiplier = math.max(0.5, math.min(1.0, 1.0 - reduction))
        if multiplier ~= lastMultiplier then
            lastMultiplier = multiplier
            local playerId = PlayerId()
            if playerId and playerId ~= -1 then
                Citizen.InvokeNative(0xBBADFB5E5E5766FB, playerId, multiplier)
            end
        end
    end
end)
