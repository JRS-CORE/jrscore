-- jrs_playerinfo | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local Core = exports.jrs_core:GetCore()
local lastUse = {}

local function money(v)
    return ('$%.2f'):format(tonumber(v) or 0)
end

local function buildRows(src, char)
    local rows, show = {}, Config.Show
    local function add(label, value) rows[#rows + 1] = { label = label, value = tostring(value) } end

    if show.job then
        local job = char.jobLabel or char.job
        if not job or job == '' or job == 'unemployed' then job = L('unemployed') end
        add(L('job'), ('%s (%s %d)'):format(job, L('grade'), tonumber(char.jobGrade) or 0))
    end
    if show.cash then add(L('cash'), money(char.money)) end
    if show.gold then add(L('gold'), ('%.2f'):format(tonumber(char.gold) or 0)) end
    if show.dirtyMoney then
        local ok, api = pcall(function() return exports.jrs_core:getCoreApi() end)
        local dirty = ok and api and api.GetDirtyMoney and api.GetDirtyMoney(src)
        if dirty then add(L('dirty'), money(dirty)) end
    end
    if show.banks and GetResourceState('jrs_banking') == 'started' then
        local ok, accounts = pcall(MySQL.query.await,
            'SELECT `name`, `money` FROM `bank_users` WHERE `charidentifier` = ? ORDER BY `name`', { char.charIdentifier })
        if ok and accounts then
            for _, a in ipairs(accounts) do
                add(('%s %s'):format(L('bank'), a.name), money(a.money))
            end
        end
    end
    if show.charId then add(L('char_id'), char.charIdentifier or L('no_data')) end
    if show.serverId then add(L('server_id'), src) end
    return rows
end

RegisterCommand(Config.Command, function(src)
    if src <= 0 then return end
    local now = os.time()
    if lastUse[src] and now - lastUse[src] < Config.Cooldown then return end
    lastUse[src] = now

    local user = Core.getUser(src)
    local char = user and user.getUsedCharacter
    if not char then return end

    TriggerClientEvent('jrs_playerinfo:client:show', src,
        ('%s %s'):format(char.firstname or '', char.lastname or ''), buildRows(src, char))
end, false)

AddEventHandler('playerDropped', function()
    lastUse[source] = nil
end)
