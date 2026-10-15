local Core = exports.jrs_core:getCoreApi()
local sessions = {}
local activeBySource = {}
local pendingInvites = {}
local pendingBySeller = {}
local actionCooldowns = {}
local onlineByIdentity = {}
local identityBySource = {}
local processing = {}
local tradeValidators = {}

local function buildValidatorContext(stage, session, extra)
    local context = {
        stage = tostring(stage or ''),
        tradeKey = session and session.key or nil,
        seller = session and tonumber(session.seller) or nil,
        buyer = session and tonumber(session.buyer) or nil,
        price = session and tonumber(session.price) or 0,
        status = session and tostring(session.status or '') or '',
        items = session and session.items or {},
        weapons = session and session.weapons or {},
    }
    if type(extra) == 'table' then
        for k, v in pairs(extra) do context[k] = v end
    end
    return context
end

local function runTradeValidators(stage, session, extra)
    local context = buildValidatorContext(stage, session, extra)
    for key, entry in pairs(tradeValidators) do
        local ok, allowed, reason = pcall(entry.callback, stage, context)
        if not ok then
            print(('^1[jrs_inventory] trade validator %s failed: %s^0'):format(key, tostring(allowed)))
            return false, 'validator_error'
        end
        if allowed == false then return false, tostring(reason or 'trade_blocked') end
    end
    return true
end

exports('RegisterTradeValidator', function(name, callback)
    if type(callback) ~= 'function' then return false, 'invalid_callback' end
    name = tostring(name or '')
    if name == '' or #name > 80 then return false, 'invalid_name' end
    local owner = tostring(GetInvokingResource() or GetCurrentResourceName())
    tradeValidators[owner .. ':' .. name] = { owner = owner, name = name, callback = callback }
    return true
end)

local function debugPrint(...)
    if TradeConfig.Debug then print('[jrs_trade]', ...) end
end

local function awaitExecute(query, params)
    local p = promise.new()
    exports.oxmysql:execute(query, params or {}, function(result)
        p:resolve(result)
    end)
    return Citizen.Await(p)
end

local function affectedRows(result)
    if type(result) == 'number' then return result end
    if type(result) == 'table' then
        return tonumber(result.affectedRows or result.changedRows or result.rowCount or result[1]) or 0
    end
    return 0
end

local function getCharacter(src)
    src = tonumber(src)
    if not src or src <= 0 or not Core then return nil end
    if type(Core.GetCharacter) == 'function' then
        local ok, character = pcall(Core.GetCharacter, src)
        if ok and character then return character end
    end
    if type(Core.getCharacter) == 'function' then
        local ok, character = pcall(Core.getCharacter, src)
        if ok and character then return character end
    end
    local user = type(Core.getUser) == 'function' and Core.getUser(src) or nil
    return user and user.getUsedCharacter or nil
end

local function coreAddCash(src, amount)
    src, amount = tonumber(src), math.floor(tonumber(amount) or 0)
    if not src or src <= 0 or amount <= 0 or not Core then return false end
    local fn = Core.AddMoney or Core.addMoney
    if type(fn) ~= 'function' then return false end
    local ok, result
    if Core.AddMoney then
        ok, result = pcall(fn, src, amount)
    else
        ok, result = pcall(fn, src, 0, amount)
    end
    return ok and result == true
end

local function coreRemoveCash(src, amount)
    src, amount = tonumber(src), math.floor(tonumber(amount) or 0)
    if not src or src <= 0 or amount <= 0 or not Core then return false end
    local fn = Core.RemoveMoney or Core.removeMoney
    if type(fn) ~= 'function' then return false end
    local ok, result
    if Core.RemoveMoney then
        ok, result = pcall(fn, src, amount)
    else
        ok, result = pcall(fn, src, 0, amount)
    end
    return ok and result == true
end

local function allowAction(src, key, cooldownMs)
    src = tonumber(src)
    if not src then return false end
    local now = GetGameTimer()
    local bucket = actionCooldowns[src] or {}
    actionCooldowns[src] = bucket
    local expires = tonumber(bucket[key]) or 0
    if expires > now then return false end
    bucket[key] = now + math.max(50, math.floor(tonumber(cooldownMs) or 250))
    return true
end

local function clearInviteForBuyer(buyer)
    buyer = tonumber(buyer)
    local invite = buyer and pendingInvites[buyer] or nil
    if invite then
        pendingBySeller[tonumber(invite.seller)] = nil
        pendingInvites[buyer] = nil
    end
    return invite
end

local function charValue(Character, keys)
    for _, key in ipairs(keys) do
        local value = Character and Character[key]
        if value ~= nil and tostring(value) ~= '' then return value end
    end
    return nil
end

local function characterName(src)
    local Character = getCharacter(src)
    if not Character then return GetPlayerName(src) or ('Player ' .. tostring(src)) end
    local first = charValue(Character, { 'firstname', 'firstName', 'first_name' })
    local last = charValue(Character, { 'lastname', 'lastName', 'last_name' })
    local name = ((first and tostring(first) or '') .. ' ' .. (last and tostring(last) or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or (GetPlayerName(src) or ('Player ' .. tostring(src)))
end

local function identityOf(src)
    local Character = getCharacter(src)
    if not Character or Character.identifier == nil or Character.charIdentifier == nil then return nil end
    return {
        identifier = tostring(Character.identifier),
        charid = tostring(Character.charIdentifier),
        key = tostring(Character.identifier) .. ':' .. tostring(Character.charIdentifier),
    }
end

local function sourceIsActive(src)
    src = tonumber(src)
    if not src then return false end
    for _, player in ipairs(GetPlayers()) do
        if tonumber(player) == src then return true end
    end
    return false
end

local function nearby(a, b)
    a, b = tonumber(a), tonumber(b)
    if not a or not b or a == b or not sourceIsActive(a) or not sourceIsActive(b) then return false end
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return false end
    local ca, cb = GetEntityCoords(pedA), GetEntityCoords(pedB)
    local dx, dy, dz = ca.x - cb.x, ca.y - cb.y, ca.z - cb.z
    local max = (tonumber(TradeConfig.MaxDistance) or 5.0) + 1.0
    return (dx * dx + dy * dy + dz * dz) <= (max * max)
end

local function notify(src, message, notifyType)
    if not sourceIsActive(src) then return false end
    local text = tostring(message or '')
    if text == '' then return false end
    if Core and type(Core.Notify) == 'function' then
        local ok, rendered = pcall(Core.Notify, tonumber(src), text, notifyType or 'info', 3500, 'Trade')
        if ok and rendered ~= false then return true end
    end
    TriggerClientEvent('jrs_trade:client:notify', src, text)
    return true
end

local function newTradeKey()
    return ('JRS-%d-%06d'):format(os.time(), math.random(0, 999999))
end

local function decodeJson(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or fallback
end

local function selectedList(session)
    local items, weapons = {}, {}
    for itemId, count in pairs(session.items or {}) do
        items[#items + 1] = { itemId = tonumber(itemId), count = tonumber(count) }
    end
    for weaponId in pairs(session.weapons or {}) do
        weapons[#weapons + 1] = tonumber(weaponId)
    end
    table.sort(items, function(a, b) return (a.itemId or 0) < (b.itemId or 0) end)
    table.sort(weapons)
    return items, weapons
end

local function getSessionForSource(src)
    local key = activeBySource[tonumber(src)]
    return key and sessions[key] or nil
end

exports('GetTradeSession', function(source)
    local session = getSessionForSource(tonumber(source))
    return session and buildValidatorContext('query', session) or nil
end)

exports('IsTrading', function(source)
    return getSessionForSource(tonumber(source)) ~= nil
end)

local function clearRuntimeSession(session)
    if not session then return end
    if session.seller then activeBySource[tonumber(session.seller)] = nil end
    if session.buyer then activeBySource[tonumber(session.buyer)] = nil end
    sessions[session.key] = nil
    processing[session.key] = nil
end

local function refreshSources(session)
    if not session then return end
    session.seller = onlineByIdentity[session.sellerIdentityKey]
    session.buyer = onlineByIdentity[session.buyerIdentityKey]
    if session.seller and not sourceIsActive(session.seller) then session.seller = nil end
    if session.buyer and not sourceIsActive(session.buyer) then session.buyer = nil end
    if session.seller then activeBySource[session.seller] = session.key end
    if session.buyer then activeBySource[session.buyer] = session.key end
end

local function findEntryById(list, id, keyName)
    for _, entry in ipairs(list or {}) do
        if tonumber(entry[keyName]) == tonumber(id) then return entry end
    end
end

local function buildState(session, viewer)
    refreshSources(session)
    local role = tonumber(viewer) == tonumber(session.seller) and 'seller' or 'buyer'
    local snapshot = nil
    if role == 'seller' and session.status == 'draft' then
        snapshot = select(1, exports.jrs_inventory:tradeGetSnapshot(viewer))
    end

    local offerItems, offerWeapons = {}, {}
    if session.status == 'draft' then
        local sourceSnapshot = snapshot or (session.seller and select(1, exports.jrs_inventory:tradeGetSnapshot(session.seller))) or { items = {}, weapons = {} }
        for itemId, amount in pairs(session.items or {}) do
            local entry = findEntryById(sourceSnapshot.items, itemId, 'itemId')
            if entry then
                offerItems[#offerItems + 1] = {
                    itemId = tonumber(itemId), item = entry.item, label = entry.label,
                    amount = tonumber(amount), count = tonumber(amount), slot = entry.slot,
                }
            end
        end
        for weaponId in pairs(session.weapons or {}) do
            local entry = findEntryById(sourceSnapshot.weapons, weaponId, 'weaponId')
            if entry then offerWeapons[#offerWeapons + 1] = entry end
        end
    else
        for _, entry in ipairs((session.escrow and session.escrow.items) or {}) do
            offerItems[#offerItems + 1] = {
                itemId = entry.itemId, item = entry.item, label = entry.label,
                amount = entry.amount, count = entry.amount, slot = entry.slot,
            }
        end
        for _, entry in ipairs((session.escrow and session.escrow.weapons) or {}) do
            offerWeapons[#offerWeapons + 1] = entry
        end
    end

    local viewerCharacter = getCharacter(viewer)
    return {
        tradeKey = session.key,
        role = role,
        status = session.status,
        price = tonumber(session.price) or 0,
        offer = { items = offerItems, weapons = offerWeapons },
        inventory = snapshot or { items = {}, weapons = {} },
        balance = viewerCharacter and tonumber(viewerCharacter.money) or 0,
        seller = { id = session.seller, name = session.sellerName, online = session.seller ~= nil and sourceIsActive(session.seller) },
        buyer = { id = session.buyer, name = session.buyerName, online = session.buyer ~= nil and sourceIsActive(session.buyer) },
        imageBase = TradeConfig.InventoryImageBase,
        expireMinutes = TradeConfig.OfferExpireMinutes,
    }
end

local function pushState(session, forceOpen)
    refreshSources(session)
    if session.seller and sourceIsActive(session.seller) then
        TriggerClientEvent(forceOpen and 'jrs_trade:client:state' or 'jrs_trade:client:refresh', session.seller, buildState(session, session.seller))
    end
    if session.buyer and sourceIsActive(session.buyer) then
        TriggerClientEvent(forceOpen and 'jrs_trade:client:state' or 'jrs_trade:client:refresh', session.buyer, buildState(session, session.buyer))
    end
end

local function persistLocked(session)
    local sellerIdentity = identityOf(session.seller)
    local buyerIdentity = identityOf(session.buyer)
    if not sellerIdentity or not buyerIdentity then return false end
    local expires = os.date('%Y-%m-%d %H:%M:%S', os.time() + math.floor((tonumber(TradeConfig.OfferExpireMinutes) or 30) * 60))
    local result = awaitExecute([[
        INSERT INTO jrs_trade_orders
            (trade_key, seller_identifier, seller_charid, seller_name, buyer_identifier, buyer_charid, buyer_name, price, status, offer_json, expires_at)
        VALUES
            (@trade_key, @seller_identifier, @seller_charid, @seller_name, @buyer_identifier, @buyer_charid, @buyer_name, @price, 'locked', @offer_json, @expires_at)
        ON DUPLICATE KEY UPDATE
            price=VALUES(price), status='locked', offer_json=VALUES(offer_json), expires_at=VALUES(expires_at),
            seller_name=VALUES(seller_name), buyer_name=VALUES(buyer_name), updated_at=CURRENT_TIMESTAMP
    ]], {
        ['trade_key'] = session.key,
        ['seller_identifier'] = sellerIdentity.identifier,
        ['seller_charid'] = sellerIdentity.charid,
        ['seller_name'] = session.sellerName,
        ['buyer_identifier'] = buyerIdentity.identifier,
        ['buyer_charid'] = buyerIdentity.charid,
        ['buyer_name'] = session.buyerName,
        ['price'] = tonumber(session.price) or 0,
        ['offer_json'] = json.encode(session.escrow or {}),
        ['expires_at'] = expires,
    })
    return affectedRows(result) > 0
end

local function setDbStatus(key, status, extra)
    local sql = 'UPDATE jrs_trade_orders SET status=@status, updated_at=CURRENT_TIMESTAMP'
    local params = { ['status'] = status, ['trade_key'] = key }
    if extra and extra.cancelReason then
        sql = sql .. ', cancel_reason=@cancel_reason'
        params.cancel_reason = tostring(extra.cancelReason)
    end
    if extra and extra.buyerCharged ~= nil then
        sql = sql .. ', buyer_charged=@buyer_charged'
        params.buyer_charged = extra.buyerCharged and 1 or 0
    end
    if extra and extra.delivered ~= nil then
        sql = sql .. ', delivered=@delivered'
        params.delivered = extra.delivered and 1 or 0
    end
    if extra and extra.sellerPaid ~= nil then
        sql = sql .. ', seller_paid=@seller_paid'
        params.seller_paid = extra.sellerPaid and 1 or 0
    end
    sql = sql .. ' WHERE trade_key=@trade_key'
    awaitExecute(sql, params)
end

local function loadSessionFromRow(row)
    local key = tostring(row.trade_key)
    local session = sessions[key]
    if not session then
        local sellerKey = tostring(row.seller_identifier) .. ':' .. tostring(row.seller_charid)
        local buyerKey = tostring(row.buyer_identifier) .. ':' .. tostring(row.buyer_charid)
        session = {
            key = key,
            status = tostring(row.status),
            price = tonumber(row.price) or 0,
            escrow = decodeJson(row.offer_json, { items = {}, weapons = {} }),
            items = {}, weapons = {},
            sellerIdentityKey = sellerKey,
            buyerIdentityKey = buyerKey,
            sellerName = row.seller_name or 'Seller',
            buyerName = row.buyer_name or 'Buyer',
            cancelReason = row.cancel_reason,
        }
        sessions[key] = session
    end
    refreshSources(session)
    return session
end

local function restoreEscrow(session, finalStatus, cancelReason)
    refreshSources(session)
    if not session.seller or not sourceIsActive(session.seller) then
        session.status = 'return_pending'
        session.cancelReason = cancelReason or finalStatus
        setDbStatus(session.key, 'return_pending', { cancelReason = session.cancelReason })
        return false, 'seller_offline'
    end
    local ok, reason = exports.jrs_inventory:tradeReturnEscrow(session.seller, session.escrow or {}, { tradeKey = session.key, finalStatus = finalStatus, cancelReason = cancelReason or finalStatus })
    if not ok then
        session.status = 'return_pending'
        session.cancelReason = cancelReason or finalStatus
        setDbStatus(session.key, 'return_pending', { cancelReason = session.cancelReason })
        return false, reason
    end
    if session.seller then notify(session.seller, TradeConfig.Text.cancelled) end
    if session.buyer then notify(session.buyer, TradeConfig.Text.cancelled) end
    if session.seller then TriggerClientEvent('jrs_trade:client:close', session.seller, finalStatus) end
    if session.buyer then TriggerClientEvent('jrs_trade:client:close', session.buyer, finalStatus) end
    clearRuntimeSession(session)
    return true, 'ok'
end

local function initializeDatabase()
    awaitExecute([[
        CREATE TABLE IF NOT EXISTS `jrs_trade_orders` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `trade_key` VARCHAR(64) NOT NULL,
          `seller_identifier` VARCHAR(128) NOT NULL,
          `seller_charid` VARCHAR(128) NOT NULL,
          `seller_name` VARCHAR(128) NULL,
          `buyer_identifier` VARCHAR(128) NOT NULL,
          `buyer_charid` VARCHAR(128) NOT NULL,
          `buyer_name` VARCHAR(128) NULL,
          `price` BIGINT UNSIGNED NOT NULL DEFAULT 0,
          `status` VARCHAR(32) NOT NULL DEFAULT 'locked',
          `offer_json` LONGTEXT NOT NULL,
          `buyer_charged` TINYINT(1) NOT NULL DEFAULT 0,
          `delivered` TINYINT(1) NOT NULL DEFAULT 0,
          `seller_paid` TINYINT(1) NOT NULL DEFAULT 0,
          `cancel_reason` VARCHAR(64) NULL,
          `expires_at` DATETIME NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_jrs_trade_key` (`trade_key`),
          KEY `idx_jrs_trade_seller` (`seller_identifier`, `seller_charid`, `status`),
          KEY `idx_jrs_trade_buyer` (`buyer_identifier`, `buyer_charid`, `status`),
          KEY `idx_jrs_trade_expiry` (`status`, `expires_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

RegisterNetEvent('jrs_trade:server:invite', function(target)
    local src = tonumber(source)
    target = tonumber(target)
    if not src or not allowAction(src, 'invite', 1000) then return end
    if not target or src == target or not sourceIsActive(target) then
        notify(src, TradeConfig.Text.invalidTarget, 'error') return
    end
    if activeBySource[src] or activeBySource[target] or pendingBySeller[src] or pendingInvites[target] then
        notify(src, TradeConfig.Text.busy, 'warning') return
    end
    if not nearby(src, target) then notify(src, TradeConfig.Text.targetTooFar, 'warning') return end
    local sellerIdentity, buyerIdentity = identityOf(src), identityOf(target)
    if not sellerIdentity or not buyerIdentity then notify(src, TradeConfig.Text.failed, 'error') return end
    local allowed, blockedReason = runTradeValidators('invite', nil, {
        seller = src, buyer = target, sellerCharId = sellerIdentity.charid, buyerCharId = buyerIdentity.charid
    })
    if not allowed then notify(src, blockedReason or TradeConfig.Text.failed, 'warning') return end

    local key = newTradeKey()
    pendingInvites[target] = {
        key = key, seller = src, buyer = target,
        sellerIdentity = sellerIdentity, buyerIdentity = buyerIdentity,
        expiresAt = GetGameTimer() + math.floor((tonumber(TradeConfig.InviteSeconds) or 30) * 1000)
    }
    pendingBySeller[src] = target
    TriggerClientEvent('jrs_trade:client:invite', target, {
        tradeKey = key,
        seller = { id = src, name = characterName(src) },
        seconds = TradeConfig.InviteSeconds,
    })
    notify(src, TradeConfig.Text.invited)
end)

RegisterNetEvent('jrs_trade:server:acceptInvite', function(key)
    local buyer = tonumber(source)
    if not buyer or not allowAction(buyer, 'invite_response', 500) then return end
    local invite = pendingInvites[buyer]
    if not invite or tostring(invite.key) ~= tostring(key) or invite.expiresAt <= GetGameTimer() then
        clearInviteForBuyer(buyer)
        notify(buyer, TradeConfig.Text.inviteExpired, 'warning') return
    end
    local seller = tonumber(invite.seller)
    if not sourceIsActive(seller) or activeBySource[seller] or activeBySource[buyer] or not nearby(seller, buyer) then
        clearInviteForBuyer(buyer)
        notify(buyer, TradeConfig.Text.failed, 'error') return
    end
    clearInviteForBuyer(buyer)

    local session = {
        key = invite.key, seller = seller, buyer = buyer, status = 'draft', price = 0,
        items = {}, weapons = {}, escrow = nil,
        sellerIdentityKey = invite.sellerIdentity.key,
        buyerIdentityKey = invite.buyerIdentity.key,
        sellerName = characterName(seller), buyerName = characterName(buyer),
    }
    sessions[session.key] = session
    activeBySource[seller] = session.key
    activeBySource[buyer] = session.key
    pushState(session, true)
end)

RegisterNetEvent('jrs_trade:server:declineInvite', function(key)
    local buyer = tonumber(source)
    if not buyer or not allowAction(buyer, 'invite_response', 500) then return end
    local invite = pendingInvites[buyer]
    if invite and tostring(invite.key) == tostring(key) then
        clearInviteForBuyer(buyer)
        notify(invite.seller, TradeConfig.Text.declined, 'warning')
    end
end)

RegisterNetEvent('jrs_trade:server:addItem', function(itemId, count)
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_mutation', 100) then return end
    local session = getSessionForSource(src)
    if not session or session.status ~= 'draft' or src ~= session.seller then return end
    itemId, count = tonumber(itemId), math.floor(tonumber(count) or 0)
    if not itemId or count <= 0 then return end
    local snapshot = select(1, exports.jrs_inventory:tradeGetSnapshot(src))
    local entry = snapshot and findEntryById(snapshot.items, itemId, 'itemId')
    if not entry or count > (tonumber(entry.count) or 0) then return end
    local lines = 0 for _ in pairs(session.items) do lines = lines + 1 end
    if not session.items[itemId] and lines >= (tonumber(TradeConfig.MaxItemLines) or 30) then return end
    session.items[itemId] = count
    pushState(session, false)
end)

RegisterNetEvent('jrs_trade:server:removeItem', function(itemId)
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_mutation', 100) then return end
    local session = getSessionForSource(src)
    if session and session.status == 'draft' and src == session.seller then
        session.items[tonumber(itemId)] = nil
        pushState(session, false)
    end
end)

RegisterNetEvent('jrs_trade:server:addWeapon', function(weaponId)
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_mutation', 100) then return end
    local session = getSessionForSource(src)
    if not session or session.status ~= 'draft' or src ~= session.seller then return end
    weaponId = tonumber(weaponId)
    if not weaponId then return end
    local snapshot = select(1, exports.jrs_inventory:tradeGetSnapshot(src))
    local entry = snapshot and findEntryById(snapshot.weapons, weaponId, 'weaponId')
    if not entry then return end
    if tonumber(entry.used) == 1 then notify(src, TradeConfig.Text.weaponEquipped) return end
    local lines = 0 for _ in pairs(session.weapons) do lines = lines + 1 end
    if not session.weapons[weaponId] and lines >= (tonumber(TradeConfig.MaxWeaponLines) or 10) then return end
    session.weapons[weaponId] = true
    pushState(session, false)
end)

RegisterNetEvent('jrs_trade:server:removeWeapon', function(weaponId)
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_mutation', 100) then return end
    local session = getSessionForSource(src)
    if session and session.status == 'draft' and src == session.seller then
        session.weapons[tonumber(weaponId)] = nil
        pushState(session, false)
    end
end)

RegisterNetEvent('jrs_trade:server:setPrice', function(price)
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_mutation', 150) then return end
    local session = getSessionForSource(src)
    if not session or session.status ~= 'draft' or src ~= session.seller then return end
    price = math.floor(tonumber(price) or 0)
    if price < 0 then price = 0 end
    if price > (tonumber(TradeConfig.MaxPrice) or 10000000) then price = tonumber(TradeConfig.MaxPrice) or 10000000 end
    session.price = price
    pushState(session, false)
end)

RegisterNetEvent('jrs_trade:server:lockOffer', function()
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_lock', 750) then return end
    local session = getSessionForSource(src)
    if not session or session.status ~= 'draft' or src ~= session.seller or processing[session.key] then return end
    if (tonumber(session.price) or 0) < (tonumber(TradeConfig.MinPrice) or 1) then
        notify(src, _Up(src, 'trade_enter_a_valid_sale_price_first')) return
    end
    local allowed, blockedReason = runTradeValidators('lock', session)
    if not allowed then notify(src, blockedReason or TradeConfig.Text.failed, 'warning') return end
    processing[session.key] = true
    local items, weapons = selectedList(session)
    local buyerIdentity = identityOf(session.buyer)
    if not buyerIdentity then
        processing[session.key] = nil
        notify(src, TradeConfig.Text.failed)
        return
    end
    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + math.floor((tonumber(TradeConfig.OfferExpireMinutes) or 30) * 60))
    local ok, reason, escrow = exports.jrs_inventory:tradeReserveOffer(src, items, weapons, {
        tradeKey = session.key,
        buyerIdentifier = buyerIdentity.identifier,
        buyerCharid = buyerIdentity.charid,
        sellerName = session.sellerName,
        buyerName = session.buyerName,
        price = session.price,
        expiresAt = expiresAt,
    })
    if not ok then
        processing[session.key] = nil
        notify(src, TradeConfig.Text.failed .. ' (' .. tostring(reason) .. ')')
        pushState(session, false)
        return
    end
    session.escrow = escrow
    session.status = 'locked'
    processing[session.key] = nil
    notify(src, TradeConfig.Text.locked)
    if session.buyer then notify(session.buyer, TradeConfig.Text.locked) end
    pushState(session, false)
end)

RegisterNetEvent('jrs_trade:server:pay', function()
    local buyer = tonumber(source)
    if not buyer or not allowAction(buyer, 'trade_pay', 1000) then return end
    local session = getSessionForSource(buyer)
    if not session or session.status ~= 'locked' or buyer ~= session.buyer or processing[session.key] then return end
    refreshSources(session)
    if not session.seller or not sourceIsActive(session.seller) then notify(buyer, TradeConfig.Text.sellerOffline) return end
    if TradeConfig.RequireNearbyToPay and not nearby(session.seller, buyer) then notify(buyer, TradeConfig.Text.targetTooFar) return end

    processing[session.key] = true
    local canReceive, receiveReason = exports.jrs_inventory:tradeCanReceive(buyer, session.escrow or {})
    if not canReceive then
        processing[session.key] = nil
        notify(buyer, receiveReason == 'weapon_full' and TradeConfig.Text.buyerWeaponFull or TradeConfig.Text.buyerFull)
        return
    end

    local buyerChar, sellerChar = getCharacter(buyer), getCharacter(session.seller)
    local price = math.floor(tonumber(session.price) or 0)
    if not buyerChar or not sellerChar or price < (tonumber(TradeConfig.MinPrice) or 1) then
        processing[session.key] = nil notify(buyer, TradeConfig.Text.failed, 'error') return
    end
    if (tonumber(buyerChar.money) or 0) < price then
        processing[session.key] = nil notify(buyer, TradeConfig.Text.insufficientMoney, 'warning') return
    end
    local allowed, blockedReason = runTradeValidators('pay', session)
    if not allowed then
        processing[session.key] = nil
        notify(buyer, blockedReason or TradeConfig.Text.failed, 'warning')
        return
    end

    session.status = 'processing'
    setDbStatus(session.key, 'processing', { buyerCharged = false, delivered = false, sellerPaid = false })

    -- Use the authoritative core economy API. It validates character readiness,
    -- balance and the true boolean result; pcall alone is not a successful payment.
    local removed = coreRemoveCash(buyer, price)
    if not removed then
        session.status = 'locked'
        setDbStatus(session.key, 'locked', { buyerCharged = false, delivered = false, sellerPaid = false })
        processing[session.key] = nil
        notify(buyer, TradeConfig.Text.failed, 'error')
        return
    end
    setDbStatus(session.key, 'processing', { buyerCharged = true })

    local delivered, deliverReason = exports.jrs_inventory:tradeDeliverEscrow(buyer, session.escrow or {}, session.key)
    if not delivered then
        local refunded = coreAddCash(buyer, price)
        if refunded then
            session.status = 'locked'
            setDbStatus(session.key, 'locked', { buyerCharged = false, delivered = false, sellerPaid = false })
            processing[session.key] = nil
            notify(buyer, TradeConfig.Text.failed .. ' (' .. tostring(deliverReason) .. ')', 'error')
            pushState(session, false)
        else
            -- Never lie about a refund. Keep a recoverable persistent state if
            -- the economy layer cannot credit the buyer immediately.
            session.status = 'buyer_refund_pending'
            setDbStatus(session.key, 'buyer_refund_pending', { buyerCharged = true, delivered = false, sellerPaid = false })
            processing[session.key] = nil
            notify(buyer, TradeConfig.Text.failed .. ' (' .. tostring(deliverReason) .. ') - refund pending recovery', 'warning')
            TriggerClientEvent('jrs_trade:client:close', buyer, 'refund_pending')
            if session.seller then TriggerClientEvent('jrs_trade:client:close', session.seller, 'refund_pending') end
        end
        return
    end

    local paidSeller = coreAddCash(session.seller, price)

    if paidSeller then
        setDbStatus(session.key, 'completed', { buyerCharged = true, delivered = true, sellerPaid = true })
    else
        setDbStatus(session.key, 'completed_payout_pending', { buyerCharged = true, delivered = true, sellerPaid = false })
    end

    notify(buyer, TradeConfig.Text.completed, 'success')
    notify(session.seller, paidSeller and TradeConfig.Text.completed or (TradeConfig.Text.completed .. ' - payout pending recovery'), paidSeller and 'success' or 'warning')
    TriggerClientEvent('jrs_trade:client:close', buyer, 'completed')
    TriggerClientEvent('jrs_trade:client:close', session.seller, 'completed')
    local completedPayload = buildValidatorContext('completed', session, { sellerPaid = paidSeller == true })
    TriggerEvent('jrs_inventory:server:tradeCompleted', completedPayload)
    if type(JRSEmitInventoryHook) == 'function' then JRSEmitInventoryHook('tradeCompleted', completedPayload) end
    clearRuntimeSession(session)
end)

RegisterNetEvent('jrs_trade:server:cancel', function()
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_cancel', 500) then return end
    local session = getSessionForSource(src)
    if not session or processing[session.key] then return end
    if session.status == 'draft' then
        if session.seller then TriggerClientEvent('jrs_trade:client:close', session.seller, 'cancelled') end
        if session.buyer then TriggerClientEvent('jrs_trade:client:close', session.buyer, 'cancelled') end
        notify(session.seller, TradeConfig.Text.cancelled)
        notify(session.buyer, TradeConfig.Text.cancelled)
        clearRuntimeSession(session)
        return
    end
    if session.status == 'locked' then
        processing[session.key] = true
        restoreEscrow(session, 'cancelled', 'manual')
        processing[session.key] = nil
    end
end)

RegisterNetEvent('jrs_trade:server:reopen', function()
    local src = tonumber(source)
    if not src or not allowAction(src, 'trade_reopen', 500) then return end
    local session = getSessionForSource(src)
    if not session then notify(src, TradeConfig.Text.noTrade) return end
    TriggerClientEvent('jrs_trade:client:state', src, buildState(session, src))
end)

local function recoverForPlayer(src)
    local identity = identityOf(src)
    if not identity then return end
    onlineByIdentity[identity.key] = src
    identityBySource[src] = identity.key

    local rows = awaitExecute([[
        SELECT * FROM jrs_trade_orders
        WHERE ((seller_identifier=@identifier AND seller_charid=@charid)
            OR (buyer_identifier=@identifier AND buyer_charid=@charid))
          AND status IN ('locked','processing','buyer_refund_pending','return_pending','completed_payout_pending')
        ORDER BY updated_at DESC
        LIMIT 10
    ]], { ['identifier'] = identity.identifier, ['charid'] = identity.charid }) or {}

    for _, row in ipairs(rows) do
        local session = loadSessionFromRow(row)
        if row.status == 'processing' then
            local charged = (row.buyer_charged == true or tonumber(row.buyer_charged) == 1)
            local delivered = (row.delivered == true or tonumber(row.delivered) == 1)
            local sellerPaid = (row.seller_paid == true or tonumber(row.seller_paid) == 1)
            if delivered and not sellerPaid and session.sellerIdentityKey == identity.key then
                if coreAddCash(src, tonumber(row.price) or 0) then
                    setDbStatus(row.trade_key, 'completed', { buyerCharged = true, delivered = true, sellerPaid = true })
                    notify(src, _Up(src, 'recovered_trade', tostring(row.price or 0)), 'success')
                    clearRuntimeSession(session)
                end
            elseif charged and not delivered and session.buyerIdentityKey == identity.key then
                if coreAddCash(src, tonumber(row.price) or 0) then
                    setDbStatus(row.trade_key, 'locked', { buyerCharged = false, delivered = false, sellerPaid = false })
                    session.status = 'locked'
                    notify(src, _Up(src, 'interrupted_refund'), 'success')
                    activeBySource[src] = session.key
                else
                    setDbStatus(row.trade_key, 'buyer_refund_pending', { buyerCharged = true, delivered = false, sellerPaid = false })
                    session.status = 'buyer_refund_pending'
                end
            elseif not charged and not delivered then
                setDbStatus(row.trade_key, 'locked', { buyerCharged = false, delivered = false, sellerPaid = false })
                session.status = 'locked'
                activeBySource[src] = session.key
            end
        elseif row.status == 'buyer_refund_pending' and session.buyerIdentityKey == identity.key then
            if coreAddCash(src, tonumber(row.price) or 0) then
                setDbStatus(row.trade_key, 'locked', { buyerCharged = false, delivered = false, sellerPaid = false })
                session.status = 'locked'
                activeBySource[src] = session.key
                notify(src, _Up(src, 'interrupted_refund'), 'success')
            end
        elseif row.status == 'return_pending' and session.sellerIdentityKey == identity.key then
            local finalStatus = tostring(row.cancel_reason) == 'expired' and 'expired' or 'cancelled'
            local ok = restoreEscrow(session, finalStatus, row.cancel_reason or 'recovery')
            if ok then debugPrint('returned pending escrow', row.trade_key) end
        elseif row.status == 'completed_payout_pending' and session.sellerIdentityKey == identity.key then
            if coreAddCash(src, tonumber(row.price) or 0) then
                setDbStatus(row.trade_key, 'completed', { buyerCharged = true, delivered = true, sellerPaid = true })
                notify(src, _Up(src, 'pending_payout', tostring(row.price or 0)), 'success')
                clearRuntimeSession(session)
            end
        elseif row.status == 'locked' then
            session.status = 'locked'
            refreshSources(session)
            activeBySource[src] = session.key
            notify(src, TradeConfig.Text.activeRestored)
        end
    end
end

RegisterNetEvent('jrs_trade:server:playerReady', function()
    recoverForPlayer(tonumber(source))
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local identityKey = identityBySource[src]
    if identityKey then onlineByIdentity[identityKey] = nil end
    identityBySource[src] = nil
    clearInviteForBuyer(src)
    local pendingTarget = pendingBySeller[src]
    if pendingTarget then clearInviteForBuyer(pendingTarget) end
    actionCooldowns[src] = nil
    local session = getSessionForSource(src)
    if session then
        activeBySource[src] = nil
        if session.status == 'draft' then
            if session.seller and tonumber(session.seller) ~= src then notify(session.seller, TradeConfig.Text.cancelled) end
            if session.buyer and tonumber(session.buyer) ~= src then notify(session.buyer, TradeConfig.Text.cancelled) end
            clearRuntimeSession(session)
        else
            if tonumber(session.seller) == src then session.seller = nil end
            if tonumber(session.buyer) == src then session.buyer = nil end
        end
    end
end)

Citizen.CreateThread(function()
    initializeDatabase()
    while true do
        Citizen.Wait(60000)
        local now = os.time()
        local rows = awaitExecute([[
            SELECT * FROM jrs_trade_orders
            WHERE status='locked' AND expires_at IS NOT NULL AND expires_at <= NOW()
            LIMIT 50
        ]], {}) or {}
        for _, row in ipairs(rows) do
            local session = loadSessionFromRow(row)
            if not processing[session.key] then
                processing[session.key] = true
                restoreEscrow(session, 'expired', 'expired')
                processing[session.key] = nil
            end
        end
        for target, invite in pairs(pendingInvites) do
            if invite.expiresAt <= GetGameTimer() then clearInviteForBuyer(target) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    for key, entry in pairs(tradeValidators) do
        if entry.owner == resourceName then tradeValidators[key] = nil end
    end
end)
