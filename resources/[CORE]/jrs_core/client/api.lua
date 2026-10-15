ClientRPC = {
    Callback = {
        TriggerAsync = function(name, callback, ...)
            local ticket = generateTicket()
            addCallbackResolution(name, ticket, function(...)
                callback(...)
                removeCallbackResolution(name, ticket)
            end)
            TriggerServerEvent("jrs:triggercallback", name, ticket, ...)
        end
    }
}

local CoreProgressState = {
    active = false,
    progress = 0,
    description = '',
    brand = nil,
    serial = 0
}

function CancelProgressBar()
    if not CoreProgressState.active then return end
    CoreProgressState.active = false
    CoreProgressState.serial = CoreProgressState.serial + 1
    SendNUIMessage({ action = 'coreProgressHide' })
end

function DisplayProgressBar(time, description, cb, shouldCancel, options)
    time = math.max(100, tonumber(time) or 1000)
    options = type(options) == 'table' and options or {}
    local brand = options.brand or (type(_U) == 'function' and _U('core_redempire')) or 'JRS'

    CoreProgressState.serial = CoreProgressState.serial + 1
    local currentSerial = CoreProgressState.serial
    CoreProgressState.active = true
    CoreProgressState.progress = 0
    CoreProgressState.description = tostring(description or '')
    CoreProgressState.brand = brand

    SendNUIMessage({
        action = 'coreProgressShow',
        brand = brand,
        label = CoreProgressState.description,
        progress = 0,
        duration = time
    })

    if cb and type(cb) == 'function' then
        Citizen.CreateThread(function()
            cb()
        end)
    end

    local steps = 100
    local delay = math.max(1, math.floor(time / steps))
    local completed = true

    for i = 1, steps do
        if not CoreProgressState.active or CoreProgressState.serial ~= currentSerial then
            completed = false
            break
        end

        local ped = PlayerPedId()
        if IsEntityDead(ped) and not options.useWhileDead then
            completed = false
            break
        end

        if shouldCancel and shouldCancel() then
            completed = false
            break
        end

        if options.canCancel ~= false and (IsControlJustPressed(0, 0x156F7119) or IsControlJustPressed(0, 0x308588E6)) then -- ESC / Backspace
            completed = false
            break
        end

        CoreProgressState.progress = i
        SendNUIMessage({
            action = 'coreProgressUpdate',
            brand = brand,
            label = CoreProgressState.description,
            progress = i
        })

        Wait(delay)
    end

    if CoreProgressState.serial == currentSerial then
        CoreProgressState.active = false
        SendNUIMessage({ action = 'coreProgressHide' })
    end

    return completed
end

function Progress(action, finish)
    if type(action) ~= 'table' then
        action = { duration = action, label = finish }
        finish = nil
    end
    local duration = tonumber(action.duration or action.time) or 1000
    local label = action.label or action.description or 'Working...'
    local brand = action.brand
    local canCancel = action.canCancel ~= false
    local useWhileDead = action.useWhileDead == true

    Citizen.CreateThread(function()
        local completed = DisplayProgressBar(duration, label, nil, nil, {
            brand = brand,
            canCancel = canCancel,
            useWhileDead = useWhileDead
        })
        if finish and type(finish) == 'function' then
            finish(not completed)
        end
    end)
end

RegisterNetEvent('jrs_core:client:progress', function(action, finish)
    Progress(action, finish)
end)

RegisterNetEvent('jrs_core:client:cancelProgress', function()
    CancelProgressBar()
end)

--[[
RegisterCommand('testcorebar', function(source, args)
    local seconds = tonumber(args and args[1]) or 5
    local text = (args and args[2]) or 'Testing Core Progress...'
    DisplayProgressBar(seconds * 1000, text)
end, false)
]]

local function buildClientAPI()
    local clientApi = {}

    clientApi.getLocale = function(key)
        local str = Locales[key]
        if str == nil then
            str = "Locale `" .. key .. "` does not seem to exist."
        end
        return str
    end

    clientApi.GetPlayerClientData = function()
        return GetFunctions().GetPlayerData()
    end

    clientApi.instancePlayers = function(set)
        TriggerServerEvent("jrs_core:instanceplayers", set)
    end

    clientApi.DisplayProgressBar = function(time, description, cb, shouldCancel, options)
        return DisplayProgressBar(time, description, cb, shouldCancel, options)
    end

    clientApi.CancelProgressBar = function()
        return CancelProgressBar()
    end

    clientApi.Progress = function(action, finish)
        return Progress(action, finish)
    end

    -- Notifications
    clientApi.NotifyLeft = function(firsttext, secondtext, dict, icon, duration, color)
        CoreNotifications.NotifyLeft(tostring(firsttext), tostring(secondtext), tostring(dict), tostring(icon), tonumber(duration), (color and tostring(color)) or "COLOR_WHITE")
    end

    clientApi.NotifyTip = function(text, duration)
        CoreNotifications.NotifyTip(tostring(text), tonumber(duration))
    end

    clientApi.NotifyTop = function(text, location, duration)
        CoreNotifications.NotifyTop(tostring(text), tostring(location), tonumber(duration))
    end

    clientApi.NotifyRightTip = function(text, duration)
        CoreNotifications.NotifyRightTip(tostring(text), tonumber(duration))
    end

    clientApi.NotifyObjective = function(text, duration)
        CoreNotifications.NotifyObjective(tostring(text), tonumber(duration))
    end

    clientApi.NotifySimpleTop = function(title, subtitle, duration)
        CoreNotifications.NotifySimpleTop(tostring(title), tostring(subtitle), tonumber(duration))
    end

    clientApi.NotifyBasicTop = function(text, duration)
        CoreNotifications.NotifyBasicTop(tostring(text), tonumber(duration))
    end

    clientApi.NotifyCenter = function(text, duration)
        CoreNotifications.NotifyCenter(tostring(text), tonumber(duration))
    end

    clientApi.NotifyBottomRight = function(text, duration)
        CoreNotifications.NotifyBottomRight(tostring(text), tonumber(duration))
    end

    clientApi.NotifyAdvanced = function(text, dict, icon, text_color, duration, quality)
        CoreNotifications.NotifyAdvanced(tostring(text), tostring(dict), tostring(icon), tostring(text_color), tonumber(duration), quality)
    end

    clientApi.NotifyAvanced = function(text, dict, icon, text_color, duration, quality)
        clientApi.NotifyAdvanced(text, dict, icon, text_color, duration, quality)
    end

    clientApi.NotifyFail = function(title, subtitle, duration)
        CoreNotifications.NotifyFail(tostring(title), tostring(subtitle), tonumber(duration))
    end

    clientApi.NotifyDead = function(title, audioRef, audioName, duration)
        CoreNotifications.NotifyDead(tostring(title), tostring(audioRef), tostring(audioName), tonumber(duration))
    end

    clientApi.NotifyUpdate = function(utitle, umsg, duration)
        CoreNotifications.NotifyUpdate(tostring(utitle), tostring(umsg), tonumber(duration))
    end

    clientApi.NotifyWarning = function(title, msg, audioRef, audioName, duration)
        CoreNotifications.NotifyWarning(tostring(title), tostring(msg), tostring(audioRef), tostring(audioName), tonumber(duration))
    end

    clientApi.NotifyLeftRank = function(title, subtitle, dict, icon, duration, color)
        CoreNotifications.NotifyLeftRank(tostring(title), tostring(subtitle), tostring(dict), tostring(icon), tonumber(duration), (color and tostring(color)) or "COLOR_WHITE")
    end

    -- Utilities
    clientApi.loadModel = function(model)
        CoreFunctions.LoadModel(model)
    end

    clientApi.loadTexture = function(hash)
        return CoreFunctions.LoadTexture(hash)
    end

    clientApi.teleportToCoords = function(x, y, z, heading)
        CoreFunctions.TeleportToCoords(x, y, z, heading)
    end

    clientApi.teleportPedToCoords = function(ped, x, y, z, heading)
        CoreFunctions.TeleportPedToCoords(ped, x, y, z, heading)
    end

    clientApi.PlayAnimation = function(ped, anim)
        if not DoesAnimDictExist(anim.dict) then
            return false
        end

        local timeout = 10000
        RequestAnimDict(anim.dict)

        while not HasAnimDictLoaded(anim.dict) do
            timeout = timeout - 10
            if timeout <= 0 then
                return false
            end
            Citizen.Wait(10)
        end

        TaskPlayAnim(ped, anim.dict, anim.name, anim.blendInSpeed, anim.blendOutSpeed, anim.duration, anim.flag, anim.playbackRate, false, false, false, '', false)
        RemoveAnimDict(anim.dict)
        return true
    end

    return clientApi
end

-- Unified public client API.
-- Usage: local JRS = exports.jrs_core:getCoreApi()
local function buildUnifiedClientAPI()
    -- GetInvokingResource() is only meaningful inside the export call itself, so
    -- the caller is captured here and stamped on each notification below. That is
    -- what lets every message name the script that raised it.
    local caller = nil
    if type(GetInvokingResource) == 'function' then
        local ok, res = pcall(GetInvokingResource)
        if ok then caller = res end
    end

    local api = buildClientAPI()

    -- Wrap the notification entry points so the source travels with the call.
    for _, name in ipairs({ 'NotifyLeft', 'NotifyTip', 'NotifyTop', 'NotifyRightTip',
                            'NotifyObjective', 'NotifySimpleTop', 'NotifyAdvanced',
                            'NotifyAvanced', 'NotifyBasicTop', 'NotifyCenter',
                            'NotifyBottomRight', 'NotifyFail' }) do
        local original = api[name]
        if type(original) == 'function' then
            api[name] = function(...)
                CoreNotifications.SetSource(caller)
                local res = original(...)
                CoreNotifications.SetSource(nil)
                return res
            end
        end
    end

    api.Rpc = function(name, callback, ...)
        return ClientRPC.Callback.TriggerAsync(name, callback, ...)
    end
    api.RpcCall = api.Rpc
    api.RPC = JRSRPCClient
    api.CallServer = function(name, ...)
        return JRSRPCClient and JRSRPCClient.CallServer and JRSRPCClient.CallServer(name, ...)
    end
    api.RegisterClientCallback = function(name, cb)
        return JRSRPCClient and JRSRPCClient.Register and JRSRPCClient.Register(name, cb)
    end
    api.GetLocale = api.getLocale
    api.GetPlayerData = api.GetPlayerClientData

    api.IsCharacterReady = function()
        return exports[GetCurrentResourceName()]:IsCharacterReady()
    end
    api.IsIdentityReady = function()
        return exports[GetCurrentResourceName()]:IsCharacterReady()
    end
    api.WaitForCharacterReady = function(timeoutMs)
        return exports[GetCurrentResourceName()]:WaitForCharacterReady(timeoutMs)
    end

    api.LoadModel = function(model)
        return CoreFunctions.LoadModel(model)
    end
    api.LoadTexture = function(texture)
        return CoreFunctions.LoadTexture(texture)
    end
    api.BigInt = function(value)
        return CoreFunctions.BigInt(value)
    end
    api.DrawText = function(...)
        return CoreFunctions.DrawText(...)
    end
    api.TeleportToCoords = function(x, y, z, heading)
        return CoreFunctions.TeleportToCoords(x, y, z, heading)
    end
    api.TeleportPedToCoords = function(ped, x, y, z, heading)
        return CoreFunctions.TeleportPedToCoords(ped, x, y, z, heading)
    end
    api.TeleportToWaypoint = function()
        return CoreFunctions.TeleportToWaypoint()
    end
    api.HealPlayer = function()
        return CoreFunctions.HealPlayer()
    end
    api.RemoveEntityProperly = function(entity, objectHash)
        return CoreFunctions.RemoveEntityProperly(entity, objectHash)
    end

    api.SetCustomDestination = function(coords, name, color)
        return exports[GetCurrentResourceName()]:SetCustomDestination(coords, name, color)
    end
    api.RemoveCustomDestination = function()
        return exports[GetCurrentResourceName()]:RemoveCustomDestination()
    end

    api.GetPerformanceMode = function()
        return exports[GetCurrentResourceName()]:GetPerformanceMode()
    end
    api.GetNearbyPlayerCount = function()
        return exports[GetCurrentResourceName()]:GetNearbyPlayerCount()
    end
    api.IsEntityProtected = function(entity)
        return exports[GetCurrentResourceName()]:IsEntityProtected(entity)
    end
    api.SetEntityProtected = function(entity, protected)
        return exports[GetCurrentResourceName()]:SetEntityProtected(entity, protected)
    end

    api.SetPlayerInstance = function(instance)
        TriggerServerEvent('jrs_core:instanceplayers', instance)
    end
    api.RequestHudLayout = function()
        TriggerServerEvent('jrs_core:hud:requestLayout')
    end
    api.SaveHudLayout = function(layout)
        TriggerServerEvent('jrs_core:hud:saveLayout', layout)
    end
    api.RequestWheelSync = function()
        TriggerServerEvent('jrs_core:wheel:requestSync')
    end
    api.UseWheelItem = function(itemName)
        TriggerServerEvent('jrs_core:wheel:useFromWheel', itemName)
    end
    -- Shared utility helpers inspired by common framework needs, implemented natively for JRS.
    api.Utils = JRSUtils
    api.WaitUntil = function(...) return JRSUtils.WaitUntil(...) end
    api.LoadModelSafe = function(...) return JRSUtils.LoadModel(...) end
    api.LoadAnimDict = function(...) return JRSUtils.LoadAnimDict(...) end
    api.LoadTextureDict = function(...) return JRSUtils.LoadTextureDict(...) end
    api.GetNearbyPlayers = function(...) return JRSUtils.GetNearbyPlayers(...) end
    api.GetClosestPlayer = function(...) return JRSUtils.GetClosestPlayer(...) end
    api.NoSpam = function(...) return JRSUtils.NoSpam(...) end
    api.SetTimeout = function(...) return JRSUtils.SetTimeout(...) end
    api.Round = function(...) return JRSUtils.Round(...) end
    api.Lerp = function(...) return JRSUtils.Lerp(...) end
    api.ApplyGameplaySettings = function()
        return exports[GetCurrentResourceName()]:ApplyGameplaySettings()
    end

    -- Unified UI modules are compiled directly into jrs_core.
    -- Core.Notify and Core.Toast now land on the same unified renderer:
    -- Notify goes through CoreNotifications.NotifyRightTip, which routes to the
    -- toast (Config.Notifications.RouteLegacyNativeFeed). One surface, so which
    -- helper a script calls no longer changes how its message looks.
    api.Notify = function(text, notifyType, duration, title)
        if text == nil or tostring(text) == '' then return false end
        CoreNotifications.SetSource(caller)
        local res = CoreNotifications.NotifyRightTip(tostring(text), tonumber(duration) or 3500, title, notifyType)
        CoreNotifications.SetSource(nil)
        return true
    end

    api.Toast = function(text, notifyType, duration, title)
        if text == nil or tostring(text) == '' then return false end
        if JRSToast and type(JRSToast.Show) == 'function' then
            return JRSToast.Show({
                text = tostring(text),
                type = notifyType,
                duration = duration,
                title = title,
                source = caller,
            }) == true
        end
        return api.Notify(text, notifyType, duration, title)
    end

    api.ShowNotification = function(payload)
        if type(payload) ~= 'table' then return false end
        if JRSToast and type(JRSToast.Show) == 'function' then
            local copy = {}
            for k, v in pairs(payload) do copy[k] = v end
            if copy.source == nil then copy.source = caller end
            return JRSToast.Show(copy) == true
        end
        return api.Notify(payload.text or payload.message, payload.type or payload.notifyType, payload.duration, payload.title)
    end

    api.Info = function(text, duration, title) return api.Toast(text, 'info', duration, title) end
    api.Success = function(text, duration, title) return api.Toast(text, 'success', duration, title) end
    api.ErrorNotify = function(text, duration, title) return api.Toast(text, 'error', duration, title) end
    api.WarningNotify = function(text, duration, title) return api.Toast(text, 'warning', duration, title) end
    api.RewardNotify = function(text, duration, title) return api.Toast(text, 'reward', duration, title) end

    api.GetInput = function(title, subtext, cb, options)
        if not JRSInputAPI or type(JRSInputAPI.Open) ~= 'function' then return false, 'input_unavailable' end
        return JRSInputAPI.Open(title, subtext, cb, options)
    end
    api.Input = api.GetInput
    api.NumberInput = function(title, subtext, cb, options)
        if not JRSInputAPI or type(JRSInputAPI.Number) ~= 'function' then return false, 'input_unavailable' end
        return JRSInputAPI.Number(title, subtext, cb, options)
    end
    api.InputAwait = function(title, subtext, options)
        if not JRSInputAPI or type(JRSInputAPI.Await) ~= 'function' then return nil, 'input_unavailable' end
        return JRSInputAPI.Await(title, subtext, options)
    end
    api.GetAnswer = function(title, first, second, cb)
        if not JRSInputAPI or type(JRSInputAPI.Confirm) ~= 'function' then return false, 'input_unavailable' end
        return JRSInputAPI.Confirm(title, first, second, cb)
    end
    api.Confirm = api.GetAnswer
    api.ConfirmAwait = function(title, first, second)
        if not JRSInputAPI or type(JRSInputAPI.ConfirmAwait) ~= 'function' then return false, 'input_unavailable' end
        return JRSInputAPI.ConfirmAwait(title, first, second)
    end
    api.IsInputOpen = function()
        return JRSInputAPI and JRSInputAPI.IsOpen and JRSInputAPI.IsOpen() == true or false
    end
    api.CloseInput = function()
        return JRSInputAPI and JRSInputAPI.Close and JRSInputAPI.Close() ~= false or false
    end

    api.GetMenu = function()
        return JRSMenuAPI
    end
    api.OpenMenu = function(typeName, namespace, name, data, submit, cancel, change, close)
        if not JRSMenuAPI or type(JRSMenuAPI.Open) ~= 'function' then return nil, 'menu_unavailable' end
        return JRSMenuAPI.Open(typeName or 'default', namespace or caller or 'jrs_core', name, data, submit, cancel, change, close)
    end
    api.CloseMenu = function(typeName, namespace, name)
        if not JRSMenuAPI or type(JRSMenuAPI.Close) ~= 'function' then return false end
        return JRSMenuAPI.Close(typeName or 'default', namespace or caller or 'jrs_core', name)
    end
    api.CloseAllMenus = function()
        if not JRSMenuAPI or type(JRSMenuAPI.CloseAll) ~= 'function' then return false end
        JRSMenuAPI.CloseAll()
        return true
    end
    api.IsAnyMenuOpen = function()
        return JRSMenuAPI and JRSMenuAPI.IsAnyOpen and JRSMenuAPI.IsAnyOpen() == true or false
    end

    api.Trade = {
        Start = function(target)
            if GetResourceState('jrs_inventory') ~= 'started' then return false, 'inventory_not_started' end
            return exports.jrs_inventory:StartTrade(target)
        end,
        Cancel = function()
            if GetResourceState('jrs_inventory') ~= 'started' then return false end
            return exports.jrs_inventory:CancelTrade()
        end,
        IsTrading = function()
            if GetResourceState('jrs_inventory') ~= 'started' then return false end
            return exports.jrs_inventory:IsTrading()
        end,
        GetSession = function()
            if GetResourceState('jrs_inventory') ~= 'started' then return nil end
            return exports.jrs_inventory:GetTradeSession()
        end,
        CanTradeWith = function(target)
            if GetResourceState('jrs_inventory') ~= 'started' then return false, 'inventory_not_started' end
            return exports.jrs_inventory:CanTradeWith(target)
        end,
        Reopen = function()
            if GetResourceState('jrs_inventory') ~= 'started' then return false end
            return exports.jrs_inventory:ReopenTrade()
        end,
    }

    api.UI = JRSUI
    api.AcquireUI = function(owner, options)
        return JRSUI and JRSUI.Acquire and JRSUI.Acquire(owner or caller, options)
    end
    api.ReleaseUI = function(owner, options)
        return JRSUI and JRSUI.Release and JRSUI.Release(owner or caller, options)
    end
    api.IsUIBusy = function(owner)
        return JRSUI and JRSUI.IsBusy and JRSUI.IsBusy(owner or caller)
    end
    api.GetOpenUI = function()
        return JRSUI and JRSUI.GetState and JRSUI.GetState() or { busy = false }
    end

    api.SetMapDiscoveriesEnabled = function(enabled)
        if type(JRSMapDiscoveryData) ~= 'table' then return false end
        for _, discovery in ipairs(JRSMapDiscoveryData) do
            if enabled == true then
                MapDiscoverRegion(discovery.hash)
            else
                MapDiscoverySetEnabled(discovery.hash, false)
            end
        end
        return true
    end

    return api
end

exports('getCoreApi', buildUnifiedClientAPI)
exports('GetCoreObject', buildUnifiedClientAPI)
exports('GetLevel', function()
    local perks = LocalPlayer and LocalPlayer.state and LocalPlayer.state.jrsPerks
    if type(perks) == 'table' and tonumber(perks.level) then
        return math.floor(tonumber(perks.level))
    end
    local state = LocalPlayer and LocalPlayer.state
    if state and tonumber(state.level) then
        return math.floor(tonumber(state.level))
    end
    return 1
end)
exports('getLevel', function()
    return exports['jrs_core']:GetLevel()
end)

-- Direct native notification aliases. These use the original RedM feed.
exports('NotifyRightTip', function(...) return buildUnifiedClientAPI().NotifyRightTip(...) end)
exports('NotifyLeft', function(...) return buildUnifiedClientAPI().NotifyLeft(...) end)
exports('NotifyTip', function(...) return buildUnifiedClientAPI().NotifyTip(...) end)
exports('NotifyTop', function(...) return buildUnifiedClientAPI().NotifyTop(...) end)
exports('NotifyObjective', function(...) return buildUnifiedClientAPI().NotifyObjective(...) end)
exports('NotifySimpleTop', function(...) return buildUnifiedClientAPI().NotifySimpleTop(...) end)
exports('NotifyAdvanced', function(...) return buildUnifiedClientAPI().NotifyAdvanced(...) end)
exports('NotifyBasicTop', function(...) return buildUnifiedClientAPI().NotifyBasicTop(...) end)
exports('NotifyCenter', function(...) return buildUnifiedClientAPI().NotifyCenter(...) end)
exports('NotifyBottomRight', function(...) return buildUnifiedClientAPI().NotifyBottomRight(...) end)
exports('NotifyFail', function(...) return buildUnifiedClientAPI().NotifyFail(...) end)
exports('NotifyDead', function(...) return buildUnifiedClientAPI().NotifyDead(...) end)
exports('NotifyUpdate', function(...) return buildUnifiedClientAPI().NotifyUpdate(...) end)
exports('NotifyWarning', function(...) return buildUnifiedClientAPI().NotifyWarning(...) end)
exports('NotifyLeftRank', function(...) return buildUnifiedClientAPI().NotifyLeftRank(...) end)

-- Direct UI ownership aliases.
exports('AcquireUI', function(...) return buildUnifiedClientAPI().AcquireUI(...) end)
exports('ReleaseUI', function(...) return buildUnifiedClientAPI().ReleaseUI(...) end)
exports('IsUIBusy', function(...) return buildUnifiedClientAPI().IsUIBusy(...) end)
exports('GetOpenUI', function(...) return buildUnifiedClientAPI().GetOpenUI(...) end)

-- Stable direct aliases for resources that prefer exports over carrying an API table.
exports('Notify', function(...) return buildUnifiedClientAPI().Notify(...) end)
exports('Toast', function(...) return buildUnifiedClientAPI().Toast(...) end)
exports('ShowNotification', function(...) return buildUnifiedClientAPI().ShowNotification(...) end)
exports('GetInput', function(...) return buildUnifiedClientAPI().GetInput(...) end)
exports('GetAnswer', function(...) return buildUnifiedClientAPI().GetAnswer(...) end)
exports('NumberInput', function(...) return buildUnifiedClientAPI().NumberInput(...) end)
exports('InputAwait', function(...) return buildUnifiedClientAPI().InputAwait(...) end)
exports('ConfirmAwait', function(...) return buildUnifiedClientAPI().ConfirmAwait(...) end)
exports('IsInputOpen', function(...) return buildUnifiedClientAPI().IsInputOpen(...) end)
exports('GetMenu', function(...) return buildUnifiedClientAPI().GetMenu(...) end)
exports('OpenMenu', function(...) return buildUnifiedClientAPI().OpenMenu(...) end)
exports('CloseMenu', function(...) return buildUnifiedClientAPI().CloseMenu(...) end)
exports('CloseAllMenus', function(...) return buildUnifiedClientAPI().CloseAllMenus(...) end)
exports('IsAnyMenuOpen', function(...) return buildUnifiedClientAPI().IsAnyMenuOpen(...) end)
exports('CloseInput', function(...) return buildUnifiedClientAPI().CloseInput(...) end)


-- Legacy jrs_notify-style exports now live on jrs_core. These intentionally use
-- the optional custom toast renderer; native Core.Notify*/NotifyRightTip/etc
-- remain unchanged.
exports('DisplayLeftNotification', function(title, subtext, icon, duration)
    if JRSToast and type(JRSToast.DisplayLeftNotification) == 'function' then
        return JRSToast.DisplayLeftNotification(title, subtext, icon, duration)
    end
    return buildUnifiedClientAPI().Toast(subtext or title, 'info', duration, title)
end)
exports('DisplayNotification', function(text, duration)
    if JRSToast and type(JRSToast.DisplayNotification) == 'function' then
        return JRSToast.DisplayNotification(text, duration)
    end
    return buildUnifiedClientAPI().Toast(text, 'info', duration)
end)
exports('DisplayLocationNotification', function(text, location, duration)
    if JRSToast and type(JRSToast.DisplayLocationNotification) == 'function' then
        return JRSToast.DisplayLocationNotification(text, location, duration)
    end
    return buildUnifiedClientAPI().Toast(text, 'info', duration, location)
end)
exports('ShowAdvancedRightNotification', function(text, dict, icon, textColor, duration)
    if JRSToast and type(JRSToast.ShowAdvancedRightNotification) == 'function' then
        return JRSToast.ShowAdvancedRightNotification(text, dict, icon, textColor, duration)
    end
    return buildUnifiedClientAPI().Toast(text, 'reward', duration)
end)
exports('SetMenuOpen', function(state, sourceName)
    if JRSToast and type(JRSToast.SetMenuOpen) == 'function' then
        return JRSToast.SetMenuOpen(state, sourceName)
    end
    return false
end)
-- SetToastCapture(true) from a resource whose fullscreen NUI covers the toasts:
-- jrs_core then raises the local event 'jrs_core:notify:captured' with each
-- toast for that resource to draw in its own layer, and only plays the sound.
exports('SetToastCapture', function(state)
    if type(JRSNotifySetCapture) ~= 'function' then return false end
    local caller = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    return JRSNotifySetCapture(state == true, caller)
end)
exports('ClearNotifications', function()
    if JRSToast and type(JRSToast.Clear) == 'function' then return JRSToast.Clear() end
    return false
end)

exports('GetPlayerInteractionsConfig', function()
    return Config.PlayerInteractions or { Enabled = false }
end)

exports('DisplayProgressBar', function(time, description, cb, shouldCancel, options)
    return DisplayProgressBar(time, description, cb, shouldCancel, options)
end)

exports('CancelProgressBar', function()
    return CancelProgressBar()
end)

exports('Progress', function(action, finish)
    return Progress(action, finish)
end)

