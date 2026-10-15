local RESOURCE = GetCurrentResourceName()
local PERF = Config.Performance or {}
local VALID_MODES = { auto = true }
local MODE_NAMES = {}
local debugPlayers = {}

for i = 1, #(PERF.Levels or {}) do
    local level = PERF.Levels[i]
    if type(level) == 'table' and type(level.name) == 'string' then
        VALID_MODES[level.name] = true
        MODE_NAMES[#MODE_NAMES + 1] = level.name
    end
end

local function hasPermission(source)
    if source == 0 then
        return true
    end

    source = tonumber(source)
    local user = source and jrsCore.getUser(source) or nil
    return user ~= nil and Config.CanUseCommand(user.group, 'performance')
end

local function sendMessage(source, message, isError)
    message = tostring(message or '')
    if source == 0 then
        print(('[%s][performance] %s'):format(RESOURCE, message))
        return
    end

    TriggerClientEvent(
        'jrsCore:notify',
        tonumber(source),
        isError and 'PERFORMANCE FAILED' or 'PERFORMANCE',
        message,
        'placeholder',
        5000
    )
end

local function deny(source)
    sendMessage(source, _U('core_you_do_not_have_permission_to_2'), true)
end

local function setGlobalMode(mode)
    mode = string.lower(tostring(mode or 'auto'))
    if not VALID_MODES[mode] then
        return false
    end

    GlobalState.jrsPerformanceMode = mode
    return true
end

CreateThread(function()
    local mode = GlobalState.jrsPerformanceMode
    if not mode or not VALID_MODES[mode] then
        GlobalState.jrsPerformanceMode = 'auto'
    end
end)

local commands = PERF.Commands or {}

RegisterCommand(commands.status or 'jrsperf', function(source)
    if not hasPermission(source) then
        deny(source)
        return
    end

    if source == 0 then
        print(('[%s][performance] Global mode: %s'):format(RESOURCE, GlobalState.jrsPerformanceMode or 'auto'))
        return
    end

    TriggerClientEvent('jrs_core:performance:showStats', source)
end, false)

RegisterCommand(commands.debug or 'jrsperfdebug', function(source)
    if source == 0 then
        print(('[%s][performance] Debug is a player command. Use /%s for console status.')
            :format(RESOURCE, commands.status or 'jrsperf'))
        return
    end

    if not hasPermission(source) then
        deny(source)
        return
    end

    debugPlayers[source] = not debugPlayers[source]
    TriggerClientEvent('jrs_core:performance:setDebug', source, debugPlayers[source])
end, false)

RegisterCommand(commands.mode or 'jrsperfmode', function(source, args)
    if not hasPermission(source) then
        deny(source)
        return
    end

    local mode = string.lower(tostring(args[1] or ''))
    if mode == '' then
        sendMessage(source, (_U('core_current_mode_valid_auto'))
            :format(GlobalState.jrsPerformanceMode or 'auto', table.concat(MODE_NAMES, ', ')))
        return
    end

    if not setGlobalMode(mode) then
        sendMessage(source, (_U('core_invalid_mode_use_auto')):format(table.concat(MODE_NAMES, ', ')), true)
        return
    end

    sendMessage(source, (_U('core_global_performance_mode_changed_to')):format(mode))
end, false)

AddEventHandler('playerDropped', function()
    debugPlayers[source] = nil
end)

local function setEntityProtected(entity, protected)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    local stateKey = PERF.ProtectionStateKey or 'jrsProtected'
    local ok = pcall(function()
        Entity(entity).state:set(stateKey, protected == true, true)
    end)
    return ok
end

exports('GetPerformanceMode', function()
    return GlobalState.jrsPerformanceMode or 'auto'
end)

exports('SetPerformanceMode', setGlobalMode)
exports('SetEntityProtected', setEntityProtected)

-- Compatibility aliases for migrated performance integrations.
exports('GetMode', function()
    return GlobalState.jrsPerformanceMode or 'auto'
end)
exports('SetMode', setGlobalMode)
