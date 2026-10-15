-- ====================================================================
-- JRS SECURITY: Server NUI DevTools Authorization & Kick Guard
-- ====================================================================

local recentlyProcessed = {}

local function isPlayerAuthorized(source)
    local src = tonumber(source)
    if not src or src <= 0 then return false end

    -- 1. Check jrs_core authoritative core owner identifiers
    if type(jrsCore) == 'table' and type(jrsCore.IsCoreOwnerSource) == 'function' then
        local ok, isOwner = pcall(jrsCore.IsCoreOwnerSource, src)
        if ok and isOwner == true then return true end
    end

    -- 2. Check jrs_admin IsOwnerAdmin export if available
    if GetResourceState('jrs_admin') == 'started' then
        local ok, isOwner = pcall(function()
            return exports['jrs_admin']:IsOwnerAdmin(src)
        end)
        if ok and isOwner == true then return true end
    end

    -- 3. Check ACE Permissions (command / group.admin / jrs.devtools / jrs.owner)
    if IsPlayerAceAllowed(src, 'command') 
        or IsPlayerAceAllowed(src, 'group.admin') 
        or IsPlayerAceAllowed(src, 'jrs.devtools') 
        or IsPlayerAceAllowed(src, 'jrs.owner') then
        return true
    end

    -- 4. Check Config.CoreOwners defined in config/config.lua
    local coreOwners = (Config and Config.CoreOwners) or {}
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        local idLower = string.lower(tostring(identifier or ''))
        if coreOwners[idLower] == true then
            return true
        end
    end

    -- 5. Check jrs_admin JRS.ServerOwnerIdentifiers if available
    if type(JRS) == 'table' and type(JRS.ServerOwnerIdentifiers) == 'table' then
        for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
            local idLower = string.lower(tostring(identifier or ''))
            if JRS.ServerOwnerIdentifiers[idLower] or JRS.ServerOwnerIdentifiers[identifier] then
                return true
            end
        end
    end

    return false
end

RegisterNetEvent('jrs_security:devtoolsOpened', function(data)
    local src = source
    if not src or src <= 0 then return end

    local now = os.time()
    if recentlyProcessed[src] and (now - recentlyProcessed[src]) < 4 then
        return
    end
    recentlyProcessed[src] = now

    local method = (type(data) == 'table' and tostring(data.method or 'unknown')) or 'unknown'
    local playerName = GetPlayerName(src) or 'Unknown'

    -- Authorization Verification
    if isPlayerAuthorized(src) then
        print(('[^2JRS SECURITY^7] Player ^3%s^7 (ID: %s) triggered %s [^2AUTHORIZED OWNER/ADMIN^7]')
            :format(playerName, src, method))
        return
    end

    -- Trap commands for known cheat injectors
    if method:find('console_trap_') then
        local kickReason = 'Security Disconnect: Blacklisted console command detected.'
        if type(JRSAdminSecurityAlert) == 'function' then
            pcall(JRSAdminSecurityAlert, src, 'cheat-command-detected', 'critical', 90, { method = method }, 1000)
        end
        DropPlayer(src, kickReason)
        return
    end

    -- DevTools events are logged but not kicked to prevent false positives and CEF hiccups
    print(('[^3JRS SECURITY^7] DevTools event logged for player ^3%s^7 (ID: %s) [Method: %s] - Kick bypassed.')
        :format(playerName, src, method))
end)

AddEventHandler('playerDropped', function()
    recentlyProcessed[source] = nil
end)
