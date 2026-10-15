local getDisplayPlayerCount -- defined near the bottom (player count poller)
local getDisplayMaxClients  -- same
local DISCORD_API = 'https://discord.com/api/v10/'
local STEAM_API = 'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/'
local STEAM_COMMUNITY_PROFILE = 'https://steamcommunity.com/profiles/%s/?xml=1'

local steamAvatarCache = {}
local steamInFlight = {}
local discordProfileCache = {}

local function debugPrint(message)
    if Config.Debug then
-- REMOVED-PRINT:         print(('[jrs_loadingscreen] %s'):format(message))
    end
end

-- 2.8.0: everything that reaches the loadscreen handover is cleaned here.
-- Names come from the player (Cfx name / Discord nick), picture URLs from
-- third-party responses, so neither is trusted as-is.
local MAX_NAME_LEN = 48

local function sanitizeText(value, maxLen)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[\0-\31\127]', ''):gsub('~[%w_]-~', ''):gsub('%^%d', '')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    if #value > maxLen then
        -- Cut on a UTF-8 boundary so Arabic names are never split mid-character.
        local cut = maxLen
        while cut > 0 and (value:byte(cut + 1) or 0) >= 0x80 and (value:byte(cut + 1) or 0) < 0xC0 do
            cut = cut - 1
        end
        value = value:sub(1, cut)
    end
    return value
end

local AVATAR_HOSTS = {
    'avatars.steamstatic.com', 'avatars.akamai.steamstatic.com',
    'avatars.cloudflare.steamstatic.com', 'steamcdn-a.akamaihd.net',
    'cdn.discordapp.com', 'media.discordapp.net',
}

local function sanitizeAvatarUrl(url)
    if type(url) ~= 'string' or #url > 512 then return nil end
    if url:find('[%s"\'<>\\]') then return nil end
    local host = url:match('^https://([%w%.%-]+)/')
    if not host then return nil end
    host = host:lower()
    for _, allowed in ipairs(AVATAR_HOSTS) do
        if host == allowed then return url end
    end
    return nil
end

local function pruneExpired(cache)
    local now = os.time()
    for key, entry in pairs(cache) do
        if type(entry) ~= 'table' or (entry.expiresAt or 0) <= now then
            cache[key] = nil
        end
    end
end

local function getDefaultAvatar()
    return (Config.PlayerAvatar and Config.PlayerAvatar.defaultAvatar) or 'assets/images/default_avatar.jpg'
end

local function getDiscordToken()
    local convarName = Config.Discord.tokenConvar or 'jrs_loadingscreen_discord_token'
    local token = GetConvar(convarName, '')
    if token == '' then return nil end
    return token
end

local function getSteamApiKey()
    local convarName = (Config.PlayerAvatar and Config.PlayerAvatar.steamApiKeyConvar) or 'jrs_loadingscreen_steam_api_key'
    local key = GetConvar(convarName, '')
    if key ~= '' then return key end

    -- Fall back to FXServer's own `steam_webApiKey` convar. Servers already set
    -- this in server.cfg for RedM's own Steam ticket validation, and it is the
    -- same kind of standard Web API key GetPlayerSummaries needs - no reason to
    -- require a second, duplicate convar just for this resource.
    key = GetConvar('steam_webApiKey', '')
    if key == '' then return nil end
    return key
end

local function httpGet(url, headers)
    local p = promise.new()
    local settled = false
    local timeoutMs = math.max(1000, tonumber(Config.ProfileLookup and Config.ProfileLookup.httpTimeoutMs) or 5000)

    local function finish(payload)
        if settled then return end
        settled = true
        p:resolve(payload)
    end

    PerformHttpRequest(url, function(code, data, responseHeaders)
        finish({
            code = code,
            data = data,
            headers = responseHeaders,
        })
    end, 'GET', '', headers or {
        ['Accept'] = 'application/json',
    })

    SetTimeout(timeoutMs, function()
        finish({
            code = 0,
            data = '',
            headers = {},
            timedOut = true,
        })
    end)

    return Citizen.Await(p)
end

local function discordRequest(endpoint)
    local token = getDiscordToken()
    if not token then
        return nil, 'missing_token'
    end

    local response = httpGet(DISCORD_API .. endpoint, {
        ['Accept'] = 'application/json',
        ['Authorization'] = 'Bot ' .. token,
    })

    if not response then
        return nil, 'request_failed'
    end

    return response
end

local function getIdentifierByPrefix(src, prefix)
    local identifierType = prefix:gsub(':$', '')
    if type(GetPlayerIdentifierByType) == 'function' then
        local direct = GetPlayerIdentifierByType(src, identifierType)
        if direct and direct ~= '' then
            return direct
        end
    end

    for _, value in ipairs(GetPlayerIdentifiers(src)) do
        if value:sub(1, #prefix) == prefix then
            return value
        end
    end

    return nil
end

local function getDiscordIdentifier(src)
    return getIdentifierByPrefix(src, 'discord:')
end

local function getSteamIdentifier(src)
    return getIdentifierByPrefix(src, 'steam:')
end

-- RedM/FiveM exposes the Steam identifier as hexadecimal (steam:1100001...).
-- Steam's GetPlayerSummaries API expects the unsigned SteamID64 as a decimal string.
-- Lua numbers cannot safely represent every uint64 value, so this conversion uses
-- string arithmetic and never converts the full identifier to a floating-point number.
local function multiplyDecimalString(value, multiplier)
    local carry = 0
    local out = {}

    for i = #value, 1, -1 do
        local digit = tonumber(value:sub(i, i)) or 0
        local product = digit * multiplier + carry
        out[#out + 1] = tostring(product % 10)
        carry = math.floor(product / 10)
    end

    while carry > 0 do
        out[#out + 1] = tostring(carry % 10)
        carry = math.floor(carry / 10)
    end

    local reversed = {}
    for i = #out, 1, -1 do
        reversed[#reversed + 1] = out[i]
    end

    return table.concat(reversed)
end

local function addDecimalSmall(value, addend)
    local carry = addend
    local out = {}

    for i = #value, 1, -1 do
        local digit = tonumber(value:sub(i, i)) or 0
        local sum = digit + carry
        out[#out + 1] = tostring(sum % 10)
        carry = math.floor(sum / 10)
    end

    while carry > 0 do
        out[#out + 1] = tostring(carry % 10)
        carry = math.floor(carry / 10)
    end

    local reversed = {}
    for i = #out, 1, -1 do
        reversed[#reversed + 1] = out[i]
    end

    return table.concat(reversed)
end

local function hexToDecimalString(hexValue)
    if type(hexValue) ~= 'string' or hexValue == '' then return nil end

    local result = '0'
    for i = 1, #hexValue do
        local nibble = tonumber(hexValue:sub(i, i), 16)
        if nibble == nil then return nil end
        result = multiplyDecimalString(result, 16)
        if nibble > 0 then
            result = addDecimalSmall(result, nibble)
        end
    end

    return result
end

local function steamIdentifierToSteamId64(identifier)
    if type(identifier) ~= 'string' then return nil end

    local hexValue = identifier:gsub('^steam:', '')
    if not hexValue:match('^%x+$') or #hexValue > 16 then return nil end

    return hexToDecimalString(hexValue)
end

local function getDefaultUserData(src)
    return {
        username = sanitizeText(GetPlayerName(src), MAX_NAME_LEN) or 'Outsider',
        avatarUrl = getDefaultAvatar(),
        displayRole = '',
        discordAvatarUrl = nil,
        steamAvatarUrl = nil,
        avatarSource = 'default',
    }
end

local function resolveDisplayRole(roles)
    if type(roles) ~= 'table' then return '' end

    for _, roleId in ipairs(roles) do
        local labels = (Config.Discord and Config.Discord.roles) or {}
        local label = labels[tostring(roleId)]
        if label then
            return label
        end
    end

    return ''
end

local function getDiscordUser(src, discordIdentifier)
    if not Config.Discord.enabled then
        return getDefaultUserData(src)
    end

    if not discordIdentifier then
        return nil, 'missing_discord'
    end

    local guildId = tostring(Config.Discord.guildId or '')
    if guildId == '' then
        return nil, 'missing_guild'
    end

    local discordId = discordIdentifier:gsub('discord:', '', 1)
    -- Snowflakes are digits only; anything else must never reach the API path.
    if not discordId:match('^%d+$') or #discordId > 20 or not guildId:match('^%d+$') then
        return nil, 'invalid_discord'
    end

    -- Reconnect spam must not turn into Discord API spam (429 / Cloudflare ban
    -- on the bot token). Successes cache for cacheSeconds, "not a member" for 60s.
    local cachedProfile = discordProfileCache[discordId]
    if cachedProfile and cachedProfile.expiresAt > os.time() then
        if cachedProfile.data then
            local copy = {}
            for k, v in pairs(cachedProfile.data) do copy[k] = v end
            return copy
        end
        return nil, cachedProfile.err
    end

    local response, requestError = discordRequest(('guilds/%s/members/%s'):format(guildId, discordId))
    if not response then
        return nil, requestError
    end

    if response.timedOut then
        return nil, 'discord_timeout'
    end

    if response.code ~= 200 then
        debugPrint(('Discord lookup failed for %s with HTTP %s'):format(discordId, tostring(response.code)))
        local err = ('discord_http_%s'):format(tostring(response.code))
        if response.code == 404 then
            discordProfileCache[discordId] = { err = err, expiresAt = os.time() + 60 }
        end
        return nil, err
    end

    local ok, data = pcall(json.decode, response.data or '')
    if not ok or type(data) ~= 'table' or type(data.user) ~= 'table' then
        return nil, 'invalid_discord_response'
    end

    local user = data.user
    local username = sanitizeText(data.nick, MAX_NAME_LEN)
        or sanitizeText(user.global_name, MAX_NAME_LEN)
        or sanitizeText(user.username, MAX_NAME_LEN)
        or sanitizeText(GetPlayerName(src), MAX_NAME_LEN)
        or 'Outsider'
    if type(user.avatar) ~= 'string' or not user.avatar:match('^[%w_]+$') then
        user.avatar = nil
    end
    local discordAvatarUrl = nil

    if user.avatar and user.avatar ~= '' then
        local ext = user.avatar:sub(1, 2) == 'a_' and 'gif' or 'png'
        discordAvatarUrl = ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=256'):format(discordId, user.avatar, ext)
    else
        -- No custom avatar uploaded (very common). Without this, players who
        -- never set a Discord profile picture always fell through to the
        -- generic local placeholder even though Discord itself has a real
        -- default avatar for them - use that instead.
        local discriminator = tonumber(user.discriminator)
        local defaultIndex
        if discriminator and discriminator > 0 then
            defaultIndex = discriminator % 5
        else
            -- New Discord username system (discriminator "0") derives the
            -- index from (user_id >> 22) % 6. A snowflake id can exceed
            -- Lua's exact-integer range once JSON-decoded as a float, so
            -- fall back to a fixed index rather than risk a bad url.
            local idNumber = math.tointeger(tonumber(user.id))
            defaultIndex = idNumber and ((idNumber >> 22) % 6) or 0
        end
        discordAvatarUrl = ('https://cdn.discordapp.com/embed/avatars/%d.png'):format(defaultIndex)
    end

    local profile = {
        username = username,
        avatarUrl = discordAvatarUrl or getDefaultAvatar(),
        discordAvatarUrl = discordAvatarUrl,
        displayRole = resolveDisplayRole(data.roles),
        steamAvatarUrl = nil,
        avatarSource = discordAvatarUrl and 'discord' or 'default',
    }

    pruneExpired(discordProfileCache)
    local ttl = math.max(60, tonumber((Config.PlayerAvatar or {}).cacheSeconds) or 900)
    local stored = {}
    for k, v in pairs(profile) do stored[k] = v end
    discordProfileCache[discordId] = { data = stored, expiresAt = os.time() + ttl }

    return profile
end

local function getCachedSteamAvatar(steamId64)
    local entry = steamAvatarCache[steamId64]
    if not entry then return nil end

    if entry.expiresAt <= os.time() then
        steamAvatarCache[steamId64] = nil
        return nil
    end

    return entry.avatarUrl
end

local function cacheSteamAvatar(steamId64, avatarUrl)
    if not avatarUrl or avatarUrl == '' then return end

    pruneExpired(steamAvatarCache)
    local ttl = math.max(0, tonumber((Config.PlayerAvatar or {}).cacheSeconds) or 900)
    steamAvatarCache[steamId64] = {
        avatarUrl = avatarUrl,
        expiresAt = os.time() + ttl,
    }
end

local function decodeXmlText(value)
    if type(value) ~= 'string' then return nil end

    return value
        :gsub('&amp;', '&')
        :gsub('&quot;', '"')
        :gsub('&apos;', "'")
        :gsub('&lt;', '<')
        :gsub('&gt;', '>')
end

local function getSteamAvatarFromWebApi(steamId64)
    local apiKey = getSteamApiKey()
    if not apiKey then
        return nil, 'missing_steam_api_key'
    end

    local url = ('%s?key=%s&steamids=%s'):format(STEAM_API, apiKey, steamId64)
    local response = httpGet(url, {
        ['Accept'] = 'application/json',
    })

    if not response then
        return nil, 'steam_request_failed'
    end

    if response.timedOut then
        return nil, 'steam_timeout'
    end

    if response.code ~= 200 then
        return nil, ('steam_http_%s'):format(tostring(response.code))
    end

    local ok, data = pcall(json.decode, response.data or '')
    local players = ok and data and data.response and data.response.players
    local player = type(players) == 'table' and players[1] or nil

    if type(player) ~= 'table' then
        return nil, 'steam_player_not_found'
    end

    local avatarUrl = player.avatarfull or player.avatarmedium or player.avatar
    if type(avatarUrl) ~= 'string' or avatarUrl == '' then
        return nil, 'steam_avatar_missing'
    end

    return avatarUrl
end

local function getSteamAvatarFromCommunity(steamId64)
    local avatarConfig = Config.PlayerAvatar or {}
    if avatarConfig.communityFallback == false then
        return nil, 'steam_community_fallback_disabled'
    end

    local response = httpGet(STEAM_COMMUNITY_PROFILE:format(steamId64), {
        ['Accept'] = 'application/xml,text/xml;q=0.9,*/*;q=0.8',
        ['User-Agent'] = 'JRS-LoadingScreen/2.8.0',
    })

    if not response then
        return nil, 'steam_community_request_failed'
    end

    if response.timedOut then
        return nil, 'steam_community_timeout'
    end

    if response.code ~= 200 then
        return nil, ('steam_community_http_%s'):format(tostring(response.code))
    end

    local body = tostring(response.data or '')
    local avatarUrl = body:match('<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>')
        or body:match('<avatarFull>(.-)</avatarFull>')
        or body:match('<avatarMedium><!%[CDATA%[(.-)%]%]></avatarMedium>')
        or body:match('<avatarMedium>(.-)</avatarMedium>')

    avatarUrl = decodeXmlText(avatarUrl)
    if type(avatarUrl) ~= 'string' or avatarUrl == '' then
        return nil, 'steam_community_avatar_missing'
    end

    return avatarUrl
end

local function getSteamAvatar(src)
    local steamIdentifier = getSteamIdentifier(src)
    if not steamIdentifier then
        return nil, 'missing_steam_identifier'
    end

    local steamId64 = steamIdentifierToSteamId64(steamIdentifier)
    if not steamId64 then
        return nil, 'invalid_steam_identifier'
    end

    local cached = getCachedSteamAvatar(steamId64)
    if cached then
        return cached, 'cache'
    end

    -- One lookup per SteamID at a time: a reconnect loop or the admin list
    -- asking at the same moment waits on the same request instead of piling up.
    local waiting = steamInFlight[steamId64]
    if waiting then
        local result = Citizen.Await(waiting)
        if result and result.url then return result.url, 'steam' end
        return nil, (result and result.err) or 'steam_avatar_unavailable'
    end

    local p = promise.new()
    steamInFlight[steamId64] = p

    local ok, avatarUrl, lookupError = pcall(function()
        -- Preferred path: official Steam Web API. If no API key is configured or Steam's
        -- Web API is temporarily unavailable, the public Steam Community profile is used
        -- as a best-effort fallback so the loadscreen does not immediately fall back to
        -- the local placeholder image.
        local url, err = getSteamAvatarFromWebApi(steamId64)
        url = sanitizeAvatarUrl(url)
        if not url then
            url, err = getSteamAvatarFromCommunity(steamId64)
            url = sanitizeAvatarUrl(url)
        end
        return url, err
    end)
    if not ok then avatarUrl, lookupError = nil, 'steam_lookup_error' end

    steamInFlight[steamId64] = nil
    p:resolve({ url = avatarUrl, err = lookupError })

    if not avatarUrl then
        return nil, lookupError or 'steam_avatar_unavailable'
    end

    cacheSteamAvatar(steamId64, avatarUrl)
    return avatarUrl, 'steam'
end

-- Config.PlayerAvatar.steam = false turns Steam pictures off only; Discord
-- and the default picture keep working.
local function steamAvatarsOn()
    local avatarConfig = Config.PlayerAvatar or {}
    return avatarConfig.enabled ~= false and avatarConfig.steam ~= false
end

-- Discord picture per discord: identifier, saved at connect so other
-- resources (jrs_admin) can show it without a new HTTP request.
local discordAvatarByIdentifier = {}

local function resolveAvatar(src, userData)
    local avatarConfig = Config.PlayerAvatar or {}
    if avatarConfig.enabled == false then
        return getDefaultAvatar(), 'default'
    end

    local sourceMode = tostring(avatarConfig.source or 'auto'):lower()

    if (sourceMode == 'steam' or sourceMode == 'auto') and steamAvatarsOn() then
        local steamAvatar, steamError = getSteamAvatar(src)
        if steamAvatar then
            return steamAvatar, 'steam'
        end

        if Config.Debug and steamError then
            debugPrint(('Steam avatar fallback for %s: %s'):format(GetPlayerName(src) or tostring(src), steamError))
        end
    end

    if sourceMode == 'discord' or sourceMode == 'auto' then
        if userData and userData.discordAvatarUrl then
            return userData.discordAvatarUrl, 'discord'
        end
    end

    return getDefaultAvatar(), 'default'
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    local userData = getDefaultUserData(src)

    if Config.Debug then
        debugPrint(('Connecting profile identifiers for %s | steam=%s | discord=%s'):format(
            GetPlayerName(src) or tostring(src),
            getSteamIdentifier(src) or 'missing',
            getDiscordIdentifier(src) or 'missing'
        ))
    end

    local avatarConfig = Config.PlayerAvatar or {}
    local avatarMode = tostring(avatarConfig.source or 'auto'):lower()
    local steamLookupEnabled = steamAvatarsOn() and (avatarMode == 'auto' or avatarMode == 'steam')
    local usingDeferral = Config.Discord.enabled == true or steamLookupEnabled

    if usingDeferral then
        -- Profile lookups use async HTTP requests, so the connection must be deferred.
        deferrals.defer()
        Wait(0)
        deferrals.update(_UConn('loadingscree_loading_jrs_profile'))
    end

    -- 2.8.0: any error inside the lookups (bad JSON, missing config table, an
    -- HTTP edge case) used to leave the deferral open forever, holding the
    -- player on "Loading JRS profile..." until they gave up. The lookups now
    -- run protected; a failure falls back to the default profile.
    local ok, rejectMessage = pcall(function()
        if Config.Discord and Config.Discord.enabled then
            local discordIdentifier = getDiscordIdentifier(src)
            local discordData, discordError = getDiscordUser(src, discordIdentifier)

            if discordData then
                userData = discordData
            elseif Config.Discord.requireDiscord then
                local message = _UConn('discord_required')
                if discordError == 'missing_token' then
                    message = _UConn('discord_config_error')
                elseif discordError == 'missing_discord' then
                    message = _UConn('discord_missing')
                elseif discordError and discordError:find('discord_http_', 1, true) then
                    message = _UConn('discord_join_server')
                end
                return message
            end
        end

        local avatarUrl, avatarSource = resolveAvatar(src, userData)
        local discordIdentifier = getDiscordIdentifier(src)
        if discordIdentifier and userData.discordAvatarUrl then
            discordAvatarByIdentifier[discordIdentifier] = userData.discordAvatarUrl
        end
        userData.avatarUrl = avatarUrl
        userData.avatarSource = avatarSource
        return nil
    end)

    if not ok then
        print(('^3[jrs_loadingscreen] profile lookup failed for %s: %s^7'):format(tostring(src), tostring(rejectMessage)))
        userData = getDefaultUserData(src)
    elseif rejectMessage then
        Wait(0)
        deferrals.done(rejectMessage)
        return
    end

    if Config.Debug then
        debugPrint(('Avatar selected for %s: %s | %s'):format(
            userData.username or GetPlayerName(src) or tostring(src),
            tostring(avatarSource),
            tostring(avatarUrl)
        ))
    end

    local avatarForScreen = userData.avatarUrl
    if avatarForScreen ~= getDefaultAvatar() then
        avatarForScreen = sanitizeAvatarUrl(avatarForScreen) or getDefaultAvatar()
    end

    local okCount, currentPlayers = pcall(getDisplayPlayerCount)

    deferrals.handover({
        name = sanitizeText(userData.username, MAX_NAME_LEN) or 'Outsider',
        avatarUrl = avatarForScreen,
        avatarSource = userData.avatarSource,
        role = sanitizeText(userData.displayRole, 32) or '',
        maxPlayers = (getDisplayMaxClients and getDisplayMaxClients()) or GetConvarInt('sv_maxclients', 48),
        currentPlayers = okCount and currentPlayers or #GetPlayers(),
    })

    if usingDeferral then
        Wait(0)
        deferrals.done()
    end
end)

-- Lets other resources (e.g. jrs_admin's player list) reuse the same
-- Steam avatar resolution + cache this resource already uses for the loadscreen,
-- instead of duplicating the Steam Web API / Community XML lookup logic.
exports('GetPlayerAvatarUrl', function(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil end

    local avatarConfig = Config.PlayerAvatar or {}
    if avatarConfig.enabled == false then return nil end

    local sourceMode = tostring(avatarConfig.source or 'auto'):lower()
    if (sourceMode == 'steam' or sourceMode == 'auto') and steamAvatarsOn() then
        -- 2.8.0: never block the caller on HTTP (the admin list asked for
        -- every row in turn, up to 10s each). Serve the cache; on a miss warm
        -- it in the background so the next call has it.
        local steamId64 = steamIdentifierToSteamId64(getSteamIdentifier(src))
        if steamId64 then
            local cached = getCachedSteamAvatar(steamId64)
            if cached then return cached end
            if not steamInFlight[steamId64] then
                CreateThread(function() pcall(getSteamAvatar, src) end)
            end
        end
    end

    if sourceMode == 'discord' or sourceMode == 'auto' then
        local discordIdentifier = getDiscordIdentifier(src)
        return discordIdentifier and discordAvatarByIdentifier[discordIdentifier] or nil
    end
    return nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    local discordIdentifier = getDiscordIdentifier(src)
    if discordIdentifier then
        discordAvatarByIdentifier[discordIdentifier] = nil
    end
end)

-- Displayed player count = the server-list/txAdmin number from /dynamic.json
-- (includes Background_Service bots). Polled in the background so deferrals
-- never wait on HTTP; never lower than the real connected count.
local listedPlayerCount = nil
local listedMaxClients = nil
local listedAt = 0

-- 2.7.2: /dynamic.json now answers "Route not found", so the bots are also
-- counted from the txAdmin bot list ('txsv:updateSyntheticPlayers', local event
-- from the monitor on every Background_Service heartbeat). KVP keeps the last
-- list so a restart counts them before the next heartbeat.
local SYNTHETIC_MAX = 256
local SYNTHETIC_STALE = 600
local syntheticIds = {}
local syntheticAt = 0
do
    local ok, saved = pcall(json.decode, GetResourceKvpString('synthetic_ids') or '[]')
    if ok and type(saved) == 'table' then
        -- 2.8.0: KVP now stores { at, ids }; the old bare list had no age, so
        -- a stopped Background_Service kept being counted after every restart.
        if type(saved.ids) == 'table' then
            syntheticIds = saved.ids
            syntheticAt = tonumber(saved.at) or 0
        else
            syntheticIds = saved
            syntheticAt = os.time()
        end
    end
end

-- 2.9.0: one switch for every player count on the server (see config/server.lua).
local function botsIncluded()
    return type(Config.PlayerCount) == 'table' and Config.PlayerCount.includeBots == true
end

if not botsIncluded() then
    syntheticIds, syntheticAt = {}, 0
    DeleteResourceKvp('synthetic_ids')
end

AddEventHandler('txsv:updateSyntheticPlayers', function(list)
    if not botsIncluded() then return end
    -- Local server event only (from the monitor). If anything ever makes the
    -- name net-registered, a client must still not be able to inflate counts.
    local src = tonumber(source)
    if src and src > 0 then return end
    if type(list) ~= 'table' then return end
    local ids, seen = {}, {}
    for _, p in ipairs(list) do
        local id = type(p) == 'table' and tonumber(p.id) or nil
        if id and id > 0 then
            id = math.floor(id)
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
                if #ids >= SYNTHETIC_MAX then break end
            end
        end
    end
    syntheticIds = ids
    syntheticAt = os.time()
    SetResourceKvp('synthetic_ids', json.encode({ at = syntheticAt, ids = ids }))
end)

local function syntheticCount()
    if syntheticAt == 0 or os.time() - syntheticAt >= SYNTHETIC_STALE then return 0 end
    local n = 0
    for _, id in ipairs(syntheticIds) do
        if not GetPlayerName(id) then n = n + 1 end
    end
    return n
end


-- 2.10.0: the card showed 2/80 while the server list said 11/80. The local
-- /dynamic.json only knows the real players, and every fresh read of it reset
-- the held bot count to 0. Now:
--   * the main source is the Cfx server-list API for this server's join code,
--     i.e. the exact number the server browser shows (bots included);
--   * /dynamic.json is only a second source - the highest fresh number wins;
--   * the bot count rises at once but only drops after a lower number has
--     been seen for dropAfterSeconds in a row, never in the first
--     bootGraceSeconds after a restart (bots reconnect slowly), and is kept
--     for holdSeconds (KVP, survives restarts) when every source is down.
local heldBots = 0
local heldAt = 0
local lowSince = 0
local lastLowAt = 0
local resourceStartedAt = os.time()
local sourceReads = {}   -- [name] = { clients = n, max = n, at = os.time() }

do
    local ok, saved = pcall(json.decode, GetResourceKvpString('held_bots') or '{}')
    if ok and type(saved) == 'table' then
        heldBots = math.max(0, math.floor(tonumber(saved.bots) or 0))
        heldAt = tonumber(saved.at) or 0
        local maxc = tonumber(saved.max)
        if maxc and maxc > 0 and maxc <= 4096 then listedMaxClients = math.floor(maxc) end
    end
end

local function countCfg()
    return type(Config.PlayerCount) == 'table' and Config.PlayerCount or {}
end

local function holdSeconds()
    return math.max(60, tonumber(countCfg().holdSeconds) or 21600)
end

local function saveHeld(force)
    local now = os.time()
    if force or now - (tonumber(GetResourceKvpInt('held_bots_saved')) or 0) >= 60 then
        SetResourceKvp('held_bots', json.encode({ bots = heldBots, at = heldAt, max = listedMaxClients }))
        SetResourceKvpInt('held_bots_saved', now)
    end
end

-- Feed one bot reading in. Rises apply now; drops need to last.
local function setHeldBots(bots)
    bots = math.max(0, math.floor(tonumber(bots) or 0))
    local now = os.time()
    local cfg = countCfg()
    local dropAfter = math.max(0, tonumber(cfg.dropAfterSeconds) or 600)
    local bootGrace = math.max(0, tonumber(cfg.bootGraceSeconds) or 600)

    if bots >= heldBots then
        local changed = bots ~= heldBots
        heldBots, heldAt, lowSince = bots, now, 0
        saveHeld(changed)
        return
    end

    -- Lower reading: keep the held number alive and start / continue the timer.
    heldAt = now
    if now - resourceStartedAt < bootGrace then
        lowSince = 0
        saveHeld(false)
        return
    end
    -- The lower readings have to be back to back; a gap (sources down)
    -- restarts the timer instead of dropping on the first new reading.
    if lowSince == 0 or now - lastLowAt > 180 then lowSince = now end
    lastLowAt = now
    if now - lowSince >= dropAfter then
        heldBots, lowSince = bots, 0
        saveHeld(true)
    else
        saveHeld(false)
    end
end

local function heldBotCount()
    if heldAt == 0 or os.time() - heldAt > holdSeconds() then return 0 end
    return heldBots
end

-- Highest fresh reading of all sources (nil when none is fresh).
local function freshListed()
    local now = os.time()
    local fresh = math.max(60, tonumber(countCfg().freshSeconds) or 180)
    local best
    for _, r in pairs(sourceReads) do
        if r.at and now - r.at <= fresh and r.clients and (not best or r.clients > best) then
            best = r.clients
        end
    end
    return best
end

local function onSourceRead(name, clients, maxc)
    clients = tonumber(clients)
    if not clients or clients < 0 or clients > 4096 then return end
    maxc = tonumber(maxc)
    if maxc and maxc > 0 and maxc <= 4096 then
        maxc = math.floor(maxc)
        -- The server list's max (what players see) wins over the local one.
        if name == 'cfxlist' or not (sourceReads.cfxlist and sourceReads.cfxlist.max) then
            listedMaxClients = maxc
        end
    else
        maxc = nil
    end
    sourceReads[name] = { clients = math.floor(clients), max = maxc, at = os.time() }
    listedPlayerCount = freshListed()
    listedAt = os.time()
    local bots = (listedPlayerCount or 0) - #GetPlayers()
    -- /dynamic.json is real players only on this host: once the server list
    -- has answered, it may raise the bot count but never lower it.
    if name ~= 'cfxlist' and sourceReads.cfxlist and bots < heldBots then return end
    setHeldBots(bots)
end

-- txAdmin bot list (if the monitor sends one) refreshes the held count too.
AddEventHandler('txsv:updateSyntheticPlayers', function()
    if not botsIncluded() then return end
    SetTimeout(0, function()
        if freshListed() then return end
        local n = syntheticCount()
        if n > 0 then setHeldBots(n) end
    end)
end)

-- The server-list number: real players + held bots, never below a fresh
-- reading. nil only when bots are off or nothing was ever seen.
local function getListedPlayerCount()
    if not botsIncluded() then return nil end
    local real = #GetPlayers()
    local bots = heldBotCount()
    local fresh = freshListed()
    if bots > 0 or fresh then
        return math.max(real + bots, fresh or 0)
    end
    return nil
end

getDisplayPlayerCount = function()
    local real = #GetPlayers()
    if not botsIncluded() then return real end
    local listed = getListedPlayerCount()
    if listed then return listed end
    return real + syntheticCount()
end

-- Join code: convar first, then config, then the CONNECT button in jrs_core.
local function cfxJoinId()
    local id = GetConvar('jrs_cfx_join_id', '')
    if id == '' then id = tostring(countCfg().cfxJoinId or '') end
    if id == '' then
        local raw = LoadResourceFile('jrs_core', 'config/config.lua') or ''
        id = raw:match('cfx%.re/join/(%w+)') or ''
    end
    id = id:lower():gsub('^.*/join/', '')
    if not id:match('^[a-z0-9]+$') or #id > 16 then return nil end
    return id
end

-- Source 1: Cfx server list (what the browser shows, bots included).
CreateThread(function()
    local cfg = countCfg()
    if cfg.useServerListCount == false or not botsIncluded() then return end
    local id = cfxJoinId()
    if not id then
        print('^3[jrs_loadingscreen] no Cfx join code - set Config.PlayerCount.cfxJoinId or "set jrs_cfx_join_id"^0')
        return
    end
    local urls = type(cfg.listUrls) == 'table' and #cfg.listUrls > 0 and cfg.listUrls or {
        'https://frontend.cfx-services.net/api/servers/single/%s',
        'https://servers-frontend.fivem.net/api/servers/single/%s',
    }
    local refreshMs = math.max(30000, tonumber(cfg.listRefreshMs) or 60000)
    local headers = { ['Accept'] = 'application/json', ['User-Agent'] = 'Mozilla/5.0 (jrs_loadingscreen)' }
    local idx = 1
    while true do
        local url = tostring(urls[idx] or urls[1]):format(id)
        PerformHttpRequest(url, function(code, body)
            if code ~= 200 or type(body) ~= 'string' then
                idx = (idx % #urls) + 1   -- try the other host next time
                return
            end
            local ok, decoded = pcall(json.decode, body)
            local data = ok and type(decoded) == 'table' and decoded.Data or nil
            if type(data) ~= 'table' then return end
            local clients = tonumber(data.clients)
            if not clients and type(data.players) == 'table' then clients = #data.players end
            onSourceRead('cfxlist', clients, data.svMaxclients or data.sv_maxclients)
        end, 'GET', '', headers)
        Wait(refreshMs)
    end
end)

-- Source 2: this server's own /dynamic.json (local and fast, may be real-only).
CreateThread(function()
    local cfg = countCfg()
    if cfg.useDynamicJson == false or not botsIncluded() then return end
    local url = tostring(cfg.url or 'http://127.0.0.1:30120/dynamic.json')
    local refreshMs = math.max(5000, tonumber(cfg.refreshMs) or 15000)
    while true do
        PerformHttpRequest(url, function(code, body)
            if code ~= 200 or type(body) ~= 'string' then return end
            local ok, decoded = pcall(json.decode, body)
            if ok and type(decoded) == 'table' then
                onSourceRead('dynamic', decoded.clients, decoded.sv_maxclients)
            end
        end, 'GET', '', { ['Accept'] = 'application/json' })
        Wait(refreshMs)
    end
end)

exports('GetDisplayPlayerCount', getDisplayPlayerCount)
exports('GetListedPlayerCount', getListedPlayerCount)
exports('IncludeBots', botsIncluded)
-- Max slots as the server list reports it, or nil.
getDisplayMaxClients = function()
    if not botsIncluded() then return nil end
    return listedMaxClients
end
exports('GetListedMaxClients', getDisplayMaxClients)
