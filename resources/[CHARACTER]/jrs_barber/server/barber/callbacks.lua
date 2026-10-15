-- JRS Core Free - barber callbacks

local function DatabaseReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while JRSBarberDatabaseReady ~= true and GetGameTimer() < deadline do Wait(50) end
    return JRSBarberDatabaseReady == true
end

local function DecodeTable(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function TintOf(data)
    return type(data) == 'table' and type(data.texture) == 'table' and tonumber(data.texture.tint0) or nil
end

-- Price of every hair/beard category whose style or colour changed. Server owned.
local function CalculateChangeMinimum(oldHair, newHair)
    oldHair = type(oldHair) == 'table' and oldHair or {}
    local total = 0.0
    for category, nextData in pairs(type(newHair) == 'table' and newHair or {}) do
        if type(nextData) == 'table' then
            local old = type(oldHair[category]) == 'table' and oldHair[category] or {}
            local nextModel = math.max(0, math.floor(tonumber(nextData.model) or 0))
            local oldModel = math.max(0, math.floor(tonumber(old.model) or 0))
            if nextModel > 0 and (nextModel ~= oldModel or TintOf(nextData) ~= TintOf(old)) then
                total = total + (tonumber(BarberConfig.Price and BarberConfig.Price[category]) or 0)
            end
        end
    end
    return math.floor(total * 100 + 0.5) / 100
end
JRSBarberChangeMinimum = CalculateChangeMinimum

local function CleanScalar(value)
    local t = type(value)
    if t == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        if value > 4294967295 or value < -4294967296 then return nil end
        return value
    elseif t == 'boolean' then
        return value
    elseif t == 'string' then
        return #value <= 64 and value or nil
    end
    return nil
end

local function CleanKey(key)
    key = tostring(key or '')
    if #key == 0 or #key > 64 or not key:match('^[%w_%-]+$') then return nil end
    return key
end

-- { category = { model = n, texture = n | { palette, tint0.. } } }
function JRSBarberSanitizeHair(payload)
    if type(payload) ~= 'table' then return nil end
    local clean, count = {}, 0
    for category, entry in pairs(payload) do
        local key = CleanKey(category)
        if key and type(entry) == 'table' then
            local out = {}
            for field, value in pairs(entry) do
                local fname = CleanKey(field)
                if fname == 'texture' and type(value) == 'table' then
                    local tex = {}
                    for tk, tv in pairs(value) do
                        local tname = CleanKey(tk)
                        if tname then tex[tname] = CleanScalar(tv) end
                    end
                    out.texture = tex
                elseif fname then
                    out[fname] = CleanScalar(value)
                end
            end
            clean[key] = out
            count = count + 1
            if count >= 64 then break end
        end
    end
    return clean
end

function JRSBarberSanitizeOverlays(payload)
    if type(payload) ~= 'table' then return nil end
    local clean = {}
    for _, layer in pairs(payload) do
        if type(layer) == 'table' then
            local out = {}
            for field, value in pairs(layer) do
                local fname = CleanKey(field)
                if fname then out[fname] = CleanScalar(value) end
            end
            clean[#clean + 1] = out
            if #clean >= 64 then break end
        end
    end
    return clean
end

Callback.register('jrs_barber:GetCurrentHairs', function(source)
    if not DatabaseReady() then return {}, 0, {}, {}, false, {} end
    local charid = GetCharIdentifier(source)
    if not charid then return {}, 0, {}, {}, false, {} end
    local row = MySQL.single.await(
        'SELECT hairstyle, outfit_id, overlays, permanentoverlay FROM jrs_barber WHERE charid = ? LIMIT 1', { charid })
    if row then
        return DecodeTable(row.hairstyle), tonumber(row.outfit_id) or 0,
            DecodeTable(row.overlays), DecodeTable(row.permanentoverlay), true, {}
    end
    local skinRow = MySQL.single.await(
        'SELECT skinPlayer FROM jrs_characters WHERE charidentifier = ? LIMIT 1', { charid })
    return {}, 0, {}, {}, false, skinRow and DecodeTable(skinRow.skinPlayer) or {}
end)

Callback.register('jrs_barber:GetCurrentHairsOnCharacter', function(source, charid)
    if not DatabaseReady() then return {}, 0, {}, {} end
    charid = tonumber(charid)
    if not charid then return {}, 0, {}, {} end
    local row = MySQL.single.await(
        'SELECT hairstyle, outfit_id, overlays, permanentoverlay FROM jrs_barber WHERE charid = ? LIMIT 1', { charid })
    if not row then return {}, 0, {}, {} end
    return DecodeTable(row.hairstyle), tonumber(row.outfit_id) or 0,
        DecodeTable(row.overlays), DecodeTable(row.permanentoverlay)
end)

Callback.register('jrs_barber:GetCurrentOverlays', function(source, requestedCharid)
    if not DatabaseReady() then return {}, {} end
    local charid = tonumber(requestedCharid) or tonumber(GetCharIdentifier(source))
    if not charid then return {}, {} end
    local row = MySQL.single.await(
        'SELECT overlays, permanentoverlay FROM jrs_barber WHERE charid = ? LIMIT 1', { charid })
    if not row then return {}, {} end
    return DecodeTable(row.overlays), DecodeTable(row.permanentoverlay)
end)

local BuyBusy = {}
Callback.register('jrs_barber:BuyHair', function(source, hair)
    local src = tonumber(source)
    if BuyBusy[src] then return false, 'failed' end
    if not DatabaseReady() then return false, 'failed' end
    local charid = tonumber(GetCharIdentifier(src))
    hair = JRSBarberSanitizeHair(hair)
    if not charid or type(hair) ~= 'table' then return false, 'failed' end

    BuyBusy[src] = true
    local ok, result, reason = pcall(function()
        local row = MySQL.single.await(
            'SELECT hairstyle, overlays, permanentoverlay, outfit_id FROM jrs_barber WHERE charid = ? LIMIT 1', { charid })
        local oldHair = row and DecodeTable(row.hairstyle) or {}
        local price = CalculateChangeMinimum(oldHair, hair)
        if price <= 0 and row then return false, 'no_changes' end
        if price > 0 and (tonumber(GetCharMoney(src)) or 0) < price then return false, 'not_enough_money' end

        -- Overlays (from the character creator) are kept exactly as stored.
        local saved = MySQL.prepare.await([[
            INSERT INTO jrs_barber (charid, hairstyle, overlays, permanentoverlay, outfit_id)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE hairstyle = VALUES(hairstyle)
        ]], {
            charid, json.encode(hair),
            row and row.overlays or '[]', row and row.permanentoverlay or '[]', tostring(row and row.outfit_id or 0),
        })
        if saved == nil then return false, 'failed' end

        if price > 0 and RemoveCurrency(src, price) ~= true then
            if row then
                MySQL.update.await('UPDATE jrs_barber SET hairstyle = ? WHERE charid = ?', { row.hairstyle or '{}', charid })
            else
                MySQL.update.await('DELETE FROM jrs_barber WHERE charid = ?', { charid })
            end
            return false, 'not_enough_money'
        end
        pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end)
        return true
    end)
    BuyBusy[src] = nil
    if not ok then return false, 'failed' end
    return result, reason
end)

AddEventHandler('playerDropped', function()
    BuyBusy[tonumber(source)] = nil
end)
