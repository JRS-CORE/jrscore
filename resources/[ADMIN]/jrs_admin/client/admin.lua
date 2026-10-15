-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | the administration section: players, actions on one player, offline actions, announcements

local T = Translation.Current()
local frozen = {}                                   -- server id -> true while frozen from this menu

function IsAdminAllowed(permission)
    local allowed = JRS.Callback.TriggerAwait('jrs_admin:CanOpenStaffMenu', permission)
    if not allowed then JRS.NotifyObjective(T.Notify.noperms, 5000) end
    return allowed
end

local function sortedPlayers()
    local result = JRS.Callback.TriggerAwait('jrs_admin:Callback:getplayersinfo', { search = 'all' })
    if not result then return nil end
    local list = {}
    for _, info in pairs(result) do list[#list + 1] = info end
    table.sort(list, function(a, b) return a.serverId < b.serverId end)
    return list
end

-- ------------------------------------------------------------------ top of the section

function Admin()
    local O = T.Menus.MainAdminOptions
    local online = tonumber(GlobalState.PlayersInSession) or 0

    Kit.open('Admin', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin,
        back = 'OpenMenu',
        items = {
            { label = O.playersList, value = 'players', gate = 'players_list_menu',
              desc = O.playersList_desc .. '<br><br>' .. (online > 0 and online or ''), go = function() PlayerList() end },
            { label = O.adminActions, value = 'actions', gate = 'admin_actions_menu', desc = O.adminActions_desc, go = function() Actions() end },
            { label = O.offLineActions, value = 'offline', gate = 'offline_actions_menu', desc = O.offLineActions_desc, go = function() OffLine() end },
            { label = O.viewReports, value = 'view', desc = O.viewReports_desc, go = function() AdminReports() end },
            { label = O.searchPlayer, value = 'search', desc = O.searchPlayer_desc, go = function()
                Kit.ask(O.MenuAdminInput, '[0-9]{1,5}', function(answer)
                    local id = tonumber(answer)
                    if not (id and id > 0) then return end
                    JRS.Callback.TriggerAsync('jrs_admin:Callback:getplayersinfo', function(found)
                        if found then OpenOnePlayerMenu(found) else JRS.NotifyObjective(T.Notify.userNotExist, 5000) end
                    end, { search = 'search', id = id })
                end, { type = 'number' })
            end },
        },
    })
end

function OpenOnePlayerMenu(info)
    local row = Kit.playerRow(info)
    row.go = function(self) OpenSubAdminMenu(self.info) end
    Kit.open('OpenOnePlayerMenu', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin,
        back = 'Admin',
        align = 'top-left',
        itemHeight = '4vh',
        items = { row },
    })
end

function PlayerList()
    local players = sortedPlayers()
    if not players then return end
    local rows = {}
    for _, info in ipairs(players) do
        local row = Kit.playerRow(info)
        row.gate = 'players_list_submenu'
        row.go = function(self) OpenSubAdminMenu(self.info) end
        rows[#rows + 1] = row
    end
    Kit.open('PlayerList', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin, back = 'Admin', align = 'top-left', itemHeight = '4vh', items = rows })
end

function OpenSubAdminMenu(player)
    local O = T.Menus.SubAdminOptions
    Kit.open('OpenSubAdminMenu', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin,
        back = 'PlayerList',
        items = {
            { label = O.simpleActions, value = 'simpleaction', gate = 'simple_actions_menu', desc = O.simpleActions_desc, go = function() OpenSimpleActionMenu(player) end },
            { label = O.advancedActions, value = 'advancedaction', gate = 'advanced_actions_menu', desc = O.advancedActions_desc, go = function() OpenAdvancedActions(player) end },
            { label = O.trollActions, value = 'trollactions', gate = 'troll_actions_menu', desc = O.trollActions_desc, go = function() OpenTrollActions(player) end },
        },
    })
end

-- ------------------------------------------------------------------ troll actions

local trolls = {
    { 'killPlayer',            'killplayer',            'ServerTrollKillPlayerHandler',           'KillPlayer' },
    { 'invisPlayer',           'invisplayer',           'ServerTrollInvisibleHandler',            'InvisPlayer' },
    { 'lightningStrikePlayer', 'lightningstrikeplayer', 'ServerTrollLightningStrikePlayerHandler', 'LightningStrikePlayer' },
    { 'setPlayerOnFire',       'setplayeronfire',       'ServerTrollSetPlayerOnFireHandler',      'SetPlayerOnFire' },
    { 'teleportToHeaven',      'tptoheaven',            'ServerTrollTPToHeavenHandler',           'TPToHeaven' },
    { 'ragdollPlayer',         'ragdollplayer',         'ServerTrollRagdollPlayerHandler',        'RagdollPlayer' },
    { 'drainPlayerStam',       'drainplayerstam',       'ServerDrainPlayerStamHandler',           'DrainPlayerStam' },
    { 'cuffPlayer',            'cuffplayer',            'ServerHandcuffPlayerHandler',            'CuffPlayer' },
    { 'tempHighPlayer',        'temphighplayer',        'ServerTempHighPlayerHandler',            'PlayerTempHigh' },
}

function OpenTrollActions(player)
    local O = T.Menus.SubTrollOptions
    local items = {}
    for _, t in ipairs(trolls) do
        items[#items + 1] = {
            label = O[t[1]], value = t[2], desc = Kit.about(O[t[1] .. '_desc'], player.PlayerName), info = player.serverId,
            go = function(row) TriggerServerEvent('jrs_admin:' .. t[3], row.info, 'jrs.staff.' .. t[4]) end,
        }
    end
    Kit.open('OpenTrollActions', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin, back = 'PlayerList', items = items })
end

-- ------------------------------------------------------------------ simple actions

function OpenSimpleActionMenu(player)
    local O = T.Menus.SubSimpleActionOptions
    local name, id = player.PlayerName, player.serverId

    local function row(key, value, go, withName)
        return { label = O[key], value = value, desc = withName == false and O[key .. '_desc'] or Kit.about(O[key .. '_desc'], name), info = id, go = go }
    end

    Kit.open('OpenSimpleActionMenu', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin,
        back = 'PlayerList',
        items = {
            row('playerSpectate', 'spectate', function(r) TriggerServerEvent('jrs_admin:spectate', r.info, 'jrs.staff.Spectate', name) end),
            row('playerFreeze', 'freeze', function(r)
                local on = not frozen[r.info]
                frozen[r.info] = on
                TriggerServerEvent('jrs_admin:freeze', r.info, on, 'jrs.staff.Frezee', name)
                TriggerEvent('jrs:TipRight', on and T.Notify.switchedOn or T.Notify.switchedOff, 3000)
            end),
            row('playerRevive', 'revive', function(r) TriggerServerEvent('jrs_admin:revive', r.info, 'jrs.staff.Revive', name) end),
            row('playerHeal', 'heal', function(r) TriggerServerEvent('jrs_admin:heal', r.info, 'jrs.staff.Heal', name) end),
            row('playerGoTo', 'goto', function(r) TriggerServerEvent('jrs_admin:TpToPlayer', r.info, 'jrs.staff.GoTo', name) end),
            row('playerGoBack', 'goback', function() TriggerServerEvent('jrs_admin:sendAdminBack', 'jrs.staff.GoTo') end),
            row('playerSendBack', 'sendback', function(r) TriggerServerEvent('jrs_admin:TeleportPlayerBack', r.info, 'jrs.staff.Bring') end),
            row('playerBring', 'bring', function(r)
                TriggerServerEvent('jrs_admin:Bring', r.info, GetEntityCoords(PlayerPedId()), 'jrs.staff.Bring', name)
            end),
        },
    })
end

-- ------------------------------------------------------------------ advanced actions

function OpenAdvancedActions(player)
    local O = T.Menus.SubAdvancedActionOptions
    local name = player.PlayerName

    local function row(key, value, go)
        return { label = O[key], value = value, desc = Kit.about(O[key .. '_desc'], name), go = go }
    end

    Kit.open('OpenAdvancedActions', {
        sub = name,
        back = 'PlayerList',
        items = {
            row('playerKick', 'kick', function()
                Kit.ask(O.KickInput, '.{3,200}', function(reason)
                    TriggerServerEvent('jrs_admin:kick', player.serverId, reason, 'jrs.staff.Kick', name)
                end)
            end),
            row('playerBan', 'ban', function()
                Kit.ask(O.BanInput, '[0-9]+[hdwmyHDWMY]?', function(length)
                    TriggerServerEvent('jrs_admin:BanPlayer', player.serverId, player.staticID, length, 'jrs.staff.Ban', name)
                end)
            end),
            row('playerUnBan', 'unban', function()
                TriggerServerEvent('jrs_admin:Unban', tonumber(player.staticID) or player.SteamId, 'jrs.staff.Unban', name)
            end),
            row('playerRespawn', 'respawn', function()
                TriggerServerEvent('jrs_admin:respawnPlayer', player.serverId, 'jrs.staff.Respawn', name)
            end),
            row('playerUnWhitelist', 'unwhitelist', function()
                TriggerServerEvent('jrs_admin:Whitelist', player.serverId, player.SteamId, 'removewhitelist', 'jrs.staff.Unwhitelist', name)
                JRS.NotifyObjective(T.Notify.whiteRemoved, 5000)
            end),
            row('playerSetJob', 'setjob', function()
                Kit.ask(O.JobInput, '.{3,100}', function(answer)
                    local w = Kit.words(answer)
                    local grade = tonumber(w[2])
                    if w[1] and grade and w[3] then
                        TriggerServerEvent('jrs_admin:setJob', player.serverId, w[1], grade, table.concat(w, ' ', 3), 'jrs.staff.Setjob', name)
                    end
                end)
            end),
            row('playerSetGroup', 'setgroup', function()
                Kit.ask(O.GroupInput, '[A-Za-z]{3,20}', function(group)
                    TriggerServerEvent('jrs_admin:setGroup', player.serverId, group, 'jrs.staff.Setgroup', name)
                end)
            end),
        },
    })
end

-- ------------------------------------------------------------------ actions that are not about one player

function Actions()
    local O = T.Menus.SubActionsAdminOptions
    Kit.open('Actions', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin,
        back = 'Admin',
        items = {
            { label = O.deleteMountHorse, value = 'delhorse', gate = 'delete_horse', desc = O.deleteMountHorse_desc,
              go = function() TriggerEvent('jrs:delHorse') end },
            { label = O.deleteMountWagon, value = 'delwagon', gate = 'delete_wagon', desc = O.deleteMountWagon_desc,
              go = function() Delwagon() end },
            { label = O.deleteWagonInRadius, value = 'delwagonradius', gate = 'delete_wagons_radius', desc = O.deleteWagonInRadius_desc,
              go = function()
                  Kit.ask(O.DelWagonRadiusInput, '[0-9]{1,3}', function(answer)
                      TriggerEvent('jrs:deleteVehicle', math.max(1, math.min(100, tonumber(answer) or 1)))
                  end, { type = 'number' })
              end },
            { label = O.getCoords, value = 'getcoords', gate = 'get_coords', desc = O.getCoords_desc, go = function() OpenCoordsMenu() end },
            { label = O.adminAnnounce, value = 'announce', desc = O.adminAnnounce_desc, go = function()
                Kit.ask(O.AnnounceInput, '.{3,300}', function(text) TriggerServerEvent('jrs_admin:announce', text) end)
            end },
        },
    })
end

function OpenCoordsMenu()
    local O = T.Menus.SubCoordsMenu
    local items = {}
    for _, f in ipairs({ { 'getCoordsXYZ', 'v2' }, { 'getCoordsVec3', 'v3' }, { 'getCoordsVec4', 'v4' }, { 'getHeading', 'heading' } }) do
        items[#items + 1] = { label = O[f[1]], value = f[2], desc = O[f[1] .. '_desc'], go = function(row) CopyToClipboard(row.value) end }
    end
    Kit.open('OpenCoordsMenu', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleCoords, back = 'Actions', items = items })
end

-- ------------------------------------------------------------------ players who are not on the server

function OffLine()
    local O = T.Menus.SubOfflineOptions
    Kit.open('OffLine', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleAdmin,
        back = 'Admin',
        items = {
            { label = O.banOrUnban, value = 'bans', desc = O.banOrUnban_desc, go = function()
                Kit.ask(O.BanTypeInput, '.{3,300}', function(answer)
                    local w = Kit.words(answer)
                    local kind, staticId, length = (w[1] or ''):lower(), tonumber(w[2]), w[3]
                    if not staticId then return JRS.NotifyObjective(T.Notify.missingArgument, 5000) end
                    if kind == 'ban' then
                        if length then TriggerServerEvent('jrs_admin:BanOffline', staticId, length, 'jrs.staff.Ban')
                        else JRS.NotifyObjective(T.Notify.missingArgument, 5000) end
                    elseif kind == 'unban' then
                        TriggerServerEvent('jrs_admin:Unban', staticId, 'jrs.staff.Unban')
                    else
                        JRS.NotifyObjective(T.Notify.incorrectType, 5000)
                    end
                end)
            end },
            { label = O.whiteOrUnwhite, value = 'whites', desc = O.whiteOrUnwhite_desc, go = function()
                Kit.ask(O.WhiteTypeInput, '.{3,300}', function(answer)
                    local w = Kit.words(answer)
                    local kind, steam = (w[1] or ''):lower(), w[2]
                    if not steam then return JRS.NotifyObjective(T.Notify.missingArgument, 5000) end
                    if kind == 'whitelist' or kind == 'unwhitelist' then
                        TriggerServerEvent('jrs_admin:Whitelistoffline', steam, kind)
                    else
                        JRS.NotifyObjective(T.Notify.incorrectType, 5000)
                    end
                end)
            end },
        },
    })
end
