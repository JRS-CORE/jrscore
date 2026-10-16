-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | server: dogs
-- Prices and models come from the config, never from the client. A dog is a row in `player_dogs`;
-- the one the player picked is kept in `player_selected_pets`.

-- what the shop window shows: every pet of the character and which are selected
JRS.CreateCallback('jrs_huntingpets:server:getShopData', function(src, reply)
    local me = Pets.who(src)
    if not me then return reply(nil) end

    local args = { me.cid, me.charid }
    local pick = Pets.selection(me)
    reply({
        ownedDogs = MySQL.query.await('SELECT * FROM player_dogs WHERE identifier = ? AND charid = ?', args) or {},
        ownedBirds = MySQL.query.await('SELECT * FROM player_birds WHERE identifier = ? AND charid = ?', args) or {},
        selectedDog = pick.selected_dog,
        selectedBird = pick.selected_bird,
    })
end)

local function breed(model)
    for _, dog in ipairs(Config.Dogs) do
        if dog.Param.Model == model then return dog end
    end
end

RegisterServerEvent('jrs_huntingpets:server:buyDog', function(model)
    local src = source
    local me = Pets.who(src)
    if not me then return end

    local dog = breed(model)
    if not dog then return Pets.sayKey(src, 'notif_not_for_sale_dog', 'error') end

    local price = dog.Param.Price
    if me.player.PlayerData.money.cash < price then return Pets.sayKey(src, 'notif_not_enough_money', 'error') end
    if not me.player.Functions.RemoveMoney('cash', price) then return end

    MySQL.insert('INSERT INTO player_dogs (identifier, charid, model, preset, xp, price) VALUES (?, ?, ?, ?, 0, ?)',
        { me.cid, me.charid, dog.Param.Model, math.random(0, 2), price })
    Pets.sayKey(src, 'notif_dog_purchased', 'success')
end)

RegisterServerEvent('jrs_huntingpets:server:sellDog', function(id)
    local src = source
    local me = Pets.who(src)
    local row = me and Pets.owned('player_dogs', id, me)
    if not row then return end

    local refund = Pets.sellBack('player_dogs', row, me)
    if not refund then return end
    TriggerClientEvent('jrs_huntingpets:client:putawayDog', src)
    Pets.sayKey(src, 'notif_dog_sold', 'success', refund)
end)

local function sendDog(src, row)
    TriggerClientEvent('jrs_huntingpets:client:spawnDog', src, row.id, row.model, row.preset, false, row.xp)
end

-- a dog picked in the shop
RegisterServerEvent('jrs_huntingpets:server:callDog', function(id)
    local src = source
    local me = Pets.who(src)
    if not me then return end
    local row = Pets.owned('player_dogs', id, me)
    if row then sendDog(src, row) else Pets.sayKey(src, 'notif_no_dog_found', 'error') end
end)

-- /calldog: the dog the player selected
RegisterServerEvent('jrs_huntingpets:server:loadDog', function()
    local src = source
    local me = Pets.who(src)
    if not me then return end

    local id = Pets.selection(me).selected_dog
    if not id then return Pets.sayKey(src, 'notif_no_dog_selected', 'error') end

    local row = Pets.owned('player_dogs', id, me)
    if row then return sendDog(src, row) end
    Pets.sayKey(src, 'notif_dog_no_longer_exists', 'error')
    Pets.clearSelection('selected_dog', me)
end)

-- feeding raises the dog's xp up to full grown; the xp is read from the database, not from the client
RegisterServerEvent('jrs_huntingpets:server:feedDog', function(id)
    local src = source
    local me = Pets.who(src)
    if not me then return end

    if not me.player.Functions.GetItemByName(Config.AnimalFood) then return Pets.sayKey(src, 'notif_no_food', 'error') end
    local row = Pets.owned('player_dogs', id, me)
    if not row then return Pets.sayKey(src, 'notif_dog_not_yours', 'error') end
    if not me.player.Functions.RemoveItem(Config.AnimalFood, 1) then return end

    local xp = math.min(row.xp + Config.DogXpPerFeed, Config.DogFullGrownXp)
    MySQL.execute('UPDATE player_dogs SET xp = ? WHERE id = ?', { xp, id })
    TriggerClientEvent('jrs_huntingpets:client:dogFed', src, xp)
    Pets.sayKey(src, 'notif_pet_fed', 'inform', xp, Config.DogFullGrownXp)
end)

-- a callback, so the window only shows "selected" once the server has saved it
JRS.CreateCallback('jrs_huntingpets:server:selectDog', function(src, reply, id)
    local me = Pets.who(src)
    if not me or not Pets.owned('player_dogs', id, me) then return reply(false) end
    Pets.select('selected_dog', id, me)
    Pets.sayKey(src, 'notif_dog_selected', 'success')
    reply(true)
end)

JRS.CreateCallback('jrs_huntingpets:server:selectBird', function(src, reply, id)
    local me = Pets.who(src)
    if not me or not Pets.owned('player_birds', id, me) then return reply(false) end
    Pets.select('selected_bird', id, me)
    Pets.sayKey(src, 'notif_bird_selected', 'success')
    reply(true)
end)

-- the care values shown in the "My pets" panel
JRS.CreateCallback('jrs_huntingpets:server:getPetData', function(_, reply)
    reply({ health = 100, hungry = 100, thirst = 100, followDistance = 5, leftRightDistance = 0 })
end)
