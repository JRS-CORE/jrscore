local tradeOpen = false
local currentTradeState = nil
local resourceName = GetCurrentResourceName()
local UI_OWNER = 'jrs_inventory:trade'

local function moduleMessage(payload)
    SendNUIMessage({ __jrsModule = 'trade', payload = payload })
end

local function acquireTradeUi()
    if GetResourceState('jrs_core') ~= 'started' then
        SetNuiFocus(true, true)
        return true
    end
    local ok, acquired = pcall(function()
        return exports.jrs_core:AcquireUI(UI_OWNER, { focus = true, cursor = true, kind = 'trade' })
    end)
    return ok and acquired == true
end

local function releaseTradeUi()
    if GetResourceState('jrs_core') == 'started' then
        pcall(function() exports.jrs_core:ReleaseUI(UI_OWNER) end)
    else
        SetNuiFocus(false, false)
    end
end
local Core = exports.jrs_core:getCoreApi()

local function setVisible(state)
    local wanted = state == true
    if wanted then
        if acquireTradeUi() ~= true then return false end
        tradeOpen = true
    else
        tradeOpen = false
        releaseTradeUi()
    end
    TriggerEvent('jrs_hud:busy', UI_OWNER, tradeOpen)
    return true
end

local function notify(message, notifyType)
    local text = tostring(message or '')
    if text == '' then return false end
    if Core and type(Core.Notify) == 'function' then
        local ok, rendered = pcall(Core.Notify, text, notifyType or 'info', 3500, 'Trade')
        if ok and rendered ~= false then return true end
    end
    TriggerEvent('jrsCore:notify', 'Trade', text, 'bag', 3500)
    return true
end

local function startTrade(target)
    target = tonumber(target)
    if not target or target <= 0 or target == GetPlayerServerId(PlayerId()) then
        notify(TradeConfig.Text.select_nearby or 'Select a valid nearby player.', 'warning')
        return false
    end
    if GetResourceState('jrs_inventory') == 'started' then
        TriggerEvent('jrs_inventory:CloseInv')
    end
    -- The player picker belongs to jrs_inventory. This resource only submits a
    -- server-validated invitation and opens after acceptance/state restoration.
    setVisible(false)
    moduleMessage({ action = 'close' })
    TriggerServerEvent('jrs_trade:server:invite', target)
    return true
end

RegisterNetEvent('jrs_trade:client:notify', function(message)
    notify(message)
end)

RegisterNetEvent('jrs_trade:client:invite', function(payload)
    currentTradeState = payload
    TriggerEvent('jrs_inventory:CloseInv')
    setVisible(true)
    moduleMessage({ action = 'invite', data = payload })
end)

RegisterNetEvent('jrs_trade:client:state', function(payload)
    currentTradeState = payload
    TriggerEvent('jrs_inventory:CloseInv')
    setVisible(true)
    moduleMessage({ action = 'state', data = payload })
end)

RegisterNetEvent('jrs_trade:client:refresh', function(payload)
    currentTradeState = payload
    if tradeOpen then
        moduleMessage({ action = 'state', data = payload })
    end
end)

RegisterNetEvent('jrs_trade:client:close', function(reason)
    currentTradeState = nil
    setVisible(false)
    moduleMessage({ action = 'close', reason = reason })
end)

RegisterNetEvent('jrs_trade:client:openFromInventory', function(target)
    startTrade(target)
end)

exports('StartTrade', startTrade)
exports('IsTradeOpen', function() return tradeOpen == true end)
exports('IsTrading', function() return currentTradeState ~= nil or tradeOpen == true end)
exports('GetTradeSession', function() return currentTradeState end)
exports('CancelTrade', function()
    TriggerServerEvent('jrs_trade:server:cancel')
    return true
end)
exports('CanTradeWith', function(target)
    target = tonumber(target)
    if not target or target <= 0 or target == GetPlayerServerId(PlayerId()) then return false, 'invalid_target' end
    local player = GetPlayerFromServerId(target)
    if player == -1 or not NetworkIsPlayerActive(player) then return false, 'offline' end
    local myPed, targetPed = PlayerPedId(), GetPlayerPed(player)
    if myPed == 0 or targetPed == 0 or not DoesEntityExist(targetPed) then return false, 'invalid_ped' end
    local distance = #(GetEntityCoords(myPed) - GetEntityCoords(targetPed))
    if distance > (tonumber(TradeConfig.MaxDistance) or 3.0) then return false, 'too_far' end
    return true, distance
end)
exports('ReopenTrade', function()
    TriggerServerEvent('jrs_trade:server:reopen')
    return true
end)

RegisterCommand(TradeConfig.Command, function(_, args)
    local target = tonumber(args[1])
    if not target then
        notify(('Use /%s [player ID]'):format(TradeConfig.Command), 'warning')
        return
    end
    startTrade(target)
end, false)

RegisterCommand(TradeConfig.ReopenCommand, function()
    TriggerServerEvent('jrs_trade:server:reopen')
end, false)

RegisterNUICallback('acceptInvite', function(data, cb)
    TriggerServerEvent('jrs_trade:server:acceptInvite', data and data.tradeKey)
    cb({ ok = true })
end)

RegisterNUICallback('declineInvite', function(data, cb)
    TriggerServerEvent('jrs_trade:server:declineInvite', data and data.tradeKey)
    setVisible(false)
    cb({ ok = true })
end)

RegisterNUICallback('addItem', function(data, cb)
    TriggerServerEvent('jrs_trade:server:addItem', tonumber(data.itemId), tonumber(data.count))
    cb({ ok = true })
end)

RegisterNUICallback('removeItem', function(data, cb)
    TriggerServerEvent('jrs_trade:server:removeItem', tonumber(data.itemId))
    cb({ ok = true })
end)

RegisterNUICallback('addWeapon', function(data, cb)
    TriggerServerEvent('jrs_trade:server:addWeapon', tonumber(data.weaponId))
    cb({ ok = true })
end)

RegisterNUICallback('removeWeapon', function(data, cb)
    TriggerServerEvent('jrs_trade:server:removeWeapon', tonumber(data.weaponId))
    cb({ ok = true })
end)

RegisterNUICallback('setPrice', function(data, cb)
    TriggerServerEvent('jrs_trade:server:setPrice', tonumber(data.price))
    cb({ ok = true })
end)

RegisterNUICallback('lockOffer', function(_, cb)
    TriggerServerEvent('jrs_trade:server:lockOffer')
    cb({ ok = true })
end)

RegisterNUICallback('pay', function(_, cb)
    TriggerServerEvent('jrs_trade:server:pay')
    cb({ ok = true })
end)

RegisterNUICallback('cancelTrade', function(_, cb)
    TriggerServerEvent('jrs_trade:server:cancel')
    cb({ ok = true })
end)

RegisterNUICallback('closeUi', function(_, cb)
    setVisible(false)
    cb({ ok = true })
end)

RegisterNetEvent('jrs_character:isPlayerReady', function()
    Citizen.SetTimeout(1000, function()
        TriggerServerEvent('jrs_trade:server:playerReady')
    end)
end)

Citizen.CreateThread(function()
    Citizen.Wait(4000)
    TriggerServerEvent('jrs_trade:server:playerReady')
end)

AddEventHandler('onClientResourceStop', function(stopped)
    if stopped ~= resourceName then return end
    tradeOpen = false
    releaseTradeUi()
    TriggerEvent('jrs_hud:busy', resourceName, false)
end)
