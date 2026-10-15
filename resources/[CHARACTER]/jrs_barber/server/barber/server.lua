-- JRS Core Free - barber persistence + exports

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

-- Raw write fired by the client loader (first-time capture of a new character /
-- re-apply). An existing look can only change through jrs_barber:BuyHair.
local lastSaveAt = {}
RegisterNetEvent('jrs_barber:updatehairstyle', function(hair, overlays, outfitid)
    local src = source
    local now = GetGameTimer()
    if now - (lastSaveAt[src] or 0) < 150 then return end
    lastSaveAt[src] = now
    hair = JRSBarberSanitizeHair(hair)
    overlays = JRSBarberSanitizeOverlays(overlays)
    if type(hair) ~= 'table' or type(overlays) ~= 'table' then return end
    local charid = tonumber(GetCharIdentifier(src))
    if not charid then return end

    CreateThread(function()
        if not DatabaseReady(10000) then return end
        local row = MySQL.single.await('SELECT hairstyle FROM jrs_barber WHERE charid = ? LIMIT 1', { charid })
        if row then
            if JRSBarberChangeMinimum(DecodeTable(row.hairstyle), hair) > 0 then return end
            MySQL.update.await('UPDATE jrs_barber SET hairstyle = ? WHERE charid = ?', { json.encode(hair), charid })
        else
            MySQL.prepare.await([[
                INSERT INTO jrs_barber (charid, hairstyle, overlays, permanentoverlay, outfit_id)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE hairstyle = VALUES(hairstyle)
            ]], { charid, json.encode(hair), json.encode(overlays), '[]', tostring(outfitid or 0) })
        end
        MySQL.query.await([[
            INSERT IGNORE INTO jrs_appearance_legacy_backup (charid, compPlayer, skinPlayer)
            SELECT charidentifier, compPlayer, skinPlayer FROM jrs_characters WHERE charidentifier = ?
        ]], { charid })

        -- Retire the legacy hair/overlay keys from skinPlayer: jrs_barber owns them now.
        local skinRow = MySQL.single.await(
            'SELECT skinPlayer FROM jrs_characters WHERE charidentifier = ? LIMIT 1', { charid })
        if skinRow then
            local skin = DecodeTable(skinRow.skinPlayer)
            skin.Hair = nil
            skin.Beard = nil
            for _, layer in pairs(BarberOverlayLayers or {}) do
                local prefix = tostring(layer.name or '') .. '_'
                for key in pairs(skin) do
                    if string.sub(tostring(key), 1, #prefix) == prefix then skin[key] = nil end
                end
            end
            MySQL.update.await('UPDATE jrs_characters SET skinPlayer = ? WHERE charidentifier = ?',
                { json.encode(skin), charid })
        end
        pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end)
    end)
end)

AddEventHandler('playerDropped', function()
    lastSaveAt[source] = nil
end)

exports('GetCharacterBarber', function(charid)
    charid = tonumber(charid)
    if not charid or not DatabaseReady(10000) then return nil end
    local row = MySQL.single.await(
        'SELECT hairstyle, overlays, permanentoverlay, outfit_id FROM jrs_barber WHERE charid = ? LIMIT 1', { charid })
    if not row then return nil end
    return {
        hairstyle = DecodeTable(row.hairstyle),
        overlays = DecodeTable(row.overlays),
        permanentoverlay = DecodeTable(row.permanentoverlay),
        outfit_id = row.outfit_id,
    }
end)

-- Used by jrs_core (character creator).
exports('SetCharacterBarber', function(charid, hairstyle, overlays, permanentoverlay, outfitid)
    charid = tonumber(charid)
    if not charid or type(hairstyle) ~= 'table' or not DatabaseReady(10000) then return false end
    local result = MySQL.prepare.await([[
        INSERT INTO jrs_barber (charid, hairstyle, overlays, permanentoverlay, outfit_id)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE hairstyle = VALUES(hairstyle), overlays = VALUES(overlays),
            permanentoverlay = VALUES(permanentoverlay), outfit_id = VALUES(outfit_id)
    ]], {
        charid, json.encode(hairstyle), json.encode(overlays or {}), json.encode(permanentoverlay or {}),
        tostring(outfitid or 0),
    })
    if result ~= nil then pcall(function() exports.jrs_core:RefreshAppearanceCache(charid) end) end
    return result ~= nil
end)
