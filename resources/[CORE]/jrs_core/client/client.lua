AddEventHandler('onClientResourceStart', function (resourceName)
    -- Network pings only for our own start: every resource start used to fire
    -- them (20/s during a join, flagged by jrs_logs netmeter).
    if resourceName == GetCurrentResourceName() then
        TriggerServerEvent("jrs:selectcharacter")
        TriggerServerEvent("jrs_core:checkPlayersOnline")
    end
    Citizen.InvokeNative(0x4B8F743A4A6D2FF8, true)
end)

local CutCoordsx = 0.0
local CutCoordsy = 0.0
local CutCoordsz = 0.0

RegisterNetEvent("jrs:isPlayerReady")
AddEventHandler("jrs:isPlayerReady", function()

    Citizen.CreateThread(function()
        while true do
            local timer = Config.CoordsSaveTimerOnesync
            if Config.Onesync ~= true then
                timer = Config.CoordsSaveTimerLegacy
            end 
	        TriggerServerEvent("jrs_core:checkPlayersOnline")
            Citizen.Wait(timer)
            local GetCoords = GetEntityCoords(PlayerPedId())
            local GetHeading = GetEntityHeading(PlayerPedId())
            local skipSave = false
            for _, zone in ipairs(Config.CoordsSaveSkipZones) do
                if GetDistanceBetweenCoords(GetCoords.x, GetCoords.y, GetCoords.z, zone.x, zone.y, zone.z) <= zone.radius then
                    skipSave = true
                    break
                end
            end
            
            if not skipSave then
                if GetDistanceBetweenCoords(GetCoords.x, GetCoords.y, GetCoords.z, CutCoordsx, CutCoordsy, CutCoordsz, false) > Config.CoordsSaveDistance then
                    CutCoordsx = tonumber(string.format("%.2f", GetCoords.x))
                    CutCoordsy = tonumber(string.format("%.2f", GetCoords.y))
                    CutCoordsz = tonumber(string.format("%.2f", GetCoords.z))
                    local CutHeading = tonumber(string.format("%.2f", GetHeading))
                    local coords_save = {x=CutCoordsx, y=CutCoordsy, z=CutCoordsz, heading=CutHeading}
                    TriggerServerEvent("jrsCore:save_coords", coords_save)
                end
            end
        end
    end)
end)

RegisterNetEvent('jrs_core:refreshPlayerVisibility')
AddEventHandler('jrs_core:refreshPlayerVisibility', function(serverId)
    local playerId = GetPlayerFromServerId(serverId)
    if playerId < 0 or playerId == PlayerId() then return end
    local ped = GetPlayerPed(playerId)
    if ped ~= 0 then
        NetworkConcealPlayer(playerId, true)
        Citizen.Wait(50)
        NetworkConcealPlayer(playerId, false)
    end
end)

local cachedMaxPlayers = Config.MaxPlayers or 48

RegisterNetEvent("jrs_core:sendBack")
AddEventHandler("jrs_core:sendBack", function(countchar, maxPlayersReceived)
    if maxPlayersReceived and tonumber(maxPlayersReceived) and tonumber(maxPlayersReceived) > 0 then
        cachedMaxPlayers = tonumber(maxPlayersReceived)
    end

    if Config.DiscordRichPresence == false then return end -- handled by the jrs_rich resource

    if Config.DiscordID and Config.DiscordID ~= "" then
        SetDiscordAppId(tostring(Config.DiscordID))
    end
    if Config.DiscordBigLogo then
        SetDiscordRichPresenceAsset(Config.DiscordBigLogo)
    end
    if Config.DiscordPText then
        SetDiscordRichPresenceAssetText(Config.DiscordPText)
    end
    if Config.DiscordSmallLogo then
        SetDiscordRichPresenceAssetSmall(Config.DiscordSmallLogo)
    end
    if Config.DiscordSText then
        SetDiscordRichPresenceAssetSmallText(Config.DiscordSText)
    end

    if Config.DiscordButtons and type(Config.DiscordButtons) == "table" then
        for k, v in ipairs(Config.DiscordButtons) do
            if k <= 2 and v.text and v.url then
                SetDiscordRichPresenceAction(k - 1, v.text, v.url)
            end
        end
    elseif Config.DiscordButton and Config.DiscordButton ~= "" then
        SetDiscordRichPresenceAction(0, "Discord", Config.DiscordButton)
    end

    local maxPlayers = cachedMaxPlayers or Config.MaxPlayers or 48
    if Config.DiscordShowNameAndId then
        local pId = GetPlayerServerId(PlayerId())
        local pName = GetPlayerName(PlayerId())
        SetRichPresence(string.format("%s/%s - ID: %s | %s", countchar, maxPlayers, pId, pName))
    else
        SetRichPresence(string.format("%s/%s", countchar, maxPlayers))
    end
end)

RegisterNetEvent("jrs:endcallback", function(callbackName, ticket, ...)
	local fn = getCallbackResolution(callbackName, ticket)
	if fn then
		fn(...)
	end
end)

RegisterNetEvent("jrs_core:ExecuteServerCallBack")
AddEventHandler("jrs_core:ExecuteServerCallBack", function(callbackName, cb, ...)
    local ticket = generateTicket()
	addCallbackResolution(callbackName, ticket, function(...)
		cb(...)
		removeCallbackResolution(callbackName, ticket)
	end)

	TriggerServerEvent("jrs:triggercallback", callbackName, ticket, ...)
end)


local Keys = {
	["ESC"] = 322
}

local hud = false

local function updatePvpHud()
    local gameplay = Config.Gameplay or {}
    local pvpHud = gameplay.PVPHud or {}
    if Config.Hud and Config.Hud.pvp == false then return end
    if pvpHud.Enabled == false then return end
    local enabled = gameplay.PVP ~= false
    local ok, pvp = pcall(function() return exports['jrs_core']:IsPvpEnabled() end)
    if ok and type(pvp) == 'boolean' then enabled = pvp end
    SendNUIMessage({ action = "setPvpState", enabled = enabled })
end

local function applyHudVisibilityConfig()
    for key, visible in pairs(Config.Hud) do
        if key ~= "enabled" then
            SendNUIMessage({action = "toggleVisibility", key = key, visible = visible})
            if Config.HudDebug then
                print("^2[jrs_core:HUD] toggleVisibility: "..key.." = "..tostring(visible))
            end
        end
    end
    updatePvpHud()
end

local commandSuggestionsReady = false

local function requestCommandSuggestions()
    CreateThread(function()
        local retryDelays = { 0, 1500, 3500, 5000 }

        for _, delay in ipairs(retryDelays) do
            Wait(delay)
            if not commandSuggestionsReady then return end
            TriggerServerEvent('jrs_core:requestCommandSuggestions')
        end
    end)
end

-- Re-send staff suggestions after either supported chat resource restarts.
AddEventHandler('onClientResourceStart', function(resourceName)
    local normalizedName = string.lower(tostring(resourceName))
    local coreResourceName = string.lower(GetCurrentResourceName())

    if normalizedName == coreResourceName then
        CreateThread(function()
            Wait(3000)
            TriggerServerEvent('jrs_core:requestCommandSuggestions')
        end)
        return
    end

    if normalizedName ~= 'chat' and normalizedName ~= 'jrs-chat' then return end

    CreateThread(function()
        Wait(1500)
        if commandSuggestionsReady then
            TriggerServerEvent('jrs_core:requestCommandSuggestions')
        end
    end)
end)

RegisterNetEvent('jrs:isPlayerready')
AddEventHandler('jrs:isPlayerready', function()
    commandSuggestionsReady = true
    requestCommandSuggestions()
   if Config.HudDebug then print("^2[jrs_core:HUD] jrs:isPlayerready received") end
   applyHudVisibilityConfig()
end)

RegisterNetEvent('jrs_core:client:characterReady', function()
    hud = true
    applyHudVisibilityConfig()
end)

RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    hud = false
end)

RegisterNetEvent('jrs:isPlayerready')
AddEventHandler('jrs:isPlayerready', function()
    Wait(3000)
    local ped = PlayerPedId()
    NetworkSetEntityInvisibleToNetwork(ped, false)
    SetEntityVisible(ped, true, false)
    NetworkConcealPlayer(PlayerId(), false)
end)

CreateThread(function()
	while true do
        Wait(250)
        local menuOpen = IsPauseMenuActive()
        local dead = IsEntityDead(PlayerPedId())
        local characterReady = LocalPlayer
            and LocalPlayer.state
            and (LocalPlayer.state.CharacterReady == true or LocalPlayer.state.jrsCharacterReady == true)
        if characterReady and not hud then
            hud = true
            applyHudVisibilityConfig()
        elseif not characterReady then
            hud = false
        end
        if Config.Hud.enabled and characterReady and not dead and not menuOpen then
           if Config.HudDebug then 
            print("^2[jrs_core:HUD] HUD visible - triggering jrscore:getFrom") 
           end
			TriggerServerEvent('jrscore:getFrom')
			Wait(Config.HudUpdateInterval)
        else
           -- hud_layout.lua owns the actual hud:setSuppressed NUI message (it
           -- also factors in the central HUD gate); sending it from here too
           -- raced with that owner's change-only cache and could leave the
           -- HUD stuck hidden after the two disagreed once.
           if Config.HudDebug and hud then
              local reason = ""
              if not Config.Hud.enabled then reason = "Hud.enabled=false "
              elseif not hud then reason = "not ready "
              elseif dead then reason = "dead "
              elseif menuOpen then reason = "menu open "
              end
              print("^1[jrs_core:HUD] HUD hidden - "..reason)
           end
        end
	end
end)

local function updateXpHud(levelData)
    if not levelData then return end

    local level = tonumber(levelData.level) or 1
    local totalXp = tonumber(levelData.totalXp) or 0
    local currentXp = tonumber(levelData.currentXp) or 0
    local requiredXp = tonumber(levelData.requiredXp) or 0
    local isMaxLevel = levelData.isMaxLevel == true

    local tooltip
    if isMaxLevel then
        tooltip = ("MAX LEVEL | Total XP: %s"):format(totalXp)
    else
        tooltip = ("XP: %s / %s | Total XP: %s"):format(currentXp, requiredXp, totalXp)
    end

    SendNUIMessage({
        action = "setValuejrscore",
        key = "xp",
        value = (Config.CurrencyXpSymbol or "LV ") .. level,
        level = level,
        tooltip = tooltip,
        progress = tonumber(levelData.progress) or 0,
    })
end

RegisterNetEvent('jrscore:sett')
AddEventHandler('jrscore:sett', function(PlayerMoney, PlayerGold, PlayerDirtyMoney, job, jobGrade, levelData)
    levelData = type(levelData) == "table" and levelData or Config.GetLevelData(levelData or 0)

    if Config.HudDebug then
        print(("^2[jrs_core:HUD] received - Gold=%s Money=%s job=%s grade=%s level=%s totalXP=%s"):format(
            tostring(PlayerGold),
            tostring(PlayerMoney),
            tostring(job),
            tostring(jobGrade),
            tostring(levelData.level),
            tostring(levelData.totalXp)
        ))
    end

    if Config.Hud.PlayerMoney then
        SendNUIMessage({ action = "setValuejrscore", key = "PlayerMoney", value = Config.CurrencyMoneySymbol .. PlayerMoney })
    end
    if Config.Hud.PlayerGold then
        local formattedGold = string.format("%.2f", tonumber(PlayerGold) or 0.0)
        SendNUIMessage({ action = "setValuejrscore", key = "PlayerGold", value = Config.CurrencyGoldSymbol .. formattedGold })
    end
    if Config.Hud.PlayerDirtyMoney then
        SendNUIMessage({ action = "setValuejrscore", key = "PlayerDirtyMoney", value = Config.CurrencyDirtyMoneySymbol .. (PlayerDirtyMoney or 0) })
    end
    if Config.Hud.id then
        SendNUIMessage({ action = "setValuejrscore", key = "id", value = GetPlayerServerId(PlayerId()) })
    end
    if Config.Hud.job then
        SendNUIMessage({ action = "setValuejrscore", key = "job", value = job, icon = job })
    end

    updateXpHud(levelData)

    if Config.Hud.town then
        SendNUIMessage({ action = "setValuejrscore", key = "town", value = GetCurentTownName() })
    end
    updatePvpHud()
end)

RegisterNetEvent('jrs_core:hud:updateCurrencies')
AddEventHandler('jrs_core:hud:updateCurrencies', function(PlayerMoney, PlayerGold, PlayerDirtyMoney)
    if Config.Hud.PlayerMoney then
        SendNUIMessage({ action = "setValuejrscore", key = "PlayerMoney", value = Config.CurrencyMoneySymbol .. (PlayerMoney or 0) })
    end
    if Config.Hud.PlayerGold then
        local formattedGold = string.format("%.2f", tonumber(PlayerGold) or 0.0)
        SendNUIMessage({ action = "setValuejrscore", key = "PlayerGold", value = Config.CurrencyGoldSymbol .. formattedGold })
    end
    if Config.Hud.PlayerDirtyMoney then
        SendNUIMessage({ action = "setValuejrscore", key = "PlayerDirtyMoney", value = Config.CurrencyDirtyMoneySymbol .. (PlayerDirtyMoney or 0) })
    end
end)

RegisterNetEvent('jrs_core:xpUpdated')
AddEventHandler('jrs_core:xpUpdated', function(levelData, changedAmount, previousLevel, reason)
    if type(levelData) ~= "table" then return end

    updateXpHud(levelData)

    changedAmount = tonumber(changedAmount) or 0
    previousLevel = tonumber(previousLevel) or levelData.level

    -- Per-job quests report the full amount through jrs_core:jobXpUpdated, so
    -- don't also toast the small core-share it feeds into the core level.
    if tostring(reason or ''):match('core%-share$') then return end

    if Config.LevelUpNotification and tonumber(levelData.level) > previousLevel then
        local title = _U and _U('core_level_up') or 'LEVEL UP'
        local msg = _U and _U('core_level_reached') and _U('core_level_reached'):format(levelData.level) or ("You reached Level %s"):format(levelData.level)
        TriggerEvent(
            'jrs_core:sendLeftNotification',
            title,
            msg,
            'menu_textures', 'menu_icon_level_up',
            Config.XpNotificationDuration, 'COLOR_WHITE'
        )
    elseif Config.XpGainNotification and changedAmount > 0 then
        local title = _U and _U('core_xp_gained') or 'XP GAINED'
        local msg = _U and _U('core_xp_gain_msg', changedAmount)
        if not msg or msg == 'core_xp_gain_msg' then
            msg = ("+%s XP"):format(changedAmount)
        end
        TriggerEvent(
            'jrs_core:sendLeftNotification',
            title,
            msg,
            'menu_textures', 'menu_icon_level_up',
            Config.XpNotificationDuration, 'COLOR_WHITE'
        )
    end
end)

RegisterNetEvent('jrs_core:giveWeapon')
AddEventHandler('jrs_core:giveWeapon', function(weaponName, ammo)
    local weaponHash = GetHashKey(weaponName)
    Citizen.InvokeNative(0x5E3BDDBCB83F3D84, PlayerPedId(), weaponHash, ammo or 100, true, 0, 0, 0)
end)

local currentInstance = 0

RegisterNetEvent('jrs:setInstancePlayer')
AddEventHandler('jrs:setInstancePlayer', function(active)
    currentInstance = active and 1 or 0
end)

RegisterNetEvent('jrs_core:instanceChanged')
AddEventHandler('jrs_core:instanceChanged', function(instanceId)
    currentInstance = instanceId or 0
end)

RegisterNetEvent('jrs_core:getPlayerJob')
AddEventHandler('jrs_core:getPlayerJob', function(data)
    if data and data.job then
        SendNUIMessage({action = "setValuejrscore", key = "job", value = data.job, icon = data.job})
    end
end)

RegisterNetEvent('jrs_core:removeWeapon')
AddEventHandler('jrs_core:removeWeapon', function(weaponHash)
    Citizen.InvokeNative(0x4899D7B8CCBF5F80, PlayerPedId(), weaponHash, true, 0)
end)

RegisterNetEvent('jrs_core:adminTeleportToWaypoint')
AddEventHandler('jrs_core:adminTeleportToWaypoint', function()
    if not IsWaypointActive() then
        TriggerEvent('jrsCore:notify', 'COMMAND FAILED', _U('teleport_no_waypoint'), 'placeholder', 4000)
        return
    end
    if CoreFunctions.TeleportToWaypoint() then
        TriggerEvent('jrsCore:notify', 'COMMAND SUCCESS', _U('teleport_success'), 'placeholder', 3000)
    else
        TriggerEvent('jrsCore:notify', 'COMMAND FAILED', _U('teleport_failed'), 'placeholder', 4000)
    end
end)

RegisterNetEvent('jrs_core:teleportToCoords')
AddEventHandler('jrs_core:teleportToCoords', function(x, y, z, heading)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, z, false, false, false, true)
    if heading then SetEntityHeading(ped, heading) end
end)

RegisterNetEvent('jrs_core:getCoords')
AddEventHandler('jrs_core:getCoords', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    TriggerServerEvent('jrs_core:returnCoords', { x = coords.x, y = coords.y, z = coords.z, heading = heading })
end)
function GetCurentTownName()
    local pedCoords = GetEntityCoords(PlayerPedId())
    local town_hash = Citizen.InvokeNative(0x43AD8FC02B429D33, pedCoords.x, pedCoords.y, pedCoords.z, 1)
    if town_hash == GetHashKey("Annesburg") then
        return _U('town_annesburg')
    elseif town_hash == GetHashKey("Armadillo") then
        return _U('town_armadillo')
    elseif town_hash == GetHashKey("Blackwater") then
        return _U('town_blackwater')
    elseif town_hash == GetHashKey("BeechersHope") then
        return _U('town_beechers_hope')
    elseif town_hash == GetHashKey("Braithwaite") then
        return _U('town_braithwaite')
    elseif town_hash == GetHashKey("Butcher") then
        return _U('town_butcher')
    elseif town_hash == GetHashKey("Caliga") then
        return _U('town_caliga')
    elseif town_hash == GetHashKey("cornwall") then
        return _U('town_cornwall')
    elseif town_hash == GetHashKey("Emerald") then
        return _U('town_emerald')
    elseif town_hash == GetHashKey("lagras") then
        return _U('town_lagras')
    elseif town_hash == GetHashKey("Manzanita") then
        return _U('town_manzanita')
    elseif town_hash == GetHashKey("Rhodes") then
        return _U('town_rhodes')
    elseif town_hash == GetHashKey("Siska") then
        return _U('town_siska')
    elseif town_hash == GetHashKey("StDenis") then
        return _U('town_saint_denis')
    elseif town_hash == GetHashKey("Strawberry") then
        return _U('town_strawberry')
    elseif town_hash == GetHashKey("Tumbleweed") then
        return _U('town_tumbleweed')
    elseif town_hash == GetHashKey("valentine") then
        return _U('town_valentine')
    elseif town_hash == GetHashKey("VANHORN") then
        return _U('town_vanhorn')
    elseif town_hash == GetHashKey("Wallace") then
        return _U('town_wallace')
    elseif town_hash == GetHashKey("wapiti") then
        return _U('town_wapiti')
    elseif town_hash == GetHashKey("AguasdulcesFarm") then
        return _U('town_aguasdulces_farm')
    elseif town_hash == GetHashKey("AguasdulcesRuins") then
        return _U('town_aguasdulces_ruins')
    elseif town_hash == GetHashKey("AguasdulcesVilla") then
        return _U('town_aguasdulces_villa')
    elseif town_hash == GetHashKey("Manicato") then
        return _U('town_manicato')
    else
        return _U('town_out_of_town')
    end
end

RegisterNetEvent('jrs_core:removePlayerPed')
AddEventHandler('jrs_core:removePlayerPed', function(serverId)
    local playerId = GetPlayerFromServerId(serverId)
    if playerId >= 0 and playerId ~= PlayerId() then
        local ped = GetPlayerPed(playerId)
        if ped ~= 0 then
            SetEntityVisible(ped, false, false)
            SetEntityAsNoLongerNeeded(ped)
        end
    end
end)
