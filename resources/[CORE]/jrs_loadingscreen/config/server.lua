-- ==========================================================================
--  JRS CORE  |  jrs_loadingscreen  |  config/server.lua
--  JRS Loading Screen - RedM / jrs_core compatible
-- ==========================================================================

Config = Config or {}


Config.ProfileLookup = {
    -- Prevent a slow Steam/Discord endpoint from holding a player in the
    -- connecting state indefinitely. Timed-out lookups fall back normally.
    httpTimeoutMs = 5000,
}

-- Player card avatar resolution.
-- auto    = Steam first -> Discord -> local default image
-- steam   = Steam only   -> local default image
-- discord = Discord only -> local default image
-- default = always use the local default image
Config.PlayerAvatar = {
    enabled = true,
    source = 'auto',

    -- Steam profile pictures: true = show, false = hidden (Discord/default still show).
    steam = true,

    defaultAvatar = 'assets/images/default_avatar.jpg',

    -- NEVER paste your Steam Web API key in this resource.
    -- Add this to server.cfg instead:
    -- set jrs_loadingscreen_steam_api_key "YOUR_STEAM_WEB_API_KEY"
    steamApiKeyConvar = 'jrs_loadingscreen_steam_api_key',

    -- If the Web API key is missing or the API lookup fails, try the public
    -- Steam Community profile XML as a best-effort fallback.
    communityFallback = true,

    -- Avoid repeated Steam API requests when a player reconnects.
    cacheSeconds = 900,
}

Config.Discord = {
    enabled = true,

    -- false = players without Discord can still join and receive fallback profile data.
    -- true  = players must have a Discord identifier and must exist in your guild.
    requireDiscord = false,

    guildId = '',

    -- NEVER paste the bot token in this file.
    -- Add this to server.cfg instead:
    -- set jrs_loadingscreen_discord_token "YOUR_BOT_TOKEN"
    tokenConvar = 'jrs_loadingscreen_discord_token',

    -- Use Discord snowflakes as strings.
    roles = {
        -- ['123456789012345678'] = 'server owner',
    },
}

-- Player count shown on the loading screen (and reused by jrs_admin).
-- Reads the server's own /dynamic.json, the same number txAdmin and the
-- server browser show (real players + [CFXBOT] Background_Service bots).
-- Falls back to the real #GetPlayers() count if the request fails.
--
-- includeBots = false -> every count (loading screen, admin panel + Live Map +
-- blips, pause menu, Discord rich presence) shows REAL connected players only.
-- includeBots = true  -> old behaviour (txAdmin/dynamic.json number + bots).
-- holdSeconds: if txAdmin's number can't be read for a while, the last known
-- bot count is kept (added to the live real count) for this long, so the
-- number never suddenly drops back to real players only. Default 6 h.
--
-- 2.10.0: the main source is now the Cfx server list itself (the same number
-- the server browser shows, e.g. 11/80), read by the join code below.
-- /dynamic.json stays as a second source; the highest fresh number wins.
-- The count goes up at once but only goes down after a lower number has been
-- seen for dropAfterSeconds in a row, and never in the first bootGraceSeconds
-- after a restart, so a slow API or a restart never flashes "2/80".
Config.PlayerCount = {
    includeBots = true,
    holdSeconds = 21600,

    -- Cfx server list (cfx.re/join/<code>). Empty = read it from the CONNECT
    -- button in jrs_core/config/config.lua. "set jrs_cfx_join_id" overrides.
    useServerListCount = true,
    cfxJoinId = '8eeyxqv',
    listRefreshMs = 60000,

    -- Local /dynamic.json (second source).
    useDynamicJson = true,
    url = 'http://127.0.0.1:30120/dynamic.json',
    refreshMs = 15000,

    freshSeconds = 180,       -- a reading counts as live for this long
    dropAfterSeconds = 600,   -- lower number must last 10 min before it shows
    bootGraceSeconds = 600,   -- no drops in the first 10 min after a restart
}
