-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | server: birds
-- Shop, hunting rewards and player to player bird sales. A hunt reward is only accepted when it matches
-- something in the config and follows a real hunt the server started.

-- ------------------------------------------------------------------ what a hunt may pay

local scavenge = {}             -- item name -> config row
for _, item in pairs(Config.ScavengerItems) do scavenge[item.name] = item end

local allowedXp = {}            -- every xp value a hunt can legitimately report
local function allow(xp) if xp and xp > 0 then allowedXp[xp] = true end end

for _, item in pairs(Config.ScavengerItems) do allow(item.xp) end
for _, item in pairs(Config.FishItems) do allow(item.xp) end
for _, areas in ipairs({ Config.Areas, Config.Districts, Config.Districts2 }) do
    for _, area in pairs(areas) do
        for _, prey in pairs(type(area[5]) == 'table' and area[5] or {}) do allow(prey.xp) end
    end
end

-- a hunt starts at checkhunt; each reward kind can be claimed once, inside a time window
local hunts = {}                -- source -> { t, xp, item }
local WINDOW = (Config.BirdGoForHuntTimer or 0) + (Config.HuntingTimer or 0) + 15
local MIN_TIME = math.max(5, math.floor(((Config.BirdGoForHuntTimer or 0) + (Config.HuntingTimer or 0)) * 0.5))

local function beginHunt(src)
    local h = hunts[src]
    if h and os.time() - h.t < MIN_TIME then return false end
    hunts[src] = { t = os.time(), xp = true, item = true }
    return true
end

local function claimHunt(src, kind)
    local h = hunts[src]
    if not h then return false end
    local age = os.time() - h.t
    if age > WINDOW or age < MIN_TIME or not h[kind] then return false end
    h[kind] = false
    return true
end

local function hasJob(me, jobs)
    for _, job in pairs(jobs or {}) do
        if me.job == job then return true end
    end
    return false
end

-- ------------------------------------------------------------------ shop

local function variantFor(model, preset)
    local wantModel, wantPreset = tonumber(model), tonumber(preset) or 0
    for _, category in ipairs(Config.Birds) do
        for _, variant in ipairs(category.variants) do
            if tonumber(variant.model) == wantModel and variant.preset == wantPreset then return variant end
        end
    end
end

RegisterServerEvent('jrs_huntingpets:server:buyBird', function(model, preset)
    local src = source
    local me = Pets.who(src)
    if not me then return end

    local bird = variantFor(model, preset)
    if not bird then return Pets.sayKey(src, 'notif_not_for_sale_bird', 'error') end
    if me.player.PlayerData.money.cash < bird.price then return Pets.sayKey(src, 'notif_not_enough_money', 'error') end
    if not me.player.Functions.RemoveMoney('cash', bird.price) then return end

    MySQL.insert('INSERT INTO player_birds (identifier, charid, model, preset, xp, price) VALUES (?, ?, ?, ?, 0, ?)',
        { me.cid, me.charid, tostring(bird.model), bird.preset, bird.price })
    Pets.sayKey(src, 'notif_bird_purchased', 'success')
end)

RegisterServerEvent('jrs_huntingpets:server:sellBird', function(id)
    local src = source
    local me = Pets.who(src)
    local row = me and Pets.owned('player_birds', id, me)
    if not row then return end

    local refund = Pets.sellBack('player_birds', row, me)
    if not refund then return end
    TriggerClientEvent('jrs_huntingpets:client:birdSold', src)
    Pets.sayKey(src, 'notif_bird_sold', 'success', refund)
end)

local function sendBird(src, row)
    TriggerClientEvent('jrs_huntingpets:client:spawnBird', src, row.id, tonumber(row.model), row.preset, row.xp)
end

RegisterServerEvent('jrs_huntingpets:server:callBird', function(id)
    local src = source
    local me = Pets.who(src)
    if not me then return end
    local row = Pets.owned('player_birds', id, me)
    if row then sendBird(src, row) else Pets.sayKey(src, 'notif_no_bird_found', 'error') end
end)

RegisterServerEvent('jrs_huntingpets:server:loadBird', function()
    local src = source
    local me = Pets.who(src)
    if not me then return end

    local id = Pets.selection(me).selected_bird
    if not id then return Pets.sayKey(src, 'notif_no_bird_selected', 'error') end

    local row = Pets.owned('player_birds', id, me)
    if row then return sendBird(src, row) end
    Pets.sayKey(src, 'notif_bird_no_longer_exists', 'error')
    Pets.clearSelection('selected_bird', me)
end)

-- ------------------------------------------------------------------ hunting

RegisterServerEvent('jrs_huntingpets:checkhunt', function()
    local src = source
    if Config.Hunting.jobrequired then
        local me = Pets.who(src)
        if not me then return end
        if not hasJob(me, Config.Hunting.jobs) then
            return Pets.say(src, L('notif_title_hunting_birds'), Config.Texts.NoJob, 'error')
        end
    end
    if beginHunt(src) then TriggerClientEvent('jrs_huntingpets:starthunt', src) end
end)

RegisterServerEvent('jrs_huntingpets:addxp', function(xp, id)
    local src = source
    local me = Pets.who(src)
    xp, id = tonumber(xp), tonumber(id)
    if not me or not xp or not id then return end
    if not allowedXp[xp] or not claimHunt(src, 'xp') then return end

    if Config.Hunting.extra_XP and hasJob(me, Config.Hunting.jobs) then xp = xp + Config.Hunting.extra_XP end

    local row = MySQL.query.await('SELECT xp FROM player_birds WHERE id = ? AND identifier = ? AND charid = ?', { id, me.cid, me.charid })
    if row and row[1] then
        MySQL.execute('UPDATE player_birds SET xp = ? WHERE id = ?', { math.min(row[1].xp + xp, Config.MaxBirdXP), id })
    end
end)

-- the item and the amount are the configured ones, whatever the client sends
RegisterServerEvent('jrs_huntingpets:addscavengeditem', function(name)
    local src = source
    local me = Pets.who(src)
    local item = me and scavenge[tostring(name)]
    if not item or not claimHunt(src, 'item') then return end
    if not me.player.Functions.AddItem(item.name, item.amount) then return end
    Pets.say(src, L('notif_title_hunting_birds'), Config.Texts.FoundScavItem, 'success')
end)

RegisterServerEvent('jrs_huntingpets:check_sell', function()
    local src = source
    local me = Pets.who(src)
    if not me then return end
    if not Config.SellingBirdJob or hasJob(me, Config.SellingBirdJob) then
        TriggerClientEvent('jrs_huntingpets:start_sell', src)
    else
        Pets.say(src, Config.Texts.Bird, Config.Texts.NoJob, 'error')
    end
end)

-- ------------------------------------------------------------------ player to player sales

local listings = {}             -- bird id -> the bird row plus sellprice, owner, sellcoords, pedid

local function tellPoints(listing, id, ped) TriggerClientEvent('jrs_huntingpets:sell:updatepoints', -1, listing, id, ped) end

AddEventHandler('playerDropped', function()
    local src = source
    hunts[src] = nil
    for id, l in pairs(listings) do
        if l.owner == src then
            tellPoints(nil, id, tonumber(l.pedid))
            listings[id] = nil
        end
    end
end)

RegisterServerEvent('jrs_huntingpets:sell:create', function(id, price, _, _, pedId)
    local src = source
    local me = Pets.who(src)
    id, price = tonumber(id), math.floor(tonumber(price) or 0)
    if not me or not id or price < 1 or price > 1000000 then return end
    if listings[id] and listings[id].owner ~= src then return end
    if Config.SellingBirdJob and not hasJob(me, Config.SellingBirdJob) then return end

    local row = Pets.owned('player_birds', id, me)
    if not row then return end

    row.identifier, row.charid = nil, nil
    row.sellprice, row.owner, row.owner_cid, row.owner_charid = price, src, me.cid, me.charid
    row.sellcoords, row.pedid = GetEntityCoords(GetPlayerPed(src)), tonumber(pedId)
    listings[id] = row
    tellPoints(row, id, nil)
end)

RegisterServerEvent('jrs_huntingpets:sell:stop', function(id)
    id = tonumber(id)
    local l = listings[id]
    if not l or l.owner ~= source then return end
    listings[id] = nil
    TriggerClientEvent('jrs_huntingpets:sell:updatepoints1', -1, id)
end)

RegisterServerEvent('jrs_huntingpets:sell:getpoints', function()
    TriggerClientEvent('jrs_huntingpets:sell:gotpoints_c', source, listings)
end)

-- the price and the seller come from the listing the server stored, never from the buyer's parameters
RegisterServerEvent('jrs_huntingpets:sell:buyoffer', function(_, _, listingId)
    local src = source
    local me = Pets.who(src)
    local id = tonumber(listingId)
    local l = me and listings[id]
    if not l then return end

    local seller, price = l.owner, tonumber(l.sellprice) or 0
    if seller == src or price < 1 then return end
    local at = l.sellcoords
    if not at or #(GetEntityCoords(GetPlayerPed(src)) - vector3(at.x, at.y, at.z)) > 10.0 then return end

    local owner = JRS.Player(seller)
    if not owner then
        Pets.say(src, Config.Texts.PlayerBuyBird, L('notif_no_bird_found'), 'error')
        listings[id] = nil
        return tellPoints(nil, id, tonumber(l.pedid))
    end

    if me.player.PlayerData.money.cash < price then
        Pets.say(src, Config.Texts.PlayerBuyBird, Config.Texts.PlayerBuyNoMoney, 'error')
        return Pets.say(seller, Config.Texts.PlayerBuyBird, Config.Texts.PlayerBuyNoMoneyAtBuyer, 'error')
    end

    -- the listing is taken first, so two buyers (or a sale to the shop) cannot both win
    listings[id] = nil
    if not me.player.Functions.RemoveMoney('cash', price) then return end

    local removed = MySQL.update.await('DELETE FROM player_birds WHERE id = ? AND identifier = ? AND charid = ?', { id, l.owner_cid, l.owner_charid })
    if not removed or removed < 1 then
        me.player.Functions.AddMoney('cash', price)
        return tellPoints(nil, id, tonumber(l.pedid))
    end
    owner.Functions.AddMoney('cash', price)

    MySQL.insert('INSERT INTO player_birds (identifier, charid, model, preset, xp, price) VALUES (?, ?, ?, ?, ?, ?)',
        { me.cid, me.charid, tostring(l.model), l.preset, l.xp, l.price or 0 })

    TriggerClientEvent('jrs_huntingpets:sell:finishsell', seller)
    tellPoints(nil, id, tonumber(l.pedid))
    Pets.say(src, Config.Texts.PlayerBuyBird, Config.Texts.PlayerBoughtBird, 'success')
    Pets.say(seller, Config.Texts.PlayerBuyBird, Config.Texts.PlayerSoldBird, 'success')
end)
