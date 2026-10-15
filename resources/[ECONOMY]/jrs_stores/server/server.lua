-- jrs_stores | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local Core = exports.jrs_core:GetCore()
local stock, sessions, playerBusy, storeBusy = {}, {}, {}, {}
local sequence = 0
local function character(src)
    local user=Core.getUser(src)
    local char=user and user.getUsedCharacter
    return char and char.charIdentifier and char or nil
end
local function notify(src,key)
    Core.NotifyRightTip(src,StoresShared.Text(src,key),4000)
end
local function available(src,id)
    local cfg=Config.Stores[id]
    local char=character(src)
    if not cfg or cfg.isDeactivated or not char or not StoresShared.JobAllowed(cfg,char.job,char.jobGrade or char.grade) then return false end
    if StoresShared.IsClosed(cfg) then return false end
    local ped=GetPlayerPed(src)
    if not ped or ped==0 then return false end
    local p=GetEntityCoords(ped)
    return #(p-vector3(cfg.Blip.Pos.x,cfg.Blip.Pos.y,cfg.Blip.Pos.z)) <= (cfg.distanceOpenStore or 3)+1.0
end
local function modeAllowed(id,mode)
    for _,row in ipairs(Config.Stores[id].storeType or {}) do if row.Type==mode then return true end end
    return false
end
local function categoryAllowed(id,category)
    for _,row in ipairs(Config.Stores[id].category or {}) do if row.Type==category then return true end end
    return false
end
local function finite(n)return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
local function cents(n)return math.floor(n*100+0.00000001)/100 end
local function quantity(value)
    local n=tonumber(value)
    return finite(n) and n>=1 and n<=500 and n==math.floor(n) and n or nil
end
local function remaining(id,mode,entry)
    if not Config.Stores[id].DynamicStore or not entry.itemLimit or entry.itemLimit<=0 then return nil end
    stock[id]=stock[id] or {buy={},sell={}}
    if stock[id][mode][entry.itemName]==nil then stock[id][mode][entry.itemName]=entry.itemLimit end
    return stock[id][mode][entry.itemName]
end
local function changeStock(id,mode,entry,qty)
    if remaining(id,mode,entry)~=nil then stock[id][mode][entry.itemName]=stock[id][mode][entry.itemName]-qty end
    if mode=='sell' and Config.Stores[id].DynamicStore then
        for _,item in ipairs(Config.BuyItems[id] or {}) do
            if item.itemName==entry.itemName and remaining(id,'buy',item)~=nil then
                stock[id].buy[item.itemName]=stock[id].buy[item.itemName]+qty;break
            end
        end
    end
end
local function eligible(item)
    if not item then return false end
    if item.isDegradable then
        return Config.AllowSellItemsWithDecay and (tonumber(item.percentage) or 0)>Config.DecayPercentage
    end
    return true
end
local function price(entry,mode,item)
    local unit=tonumber(mode=='buy' and entry.buyprice or entry.sellprice)
    if not finite(unit) or unit<0 then return nil end
    if mode=='sell' and Config.SellItemBasedOnPercentage and item and item.isDegradable then
        unit=unit*math.max(0,math.min(100,tonumber(item.percentage) or 0))/100
    end
    return unit
end
local function label(src,item)
    local ok,value=pcall(function()return exports.jrs_inventory:GetItemLabel(src,item.itemName)end)
    return ok and type(value)=='string' and value~=item.itemName and value~='' and value or item.itemLabel or item.itemName
end
local function description(src,item)
    if StoresShared.Language(src)=='ar' then
        local ok,value=pcall(function()return exports.jrs_inventory:GetItemDescription(src,item.itemName)end)
        if ok and type(value)=='string' and value~='' then return value end
        return ''
    end
    return item.desc or ''
end
local function catalogue(src,id)
    local cfg,char=Config.Stores[id],character(src)
    if not cfg or not char then return nil end
    local rows={buy={},sell={}}
    for i,entry in ipairs(Config.BuyItems[id] or {}) do
        if StoresShared.IsProductAllowed(entry) and categoryAllowed(id,entry.category) then
            local p=price(entry,'buy')
            if p then rows.buy[#rows.buy+1]={key='buy:'..i,name=entry.itemName,label=label(src,entry),desc=description(src,entry),category=entry.category,
                price=p,currency=entry.currencyType=='gold' and 'gold' or 'cash',max=math.min(entry.equipment=='fishingrod' and 1 or 500,remaining(id,'buy',entry) or 500)} end
        end
    end
    if modeAllowed(id,'sell') then
        for _,owned in pairs(exports.jrs_inventory:getUserInventoryItems(src) or {}) do
            if eligible(owned) then
                for i,entry in ipairs(Config.SellItems[id] or {}) do
                    if entry.itemName==owned.name and StoresShared.IsProductAllowed(entry) and categoryAllowed(id,entry.category) then
                        local p=price(entry,'sell',owned)
                        if p and p>0 then rows.sell[#rows.sell+1]={key='sell:'..i..':'..tostring(owned.id),name=entry.itemName,label=label(src,entry),desc=description(src,entry),category=entry.category,
                            price=p,currency=entry.currencyType=='gold' and 'gold' or 'cash',max=math.min(500,tonumber(owned.count) or 0,remaining(id,'sell',entry) or 500)} end
                    end
                end
            end
        end
    end
    local categories={}
    for _,row in ipairs(cfg.category or {}) do categories[#categories+1]={id=row.Type,label=row.label,desc=row.desc} end
    return {id=id,title=cfg.storeName,language=StoresShared.Language(src),categories=categories,buyEnabled=modeAllowed(id,'buy'),sellEnabled=modeAllowed(id,'sell'),
        money=tonumber(char.money) or 0,gold=tonumber(char.gold) or 0,products=rows}
end
local function release(src,id,token)
    local session=sessions[id]
    if session and session.src==src and (token==nil or session.token==token) then sessions[id]=nil;return true end
    return false
end
local function liveSession(src,id,token)
    local s=sessions[id]
    if not s or s.src~=src or s.token~=token or s.expires<GetGameTimer() or not available(src,id) then return false end
    local char=character(src)
    return char and tostring(char.charIdentifier)==s.charId
end
local function open(src,id)
    if not available(src,id) then return {ok=false,error='unavailable'} end
    local existing=sessions[id]
    if storeBusy[id] or existing and existing.expires>=GetGameTimer() and existing.src~=src then return {ok=false,error='StoreInUse'} end
    -- A player can hold one storefront at a time.
    for key,s in pairs(sessions) do if s.src==src then sessions[key]=nil end end
    sequence=sequence+1
    local token=sequence
    sessions[id]={src=src,token=token,charId=tostring(character(src).charIdentifier),expires=GetGameTimer()+45000,seen={}}
    local data=catalogue(src,id)
    if not liveSession(src,id,token) then release(src,id,token);return {ok=false,error='unavailable'} end
    return {ok=true,token=token,data=data}
end
local function log(src,char,entry,mode,qty,total)
    local gold=entry.currencyType=='gold'
    Core.NotifyRightTip(src,StoresShared.Text(src,mode=='buy' and 'youbought' or 'yousold')..qty..' '..label(src,entry)..StoresShared.Text(src,gold and 'fr' or 'frcash')..string.format('%.2f',total)..StoresShared.Text(src,gold and 'ofgold' or 'ofcash'),4000)
    if Config.UseWebhook then
        local cfg=Config.WebhookLanguage
        Core.AddWebhook(cfg.WebhookTitle,Config.WebhookURL or '',char.firstname..' '..char.lastname..' '..mode..' '..qty..' '..entry.itemName..' '..total,cfg.WebhookColor,cfg.WebhookName,cfg.WebhookLogo,cfg.WebhookLogo2,cfg.WebhookAvatar)
    end
end
local function grantFishingRod(src)
    local result=promise.new();local answered=false
    local function answer(ok)if not answered then answered=true;result:resolve(ok==true)end end
    local ok,returned=pcall(function()return exports.jrs_inventory:createWeaponOwned(src,'WEAPON_FISHINGROD',{}, {},answer,{sourceResource=GetCurrentResourceName()})end)
    if not ok or returned==false then answer(false) end
    return Citizen.Await(result)
end
local function trade(src,id,mode,request)
    local cfg,char=Config.Stores[id],character(src)
    local index,itemId
    if mode=='buy' then index=tonumber(request.key:match('^buy:(%d+)$'))
    else index,itemId=request.key:match('^sell:(%d+):(%d+)$');index=tonumber(index);itemId=tonumber(itemId) end
    local entry=(mode=='buy' and Config.BuyItems[id] or Config.SellItems[id] or {})[index or 0]
    local qty=quantity(request.quantity)
    if not entry or not StoresShared.IsProductAllowed(entry) or not categoryAllowed(id,entry.category) or not qty then return false,'invalid' end
    if not available(src,id) then return false,'unavailable' end
    local item
    if mode=='sell' then
        item=itemId and exports.jrs_inventory:getItemById(src,itemId)
        if not item or item.name~=entry.itemName or not eligible(item) or (tonumber(item.count) or 0)<qty then return false,'noManyQty' end
    end
    local unit=price(entry,mode,item)
    if not unit then return false,'invalid' end
    local total=cents(unit*qty)
    if mode=='sell' and total<=0 then return false,'invalid' end
    local left=remaining(id,mode,entry)
    if left and qty>left then return false,mode=='buy' and 'limitBuy' or 'limitSell' end
    local currency=entry.currencyType=='gold' and 1 or 0
    if mode=='buy' then
        if (currency==1 and char.gold or char.money)<total then return false,currency==1 and 'youdontgold' or 'youdontcash' end
        local rod=entry.equipment=='fishingrod'
        if rod then
            if qty~=1 or not exports.jrs_inventory:canCarryWeapons(src,1,nil,'WEAPON_FISHINGROD') then return false,'cantcarryitem' end
        elseif not exports.jrs_inventory:canCarryItem(src,entry.itemName,qty) then return false,'cantcarryitem' end
        local charged=true
        if total>0 then charged=char.removeCurrency(currency,total)end
        if charged==false then return false,currency==1 and 'youdontgold' or 'youdontcash' end
        local ok,granted=pcall(function()
            if rod then return grantFishingRod(src) end
            return exports.jrs_inventory:addItem(src,entry.itemName,qty)
        end)
        if not ok or granted~=true then if total>0 then char.addCurrency(currency,total)end;return false,'failed' end
    else
        if exports.jrs_inventory:subItemById(src,itemId,nil,nil,qty)~=true then return false,'noManyQty' end
        char.addCurrency(currency,total)
    end
    changeStock(id,mode,entry,qty)
    log(src,char,entry,mode,qty,total)
    return true
end
local function checkout(src,request)
    if type(request)~='table' or not liveSession(src,request.id,request.token) then return {ok=false,error='unavailable'} end
    local id,mode=request.id,request.mode
    if (mode~='buy' and mode~='sell') or not modeAllowed(id,mode) or type(request.items)~='table'
        or #request.items<1 or #request.items>50 or type(request.requestId)~='string' or #request.requestId>80 then return {ok=false,error='invalid'} end
    local session=sessions[id]
    if session.seen[request.requestId] then return {ok=false,error='invalid'} end
    if playerBusy[src] or storeBusy[id] then return {ok=false,error='StoreInUse'} end
    session.seen[request.requestId]=true;session.seenCount=(session.seenCount or 0)+1
    if session.seenCount>1000 then release(src,id,request.token);return {ok=false,error='unavailable'} end
    playerBusy[src],storeBusy[id]=true,true
    local successful,errors,keys={}, {}, {}
    local ok=pcall(function()
        for _,row in ipairs(request.items) do
            if not liveSession(src,id,request.token) then errors[#errors+1]='unavailable';break end
            if type(row)~='table' or type(row.key)~='string' or keys[row.key] then errors[#errors+1]='invalid'
            else
                keys[row.key]=true
                local done,err=trade(src,id,mode,row)
                if done then successful[#successful+1]=row.key else errors[#errors+1]=err end
            end
        end
    end)
    playerBusy[src],storeBusy[id]=nil,nil
    if not ok then errors[#errors+1]='failed';print('JRS stores: inventory transaction failed') end
    if errors[1] then notify(src,errors[1]) end
    if liveSession(src,id,request.token) then sessions[id].expires=GetGameTimer()+45000 end
    return {ok=true,successful=successful,errors=errors,data=liveSession(src,id,request.token) and catalogue(src,id) or nil}
end
Core.Callback.Register('jrs_stores:callback:openUI',function(src,cb,id)cb(open(src,id))end)
Core.Callback.Register('jrs_stores:callback:closeUI',function(src,cb,id,token)cb(release(src,id,token))end)
Core.Callback.Register('jrs_stores:callback:refreshUI',function(src,cb,id,token)
    if not liveSession(src,id,token) then return cb({ok=false,error='unavailable'}) end
    sessions[id].expires=GetGameTimer()+45000
    cb({ok=true,data=catalogue(src,id)})
end)
Core.Callback.Register('jrs_stores:callback:checkoutUI',function(src,cb,request)cb(checkout(src,request))end)
-- Keep the existing callback/event names for JRS integrations; prices stay server-owned.
Core.Callback.Register('jrs_stores:callback:canOpenStore',function(src,cb,id)cb(open(src,id).ok)end)
Core.Callback.Register('jrs_stores:callback:CloseStore',function(src,cb,id)cb(release(src,id))end)
local function legacyStock(id)
    local rows={}
    for _,mode in ipairs({'buy','sell'})do
        for _,entry in ipairs((mode=='buy' and Config.BuyItems[id] or Config.SellItems[id]) or {})do
            local amount=remaining(id,mode,entry)
            if amount~=nil then rows[#rows+1]={itemName=entry.itemName,amount=amount,type=mode}end
        end
    end
    return rows
end
Core.Callback.Register('jrs_stores:callback:ShopStock',function(src,cb,id)
    cb(available(src,id) and {shopStock=legacyStock(id)} or false)
end)
Core.Callback.Register('jrs_stores:callback:getShopStock',function(src,cb,id)
    if not available(src,id) then return cb(false)end
    local found={}
    for _,item in pairs(exports.jrs_inventory:getUserInventoryItems(src) or {})do
        if eligible(item) then
            for _,entry in ipairs(Config.SellItems[id] or {})do
                if entry.itemName==item.name and StoresShared.IsProductAllowed(entry)then found[item.name]=item;break end
            end
        end
    end
    if not next(found)then return cb(false)end
    cb({shopStocks=legacyStock(id),ItemsFound=found})
end)
local function legacyTrade(src,data,id,mode)
    local session=sessions[id]
    if type(data)~='table' or not session or session.src~=src then return end
    local rows={}
    for name,value in pairs(data) do
        if type(value)=='table' then
            for i,entry in ipairs((mode=='buy' and Config.BuyItems[id] or Config.SellItems[id]) or {}) do
                if entry.itemName==name then
                    local key=mode..':'..i
                    if mode=='sell' then key=key..':'..tostring(type(value.item)=='table' and value.item.id or 0) end
                    rows[#rows+1]={key=key,quantity=value.quantity};break
                end
            end
        end
    end
    sequence=sequence+1
    checkout(src,{id=id,token=session.token,mode=mode,items=rows,requestId='legacy:'..sequence})
end
RegisterServerEvent('jrs_stores:Client:buyItems',function(data,id)legacyTrade(source,data,id,'buy')end)
RegisterServerEvent('jrs_stores:Client:sellItems',function(data,id)legacyTrade(source,data,id,'sell')end)
AddEventHandler('onResourceStart',function(name)
    if name~=GetCurrentResourceName() then return end
    for id,cfg in pairs(Config.Stores) do
        if cfg.RandomPrices then
            for _,items in ipairs({Config.BuyItems[id] or {},Config.SellItems[id] or {}}) do
                for _,item in ipairs(items) do
                    if item.randomprice then
                        if item.buyprice~=nil then item.buyprice=item.randomprice end
                        if item.sellprice~=nil then item.sellprice=item.randomprice end
                    end
                end
            end
        end
        local positions=cfg.possibleLocations
        if cfg.useRandomLocation and positions and #positions.OpenMenu>0 and #positions.OpenMenu==#positions.Npcs then
            local index=math.random(1,#positions.OpenMenu);cfg.Blip.Pos=positions.OpenMenu[index];cfg.Npc.Pos=positions.Npcs[index]
        end
    end
end)
RegisterServerEvent('jrs_stores:GetRefreshedPrices',function()
    TriggerClientEvent('jrs_stores:RefreshStorePrices',source,{sell=Config.SellItems,buy=Config.BuyItems,stores=Config.Stores})
end)
AddEventHandler('playerDropped',function()
    local src=source;playerBusy[src]=nil
    for id,session in pairs(sessions) do if session.src==src then sessions[id]=nil end end
end)
-- Dedicated weapon stores no longer belong to this resource.
exports('GetShopLinkState',function()return nil end)
exports('IsWeaponShopRented',function()return false end)
