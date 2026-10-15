-- ============================================================================
-- jrs_inventory / shared/personal_items.lua
-- Personal-only item lookup.
--
-- Moved out of config/config.lua (2026-09-18 config cleanup) so that file
-- stays values-only for buyers. The data (Config.PersonalItems) still lives
-- in config/config.lua; only the lookup logic lives here. Shared so it runs
-- identically on both client and server, which both call
-- Config.IsPersonalItem(itemName).
-- ============================================================================

local personalItemLookup = {}
for _, itemName in ipairs(Config.PersonalItems) do
    personalItemLookup[string.lower(tostring(itemName))] = true
end

function Config.IsPersonalItem(itemName)
    return itemName ~= nil and personalItemLookup[string.lower(tostring(itemName))] == true
end

-- Job resources that may not change hands between players (see
-- Config.NoTransferItems). Storage is allowed, give/drop/trade are not.
local noTransferLookup = {}
for _, itemName in ipairs(Config.NoTransferItems or {}) do
    noTransferLookup[string.lower(tostring(itemName))] = true
end

function Config.IsNoTransferItem(itemName)
    return itemName ~= nil and noTransferLookup[string.lower(tostring(itemName))] == true
end
