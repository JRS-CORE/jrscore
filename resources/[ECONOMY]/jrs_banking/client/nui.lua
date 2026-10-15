-- jrs_banking | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- The NUI dispatches the existing banking events. Balances remain server-owned.
BankUI = {}
local Core = exports.jrs_core:GetCore()
local owner = GetCurrentResourceName()
local active, loading, focused, submitting = nil, false, false, false
local serial, reopenAt = 0, 0
local function notify(key)
    Core.NotifyRightTip(BankTranslation.For()[key] or key, 4000)
end
local function available(name)
    local cfg = Config.banks[name]
    if not cfg or IsEntityDead(PlayerPedId()) or IsPauseMenuActive() then return false end
    if not LocalPlayer.state.IsInSession or LocalPlayer.state.CharacterReady == false then return false end
    local p = cfg.BankLocation
    if #(GetEntityCoords(PlayerPedId()) - vector3(p.x,p.y,p.z)) > cfg.distOpen + 1.0 then return false end
    if cfg.StoreHoursAllowed then
        local hour = GetClockHours()
        if hour >= cfg.StoreClose or hour < cfg.StoreOpen then return false end
    end
    return true
end
function BankUI.IsOpen() return focused or loading or GetGameTimer() < reopenAt end
function BankUI.Close()
    serial = serial + 1
    active, loading, submitting = nil, false, false
    SendNUIMessage({ action = 'bank:close' })
    if focused then
        focused = false
        SetNuiFocus(false,false)
        SetNuiFocusKeepInput(false)
        exports.jrs_core:ReleaseUI(owner, { manageFocus = false })
        ClearPedTasks(PlayerPedId())
        DisplayRadar(true)
    end
    reopenAt = GetGameTimer() + 500
end
function BankUI.Render()
    if not active then return end
    local cfg = Config.banks[active.name]
    local accounts = {}
    for _, row in ipairs(active.accounts) do
        if row.name ~= active.name and Config.banks[row.name] then
            accounts[#accounts+1] = { name=row.name, money=tonumber(row.money) or 0 }
        end
    end
    table.sort(accounts,function(a,b)return a.name < b.name end)
    SendNUIMessage({ action='bank:open', token=serial, language=BankTranslation.Language(),
        name=active.name, title=cfg.name, money=tonumber(active.info.money) or 0,
        gold=tonumber(active.info.gold) or 0, slots=tonumber(active.info.invspace) or 0,
        maxSlots=cfg.maxslots, slotPrice=cfg.costslot, goldEnabled=cfg.gold == true,
        vaultEnabled=cfg.items == true, upgradeEnabled=cfg.upgrade == true,
        transferEnabled=Config.banktransfer == true, feeMultiplier=tonumber(Config.feeamount) or 1,
        accounts=accounts })
end
function BankUI.Open(name)
    if BankUI.IsOpen() or not available(name) then return false end
    if not exports.jrs_core:AcquireUI(owner,{focus=true,cursor=true,manageFocus=false,kind='bank'}) then return false end
    focused, loading = true, true
    serial = serial + 1
    local token = serial
    CreateThread(function()
        Wait(10000)
        if loading and token == serial then BankUI.Close() end
    end)
    local ok, result = pcall(function() return Core.Callback.TriggerAwait('jrs_bank:getinfo',name) end)
    -- Ignore late replies after close / character change / a newer request.
    if token ~= serial then return false end
    loading = false
    if not ok or type(result) ~= 'table' or type(result[1]) ~= 'table'
        or result[1].money == nil or not available(name) then
        BankUI.Close(); return false
    end
    active = {name=name,info=result[1],accounts=type(result[2])=='table' and result[2] or {}}
    SetNuiFocus(true,true)
    SetNuiFocusKeepInput(false)
    TaskStandStill(PlayerPedId(),-1)
    DisplayRadar(false)
    BankUI.Render()
    return true
end
local function validate(data)
    if type(data) ~= 'table' or not active or data.token ~= serial or submitting then return false end
    if not available(active.name) then BankUI.Close();return false end
    return true
end
RegisterNUICallback('bankReady',function(_,cb)BankUI.Render();cb({ok=true})end)
RegisterNUICallback('bankClose',function(data,cb)
    if type(data)=='table' and data.token == serial then BankUI.Close() end
    cb({ok=true})
end)
RegisterNUICallback('bankVault',function(data,cb)
    if not validate(data) or not Config.banks[active.name].items then cb({ok=false,error='unavailable'});return end
    if (tonumber(active.info.invspace) or 0) <= 0 then cb({ok=false,error='buySlots'});return end
    local name=active.name
    -- Release mouse focus before jrs_inventory acquires it.
    BankUI.Close()
    TriggerServerEvent('jrs_banking:server:OpenBankInventory',name)
    cb({ok=true})
end)
RegisterNUICallback('bankSubmit',function(data,cb)
    if not validate(data) then cb({ok=false,error='unavailable'});return end
    local cfg = Config.banks[active.name]
    local amount = tonumber(data.amount)
    local integer = data.action == 'dgold' or data.action == 'wgold' or data.action == 'upgrade'
    if not amount or amount ~= amount or amount <= 0 or amount > 10000000
        or (integer and amount ~= math.floor(amount))
        or math.abs(amount * 100 - math.floor(amount * 100 + 0.5)) > 0.000001 then
        cb({ok=false,error=integer and 'integerOnly' or 'invalid'});return
    end
    local routes={ dcash='jrs_bank:depositcash',wcash='jrs_bank:withcash',dgold='jrs_bank:depositgold',wgold='jrs_bank:withgold' }
    local action, name, from = data.action, active.name, data.from
    if routes[action] then
        if (action=='dgold' or action=='wgold') and not cfg.gold then cb({ok=false,error='unavailable'});return end
    elseif action == 'upgrade' then
        if not cfg.upgrade or amount + (tonumber(active.info.invspace) or 0) > cfg.maxslots then
            cb({ok=false,error='maxSlots'});return
        end
    elseif action == 'transfer' then
        local owned=false
        for _,row in ipairs(active.accounts) do if row.name==from then owned=true;break end end
        if not Config.banktransfer or not owned or not Config.banks[from] or from==name then
            cb({ok=false,error='unavailable'});return
        end
    else cb({ok=false,error='unavailable'});return end
    submitting=true
    if routes[action] then TriggerServerEvent(routes[action],amount,name)
    elseif action=='upgrade' then TriggerServerEvent('jrs_bank:UpgradeSafeBox',amount,active.info.invspace,name)
    else TriggerServerEvent('jrs_bank:transfer',amount,from,name) end
    -- Existing server notifications report the actual result; no guessed balances.
    BankUI.Close()
    cb({ok=true})
end)
AddEventHandler('jrs_core:language:changed',function() BankUI.Render() end)
RegisterNetEvent('jrs_core:client:characterUnloaded',function()BankUI.Close()end)
AddEventHandler('onResourceStop',function(resource)if resource==owner then BankUI.Close()end end)
CreateThread(function()
    while true do
        Wait(200)
        if active and not available(active.name) then BankUI.Close() end
    end
end)
