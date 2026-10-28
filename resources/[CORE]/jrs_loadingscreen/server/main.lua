-- ==========================================================================
--  JRS CORE  |  jrs_loadingscreen  |  server/main.lua
--  Clean Native Loading Screen Server Logic for JRS Core
-- ==========================================================================

local STEAM_API = 'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/'
local DISCORD_API = 'https://discord.com/api/v10/'

local steamAvatarCache = {}
local discordProfileCache = {}
local discordAvatarByIdentifier = {}

local MAX_NAME_LEN = 48
local AVATAR_HOSTS = {
    ['avatars.steamstatic.com'] = true,
    ['avatars.akamai.steamstatic.com'] = true,
    ['avatars.cloudflare.steamstatic.com'] = true,
    ['steamcdn-a.akamaihd.net'] = true,
    ['cdn.discordapp.com'] = true,
    ['media.discordapp.net'] = true,
}

local function debugPrint(message)
    if Config.Debug then
        print(('[jrs_loadingscreen] %s'):format(message))
    end
end

-- Sanitize player name, preserving UTF-8 multi-byte characters (such as Arabic)
local function sanitizeText(value, maxLen)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[\0-\31\127]', ''):gsub('~[%w_]-~', ''):gsub('%^%d', '')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end

    if #value > maxLen then
        local cut = maxLen
        while cut > 0 and (value:byte(cut + 1) or 0) >= 0x80 and (value:byte(cut + 1) or 0) < 0xC0 do
            cut = cut - 1
        end
        value = value:sub(1, cut)
    end
    return value
end

local function sanitizeAvatarUrl(url)
    if type(url) ~= 'string' or #url > 512 then return nil end
    if url:find('[%s"\'<>\\]') then return nil end
    local host = url:match('^https://([%w%.%-]+)/')
    if not host or not AVATAR_HOSTS[host:lower()] then return nil end
    return url
end

local function getDefaultAvatar()
    return (Config.PlayerAvatar and Config.PlayerAvatar.defaultAvatar) or 'assets/images/default_avatar.jpg'
end

local function getSteamApiKey()
    local convar = (Config.PlayerAvatar and Config.PlayerAvatar.steamApiKeyConvar) or 'jrs_loadingscreen_steam_api_key'
    local key = GetConvar(convar, '')
    if key ~= '' then return key end
    key = GetConvar('steam_webApiKey', '')
    if key ~= '' then return key end
    return nil
end

local function getDiscordToken()
    local convar = (Config.Discord and Config.Discord.tokenConvar) or 'jrs_loadingscreen_discord_token'
    local token = GetConvar(convar, '')
    if token ~= '' then return token end
    return nil
end

local function getIdentifier(src, prefix)
    local num = GetNumPlayerIdentifiers(src)
    for i = 0, num - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, #prefix):lower() == prefix:lower() then
            return id:sub(#prefix + 1)
        end
    end
    return nil
end

-- Converts Steam hex identifier to standard 64-bit SteamID using native 64-bit integer
local function steamHexToSteamId64(hex)
    if type(hex) ~= 'string' or hex == '' then return nil end
    local cleanHex = hex:gsub('^steam:', ''):lower()
    local num = tonumber(cleanHex, 16)
    if not num or num <= 0 then return nil end
    return string.format('%.0f', num)
end

-- Asynchronous HTTP GET helper with timeout
local function httpGet(url, headers)
    local p = promise.new()
    local settled = false
    local timeoutMs = math.max(1000, tonumber(Config.ProfileLookup and Config.ProfileLookup.httpTimeoutMs) or 5000)

    local function finish(payload)
        if settled then return end
        settled = true
        p:resolve(payload)
    end

    PerformHttpRequest(url, function(status, body, respHeaders)
        finish({ status = status, body = body, headers = respHeaders })
    end, 'GET', '', headers or {})

    SetTimeout(timeoutMs, function()
        finish({ status = 0, body = nil, headers = {}, timedOut = true })
    end)

    return Citizen.Await(p)
end

local function fetchSteamAvatar(steamId64)
    if not steamId64 then return nil end
    local cached = steamAvatarCache[steamId64]
    if cached and (cached.expiresAt or 0) > os.time() then
        return cached.url
    end

    local apiKey = getSteamApiKey()
    if not apiKey then return nil end

    local url = ('%s?key=%s&steamids=%s'):format(STEAM_API, apiKey, steamId64)
    local resp = httpGet(url)
    if not resp or resp.status ~= 200 or not resp.body then return nil end

    local ok, data = pcall(json.decode, resp.body)
    if not ok or type(data) ~= 'table' or not data.response or not data.response.players then
        return nil
    end

    local player = data.response.players[1]
    if not player then return nil end

    local avatarUrl = player.avatarfull or player.avatarmedium or player.avatar
    avatarUrl = sanitizeAvatarUrl(avatarUrl)

    if avatarUrl then
        local cacheTtl = tonumber(Config.PlayerAvatar and Config.PlayerAvatar.cacheSeconds) or 900
        steamAvatarCache[steamId64] = {
            url = avatarUrl,
            expiresAt = os.time() + cacheTtl,
        }
    end

    return avatarUrl
end

local function fetchDiscordUser(discordId)
    if not discordId then return nil end
    local cached = discordProfileCache[discordId]
    if cached and (cached.expiresAt or 0) > os.time() then
        return cached.data
    end

    local token = getDiscordToken()
    if not token then return nil end

    local headers = {
        ['Authorization'] = 'Bot ' .. token,
        ['User-Agent'] = 'DiscordBot (JRS-Core, 1.0)',
    }

    local guildId = Config.Discord and Config.Discord.guildId or ''
    local url = (guildId ~= '')
        and ('%sguilds/%s/members/%s'):format(DISCORD_API, guildId, discordId)
        or ('%susers/%s'):format(DISCORD_API, discordId)

    local resp = httpGet(url, headers)
    if not resp or resp.status ~= 200 or not resp.body then return nil end

    local ok, raw = pcall(json.decode, resp.body)
    if not ok or type(raw) ~= 'table' then return nil end

    local userObj = raw.user or raw
    local avatarHash = raw.avatar or userObj.avatar
    local avatarUrl = nil

    if avatarHash and avatarHash ~= '' then
        if raw.avatar and guildId ~= '' then
            avatarUrl = ('https://cdn.discordapp.com/guilds/%s/users/%s/avatars/%s.png'):format(guildId, discordId, avatarHash)
        else
            avatarUrl = ('https://cdn.discordapp.com/avatars/%s/%s.png'):format(discordId, avatarHash)
        end
    end

    local displayRole = ''
    if type(raw.roles) == 'table' and type(Config.Discord.roles) == 'table' then
        for _, rId in ipairs(raw.roles) do
            local title = Config.Discord.roles[tostring(rId)]
            if title then
                displayRole = title
                break
            end
        end
    end

    local profile = {
        avatarUrl = sanitizeAvatarUrl(avatarUrl),
        role = displayRole,
    }

    local cacheTtl = tonumber(Config.PlayerAvatar and Config.PlayerAvatar.cacheSeconds) or 900
    discordProfileCache[discordId] = {
        data = profile,
        expiresAt = os.time() + cacheTtl,
    }

    return profile
end

-- Primary player connecting handler for loading screen handover
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    local usingDeferral = deferrals and type(deferrals.handover) == 'function'

    if not usingDeferral then return end

    deferrals.defer()
    Wait(50)

    local rawName = GetPlayerName(src) or playerName or 'Outsider'
    local cleanName = sanitizeText(rawName, MAX_NAME_LEN) or 'Outsider'

    local steamHex = getIdentifier(src, 'steam:')
    local discordId = getIdentifier(src, 'discord:')

    local avatarSource = 'default'
    local avatarUrl = getDefaultAvatar()
    local displayRole = ''

    local avatarCfg = Config.PlayerAvatar or {}
    local sourceMode = tostring(avatarCfg.source or 'auto'):lower()

    if avatarCfg.enabled ~= false then
        if sourceMode == 'steam' or sourceMode == 'auto' then
            local steam64 = steamHexToSteamId64(steamHex)
            if steam64 then
                local sUrl = fetchSteamAvatar(steam64)
                if sUrl then
                    avatarUrl = sUrl
                    avatarSource = 'steam'
                end
            end
        end

        if avatarSource == 'default' and (sourceMode == 'discord' or sourceMode == 'auto') and discordId then
            local dProfile = fetchDiscordUser(discordId)
            if dProfile then
                if dProfile.avatarUrl then
                    avatarUrl = dProfile.avatarUrl
                    avatarSource = 'discord'
                    discordAvatarByIdentifier[discordId] = avatarUrl
                end
                if dProfile.role and dProfile.role ~= '' then
                    displayRole = dProfile.role
                end
            end
        end
    end

    local maxSlots = GetConvarInt('sv_maxclients', 48)
    local currentCount = #GetPlayers()

    deferrals.handover({
        name = cleanName,
        avatarUrl = avatarUrl,
        avatarSource = avatarSource,
        role = displayRole,
        maxPlayers = maxSlots,
        currentPlayers = currentCount,
    })

    Wait(50)
    deferrals.done()
end)

AddEventHandler('playerDropped', function()
    local src = source
    local discordId = getIdentifier(src, 'discord:')
    if discordId then
        discordAvatarByIdentifier[discordId] = nil
    end
end)

-- Public Framework Exports
exports('GetPlayerAvatarUrl', function(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil end

    local steamHex = getIdentifier(src, 'steam:')
    local steam64 = steamHexToSteamId64(steamHex)
    if steam64 and steamAvatarCache[steam64] then
        return steamAvatarCache[steam64].url
    end

    local discordId = getIdentifier(src, 'discord:')
    if discordId and discordAvatarByIdentifier[discordId] then
        return discordAvatarByIdentifier[discordId]
    end

    return getDefaultAvatar()
end)

exports('GetPlayerCount', function()
    return #GetPlayers()
end)

exports('GetDisplayPlayerCount', function()
    return #GetPlayers()
end)

exports('GetListedPlayerCount', function()
    return #GetPlayers()
end)

exports('GetListedMaxClients', function()
    return GetConvarInt('sv_maxclients', 48)
end)

exports('IncludeBots', function()
    return false
end)
