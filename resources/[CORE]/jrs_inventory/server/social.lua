-- ===========================================================================
-- Social Interactions
-- Server-authoritative target, range, cooldown and hostage-session validation.
-- ===========================================================================

local hostageByCaptor = {}
local captorByTarget = {}
local socialCooldowns = {}
local playerInteractions = Config.GetPlayerInteractions()

local function interactionEnabled(action)
    if playerInteractions.Enabled == false then return false end
    if action == 'hand' then return playerInteractions.GiveHand ~= false end
    if action == 'slap' then return playerInteractions.GiveSlap ~= false end
    if action == 'hostage' then return playerInteractions.TakeHostage ~= false end
    return false
end

local function nowMs()
    return GetGameTimer()
end

local function socialCooldown(playerId, action, cooldownMs)
    playerId = tonumber(playerId)
    if not playerId then return false end
    socialCooldowns[playerId] = socialCooldowns[playerId] or {}
    local now = nowMs()
    local expiresAt = tonumber(socialCooldowns[playerId][action]) or 0
    if expiresAt > now then return false end
    socialCooldowns[playerId][action] = now + math.max(250, tonumber(cooldownMs) or 1000)
    return true
end

local function validSocialTarget(sourcePlayer, targetPlayer)
    sourcePlayer = tonumber(sourcePlayer)
    targetPlayer = tonumber(targetPlayer)
    if not sourcePlayer or not targetPlayer or sourcePlayer == targetPlayer then return false end
    if not isValidTarget(targetPlayer) then return false end
    return ArePlayersWithinTransferDistance(sourcePlayer, targetPlayer)
end

local function clearHostagePair(captor, target, notifyBoth)
    captor = tonumber(captor)
    target = tonumber(target)
    if not captor or not target then return false end
    if tonumber(hostageByCaptor[captor]) ~= target or tonumber(captorByTarget[target]) ~= captor then
        return false
    end

    hostageByCaptor[captor] = nil
    captorByTarget[target] = nil
    if notifyBoth ~= false then
        TriggerClientEvent('jrs_inventory:clearHostage', captor)
        TriggerClientEvent('jrs_inventory:clearHostage', target)
    end
    return true
end

local function beginSocialAction(action, target, cooldownMs)
    local sourcePlayer = tonumber(source)
    target = tonumber(target)
    if not interactionEnabled(action) then return nil, nil end
    if not sourcePlayer or not AllowInventoryRequest(sourcePlayer, 'social') then return nil, nil end
    if not validSocialTarget(sourcePlayer, target) then
        RecordInventorySecurityViolation(sourcePlayer, 'invalid_social_target', action .. ':' .. tostring(target))
        return nil, nil
    end
    if not socialCooldown(sourcePlayer, action, cooldownMs) then return nil, nil end
    return sourcePlayer, target
end

RegisterNetEvent('jrs_inventory:give_slap')
AddEventHandler('jrs_inventory:give_slap', function(target)
    local sourcePlayer, targetPlayer = beginSocialAction('slap', target, playerInteractions.SocialActionCooldownMs)
    if not sourcePlayer then return end

    local random = math.random(1, 7)
    TriggerClientEvent('jrs_inventory:send_slap', sourcePlayer, targetPlayer, random, true)
    TriggerClientEvent('jrs_inventory:send_slap', targetPlayer, sourcePlayer, random, false)
end)

RegisterNetEvent('jrs_inventory:give_hand')
AddEventHandler('jrs_inventory:give_hand', function(target)
    local sourcePlayer, targetPlayer = beginSocialAction('hand', target, playerInteractions.SocialActionCooldownMs)
    if not sourcePlayer then return end

    TriggerClientEvent('jrs_inventory:send_hand', sourcePlayer, targetPlayer, true)
    TriggerClientEvent('jrs_inventory:send_hand', targetPlayer, sourcePlayer, false)
end)

RegisterNetEvent('jrs_inventory:hostage')
AddEventHandler('jrs_inventory:hostage', function(target)
    local sourcePlayer, targetPlayer = beginSocialAction('hostage', target, playerInteractions.HostageTakeCooldownMs)
    if not sourcePlayer then return end
    -- The client only offers the prompt for a living target outside the arena;
    -- repeat what the server can see so a modified client cannot grab a dead,
    -- downed or arena player. isDead is the jrs_character state bag (server-side
    -- GetEntityHealth reads 0 for live players, see jrs_fightarena 2.2.1).
    local captorState, targetState = Player(sourcePlayer).state, Player(targetPlayer).state
    if captorState.jrsArena == true or targetState.jrsArena == true
        or captorState.isDead == true or targetState.isDead == true
        or targetState.jrsIncapacitated == true then
        return
    end
    if hostageByCaptor[sourcePlayer] or captorByTarget[sourcePlayer]
        or hostageByCaptor[targetPlayer] or captorByTarget[targetPlayer] then
        return
    end

    hostageByCaptor[sourcePlayer] = targetPlayer
    captorByTarget[targetPlayer] = sourcePlayer
    TriggerClientEvent('jrs_inventory:hostage', sourcePlayer, targetPlayer, true)
    TriggerClientEvent('jrs_inventory:hostage', targetPlayer, sourcePlayer, false)

    local timeout = math.max(5000, tonumber(Config.Security and Config.Security.SocialSessionTimeoutMs) or 30000)
    SetTimeout(timeout, function()
        clearHostagePair(sourcePlayer, targetPlayer, true)
    end)
end)

RegisterNetEvent('jrs_inventory:clearHostage')
AddEventHandler('jrs_inventory:clearHostage', function(target)
    local sourcePlayer = tonumber(source)
    target = tonumber(target)
    if not sourcePlayer or not AllowInventoryRequest(sourcePlayer, 'social') then return end

    local captor = hostageByCaptor[sourcePlayer] and sourcePlayer or captorByTarget[sourcePlayer]
    local hostage = hostageByCaptor[sourcePlayer] or (captor and sourcePlayer)
    if not captor or not hostage then return end
    if target and target ~= captor and target ~= hostage then
        RecordInventorySecurityViolation(sourcePlayer, 'invalid_hostage_release_target', tostring(target))
        return
    end

    clearHostagePair(captor, hostage, true)
end)

AddEventHandler('playerDropped', function()
    local playerId = tonumber(source)
    local captor = hostageByCaptor[playerId] and playerId or captorByTarget[playerId]
    local hostage = hostageByCaptor[playerId] or (captor and playerId)
    if captor and hostage then clearHostagePair(captor, hostage, true) end
    socialCooldowns[playerId] = nil
end)
