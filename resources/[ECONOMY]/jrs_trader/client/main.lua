-- jrs_trader | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local peds, blips = {}, {}

local function sound(kind)
    local s = Config.Sounds.enabled and Config.Sounds[kind]
    if s then PlaySoundFrontend(s.name, s.set, true, 0) end
end

local function result(r)
    if r and r.msg then JRS.Notify(r.msg) end
    sound(r and r.ok and 'success' or 'fail')
    return r and r.ok
end

---------------------------------------------------------------- shop
local openShop

local function tradeMenu(t, mode)
    local rows = JRS.Await('jrs_trader:data', t.traderid) or {}
    local elements = {}
    for _, r in ipairs(rows) do
        if mode == 'buy' then
            elements[#elements + 1] = { label = r.label, value = r.item, desc = L('item_line', r.buyprice, r.stock) }
        elseif r.owned > 0 then
            elements[#elements + 1] = { label = r.label, value = r.item, desc = L('sell_line', r.sellprice, r.owned) }
        end
    end
    if #elements == 0 then return JRS.Notify(L('nothing')) end

    JRS.OpenMenu('jrs_trader_' .. mode, t.tradername, L(mode == 'buy' and 'buy_sub' or 'sell_sub'), elements, function(el, menu)
        menu.close()
        local max = mode == 'buy' and Config.MaxBuyAmount or Config.MaxSellAmount
        local amount = JRS.Input(el.label, L('amount', max), true)
        if not amount then return tradeMenu(t, mode) end
        result(JRS.Await(mode == 'buy' and 'jrs_trader:buy' or 'jrs_trader:sell', t.traderid, el.value, math.floor(amount)))
        tradeMenu(t, mode)
    end, function() openShop(t) end)
end

openShop = function(t)
    JRS.OpenMenu('jrs_trader', t.tradername, '', {
        { label = L('buy'), value = 'buy', desc = L('buy_sub') },
        { label = L('sell'), value = 'sell', desc = L('sell_sub') },
    }, function(el, menu)
        menu.close()
        tradeMenu(t, el.value)
    end)
end

---------------------------------------------------------------- npcs + prompt
local function traders() return GlobalState.jrsTraders or {} end

local function refreshBlips()
    for _, b in pairs(blips) do RemoveBlip(b) end
    blips = {}
    for _, t in ipairs(traders()) do
        if t.showblip then
            blips[t.traderid] = JRS.Blip(vector3(t.x, t.y, t.z), Config.DefaultBlip.sprite, t.tradername, Config.DefaultBlip.scale)
        end
    end
end

local function despawn(id)
    if peds[id] and DoesEntityExist(peds[id].ped) then DeletePed(peds[id].ped) end
    peds[id] = nil
end

AddStateBagChangeHandler('jrsTraders', 'global', function()
    Wait(100)
    for id in pairs(peds) do despawn(id) end -- respawn with the new data
    refreshBlips()
end)

CreateThread(function()
    Wait(2000)
    refreshBlips()
    local prompts = JRS.Prompts()
    local talk = prompts:add(0x760A9C6F, LE('prompt'))
    while true do
        local wait = 1000
        local pos = GetEntityCoords(PlayerPedId())
        for _, t in ipairs(traders()) do
            local c = vector3(t.x, t.y, t.z)
            local dist = #(pos - c)
            if dist < Config.DistanceSpawn then
                if not peds[t.traderid] and JRS.LoadModel(t.npcmodel) then
                    local ped = CreatePed(joaat(t.npcmodel), t.x, t.y, t.z - 1.0, t.heading, false, false, false, false)
                    SetModelAsNoLongerNeeded(joaat(t.npcmodel))
                    SetRandomOutfitVariation(ped, true)
                    SetEntityInvincible(ped, true)
                    SetEntityCanBeDamaged(ped, false)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    peds[t.traderid] = { ped = ped }
                end
                if dist < Config.UseDistance then
                    wait = 0
                    prompts:show(t.tradername)
                    if prompts:done(talk) then openShop(t) end
                end
            elseif peds[t.traderid] then
                despawn(t.traderid)
            end
        end
        Wait(wait)
    end
end)

---------------------------------------------------------------- admin (/traderadmin)
local adminMain

local function itemMenu(t, it)
    JRS.OpenMenu('jrs_trader_item', it.label, t.tradername, {
        { label = L('i_stock'), value = 'stock', desc = tostring(it.stock) },
        { label = L('i_price'), value = 'baseprice', desc = ('$%.2f'):format(it.baseprice) },
        { label = L('i_low'), value = 'lowstock', desc = tostring(it.lowstock) },
        { label = L('i_high'), value = 'highstock', desc = tostring(it.highstock) },
        { label = L('i_remove'), value = 'remove', desc = '' },
    }, function(el, menu)
        menu.close()
        local value
        if el.value ~= 'remove' then
            value = JRS.Input(el.label, el.desc, true)
            if not value then return itemMenu(t, it) end
        end
        result(JRS.Await('jrs_trader:admin:setItem', t.traderid, it.item, el.value, value))
        adminMain()
    end)
end

local function traderMenu(t)
    local items = JRS.Await('jrs_trader:admin:items', t.traderid) or {}
    local elements = {
        { label = L('t_add_item'), value = '__add', desc = '' },
        { label = L('t_move'), value = '__move', desc = '' },
        { label = L('t_blip'), value = '__blip', desc = t.showblip and 'ON' or 'OFF' },
        { label = L('t_rename'), value = '__rename', desc = '' },
        { label = L('t_delete'), value = '__delete', desc = '' },
    }
    for _, it in ipairs(items) do
        elements[#elements + 1] = { label = it.label, value = it.item, desc = L('item_line', it.baseprice, it.stock), data = it }
    end
    JRS.OpenMenu('jrs_trader_admin_t', t.tradername, L('t_items'), elements, function(el, menu)
        menu.close()
        if el.value == '__add' then
            local item = JRS.Input(L('t_add_item'), L('item_prompt'))
            if not item then return traderMenu(t) end
            local price = JRS.Input(L('price_prompt'), '1.00', true)
            if not price then return traderMenu(t) end
            result(JRS.Await('jrs_trader:admin:addItem', t.traderid, item, price))
            return traderMenu(t)
        elseif el.value == '__move' or el.value == '__blip' or el.value == '__delete' then
            result(JRS.Await('jrs_trader:admin:edit', t.traderid, el.value:sub(3)))
            return adminMain()
        elseif el.value == '__rename' then
            local name = JRS.Input(L('t_rename'), t.tradername)
            if name then result(JRS.Await('jrs_trader:admin:edit', t.traderid, 'rename', name)) end
            return adminMain()
        end
        if el.data then itemMenu(t, el.data) end
    end, function() adminMain() end)
end

adminMain = function()
    local list = JRS.Await('jrs_trader:admin:list')
    if not list then return JRS.Notify(L('no_permission')) end
    local elements = { { label = L('admin_new'), value = '__new', desc = '' } }
    for _, t in ipairs(list) do
        elements[#elements + 1] = { label = t.tradername, value = t.traderid, desc = t.traderid, data = t }
    end
    JRS.OpenMenu('jrs_trader_admin', L('admin_title'), L('admin_sub'), elements, function(el, menu)
        menu.close()
        if el.value == '__new' then
            local name = JRS.Input(L('admin_new'), L('name_prompt'))
            if not name then return adminMain() end
            local model = JRS.Input(L('model_prompt'), Config.DefaultModel) or ''
            result(JRS.Await('jrs_trader:admin:create', name, model))
            return adminMain()
        end
        for _, t in ipairs(traders()) do
            if t.traderid == el.value then return traderMenu(t) end
        end
    end)
end

RegisterNetEvent('jrs_trader:client:admin', adminMain)
TriggerEvent('chat:addSuggestion', '/traderadmin', L('cmd_help'))

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(peds) do despawn(id) end
    for _, b in pairs(blips) do RemoveBlip(b) end
end)
