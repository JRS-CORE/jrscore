-- ===================================================================
-- JRS INVENTORY | Native Custom Storage & Container Engine
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local RegisteredStorages = {}

JRSStorage = JRSStorage or {}

--- Registers a custom storage container in the inventory engine.
--- @param id string Unique identifier for the storage (e.g. 'chest_valentine')
--- @param config table Configuration table: `{ name = 'Chest', limit = 100.0, shared = true, acceptWeapons = true }`
function JRSStorage.Register(id, config)
    id = tostring(id or '')
    if id == '' then return false, 'invalid_id' end

    config = type(config) == 'table' and config or {}
    local name = tostring(config.name or config.label or id)
    local limit = tonumber(config.limit or config.capacity or config.maxWeight) or 100.0
    local acceptWeapons = config.acceptWeapons ~= false
    local shared = config.shared == true

    RegisteredStorages[id] = {
        name = name,
        limit = limit,
        acceptWeapons = acceptWeapons,
        shared = shared
    }

    if Inventory and Inventory.createstorage then
        Inventory.createstorage(id, name, limit, acceptWeapons, shared)
    end

    return true
end

--- Opens a registered custom storage for a player.
--- @param playerId number Player server id
--- @param id string Storage id
--- @param info table|string Optional extra display info
function JRSStorage.Open(playerId, id, info)
    local src = tonumber(playerId)
    id = tostring(id or '')
    if not src or src <= 0 or id == '' then return false end

    local def = RegisteredStorages[id]
    if def and Inventory and Inventory.createstorage then
        Inventory.createstorage(id, def.name, def.limit, def.acceptWeapons, def.shared)
    end

    if Inventory and Inventory.openstorage then
        Inventory.openstorage(src, id, info or (def and def.name))
        return true
    end

    return false
end

-- Server Exports
exports('RegisterCustomStorage', JRSStorage.Register)
exports('OpenCustomStorage', JRSStorage.Open)
exports('GetRegisteredStorages', function() return RegisteredStorages end)
