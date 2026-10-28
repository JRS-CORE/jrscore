-- ==========================================================================
--  JRS CORE  |  jrs_loadingscreen  |  config/server.lua
--  Native Loading Screen Configuration for JRS Core
-- ==========================================================================

Config = Config or {}

Config.Debug = false

Config.ProfileLookup = {
    -- Maximum wait time for Steam or Discord API response before falling back to default
    httpTimeoutMs = 5000,
}

-- Player card avatar resolution.
-- Options:
-- 'auto'    = Steam first -> Discord -> local default image
-- 'steam'   = Steam only   -> local default image
-- 'discord' = Discord only -> local default image
-- 'default' = always use the local default image
Config.PlayerAvatar = {
    enabled = true,
    source = 'auto',
    steam = true,
    defaultAvatar = 'assets/images/default_avatar.jpg',

    -- Steam Web API key convar. Set in server.cfg:
    -- set jrs_loadingscreen_steam_api_key "YOUR_STEAM_KEY"
    steamApiKeyConvar = 'jrs_loadingscreen_steam_api_key',

    -- Cache duration for player avatars (in seconds, default 15 minutes)
    cacheSeconds = 900,
}

Config.Discord = {
    enabled = true,

    -- Set to true if Discord membership in your guild is required
    requireDiscord = false,
    guildId = '',

    -- Discord Bot Token convar. Set in server.cfg:
    -- set jrs_loadingscreen_discord_token "YOUR_DISCORD_BOT_TOKEN"
    tokenConvar = 'jrs_loadingscreen_discord_token',

    -- Map Discord role IDs to display titles on the loading screen:
    -- ['ROLE_ID'] = 'ROLE_TITLE'
    roles = {
        -- ['123456789012345678'] = 'Server Owner',
    },
}

-- Real-time player counter configuration
Config.PlayerCount = {
    -- Uses real connected players (#GetPlayers())
    includeBots = false,
}
