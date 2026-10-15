local Traders = {}      -- traderid -> row
local cooldowns = {}
local round2 = Config.Round2

local function res(ok, msg) return { ok = ok, msg = msg } end

local function itemExists(item)
    return exports.jrs_inventory:getItemDB(item) ~= nil
end

local function sync()
    local list = {}
    for _, t in pairs(Traders) do list[#list + 1] = t end
    GlobalState.jrsTraders = list
end

local function loadTraders()
    Traders = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM jrs_trader_npcs') or {}) do
        r.showblip = r.showblip == 1 or r.showblip == true
        Traders[r.traderid] = r
    end
    sync()
end

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jrs_trader_npcs` (
        `traderid` VARCHAR(50) NOT NULL, `tradername` VARCHAR(50) NOT NULL, `npcmodel` VARCHAR(60) NOT NULL,
        `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `heading` DOUBLE NOT NULL DEFAULT 0,
        `showblip` TINYINT(1) NOT NULL DEFAULT 1, PRIMARY KEY (`traderid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jrs_trader` (
        `id` INT(11) NOT NULL AUTO_INCREMENT, `traderid` VARCHAR(50) NOT NULL, `item` VARCHAR(50) NOT NULL,
        `stock` INT(11) NOT NULL DEFAULT 0, `lowstock` INT(11) NOT NULL DEFAULT 0, `highstock` INT(11) NOT NULL DEFAULT 0,
        `baseprice` DECIMAL(11,2) NOT NULL DEFAULT 0.00, PRIMARY KEY (`id`), UNIQUE KEY `trader_item` (`traderid`, `item`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if (MySQL.scalar.await('SELECT COUNT(*) FROM jrs_trader_npcs') or 0) == 0 then
        for _, t in ipairs(Config.DefaultTraders) do
            MySQL.insert.await('INSERT IGNORE INTO jrs_trader_npcs (traderid, tradername, npcmodel, x, y, z, heading, showblip) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
                { t.traderid, t.tradername, Config.DefaultModel, t.coords.x, t.coords.y, t.coords.z, t.coords.w })
        end
        for _, i in ipairs(Config.DefaultItems) do
            MySQL.insert.await('INSERT IGNORE INTO jrs_trader (traderid, item, stock, lowstock, highstock, baseprice) VALUES (?, ?, ?, ?, ?, ?)',
                { i.traderid, i.item, i.stock, i.lowstock, i.highstock, i.baseprice })
        end
    end
    loadTraders()
end)

local function toInt(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if (min and v < min) or (max and v > max) then return nil end
    return v
end

local function trim(s)
    return type(s) == 'string' and (s:gsub('^%s+', ''):gsub('%s+$', '')) or nil
end

local function onCooldown(src)
    local now = GetGameTimer()
    if cooldowns[src] and now - cooldowns[src] < Config.Cooldown then return true end
    cooldowns[src] = now
    return false
end

local function nearTrader(src, t)
    return JRS.Near(src, vector3(t.x, t.y, t.z), Config.InteractDistance)
end

-- returns trader, row, qty or nil, message
local function validateTrade(src, traderid, item, amount, max)
    if not JRS.Char(src) or type(traderid) ~= 'string' or type(item) ~= 'string' then return nil, L('invalid_trade') end
    local trader = Traders[traderid]
    local qty = toInt(amount, 1, max)
    if not trader or not qty or not itemExists(item) then return nil, L('invalid_trade') end
    if not nearTrader(src, trader) then return nil, L('too_far') end
    if onCooldown(src) then return nil, L('cooldown') end
    local row = MySQL.single.await('SELECT * FROM jrs_trader WHERE traderid = ? AND item = ?', { traderid, item })
    if not row then return nil, L('invalid_trade') end
    return trader, row, qty
end

---------------------------------------------------------------- shop
JRS.Callback('jrs_trader:data', function(src, traderid)
    if not Traders[traderid] then return {} end
    local list = {}
    for _, r in ipairs(MySQL.query.await('SELECT item, stock, lowstock, highstock, baseprice FROM jrs_trader WHERE traderid = ? ORDER BY item', { traderid }) or {}) do
        if itemExists(r.item) then
            r.label = JRS.ItemLabel(r.item)
            r.buyprice = Config.GetBuyPrice(r.stock, r.lowstock, r.highstock, r.baseprice)
            r.sellprice = Config.GetSellPrice(r.stock, r.lowstock, r.highstock, r.baseprice)
            r.owned = JRS.Count(src, r.item)
            list[#list + 1] = r
        end
    end
    return list
end)

JRS.Callback('jrs_trader:buy', function(src, traderid, item, amount)
    local trader, row, qty = validateTrade(src, traderid, item, amount, Config.MaxBuyAmount)
    if not trader then return res(false, row) end
    if row.stock < qty then return res(false, L('not_enough_stock', row.stock)) end
    local total = round2(Config.GetBuyPrice(row.stock, row.lowstock, row.highstock, row.baseprice) * qty)
    if JRS.Money(src) < total then return res(false, L('not_enough_money')) end
    if not JRS.CanCarry(src, item, qty) then return res(false, L('inventory_full')) end

    -- reserve stock atomically (two players cannot buy the same units)
    local affected = MySQL.update.await('UPDATE jrs_trader SET stock = stock - ? WHERE traderid = ? AND item = ? AND stock >= ?', { qty, traderid, item, qty })
    if not affected or affected < 1 then return res(false, L('stock_changed')) end
    if not JRS.TakeMoney(src, total) then
        MySQL.update('UPDATE jrs_trader SET stock = stock + ? WHERE traderid = ? AND item = ?', { qty, traderid, item })
        return res(false, L('not_enough_money'))
    end
    if not exports.jrs_inventory:addItem(src, item, qty) then
        JRS.GiveMoney(src, total)
        MySQL.update('UPDATE jrs_trader SET stock = stock + ? WHERE traderid = ? AND item = ?', { qty, traderid, item })
        return res(false, L('inventory_full'))
    end
    return res(true, L('bought', qty, JRS.ItemLabel(item), ('%.2f'):format(total)))
end)

JRS.Callback('jrs_trader:sell', function(src, traderid, item, amount)
    local trader, row, qty = validateTrade(src, traderid, item, amount, Config.MaxSellAmount)
    if not trader then return res(false, row) end
    local total = round2(Config.GetSellPrice(row.stock, row.lowstock, row.highstock, row.baseprice) * qty)
    if not JRS.Has(src, item, qty) or not JRS.Remove(src, item, qty) then return res(false, L('not_enough_items')) end
    JRS.GiveMoney(src, total)
    MySQL.update.await('UPDATE jrs_trader SET stock = stock + ? WHERE traderid = ? AND item = ?', { qty, traderid, item })
    return res(true, L('sold', qty, JRS.ItemLabel(item), ('%.2f'):format(total)))
end)

---------------------------------------------------------------- admin
local function admin(src) return JRS.Char(src) ~= nil and JRS.IsAdmin(src) end

RegisterCommand('traderadmin', function(src)
    if src > 0 and admin(src) then TriggerClientEvent('jrs_trader:client:admin', src) end
end, false)

local function makeId(name)
    local base = name:lower():gsub('[^%w]', ''):sub(1, 40)
    if base == '' then base = 'trader' end
    local id, n = base, 1
    while Traders[id] do n = n + 1; id = base .. n end
    return id
end

local function saveTrader(t)
    MySQL.query.await([[INSERT INTO jrs_trader_npcs (traderid, tradername, npcmodel, x, y, z, heading, showblip) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE tradername = VALUES(tradername), npcmodel = VALUES(npcmodel), x = VALUES(x), y = VALUES(y),
        z = VALUES(z), heading = VALUES(heading), showblip = VALUES(showblip)]],
        { t.traderid, t.tradername, t.npcmodel, t.x, t.y, t.z, t.heading, t.showblip and 1 or 0 })
    Traders[t.traderid] = t
    sync()
end

JRS.Callback('jrs_trader:admin:list', function(src)
    if not admin(src) then return nil end
    local list = {}
    for _, t in pairs(Traders) do list[#list + 1] = { traderid = t.traderid, tradername = t.tradername, showblip = t.showblip } end
    table.sort(list, function(a, b) return a.tradername < b.tradername end)
    return list
end)

JRS.Callback('jrs_trader:admin:create', function(src, name, model)
    if not admin(src) then return res(false, L('no_permission')) end
    name = trim(name)
    if not name or #name < 2 or #name > 50 then return res(false, L('invalid_name')) end
    model = trim(model)
    model = (model and model ~= '') and model:lower() or Config.DefaultModel
    if #model > 60 or model:find('[^%w_]') then return res(false, L('invalid_model')) end
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    saveTrader({ traderid = makeId(name), tradername = name, npcmodel = model, x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped), showblip = true })
    return res(true, L('trader_added', name))
end)

JRS.Callback('jrs_trader:admin:edit', function(src, traderid, action, value)
    if not admin(src) then return res(false, L('no_permission')) end
    local t = Traders[traderid]
    if not t then return res(false, L('not_found')) end
    if action == 'move' then
        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped)
        t.x, t.y, t.z, t.heading = c.x, c.y, c.z, GetEntityHeading(ped)
    elseif action == 'blip' then
        t.showblip = not t.showblip
    elseif action == 'rename' then
        local name = trim(value)
        if not name or #name < 2 or #name > 50 then return res(false, L('invalid_name')) end
        t.tradername = name
    elseif action == 'delete' then
        MySQL.query.await('DELETE FROM jrs_trader_npcs WHERE traderid = ?', { traderid })
        MySQL.query.await('DELETE FROM jrs_trader WHERE traderid = ?', { traderid })
        Traders[traderid] = nil
        sync()
        return res(true, L('trader_removed', t.tradername))
    else
        return res(false, L('invalid_input'))
    end
    saveTrader(t)
    return res(true, L('trader_updated', t.tradername))
end)

JRS.Callback('jrs_trader:admin:items', function(src, traderid)
    if not admin(src) or not Traders[traderid] then return nil end
    local list = MySQL.query.await('SELECT item, stock, lowstock, highstock, baseprice FROM jrs_trader WHERE traderid = ? ORDER BY item', { traderid }) or {}
    for _, r in ipairs(list) do r.label = JRS.ItemLabel(r.item) end
    return list
end)

JRS.Callback('jrs_trader:admin:addItem', function(src, traderid, item, baseprice)
    if not admin(src) or not Traders[traderid] then return res(false, L('no_permission')) end
    item = trim(item)
    item = item and item:lower()
    if not item or not itemExists(item) then return res(false, L('item_missing')) end
    baseprice = tonumber(baseprice)
    if not baseprice or baseprice <= 0 or baseprice > 1000000 then return res(false, L('invalid_input')) end
    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM jrs_trader WHERE traderid = ? AND item = ?', { traderid, item })
    if exists and exists > 0 then return res(false, L('already_exists')) end
    MySQL.insert.await('INSERT INTO jrs_trader (traderid, item, stock, lowstock, highstock, baseprice) VALUES (?, ?, 0, 10, 100, ?)',
        { traderid, item, round2(baseprice) })
    return res(true, L('saved'))
end)

local FIELDS = { stock = { 0, 1000000 }, lowstock = { 0, 1000000 }, highstock = { 1, 1000000 } }

JRS.Callback('jrs_trader:admin:setItem', function(src, traderid, item, field, value)
    if not admin(src) or not Traders[traderid] or type(item) ~= 'string' then return res(false, L('no_permission')) end
    if field == 'remove' then
        MySQL.query.await('DELETE FROM jrs_trader WHERE traderid = ? AND item = ?', { traderid, item })
        return res(true, L('removed'))
    end
    local row = MySQL.single.await('SELECT * FROM jrs_trader WHERE traderid = ? AND item = ?', { traderid, item })
    if not row then return res(false, L('invalid_input')) end
    if field == 'baseprice' then
        value = tonumber(value)
        if not value or value <= 0 or value > 1000000 then return res(false, L('invalid_input')) end
        value = round2(value)
    elseif FIELDS[field] then
        value = toInt(value, FIELDS[field][1], FIELDS[field][2])
        if not value then return res(false, L('invalid_input')) end
        local low = field == 'lowstock' and value or row.lowstock
        local high = field == 'highstock' and value or row.highstock
        if high <= low then return res(false, L('invalid_input')) end
    else
        return res(false, L('invalid_input'))
    end
    MySQL.update.await(('UPDATE jrs_trader SET `%s` = ? WHERE traderid = ? AND item = ?'):format(field), { value, traderid, item })
    return res(true, L('saved'))
end)

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)
