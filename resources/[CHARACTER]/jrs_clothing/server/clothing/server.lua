-- JRS Core Free - clothing server

local function DatabaseReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while JRSClothingDatabaseReady ~= true and GetGameTimer() < deadline do Wait(50) end
    return JRSClothingDatabaseReady == true
end

local function Decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'string' then ok, decoded = pcall(json.decode, decoded) end
    return ok and type(decoded) == 'table' and decoded or {}
end

local function VariantOf(data)
    if type(data) ~= 'table' then return nil end
    if type(data.texture) == 'table' then return tonumber(data.texture.palette or data.texture.model) end
    return tonumber(data.texture)
end

-- Price of everything that changed (new piece or new colour). Server owned.
local function ChangePrice(oldClothes, newClothes)
    local total = 0.0
    for category, nextData in pairs(type(newClothes) == 'table' and newClothes or {}) do
        if category ~= 'bodies_upper' and category ~= 'bodies_lower' and type(nextData) == 'table' then
            local nextModel = math.floor(tonumber(nextData.model) or 0)
            local old = type(oldClothes[category]) == 'table' and oldClothes[category] or {}
            if nextModel > 0 and (nextModel ~= math.floor(tonumber(old.model) or 0) or VariantOf(nextData) ~= VariantOf(old)) then
                total = total + (tonumber(ClothingConfig.Price and ClothingConfig.Price[category]) or 0)
            end
        end
    end
    return math.floor(total * 100 + 0.5) / 100
end

local function GetCurrentRow(charid)
    local ok, row = pcall(MySQL.single.await,
        'SELECT clothes, outfit_id FROM jrs_clothing_current WHERE charid = ? LIMIT 1', { tonumber(charid) })
    return ok and row or nil
end

local function SetCurrentClothes(charid, clothesJson, outfitid)
    charid = tonumber(charid)
    if not charid then return false end
    clothesJson = tostring(clothesJson or '{}')
    outfitid = tostring(outfitid or '0')
    if outfitid == '' then outfitid = '0' end

    local exists = MySQL.scalar.await('SELECT 1 FROM jrs_clothing_current WHERE charid = ? LIMIT 1', { charid })
    if exists then
        MySQL.update.await('UPDATE jrs_clothing_current SET clothes = ?, outfit_id = ? WHERE charid = ?',
            { clothesJson, outfitid, charid })
    else
        MySQL.insert.await('INSERT INTO jrs_clothing_current (charid, clothes, outfit_id, hidden_categories) VALUES (?, ?, ?, ?)',
            { charid, clothesJson, outfitid, '{}' })
    end
    local saved = MySQL.scalar.await('SELECT 1 FROM jrs_clothing_current WHERE charid = ? LIMIT 1', { charid })
    return saved ~= nil
end

local function RetireLegacyClothes(charid)
    MySQL.query.await([[
        INSERT IGNORE INTO jrs_appearance_legacy_backup (charid, compPlayer, skinPlayer)
        SELECT charidentifier, compPlayer, skinPlayer FROM jrs_characters WHERE charidentifier = ?
    ]], { charid })
    MySQL.update.await('UPDATE jrs_characters SET compPlayer = ? WHERE charidentifier = ?', { '{}', charid })
    pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end)
end

Callback.register('jrs_clothing:GetCurrentClothes', function(source, targetSrc)
    if not DatabaseReady() then return {}, 0, false, {} end
    local charid = GetCharIdentifier(tonumber(targetSrc) or source)
    if not charid then return {}, 0, false, {} end
    local row = GetCurrentRow(charid)
    if not row then return {}, 0, false, {} end
    return Decode(row.clothes), tonumber(row.outfit_id) or row.outfit_id or 0, true, {}
end)

Callback.register('jrs_clothing:GetCurrentClothesCharid', function(source, charid)
    if not DatabaseReady() then return {}, 0, {} end
    local row = GetCurrentRow(charid)
    if not row then return {}, 0, {} end
    return Decode(row.clothes), tonumber(row.outfit_id) or row.outfit_id or 0, {}
end)

local BuyBusy = {}
Callback.register('jrs_clothing:BuyClothes', function(source, clothes, male)
    local src = tonumber(source)
    if BuyBusy[src] then return false, 'save_busy' end
    if not DatabaseReady() then return false, 'database_not_ready' end
    local charid = tonumber(GetCharIdentifier(src))
    if not charid then return false, 'character_not_loaded' end

    clothes = JRSClothingSanitizePayload(clothes)
    if type(clothes) ~= 'table' or not next(clothes) then return false, 'invalid_clothes' end

    -- Only allowed (MP, non-law) pieces can be bought.
    local gender = (male == true or male == 1) and 'male' or 'female'
    for category, data in pairs(clothes) do
        local model = type(data) == 'table' and tonumber(data.model) or 0
        if model and model > 0 then
            local asset = ClothingAssets[gender] and ClothingAssets[gender][category] and ClothingAssets[gender][category][model]
            local variant = VariantOf(data)
            if not asset or asset.drawable or not IsClothingAssetAllowed(gender, category, model)
                or (variant and not IsClothingVariantAllowed(gender, category, model, variant)) then
                clothes[category] = { model = 0, texture = 0 }
            end
        end
    end

    BuyBusy[src] = true
    local ok, result, reason, saved = pcall(function()
        local row = GetCurrentRow(charid)
        local price = ChangePrice(row and Decode(row.clothes) or {}, clothes)
        if price > 0 and (tonumber(GetCharMoney(src)) or 0) < price then return false, 'not_enough_money' end

        local clothesJson = json.encode(clothes)
        local outfitId = row and row.outfit_id or '0'
        local previous = row and row.clothes or nil
        if not SetCurrentClothes(charid, clothesJson, outfitId) then return false, 'current_outfit_failed' end

        if price > 0 and RemoveCurrency(src, price) ~= true then
            if previous then SetCurrentClothes(charid, previous, outfitId) end
            return false, 'not_enough_money'
        end
        RetireLegacyClothes(charid)
        return true, nil, clothes
    end)
    BuyBusy[src] = nil
    if not ok then return false, 'save_exception' end
    return result, reason, saved
end)

-- Raw persistence used by the outfit loader (first-time capture / re-apply).
-- A stored look can never be swapped for a different one through this event:
-- new pieces are only sold through jrs_clothing:BuyClothes.
local lastSaveAt = {}
RegisterNetEvent('jrs_clothes:updateclothes', function(clothes, outfitid)
    local src = source
    local now = GetGameTimer()
    if type(clothes) ~= 'table' or now - (lastSaveAt[src] or 0) < 150 then return end
    lastSaveAt[src] = now
    local charid = tonumber(GetCharIdentifier(src))
    if not charid then return end
    clothes = JRSClothingSanitizePayload(clothes)
    if not clothes then return end

    CreateThread(function()
        if not DatabaseReady(10000) then return end
        local row = GetCurrentRow(charid)
        if row and ChangePrice(Decode(row.clothes), clothes) > 0 then return end
        local key = tostring(outfitid or (row and row.outfit_id) or 0)
        if #key > 32 or not key:match('^[%w_%-]+$') then key = '0' end
        if SetCurrentClothes(charid, json.encode(clothes), key) then RetireLegacyClothes(charid) end
    end)
end)

AddEventHandler('playerDropped', function()
    lastSaveAt[source] = nil
    BuyBusy[tonumber(source)] = nil
end)

exports('GetCharacterClothes', function(charid)
    charid = tonumber(charid)
    if not charid or not DatabaseReady(10000) then return nil end
    local row = GetCurrentRow(charid)
    if not row then return nil end
    return Decode(row.clothes), row.outfit_id, {}
end)

-- Used by jrs_core (character creator / admin skin changes).
exports('SetCharacterClothes', function(charid, clothes, outfitid)
    charid = tonumber(charid)
    if not charid or type(clothes) ~= 'table' or not DatabaseReady(10000) then return false end
    local id = tostring(outfitid or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if id == '' or id == '0' then
        local row = GetCurrentRow(charid)
        id = tostring(row and row.outfit_id or '0')
    end
    if SetCurrentClothes(charid, json.encode(clothes), id) ~= true then return false end
    RetireLegacyClothes(charid)
    return true
end)

-- Legacy callback API kept for other resources.
AddEventHandler('jrs_clothes:retrieveClothes', function(charid, callback)
    if type(callback) ~= 'function' then return end
    CreateThread(function()
        if not DatabaseReady(10000) then callback(false) return end
        callback(GetCurrentRow(charid) or false)
    end)
end)
