-- jrs_backpacks | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'

local function newSerial()
    local out = {}
    for i = 1, 4 do out[#out + 1] = tostring(math.random(0, 9)) end
    for i = 1, 3 do local n = math.random(1, #LETTERS); out[#out + 1] = LETTERS:sub(n, n) end
    for i = 1, 4 do out[#out + 1] = tostring(math.random(0, 9)) end
    return table.concat(out)
end

local function carriedBackpacks(src)
    local total, first = 0, nil
    for _, b in ipairs(Config.Backpacks) do
        local n = JRS.Count(src, b.item)
        if n > 0 then
            total = total + n
            first = first or b.item
        end
    end
    return total, first
end

local function storageId(serial) return 'backpack_' .. serial end

local function openBackpack(src, cfg, item)
    if not JRS.Cooldown(src, 'open', Config.UseCooldown) then return end
    if Config.OneBackpackOnly and carriedBackpacks(src) > 1 then
        return JRS.Notify(src, L('only_one'))
    end

    local meta = type(item.metadata) == 'table' and item.metadata or {}
    local serial = meta.serial
    if type(serial) ~= 'string' or not serial:match('^%w+$') or #serial > 16 then
        -- first use: stamp a serial on this exact item
        serial = newSerial()
        local newMeta = {}
        for k, v in pairs(meta) do newMeta[k] = v end
        newMeta.serial = serial
        newMeta.description = L('serial', serial)
        if not exports.jrs_inventory:setItemMetadata(src, item.id, newMeta, 1) then
            return JRS.Notify(src, L('failed'))
        end
    end

    local id = storageId(serial)
    exports.jrs_inventory:registerInventory({ id = id, name = L('title'), limit = cfg.slots })
    JRS.CloseInventory(src)
    TriggerClientEvent('jrs_backpacks:client:wear', src, cfg.item)
    SetTimeout(250, function()
        exports.jrs_inventory:openInventory(src, id)
    end)
end

for _, cfg in ipairs(Config.Backpacks) do
    JRS.Usable(cfg.item, function(src, item)
        if JRS.Char(src) and type(item) == 'table' then openBackpack(src, cfg, item) end
    end)
end

-- which backpack (if any) the player carries -> the prop on their back
JRS.Callback('jrs_backpacks:carried', function(src)
    local _, item = carriedBackpacks(src)
    return item
end)
