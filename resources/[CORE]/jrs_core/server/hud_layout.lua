local HUD_LAYOUT_TABLE = 'jrs_core_hud_layouts'
local tableReady = false
local pendingRequests = {}
local lastRequestAt = {}
local lastSaveAt = {}
local loadLayoutForSource
local allowedElements = {
    PlayerGold = true,
    PlayerMoney = true,
    PlayerDirtyMoney = true,
    id = true,
    job = true,
    xp = true,
    town = true,
    pvp = true,
    doubleXpHud = true,
}

-- Matches html/main.js's own CROSSHAIR_COLORS keys - a fixed palette rather
-- than an arbitrary hex, since the reticle is a tinted raster PNG, not text
-- or an SVG path that could just take a plain colour.
local allowedCrosshairColors = {
    white = true, red = true, green = true, blue = true, yellow = true,
    pink = true, purple = true, cyan = true, orange = true, black = true,
}

local function sanitizeCrosshairColor(value)
    if type(value) == 'string' and allowedCrosshairColors[value] then return value end
    return 'white'
end

-- 0 = game default reticle, 1..12 = custom shapes. Saves from before the
-- dedicated default tile carry no v=2 stamp, and there shape 1 meant "game
-- default" - keep it that way so nobody's reticle changes on its own.
local CROSSHAIR_LAYOUT_VERSION = 2

local function sanitizeCrosshairShape(value, version)
    local shape = math.floor(tonumber(value) or 0)
    if shape ~= shape then shape = 0 end
    if tonumber(version) ~= CROSSHAIR_LAYOUT_VERSION and shape == 1 then shape = 0 end
    return math.max(0, math.min(12, shape))
end

local function initializeHudLayoutTable()
    exports.oxmysql:execute(([=[
        CREATE TABLE IF NOT EXISTS `%s` (
            `identifier` VARCHAR(100) NOT NULL,
            `charidentifier` INT NOT NULL,
            `layout` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `charidentifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]=]):format(HUD_LAYOUT_TABLE), {}, function()
        tableReady = true
        for src in pairs(pendingRequests) do
            pendingRequests[src] = nil
            if loadLayoutForSource then loadLayoutForSource(src) end
        end
    end)
end

local function getAuthoritativeCharacter(playerSource)
    local src = tonumber(playerSource)
    if not src or src <= 0 or not jrsCore.IsCharacterReady(src) then return nil end
    local character = jrsCore.GetCharacter(src)
    if type(character) ~= 'table' or character.identifier == nil or character.charIdentifier == nil then return nil end
    return character
end

-- #rrggbb only, matching html/main.js's own HEX_COLOR_RE - anything else
-- (missing, malformed, an attempted CSS injection) is dropped rather than
-- saved, same as every other field here.
local function sanitizeHexColor(value)
    if type(value) ~= 'string' then return nil end
    if not value:match('^#%x%x%x%x%x%x$') then return nil end
    return value
end

-- Global on purpose (not `local`) - this file loads before hud_export.lua in
-- fxmanifest.lua's explicit server_scripts list, so the export handler can
-- reuse this exact same validation on the layout it receives from the NUI,
-- rather than trusting client-sent data or duplicating the rules.
function sanitizeLayout(layout)
    if type(layout) ~= 'table' then return nil end
    local clean = {}
    local count = 0

    if type(layout.crosshair) == 'table' then
        clean.crosshair = {
            shape = sanitizeCrosshairShape(layout.crosshair.shape, layout.crosshair.v),
            color = sanitizeCrosshairColor(layout.crosshair.color),
            v = CROSSHAIR_LAYOUT_VERSION,
        }
    end

    for elementId, point in pairs(layout) do
        if elementId ~= 'crosshair' and allowedElements[elementId] and type(point) == 'table' then
            local x = tonumber(point.x)
            local y = tonumber(point.y)
            if x and y and x == x and y == y then
                local scale = tonumber(point.scale) or 1.0
                if scale ~= scale then scale = 1.0 end
                clean[elementId] = {
                    x = math.max(0.0, math.min(1.0, x)),
                    y = math.max(0.0, math.min(1.0, y)),
                    scale = math.max(0.5, math.min(1.8, scale)),
                    visible = false, -- All core HUD elements are permanently inactive ("غير نشط")
                    color = sanitizeHexColor(point.color),
                }
                count = count + 1
            end
        end
        if count >= 10 then break end
    end

    return clean
end

local function sameCharacter(left, right)
    return type(left) == 'table'
        and type(right) == 'table'
        and tostring(left.identifier) == tostring(right.identifier)
        and tostring(left.charIdentifier) == tostring(right.charIdentifier)
end

loadLayoutForSource = function(src)
    local requestedCharacter = getAuthoritativeCharacter(src)
    if not requestedCharacter then return end

    local identifier = tostring(requestedCharacter.identifier)
    local charId = tonumber(requestedCharacter.charIdentifier) or requestedCharacter.charIdentifier
    exports.oxmysql:fetch(
        ('SELECT `layout` FROM `%s` WHERE `identifier` = ? AND `charidentifier` = ? LIMIT 1'):format(HUD_LAYOUT_TABLE),
        { identifier, charId },
        function(rows)
            if GetPlayerPing(src) <= 0 then return end
            local activeCharacter = getAuthoritativeCharacter(src)
            if not sameCharacter(requestedCharacter, activeCharacter) then return end

            local layout = nil
            if rows and rows[1] and type(rows[1].layout) == 'string' then
                local ok, decoded = pcall(json.decode, rows[1].layout)
                if ok then layout = sanitizeLayout(decoded) end
            end

            -- No saved row for this character yet - fall back to the exported/
            -- admin-set house default (server/hud_export.lua) instead of an
            -- empty table, so a fresh character actually sees whatever an
            -- admin exported, not just the NUI's own hardcoded CSS positions.
            if not layout or next(layout) == nil then
                layout = sanitizeLayout(Config.HudDefaultLayout) or {}
            end

            -- isAdmin() is defined (as a global) in hud_export.lua - reused
            -- here so the NUI knows whether to show the Developer/"Export
            -- Defaults" section at all, on top of hud_export.lua's own
            -- server-side enforcement.
            TriggerClientEvent('jrs_core:hud:applyLayout', src, layout, charId, isAdmin(src))
        end
    )
end

RegisterNetEvent('jrs_core:hud:requestLayout', function()
    local src = tonumber(source)
    if not src then return end

    local now = GetGameTimer()
    if lastRequestAt[src] and now - lastRequestAt[src] < 500 then return end
    lastRequestAt[src] = now

    if not tableReady then
        pendingRequests[src] = true
        return
    end
    loadLayoutForSource(src)
end)

RegisterNetEvent('jrs_core:hud:saveLayout', function(layout)
    local src = tonumber(source)
    if not src then return end

    local now = GetGameTimer()
    if lastSaveAt[src] and now - lastSaveAt[src] < 750 then return end
    lastSaveAt[src] = now

    local character = getAuthoritativeCharacter(src)
    local clean = sanitizeLayout(layout)
    if not character or not clean then return end

    exports.oxmysql:execute(
        ('INSERT INTO `%s` (`identifier`, `charidentifier`, `layout`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `layout` = VALUES(`layout`)'):format(HUD_LAYOUT_TABLE),
        {
            tostring(character.identifier),
            tonumber(character.charIdentifier) or character.charIdentifier,
            json.encode(clean),
        }
    )
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    pendingRequests[src] = nil
    lastRequestAt[src] = nil
    lastSaveAt[src] = nil
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    initializeHudLayoutTable()
end)
