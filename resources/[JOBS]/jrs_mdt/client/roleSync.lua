-- jrs_mdt | client: this player's copy of the officers' roles, always overwritten by the server's
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local state = { mine = nil, all = {}, version = 0, ready = false }

local function say(text) print('[jrs_mdt] RoleSync: ' .. text) end

local function describe(role)
    if not role then return 'nil' end
    return ('job=%s, grade=%s, configVersion=%s'):format(tostring(role.job and role.job.name), tostring(role.job and role.job.grade), tostring(role.configVersion))
end

local function permitted(permission)
    return state.mine ~= nil and state.mine.permissions ~= nil and state.mine.permissions[permission] == true
end

local function requestAll() TriggerServerEvent('jrs_mdt:roleSync:requestRoles') end

exports('getMyRole', function() return state.mine end)
exports('getAllRoles', function() return state.all end)
exports('getConfigVersion', function() return state.version end)
exports('isLawOfficer', function() return state.mine ~= nil end)
exports('hasRolePermission', permitted)
exports('isAdmin', function() return permitted('isAdmin') end)
exports('getJobInfo', function() return state.mine and state.mine.job or nil end)
exports('requestRoleSync', requestAll)
exports('validateLocalState', function()
    if state.mine then TriggerServerEvent('jrs_mdt:roleSync:validateLocalState', state.mine) end
end)

-- the client may not change its own role; the attempt is only logged
exports('attemptLocalOverride', function(role)
    say('local role change refused: ' .. describe(role))
    return false, locale('role_cannot_override')
end)

local function indexOf(source)
    for i, role in ipairs(state.all) do
        if role.source == source then return i end
    end
end

RegisterNetEvent('jrs_mdt:roleSync:receiveRoles', function(data)
    state.all, state.version, state.mine, state.ready = data.roles or {}, data.configVersion or 0, data.yourRole, true
    TriggerEvent('jrs_mdt:roleSync:stateUpdated', { myRole = state.mine, roleCount = #state.all, configVersion = state.version })
end)

RegisterNetEvent('jrs_mdt:roleSync:receiveMyRole', function(role)
    local before = state.mine
    state.mine = role

    if role and before and (role.job.name ~= before.job.name or role.job.grade ~= before.job.grade) then
        say(locale('role_updated', before.job.name, role.job.name))
    elseif role and not before then
        say(locale('role_added', role.job.name, role.job.grade))
    elseif before and not role then
        say(locale('role_removed', before.job.name))
    end
    TriggerEvent('jrs_mdt:roleSync:myRoleUpdated', role)
end)

RegisterNetEvent('jrs_mdt:roleSync:roleUpdated', function(data)
    local slot = indexOf(data.source)

    if data.changeType == 'add' then
        state.all[#state.all + 1] = data.roleData
        TriggerEvent('jrs_mdt:roleSync:playerAdded', data.roleData)
    elseif data.changeType == 'update' then
        if slot then state.all[slot] = data.roleData end
        TriggerEvent('jrs_mdt:roleSync:playerUpdated', data.roleData)
    elseif data.changeType == 'remove' then
        if slot then table.remove(state.all, slot) end
        TriggerEvent('jrs_mdt:roleSync:playerRemoved', data.roleData)
    end
end)

RegisterNetEvent('jrs_mdt:roleSync:forceRefresh', function(data)
    state.all, state.version = data.roles or {}, data.configVersion or 0
    say('forced refresh, config version ' .. state.version)
    TriggerEvent('jrs_mdt:roleSync:forceRefreshReceived', { configVersion = state.version, roleCount = #state.all })
end)

RegisterNetEvent('jrs_mdt:roleSync:stateMismatch', function(data)
    say(('mismatch (%s) local: %s | server: %s'):format(tostring(data.message), describe(data.localState), describe(data.serverState)))
    state.mine = data.serverState
    TriggerEvent('jrs_mdt:roleSync:stateCorrected', { correctedRole = data.serverState, message = data.message })
end)

RegisterNetEvent('jrs_mdt:roleSync:refreshComplete', function(data)
    say((data.success and 'admin refresh done: ' or 'admin refresh failed: ') .. tostring(data.message))
    TriggerEvent('jrs_mdt:roleSync:adminRefreshResult', data)
end)

CreateThread(function()
    Wait(3000)
    requestAll()
end)

RegisterNetEvent('jrs:SelectedCharacter', function()
    Wait(2000)
    requestAll()
end)

RegisterNetEvent('jrs_core:client:jobChanged', function(data)
    if data then
        Wait(1000)
        TriggerServerEvent('jrs_mdt:roleSync:requestMyRole')
    end
end)

-- every five minutes the server checks that this copy is still right
CreateThread(function()
    while true do
        Wait(300000)
        if state.ready and state.mine then TriggerServerEvent('jrs_mdt:roleSync:validateLocalState', state.mine) end
    end
end)
