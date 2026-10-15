local CORE_STARTED_AT = os.time()

local function connectionGuardCheckPlayerName(name)
    local guard = Config.ConnectionGuard and Config.ConnectionGuard.PlayerName
    if not guard or guard.Enabled ~= true then return true end

    local value = tostring(name or '')
    local maxLength = math.max(1, tonumber(guard.MaxLength) or 64)
    if #value > maxLength then
        return false, tostring(guard.Message or 'Your player name is not allowed.')
    end

    local lowerValue = string.lower(value)
    for _, pattern in ipairs(guard.RejectPatterns or {}) do
        local needle = string.lower(tostring(pattern or ''))
        if needle ~= '' and string.find(lowerValue, needle, 1, true) then
            return false, tostring(guard.Message or 'Your player name is not allowed.')
        end
    end

    return true
end

local function connectionGuardCheckServerState()
    local restart = Config.RestartManagement
    if restart and restart.Enabled == true and JRSRestartManager and not JRSRestartManager.CanJoin() then
        return false, tostring(restart.ConnectBlockedMessage or 'The server is preparing to restart.')
    end

    local startup = Config.ConnectionGuard and Config.ConnectionGuard.StartupDelay
    if startup and startup.Enabled == true then
        local required = math.max(0, tonumber(startup.Seconds) or 0)
        local elapsed = os.time() - CORE_STARTED_AT
        if elapsed < required then
            local remaining = required - elapsed
            local template = tostring(startup.Message or 'The server is still starting. Please reconnect in %s seconds.')
            local ok, message = pcall(string.format, template, remaining)
            return false, ok and message or template
        end
    end

    return true
end

local function collectPlayerIdentifiers(src)
    local identifiers = {
        steam = nil,
        license = nil,
        discord = nil,
    }

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 6) == "steam:" then
            identifiers.steam = identifier
        elseif identifier:sub(1, 8) == "license:" then
            identifiers.license = identifier
        elseif identifier:sub(1, 8) == "discord:" then
            identifiers.discord = identifier
        end
    end

    return identifiers
end

local function hasDuplicateConnection(src, identifiers)
    local currentSource = tonumber(src)

    for _, playerId in ipairs(GetPlayers()) do
        local otherSource = tonumber(playerId)

        if otherSource and otherSource ~= currentSource then
            local otherIdentifiers = collectPlayerIdentifiers(otherSource)
            local sameSteam = identifiers.steam and otherIdentifiers.steam == identifiers.steam
            local sameLicense = identifiers.license and otherIdentifiers.license == identifiers.license

            if sameSteam or sameLicense then
                return true
            end
        end
    end

    return false
end

local function OnPlayerConnecting(name, setKickReason, deferrals)
    local src = source
    local playerIdentifiers = collectPlayerIdentifiers(src)
    local identifiers = playerIdentifiers.steam or playerIdentifiers.license
    deferrals.defer()

    Wait(0)

    local nameAllowed, nameReason = connectionGuardCheckPlayerName(name)
    if not nameAllowed then
        deferrals.done(nameReason)
        return
    end

    local serverReady, serverReason = connectionGuardCheckServerState()
    if not serverReady then
        deferrals.done(serverReason)
        return
    end

    deferrals.update(_UConn('checking_identifiers'))
    Wait(500)

    if not identifiers then
        deferrals.done(_UConn('no_steam_license'))
        return
    end

    if hasDuplicateConnection(src, playerIdentifiers) then
        deferrals.done(_UConn('already_connected'))
        return
    end

    if Config.RequireSteam then
        deferrals.update(_UConn('checking_steam', name))
        Wait(1500)
        if not playerIdentifiers.steam then
            deferrals.done(_UConn('need_steam'))
            return
        end
    end

    if Config.RequireDiscord then
        deferrals.update(_UConn('checking_discord', name))
        Wait(1500)
        if not playerIdentifiers.discord then
            deferrals.done(_UConn('need_discord'))
            return
        end
    end

    deferrals.update(_UConn('checking_bans', name))
    Wait(500)

    local banOk, banRow = pcall(MySQL.single.await,
        'SELECT reason, DATE_FORMAT(date, "%d.%m.%Y") AS date_convert FROM jrs_bans WHERE identifier = ? AND (date IS NULL OR date > NOW()) LIMIT 1',
        { identifiers }
    )
    if banOk and banRow then
        deferrals.done(_UConn('banned', banRow.reason or '', banRow.date_convert or ''))
        return
    end

    local userCheckOk, bannedUserRow = pcall(MySQL.single.await,
        'SELECT banned FROM jrs_users WHERE identifier = ? LIMIT 1',
        { identifiers }
    )
    if userCheckOk and bannedUserRow then
        -- oxmysql can hand back this TINYINT(1) column as a real boolean or as
        -- 0/1 depending on driver path; tonumber(true) is nil so a plain == 1
        -- check would silently let a banned account's connection through.
        local bannedValue = bannedUserRow.banned
        if bannedValue == true or tonumber(bannedValue) == 1 then
            deferrals.done(_UConn('banned_account'))
            return
        end
    end

    local coreOwner = type(jrsCore.IsCoreOwnerIdentifier) == 'function'
        and jrsCore.IsCoreOwnerIdentifier(identifiers) or false
    if not coreOwner and IsPlayerAceAllowed(src, 'jrscore.owner') then
        coreOwner = true
        print(('^2[JRS] %s has the jrscore.owner permission -> owner group^0'):format(name))
    end

    if Config.Whitelist or Config.WhitelistDiscord then
        deferrals.update(_UConn('checking_whitelist', name))
        local discordId = playerIdentifiers.discord
        local steamId = playerIdentifiers.steam

        if not coreOwner then
            local inWhitelist = false

            -- 1. Check database tables (discord_whitelist and whitelist)
            local queryOk, row = pcall(MySQL.single.await,
                'SELECT identifier FROM jrs_discord_whitelist WHERE identifier = ? OR identifier = ? UNION SELECT identifier FROM jrs_whitelist WHERE identifier = ? OR identifier = ? LIMIT 1',
                { discordId, steamId, discordId, steamId }
            )
            if queryOk and row and row.identifier then
                inWhitelist = true
            end

            -- 2. Check Discord role via jrs_admin export if available
            if not inWhitelist and GetResourceState('jrs_admin') == 'started' then
                local ok, roles = pcall(function() return exports.jrs_admin:GetPlayerDiscordRoles(src) end)
                if ok and type(roles) == 'table' then
                    local wantedRole = tostring(Config.DiscordWhitelistRole or '')
                    for _, r in ipairs(roles) do
                        if tostring(r) == wantedRole then
                            inWhitelist = true
                            break
                        end
                    end
                end
            end

            if not inWhitelist then
                deferrals.done(_UConn('not_whitelisted'))
                return
            end
        end
    end

    local queryUserOk, userResult = pcall(MySQL.single.await,
        'SELECT * FROM jrs_users WHERE identifier = ? LIMIT 1',
        { identifiers }
    )

    if (not queryUserOk or not userResult) and not coreOwner and GetConvarInt('jrs_first_player_owner', 1) == 1 then
        local countOk, total = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM jrs_users')
        if countOk and tonumber(total) == 0 then
            coreOwner = true
            print(('^2[JRS] First account on this server: %s is now the owner^0'):format(name))
        end
    end

    if not queryUserOk or not userResult then
        if coreOwner then
            -- Core owners start with the owner group persisted from the very first connect.
            pcall(MySQL.insert.await,
                "INSERT INTO jrs_users (`identifier`, `chars`, `group`) VALUES (?, ?, 'owner')",
                { identifiers, Config.Char_Count }
            )
        else
            pcall(MySQL.insert.await,
                "INSERT INTO jrs_users (`identifier`, `chars`) VALUES (?, ?)",
                { identifiers, Config.Char_Count }
            )
        end
        LoadedUsers[identifiers] = {
            identifier = identifiers,
            group = coreOwner and "owner" or "user",
            chars = Config.Char_Count,
            warnings = 0,
            banned = 0,
            setUsedCharacter = User.setUsedCharacter,
            addCharacter = jrsCore.addCharacter,
            setGroup = User.setGroup,
        }
    elseif not LoadedUsers[identifiers] then
        local dbGroup = userResult.group or "user"
        if coreOwner and dbGroup ~= "owner" then
            -- Repair an outdated database row for a core owner.
            pcall(MySQL.update.await,
                "UPDATE jrs_users SET `group` = 'owner' WHERE identifier = ? AND (`group` IS NULL OR `group` <> 'owner')",
                { identifiers }
            )
            dbGroup = "owner"
        end

        LoadedUsers[identifiers] = {
            identifier = userResult.identifier,
            group = dbGroup,
            chars = tonumber(userResult.chars_override) or tonumber(userResult.chars) or Config.Char_Count,
            warnings = userResult.warnings or 0,
            banned = userResult.banned or 0,
            setUsedCharacter = User.setUsedCharacter,
            addCharacter = jrsCore.addCharacter,
            setGroup = User.setGroup,
        }
    elseif coreOwner then
        LoadedUsers[identifiers].group = "owner"
    end

    -- Do not let the client start character loading until its user object exists.
    deferrals.done()
end

AddEventHandler("playerConnecting", OnPlayerConnecting)
