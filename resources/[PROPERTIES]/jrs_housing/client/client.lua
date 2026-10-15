-- JRS housing (client): entrance prompt + house menu, storage / wardrobe
-- prompts for owners and key holders, map blips.
local State = {}        -- [index] = { owned, owner, ownerName, keys = { charid, ... } }
local Entrances = {}    -- [index] = vector3
local Blips = {}        -- [index] = blip
local myCharId = nil

local function notify(text) if text and text ~= '' then JRS.Notify(text, 5000) end end
RegisterNetEvent('jrs_housing:notify', function(text, ms) JRS.Notify(text, ms or 5000) end)

-- JRS.Me() is cached for 5 s by the kit, so a character switch is picked up
local function charId()
    local me = JRS.Me()
    myCharId = me and tonumber(me.charIdentifier) or myCharId
    return myCharId
end

local function access(index)
    local st = State[index]
    if not st or not st.owned then return nil end
    local cid = charId()
    if not cid then return nil end
    if tonumber(st.owner) == cid then return 'owner' end
    for _, k in ipairs(st.keys or {}) do if tonumber(k) == cid then return 'key' end end
    return nil
end

-- ─── blips ─────────────────────────────────────────────────────────────────
local function removeBlip(index)
    if Blips[index] then RemoveBlip(Blips[index]) Blips[index] = nil end
end

local function refreshBlip(index)
    removeBlip(index)
    local house, st = Config.Houses[index], State[index]
    if not house or not st then return end
    local lvl = access(index)
    local cfg, name
    if not st.owned and Config.Blips.forSale.show then
        cfg, name = Config.Blips.forSale, LE('blip_sale')
    elseif lvl and Config.Blips.owned.show then
        cfg, name = Config.Blips.owned, lvl == 'owner' and LE('blip_owned') or LE('blip_key')
    end
    if not cfg then return end
    local p = house.position
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, p.x, p.y, p.z) -- BlipAddForCoords
    SetBlipSprite(blip, cfg.sprite, true)
    SetBlipScale(blip, cfg.scale or 0.2)
    Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(cfg.modifier))            -- BlipAddModifier
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, ('%s - %s'):format(name, house.label)) -- SetBlipName
    Blips[index] = blip
end

local function refreshAll()
    for index in ipairs(Config.Houses) do refreshBlip(index) end
end

local function load()
    local list, entrances = JRS.Await('jrs_housing:state')
    if type(list) ~= 'table' then return false end
    for index in ipairs(Config.Houses) do
        State[index] = list[index] or { owned = false }
        local e = entrances and entrances[index]
        Entrances[index] = e and vector3(e.x, e.y, e.z) or Config.Houses[index].position
    end
    refreshAll()
    return true
end

RegisterNetEvent('jrs_housing:client:update', function(index, st)
    if not Config.Houses[index] then return end
    State[index] = st or { owned = false }
    refreshBlip(index)
end)

-- ─── menus ─────────────────────────────────────────────────────────────────
local OpenHouseMenu

local function closestPlayer()
    local pid = JRS.ClosestPlayer(Config.GiveKeyDistance)
    return pid and GetPlayerServerId(pid) or nil
end

local function openKeys(index)
    local list = JRS.Await('jrs_housing:keys', index) or {}
    local elements = {}
    for _, k in ipairs(list) do
        elements[#elements + 1] = { label = L('take_key', k.name), value = k.charId, desc = L('keys_desc') }
    end
    if #elements == 0 then elements[1] = { label = L('no_keys'), value = 'none', disabled = true, desc = '' } end
    JRS.OpenMenu('jrs_housing_keys', Config.Houses[index].label, L('keys', #list, Config.MaxKeys), elements, function(el, menu)
        if el.value == 'none' then return end
        menu.close()
        local ok, msg = JRS.Await('jrs_housing:takeKey', index, el.value)
        notify(msg)
        if ok then openKeys(index) end
    end, function() OpenHouseMenu(index) end)
end

OpenHouseMenu = function(index)
    local house, st = Config.Houses[index], State[index] or {}
    local lvl = access(index)
    local info = L('info', #(house.storages or {}), house.wardrobe and L('yes') or L('no'), #(house.doors or {}))
    local elements, sub = {}, nil

    if not st.owned then
        sub = L('for_sale')
        elements[#elements + 1] = { label = L('buy'), value = 'buy', rightLabel = '$' .. house.price, desc = L('buy_desc', house.price) .. '<br>' .. info }
    elseif lvl == 'owner' then
        sub = L('my_house')
        elements[#elements + 1] = { label = L('give_key'), value = 'give', desc = info }
        elements[#elements + 1] = { label = L('keys', #(st.keys or {}), Config.MaxKeys), value = 'keys', desc = L('keys_desc') }
        local refund = math.floor(house.price * (Config.SellBackPercent / 100))
        elements[#elements + 1] = { label = L('sell'), value = 'sell', rightLabel = '$' .. refund, desc = L('sell_desc', refund) }
    else
        sub = L('owned_by', st.ownerName or '?')
        elements[#elements + 1] = { label = sub, value = 'info', disabled = true, desc = info }
    end
    elements[#elements + 1] = { label = L('close'), value = 'close', desc = '' }

    JRS.OpenMenu('jrs_housing', house.label, sub, elements, function(el, menu)
        if el.value == 'close' or el.value == 'info' then return menu.close() end
        if el.value == 'buy' then
            menu.close()
            local ok, msg = JRS.Await('jrs_housing:buy', index)
            notify(msg)
            if ok then OpenHouseMenu(index) end
        elseif el.value == 'give' then
            local target = closestPlayer()
            if not target then return notify(L('no_player')) end
            local _, msg = JRS.Await('jrs_housing:giveKey', index, target)
            notify(msg)
            menu.close()
            OpenHouseMenu(index)
        elseif el.value == 'keys' then
            menu.close()
            openKeys(index)
        elseif el.value == 'sell' then
            menu.close()
            local refund = math.floor(house.price * (Config.SellBackPercent / 100))
            if JRS.Confirm({ header = house.label, content = L('sell_confirm', refund),
                labels = { confirm = L('confirm'), cancel = L('cancel') } }) == 'confirm' then
                local _, msg = JRS.Await('jrs_housing:sell', index)
                notify(msg)
            end
        end
    end)
end

-- ─── prompts ───────────────────────────────────────────────────────────────
CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(1000) end
    while not load() do Wait(5000) end

    local prompts = JRS.Prompts()
    local pView = prompts:add(Config.InteractKey, LE('view_house'))
    local pStorage = prompts:add(Config.InteractKey, LE('storage'))
    local pWardrobe = prompts:add(Config.InteractKey, LE('wardrobe'))

    AddEventHandler('onResourceStop', function(res)
        if res ~= GetCurrentResourceName() then return end
        prompts:delete()
        for index in pairs(Blips) do removeBlip(index) end
    end)

    while true do
        local wait = 1000
        local ped = PlayerPedId()
        if not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) then
            local pos = GetEntityCoords(ped)
            for index, house in ipairs(Config.Houses) do
                local near = #(pos - house.position)
                if near < 40.0 then
                    wait = math.min(wait, 250)
                    local lvl = access(index)
                    local action, title, arg

                    if #(pos - Entrances[index]) <= Config.EntranceDistance then
                        action, title = pView, house.label
                    elseif lvl then
                        for s, st in ipairs(house.storages or {}) do
                            if #(pos - st.coords) <= Config.SpotDistance then
                                action, title, arg = pStorage, st.label, s
                                break
                            end
                        end
                        if not action and house.wardrobe and #(pos - house.wardrobe) <= Config.SpotDistance then
                            action, title = pWardrobe, house.label
                        end
                    end

                    if action then
                        wait = 0
                        prompts:visible(pView, action == pView)
                        prompts:visible(pStorage, action == pStorage)
                        prompts:visible(pWardrobe, action == pWardrobe)
                        prompts:show(title)
                        if prompts:done(action) then
                            if action == pView then
                                OpenHouseMenu(index)
                            elseif action == pStorage then
                                TriggerServerEvent('jrs_housing:server:openStorage', index, arg)
                            else
                                TriggerServerEvent('jrs_housing:server:openWardrobe', index)
                            end
                            Wait(800)
                        end
                        break
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- redraw the owner blips now and then (character switch, keys given offline)
CreateThread(function()
    while true do
        Wait(60000)
        if next(State) then refreshAll() end
    end
end)
