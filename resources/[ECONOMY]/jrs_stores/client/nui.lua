-- jrs_stores | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
StoresUI = {}
local Core=exports.jrs_core:GetCore()
local owner=GetCurrentResourceName()
local active,loading,focused,busy=nil,false,false,false
local serial,reopenAt,nextRefresh=0,0,0
local function available(id)
    local cfg=Config.Stores[id]
    local state=LocalPlayer.state
    if not cfg or cfg.isDeactivated or not state.IsInSession or state.CharacterReady==false
        or IsEntityDead(PlayerPedId()) or IsPauseMenuActive() or StoresShared.IsClosed(cfg) then return false end
    local char=state.Character or {}
    if not StoresShared.JobAllowed(cfg,char.Job or char.job,char.Grade or char.jobGrade or char.grade) then return false end
    return #(GetEntityCoords(PlayerPedId())-cfg.Blip.Pos) <= (cfg.distanceOpenStore or 3)+1
end
local function releaseLease(id,token)
    Core.Callback.TriggerAsync('jrs_stores:callback:closeUI',function()end,id,token)
end
function StoresUI.IsOpen()return loading or focused or GetGameTimer()<reopenAt end
function StoresUI.Close()
    serial=serial+1
    local previous=active
    active,loading,busy=nil,false,false
    SendNUIMessage({action='store:close'})
    if focused then
        focused=false;SetNuiFocus(false,false);SetNuiFocusKeepInput(false)
        exports.jrs_core:ReleaseUI(owner,{manageFocus=false})
        ClearPedTasks(PlayerPedId());DisplayRadar(true);Config.UI(false)
    end
    if previous then releaseLease(previous.id,previous.lease)end
    reopenAt=GetGameTimer()+500
end
function StoresUI.Render()
    if active then SendNUIMessage({action='store:open',token=serial,data=active.data,busy=busy})end
end
function StoresUI.Open(id)
    if StoresUI.IsOpen() or not available(id) then return false end
    if not exports.jrs_core:AcquireUI(owner,{focus=true,cursor=true,manageFocus=false,kind='store'})then return false end
    serial=serial+1;local generation=serial
    loading,focused=true,true
    CreateThread(function()Wait(15000);if loading and generation==serial then StoresUI.Close()end end)
    Core.Callback.TriggerAsync('jrs_stores:callback:openUI',function(result)
        if generation~=serial then
            if result and result.ok then releaseLease(id,result.token)end
            return
        end
        loading=false
        if type(result)~='table' or not result.ok or not result.data or not available(id)then
            if result and result.ok then releaseLease(id,result.token)end
            if result and result.error then Core.NotifyRightTip(StoresShared.Text(nil,result.error),4000)end
            StoresUI.Close();return
        end
        active={id=id,lease=result.token,data=result.data};nextRefresh=GetGameTimer()+15000
        SetNuiFocus(true,true);SetNuiFocusKeepInput(false);TaskStandStill(PlayerPedId(),-1);DisplayRadar(false);Config.UI(true)
        StoresUI.Render()
    end,id)
    return true
end
local function validate(data)
    if type(data)~='table' or not active or data.token~=serial or busy then return false end
    if not available(active.id)then StoresUI.Close();return false end
    return true
end
RegisterNUICallback('storeReady',function(_,cb)StoresUI.Render();cb({ok=true})end)
RegisterNUICallback('storeClose',function(data,cb)
    if type(data)=='table' and data.token==serial then StoresUI.Close()end
    cb({ok=true})
end)
RegisterNUICallback('storeCheckout',function(data,cb)
    if not validate(data) then cb({ok=false,error='unavailable'});return end
    if (data.mode~='buy' and data.mode~='sell') or type(data.items)~='table' or #data.items<1 or #data.items>50
        or type(data.requestId)~='string' or #data.requestId>80 then cb({ok=false,error='invalid'});return end
    local rows={}
    for _,row in ipairs(active.data.products[data.mode] or {})do rows[row.key]=row end
    local seen={}
    for _,row in ipairs(data.items)do
        local count=type(row)=='table' and tonumber(row.quantity)
        if not count or count~=count or count<1 or count>500 or count~=math.floor(count) or not rows[row.key]
            or count>rows[row.key].max or seen[row.key] then cb({ok=false,error='invalid'});return end
        seen[row.key]=true
    end
    busy=true;local generation=serial
    local id,lease=active.id,active.lease
    Core.Callback.TriggerAsync('jrs_stores:callback:checkoutUI',function(result)
        if generation~=serial then cb({ok=false,error='unavailable'});return end
        busy=false
        if result and result.data then active.data=result.data;StoresUI.Render()end
        if result and result.error=='unavailable' then StoresUI.Close()end
        cb(result or {ok=false,error='failed'})
    end,{id=id,token=lease,mode=data.mode,items=data.items,requestId=data.requestId})
end)
local function refresh()
    if not active or busy then return end
    local generation,id,lease=serial,active.id,active.lease
    busy=true
    Core.Callback.TriggerAsync('jrs_stores:callback:refreshUI',function(result)
        if generation~=serial then return end
        busy=false
        if not result or not result.ok then StoresUI.Close();return end
        active.data=result.data;StoresUI.Render()
    end,id,lease)
end
AddEventHandler('jrs_core:language:changed',function()refresh()end)
RegisterNetEvent('jrs_core:client:characterUnloaded',function()StoresUI.Close()end)
AddEventHandler('onResourceStop',function(name)if name==owner then StoresUI.Close()end end)
CreateThread(function()
    while true do
        Wait(200)
        if active then
            if not available(active.id)then StoresUI.Close()
            elseif GetGameTimer()>=nextRefresh and not busy then nextRefresh=GetGameTimer()+15000;refresh()end
        end
    end
end)
