-- ============================================================================
-- jrs_inventory / shared/player_interactions.lua
-- Player-interaction settings bridge to jrs_core.
--
-- Moved out of config/config.lua (2026-09-18 config cleanup) so that file
-- stays values-only for buyers. Player interaction toggles themselves now
-- live in jrs_core's config (Config.PlayerInteractions); this just fetches
-- them. Shared so it runs identically on both client and server, which both
-- call Config.GetPlayerInteractions().
-- ============================================================================

function Config.GetPlayerInteractions()
	local ok, settings = pcall(function()
		return exports['jrs_core']:GetPlayerInteractionsConfig()
	end)
	if ok and type(settings) == 'table' then return settings end
	return { Enabled = false }
end
