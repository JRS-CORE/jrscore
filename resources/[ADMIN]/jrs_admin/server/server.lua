-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | server
-- Every staff action arrives as a net event. Each one is checked the same way: the sender needs the permission
-- of the action in Config.AllowedActions, the target has to be a player who is in the game, and whoever acts
-- on a player must outrank them. The action is then logged to Discord.

local staffOnline, snapshot = {}, {}                -- server id -> true / last player card
local reports, lastReportId = {}, 0
local lastAlert = {}                                -- server id -> os.time of their last report or request

for _, name in ipairs({ 'jrs_inventory', 'jrs_core' }) do
    if GetResourceState(name) ~= 'started' then
        error(('Resource %s is not started, jrs_admin will stop'):format(name))
    end
end

local Core <const> = exports.jrs_core:GetCore()

-- ------------------------------------------------------------------ who is who

local function groupOf(src)
    local user = Core.getUser(src)
    if not user then return nil end
    if Config.UseCharactersAdmin then
        return user.getUsedCharacter and user.getUsedCharacter.group
    end
    return type(user.getGroup) == 'function' and user.getGroup() or user.getGroup
end

local function rankOf(group) return Config.GroupRank[group] or 0 end

-- may this player run `action`? (the group `all` may run everything)
local function may(src, action)
    local user = Core.getUser(src)
    if not user or not user.getUsedCharacter then return false end
    local rules = Config.AllowedActions[groupOf(src)]
    if not rules then return false end
    return rules.actions.all == true or rules.actions[action] == true
end

local function isStaff(src)
    return groupOf(src) ~= nil and may(src, 'open_menu')
end

local function card(user, src)
    local character = user.getUsedCharacter
    if not character then return nil end
    local entry = Core.Whitelist.getEntry(character.identifier)
    return {
        serverId = src,
        name = GetPlayerName(src),
        Group = character.group,
        PlayerName = (character.firstname or 'no name') .. ' ' .. (character.lastname or 'noname'),
        Job = character.job,
        SteamId = character.identifier,
        Money = character.money,
        Gold = character.gold,
        Grade = character.jobGrade,
        staticID = entry and tonumber(entry.id) or 'no id',
        WLstatus = entry and tostring(entry.status) or 'no status',
    }
end

local function characterName(src)
    local user = Core.getUser(src)
    local c = user and user.getUsedCharacter
    return c and ((c.firstname or '') .. ' ' .. (c.lastname or '')) or (GetPlayerName(src) or 'Unknown')
end

-- ------------------------------------------------------------------ small helpers

local function cleanText(value, limit)
    value = tostring(value or ''):gsub('[`@\r]', ''):gsub('[%z\1-\31\127]', ' ')
    if not utf8.len(value) then return '' end
    local cut = utf8.offset(value, (limit or 200) + 1)
    return cut and value:sub(1, cut - 1) or value
end

-- "2d", "1w", "1m", "1y" or plain hours -> hours (0 = forever); nil when it makes no sense
local function banHours(text)
    local amount, unit = tostring(text or ''):lower():gsub('%s', ''):match('^(%d+)([hdwmy]?)$')
    amount = tonumber(amount)
    if not amount then return nil end
    local per = { d = 24, w = 168, m = 720, y = 8760 }
    return math.min(amount * (per[unit] or 1), 87600)
end

local function target(id)
    id = tonumber(id)
    return id and Core.getUser(id) and id or nil
end

local function say(src, key, ms)
    Core.NotifyRightTip(src, Translation.ForPlayer(src).Notify[key], ms or 8000)
end

local function audit(src, hook, title, text)
    TriggerEvent('jrs_admin:logs', src, hook, title, text)
end

-- the one entry point of staff events: permission first, then the handler with the player's own language
local function staffEvent(event, action, handler)
    RegisterNetEvent(event, function(...)
        local src = source
        if not may(src, action) then return say(src, 'noperms') end
        handler(src, Translation.ForPlayer(src), ...)
    end)
end

-- same, for events that need an existing target player as their first argument
local function targetEvent(event, action, handler)
    staffEvent(event, action, function(src, T, who, ...)
        who = target(who)
        if not who then return say(src, 'userNotExist') end
        handler(src, T, who, ...)
    end)
end

local function outranks(src, other)
    return rankOf(groupOf(other)) < rankOf(groupOf(src))
end

local function cooling(src)
    local now, wait = os.time(), tonumber(Config.AlertCooldown) or 60
    if lastAlert[src] and now - lastAlert[src] < wait then
        Core.NotifyRightTip(src, Translation.ForPlayer(src).Notify.waitToReportAgain .. tostring(wait - (now - lastAlert[src])), 4000)
        return true
    end
    lastAlert[src] = now
    return false
end

-- the identifier behind a whitelist id or an identifier, as long as that person ranks below the sender
local function offlineIdentifier(src, value)
    local id = tonumber(value)
    local identifier = type(value) == 'string' and value:match('^[%w_]+:[%w]+$') and value or nil
    if not identifier and id then
        local row = MySQL.single.await('SELECT identifier FROM jrs_whitelist WHERE id = ?', { id })
        identifier = row and row.identifier
    end
    if not identifier then return nil end

    local best = rankOf((MySQL.single.await('SELECT `group` FROM users WHERE identifier = ?', { identifier }) or {}).group or 'user')
    if Config.UseCharactersAdmin then
        for _, row in ipairs(MySQL.query.await('SELECT `group` FROM characters WHERE identifier = ?', { identifier }) or {}) do
            best = math.max(best, rankOf(row.group))
        end
    end
    if best >= rankOf(groupOf(src)) then return nil end
    return identifier
end

-- ------------------------------------------------------------------ callbacks

Core.Callback.Register('jrs_admin:Callback:getplayersinfo', function(src, cb, args)
    if type(args) ~= 'table' then return cb(false) end
    local staff = isStaff(src)
    local publicBoard = not staff and Config.UseUsersMenu and Config.EnablePlayerlist and args.search == 'all'
    if not staff and not publicBoard then return cb(false) end

    local now = {}
    for _, raw in ipairs(GetPlayers()) do
        local id = tonumber(raw)
        local user = Core.getUser(id)
        local data = user and card(user, id)
        if data then
            data.Group = groupOf(id) or 'user'
            now[id] = publicBoard and { serverId = id, PlayerName = data.PlayerName, Job = data.Job, Group = data.Group } or data
        end
    end
    snapshot = now

    if args.search == 'search' then return cb(now[tonumber(args.id)] or false) end
    cb(now)
end)

Core.Callback.Register('jrs_admin:getSelfInfo', function(src, cb)
    local user = Core.getUser(src)
    cb(user and card(user, src) or false)
end)

Core.Callback.Register('jrs_admin:CanOpenStaffMenu', function(src, cb, action)
    cb(Core.getUser(src) ~= nil and may(src, action))
end)

Core.Callback.Register('jrs_admin:getReports', function(src, cb)
    cb(may(src, 'view_reports_menu') and reports or false)
end)

-- ------------------------------------------------------------------ going to and from players

targetEvent('jrs_admin:TpToPlayer', 'tp_to_player', function(src, T, who, _, name)
    name = cleanText(name, 80)
    TriggerClientEvent('jrs_admin:gotoPlayer', src, GetEntityCoords(GetPlayerPed(who)))
    if name ~= '' then
        audit(src, Logs.AdminLogs.Goto, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedgoto .. '\n> ' .. name)
    else
        audit(src, Logs.TeleportLogs.Tptoplayer, T.Webhooks.ActionTeleport.title, T.Webhooks.ActionTeleport.usedtptoplayer .. '\nID: ' .. who)
    end
end)

staffEvent('jrs_admin:sendAdminBack', 'send_player_back', function(src)
    TriggerClientEvent('jrs_admin:sendAdminBack', src)
end)

targetEvent('jrs_admin:Bring', 'bring_player', function(src, T, who, _, _, name, label)
    name = cleanText(name, 80)
    TriggerClientEvent('jrs_admin:Bring', who, GetEntityCoords(GetPlayerPed(src)))
    if name ~= '' then
        audit(src, Logs.AdminLogs.Bring, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedbring .. '\n> ' .. name)
    end
    if label then
        audit(src, Logs.TeleportLogs.Bringplayer, T.Webhooks.ActionTeleport.title, T.Webhooks.ActionTeleport.usedbringplayer .. '\nID: ' .. tostring(label))
    end
end)

targetEvent('jrs_admin:TeleportPlayerBack', 'tp_player_back', function(_, _, who)
    TriggerClientEvent('jrs_admin:TeleportPlayerBack', who)
end)

targetEvent('jrs_admin:spectate', 'spectate', function(src, T, who, _, name)
    TriggerClientEvent('jrs_admin:spectatePlayer', src, who, GetEntityCoords(GetPlayerPed(who)))
    audit(src, Logs.AdminLogs.Spectate, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedspectate .. '\n > ' .. cleanText(name, 64))
end)

staffEvent('jrs:teleportWayPoint', 'tp_to_waypoint', function(src, T, _, coords, waypoint)
    local text = T.Webhooks.ActionTeleport.usedtpm .. '\nWaypoint teleported to ' .. tostring(waypoint) .. '\nfrom Coords : ' .. tostring(coords)
    audit(src, Logs.TeleportLogs.Tpm, T.Webhooks.ActionTeleport.title, text)
    TriggerClientEvent('jrs:teleportWayPoint', src, coords)
end)

staffEvent('jrs_admin:tptocoords', 'tp_to_coords', function(src, T, from, x, y, z)
    audit(src, Logs.TeleportLogs.Tptocoords, T.Webhooks.ActionTeleport.title,
        T.Webhooks.ActionTeleport.usedtptocoords .. '\nfrom coords: ' .. tostring(from) .. '\nto coords: ' .. tostring(vector3(x, y, z)))
end)

-- ------------------------------------------------------------------ actions on one player

targetEvent('jrs_admin:freeze', 'freeze_player', function(src, T, who, frozen, _, name)
    TriggerClientEvent('jrs_admin:Freezeplayer', who, frozen == true)
    name = cleanText(name, 80)
    if name ~= '' then
        audit(src, Logs.AdminLogs.Freezed, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedfreeze .. '\n> ' .. name)
    end
end)

targetEvent('jrs_admin:revive', 'revive_player', function(src, T, who, _, name)
    name = cleanText(name, 80)
    if name ~= '' then audit(src, Logs.AdminLogs.Revive, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedreviveplayer .. '\n> ' .. name) end
    Core.Player.Revive(who)
end)

targetEvent('jrs_admin:heal', 'heal_player', function(src, T, who, _, name)
    name = cleanText(name, 80)
    if name ~= '' then audit(src, Logs.AdminLogs.Heal, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedhealplayer .. '\n> ' .. name) end
    Core.Player.Heal(who)
end)

targetEvent('jrs_admin:respawnPlayer', 'respawn_player', function(src, T, who, _, name)
    exports.jrs_inventory:closeInventory(who)
    local N = Translation.ForPlayer(who).Notify
    TriggerClientEvent('jrs:updatemissioNotify', who, N.respawnedNotify, N.lostAllItems, 8000)
    SetTimeout(5000, function()
        Core.Player.Respawn(who)
        TriggerClientEvent('jrs_admin:respawn', who)
    end)
    audit(src, Logs.AdminLogs.Respawn, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedrespawn .. '\n > ' .. cleanText(name, 80))
end)

targetEvent('jrs_admin:kick', 'kick_player', function(src, T, who, reason, _, name)
    if not outranks(src, who) then return say(src, 'cantKickStaff') end
    reason = cleanText(reason, 200)
    local N = Translation.ForPlayer(who).Notify
    TriggerClientEvent('jrs:updatemissioNotify', who, N.kickedNotify, N.kickedNotify, 5000)
    SetTimeout(5000, function() DropPlayer(who, reason) end)
    audit(src, Logs.AdminLogs.Kick, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedkick .. '\n > ' .. cleanText(name, 64) .. '\n: ' .. reason)
end)

staffEvent('jrs_admin:BanPlayer', 'ban_player', function(src, T, who, staticId, length, _, name)
    who = target(who)
    local hours = banHours(length)
    if not who or not hours then return say(src, 'userNotExist') end
    if not outranks(src, who) then return say(src, 'cantBanStaff') end

    local identifier = Core.getUser(who).getUsedCharacter.identifier
    local until_ = hours == 0 and 0 or os.time() + hours * 3600
    local N = Translation.ForPlayer(who).Notify
    TriggerClientEvent('jrs:updatemissioNotify', who, N.bannedNotify, N.bannedNotify, 8000)
    SetTimeout(8000, function() TriggerEvent('jrsbans:addtodb', true, identifier or tonumber(staticId), until_) end)
    audit(src, Logs.AdminLogs.Ban, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedban .. '\n > ' .. cleanText(name, 64) .. '\n: ' .. cleanText(length, 16))
end)

staffEvent('jrs_admin:setGroup', 'set_group', function(src, T, who, group, _, name)
    who = target(who)
    if not who then return say(src, 'userNotExist') end
    group = tostring(group or '')
    if group ~= 'user' and not Config.AllowedActions[group] then return say(src, 'invalidGroup') end

    local mine = rankOf(groupOf(src))
    if mine < rankOf('owner') and (rankOf(group) >= mine or rankOf(groupOf(who)) >= mine) then
        return say(src, 'cannotGiveGroup')
    end

    local user = Core.getUser(who)
    if Config.giveCharacterGroup then user.getUsedCharacter.setGroup(group) end
    if Config.giveUserGroup then user.setGroup(group) end

    local effective = 'none'
    if (Config.UseCharactersAdmin and Config.giveCharacterGroup) or (not Config.UseCharactersAdmin and Config.giveUserGroup) then
        effective = group
    end
    staffOnline[who] = Config.AllowedActions[effective] and true or nil

    Core.NotifyRightTip(who, Translation.ForPlayer(who).Notify.groupGiven .. effective, 5000)
    audit(src, Logs.AdminLogs.Setgroup, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedsetgroup .. '\n > ' .. cleanText(name, 80) .. '\nGroup: ' .. group)
end)

staffEvent('jrs_admin:setJob', 'set_job', function(src, T, who, job, grade, label, _, name)
    who = target(who)
    if not who then return say(src, 'userNotExist') end

    job = cleanText(job, 50)
    grade = math.floor(tonumber(grade) or 0)
    label = cleanText(label or job, 50)
    if job == '' or grade < 0 or grade > 100 then return say(src, 'invalidAdd') end

    local character = Core.getUser(who).getUsedCharacter
    if exports.jrs_core:SetJob(who, job, grade) ~= true then return say(src, 'actionFailed', 4000) end
    character.setJobLabel(label)
    MySQL.update.await('UPDATE characters SET joblabel = ? WHERE identifier = ? AND charidentifier = ?', { label, character.identifier, character.charIdentifier })
    Player(who).state:set('JobLabel', label, true)

    local N = Translation.ForPlayer(who).Notify
    Core.NotifyRightTip(who, N.jobGiven .. job, 5000)
    Core.NotifyRightTip(who, N.gradeGiven .. grade, 5000)
    Core.NotifyRightTip(who, N.jobLabelGiven .. label, 5000)
    audit(src, Logs.AdminLogs.Setjob, T.Webhooks.ActionsAdmin.title,
        T.Webhooks.ActionsAdmin.usedsetjob .. '\n > ' .. cleanText(name, 80) .. '\nJob:  ' .. job .. ' \nGrade: ' .. grade)
end)

-- ------------------------------------------------------------------ whitelist and bans

local function validIdentifier(value) return type(value) == 'string' and value:match('^[%w_]+:[%w]+$') ~= nil end

staffEvent('jrs_admin:Whitelist', 'whitelist_player', function(src, T, _, steam, _, _, name)
    if not validIdentifier(steam) then return say(src, 'invalidAdd', 4000) end
    Core.Whitelist.unWhitelistUser(steam)
    audit(src, Logs.AdminLogs.Unwhitelist, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedunwhitelist .. '\n > ' .. cleanText(name, 80) .. '\n: ' .. steam)
end)

staffEvent('jrs_admin:Whitelistoffline', 'whitelist_player', function(src, _, steam, action)
    if action ~= 'whitelist' and action ~= 'unwhitelist' then return end
    if not validIdentifier(steam) then return say(src, 'invalidAdd', 4000) end
    if action == 'whitelist' then Core.Whitelist.whitelistUser(steam) else Core.Whitelist.unWhitelistUser(steam) end
end)

staffEvent('jrs_admin:Unban', 'unban_player', function(src, T, staticId, _, name)
    audit(src, Logs.AdminLogs.Unban, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedunban .. '\n > ' .. cleanText(name, 80) .. '\n: ' .. tostring(staticId))
    local identifier = offlineIdentifier(src, staticId)
    if not identifier then return say(src, 'invalidAdd', 4000) end
    TriggerEvent('jrsbans:addtodb', false, identifier, 0)
end)

staffEvent('jrs_admin:BanOffline', 'ban_offline', function(src, T, staticId, length)
    local hours = banHours(length)
    if not tonumber(staticId) or not hours then return say(src, 'invalidAdd') end
    local identifier = offlineIdentifier(src, staticId)
    if not identifier then return say(src, 'invalidAdd', 4000) end
    TriggerEvent('jrsbans:addtodb', true, identifier, hours == 0 and 0 or os.time() + hours * 3600)
    audit(src, Logs.AdminLogs.Ban, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedban .. '\n > offline ID ' .. tonumber(staticId) .. '\n: ' .. cleanText(length, 16))
end)

-- ------------------------------------------------------------------ the database section

local stableModels = nil           -- horse models the stable resource knows, read once from its config
local function giveHorse(character, model, name, sex)
    local resource = Config.Integrations.horseResource
    if GetResourceState(resource) ~= 'started' then return false end
    model = tostring(model or ''):lower()

    if not stableModels then
        stableModels = {}
        local raw = (LoadResourceFile(resource, 'config/horses.lua') or ''):lower()
        for found in raw:gmatch('["\'](a_c_horse_[%w_]+)["\']') do stableModels[found] = true end
    end

    local gender = ({ [0] = 'male', [1] = 'female' })[tonumber(sex)]
    name = cleanText(name, 80)
    if not stableModels[model] or not gender or name == '' then return false end

    local row = MySQL.insert.await('INSERT INTO player_horses (identifier, charid, name, model, gender, captured) VALUES (?, ?, ?, ?, ?, ?)',
        { character.identifier, character.charIdentifier, name, model, gender, 0 })
    return row ~= nil and row ~= false
end

local gifts = {}

function gifts.item(ctx, a, b)
    local item = type(a) == 'string' and a or nil
    local qty = math.floor(tonumber(b) or 0)
    if not item or qty < 1 or qty > 10000 then return say(ctx.src, 'invalidAdd', 5000) end

    local def = exports.jrs_inventory:getItemDB(item)
    if not def then return say(ctx.src, 'doesNotExistInDB', 5000) end
    if not exports.jrs_inventory:canCarryItem(ctx.who, item, qty) then return say(ctx.src, 'itemLimit', 5000) end

    exports.jrs_inventory:addItem(ctx.who, item, qty)
    local N = Translation.ForPlayer(ctx.who).Notify
    Core.NotifyRightTip(ctx.who, N.receivedItem .. qty .. N['of'] .. def.label .. '~q~', 5000)
    say(ctx.src, 'itemGiven', 4000)
    audit(ctx.src, Logs.DatabaseLogs.Giveitem, ctx.T.Webhooks.ActionDatabase.title,
        ctx.T.Webhooks.ActionDatabase.usedgiveitem .. '\nPlayer: ' .. ctx.name .. '\nItem: ' .. item .. '\nQTY: ' .. qty)
end

function gifts.weapon(ctx, a)
    local weapon = type(a) == 'string' and a:upper() or nil
    if not weapon or not weapon:find('^WEAPON_') then return say(ctx.src, 'invalidAdd', 5000) end
    if not exports.jrs_inventory:canCarryWeapons(ctx.who, 1, nil, weapon) then return say(ctx.src, 'cantCarryWeapon', 5000) end

    local character = ctx.character
    local finished = false
    local function finish(ok, why)
        if finished then return end
        finished = true
        if ok ~= true then
            return say(ctx.src, why == 'invalid_weapon' and 'invalidAdd' or why == 'full' and 'cantCarryWeapon' or 'actionFailed', 4000)
        end
        local now = Core.getUser(ctx.who)
        local c = now and now.getUsedCharacter
        if c and c.identifier == character.identifier and c.charIdentifier == character.charIdentifier then
            say(ctx.who, 'receivedWeapon', 5000)
        end
        say(ctx.src, 'weaponGiven', 4000)
        audit(ctx.src, Logs.DatabaseLogs.Giveweapon, ctx.T.Webhooks.ActionDatabase.title,
            ctx.T.Webhooks.ActionDatabase.usedgiveweapon .. '\nPlayer: ' .. ctx.name .. '\nWeapon: ' .. weapon)
    end

    local ok, accepted = pcall(function()
        return exports.jrs_inventory:createWeaponOwned(ctx.who, weapon, {}, {}, finish, { sourceResource = 'jrs_admin' })
    end)
    if not ok or accepted == false then finish(false) end
    SetTimeout(15000, function() finish(false, 'timeout') end)
end

function gifts.moneygold(ctx, a, b)
    local currency, qty = tonumber(a), tonumber(b)
    if not qty or qty ~= qty or qty <= 0 or qty > 1000000 or (currency ~= 0 and currency ~= 1) then
        return say(ctx.src, 'addQuantity', 5000)
    end
    ctx.character.addCurrency(currency, qty)
    local N = Translation.ForPlayer(ctx.who).Notify
    Core.NotifyRightTip(ctx.who, N.receivedItem .. qty .. (currency == 0 and N.money or N.gold), 5000)
    say(ctx.src, 'sent', 4000)
    audit(ctx.src, Logs.DatabaseLogs.Givecurrency, ctx.T.Webhooks.ActionDatabase.title,
        ctx.T.Webhooks.ActionDatabase.usedgivecurrency .. '\nPlayer: ' .. ctx.name .. '\nCurrency: ' .. currency .. '\nQTY: ' .. qty)
end

function gifts.horse(ctx, model, name, sex)
    if not giveHorse(ctx.character, model, name, sex) then return say(ctx.src, 'invalidAdd', 5000) end
    say(ctx.who, 'horseReceived', 5000)
    say(ctx.src, 'horseGiven', 4000)
    audit(ctx.src, Logs.DatabaseLogs.Givehorse, ctx.T.Webhooks.ActionDatabase.title, 'Horse: ' .. tostring(model) .. ' -> ' .. tostring(ctx.who))
end

function gifts.wagon(ctx, a, b)
    local resource = Config.Integrations.wagonResource
    if resource == '' or GetResourceState(resource) ~= 'started' then return say(ctx.src, 'integrationMissing', 5000) end
    local model, name = cleanText(a, 50), cleanText(b, 50)
    if model == '' or name == '' then return say(ctx.src, 'invalidAdd', 4000) end
    local ok, granted = pcall(function() return exports[resource]:GrantWagon(ctx.who, model, name) end)
    if not ok or granted ~= true then return say(ctx.src, 'actionFailed', 4000) end
    say(ctx.who, 'wagonReceived', 5000)
    say(ctx.src, 'givenWagon', 4000)
    audit(ctx.src, Logs.DatabaseLogs.Givewagon, ctx.T.Webhooks.ActionDatabase.title, 'Wagon: ' .. model .. ' -> ' .. tostring(ctx.who))
end

RegisterNetEvent('jrs_admin:givePlayer', function(who, kind, a, b, c, _, name)
    local src = source
    local T = Translation.ForPlayer(src)
    who = tonumber(who)
    local user = who and Core.getUser(who)
    if not user then return say(src, 'userNotExist') end
    if type(kind) ~= 'string' or not gifts[kind] or not may(src, 'give_' .. kind) then return say(src, 'noperms') end

    gifts[kind]({ src = src, who = who, T = T, name = cleanText(name, 80), character = user.getUsedCharacter }, a, b, c)
end)

RegisterNetEvent('jrs_admin:ClearAllItems', function(kind, who, _, name)
    local src = source
    local T = Translation.ForPlayer(src)
    if not may(src, 'clear_inventory') then return say(src, 'noperms') end
    who = target(who)
    if not who then return say(src, 'userNotExist') end
    name = cleanText(name, 80)

    exports.jrs_inventory:closeInventory(who)
    local D = T.Webhooks.ActionDatabase

    if kind == 'items' then
        if not exports.jrs_inventory:getUserInventoryItems(who) then return say(src, 'inventoryEmpty') end
        exports.jrs_inventory:subAllItems(who)
        say(src, 'itemsWiped', 4000)
        say(who, 'itemWipe', 5000)
        audit(src, Logs.DatabaseLogs.Clearitems, D.title, D.usedclearitems .. '\nPlayer: ' .. name .. '\nID: ' .. who)
    elseif kind == 'weapons' then
        for _, weapon in pairs(exports.jrs_inventory:getUserInventoryWeapons(who) or {}) do
            exports.jrs_inventory:subWeapon(who, weapon.id)
        end
        TriggerClientEvent('jrs_admin:clearAmmo', who)
        say(src, 'weaponsWiped', 4000)
        say(who, 'weaponWipe', 5000)
        audit(src, Logs.DatabaseLogs.Clearweapons, D.title, D.usedclearweapons .. '\nPlayer: ' .. name .. '\nID: ' .. who)
    end
end)

targetEvent('jrs_admin:checkInventory', 'check_player_inventory', function(src, _, who)
    TriggerClientEvent('jrs_admin:getplayerInventory', src, exports.jrs_inventory:getUserInventoryItems(who))
end)

targetEvent('jrs_admin:openInventory', 'check_player_inventory', function(src, _, who)
    local ok, opened = pcall(function() return exports.jrs_inventory:OpenPlayerInventoryAdmin(src, who) end)
    if not ok or opened == false then say(src, 'actionFailed', 4000) end
end)

staffEvent('jrs_admin:ClearCurrency', 'clear_currency', function(src, T, who, kind, _, name)
    who = target(who)
    if not who then return say(src, 'userNotExist') end
    local character = Core.getUser(who).getUsedCharacter
    local D = T.Webhooks.ActionDatabase
    name = cleanText(name, 80)

    if kind == 'money' then
        character.removeCurrency(0, character.money)
        say(src, 'moneyRemoved', 4000)
        say(who, 'moneyRemovedFromAdmin', 4000)
        audit(src, Logs.DatabaseLogs.Clearmoney, D.title, D.usedclearmoney .. '\nPlayer: ' .. name .. '\nID: ' .. who .. '\nCurrency: ' .. kind)
    elseif kind == 'gold' then
        character.removeCurrency(1, character.gold)
        say(src, 'goldRemoved', 4000)
        say(who, 'goldRemovedFromAdmin', 4000)
        audit(src, Logs.DatabaseLogs.Cleargold, D.title, D.usedcleargold .. '\nPlayer: ' .. name .. '\nID: ' .. who .. '\nCurrency: ' .. kind)
    end
end)

-- ------------------------------------------------------------------ boosters (the client does the work, the server logs it)

local function booster(event, action, hook, text, formatter)
    staffEvent(event, action, function(src, T, value)
        local B = T.Webhooks.ActionBoosters
        audit(src, Logs.BoosterLogs[hook], B.title, formatter and formatter(value) or B[text])
    end)
end

booster('jrs_admin:spawnHorse', 'spawn_horse', 'SelfSpawnHorse', nil, function(model) return 'Horse: ' .. tostring(model) end)
booster('jrs_admin:spawnWagon', 'spawn_wagon', 'SelfSpawnWagon', nil, function(model) return 'Wagon: ' .. tostring(model) end)
booster('jrs_admin:GodMode', 'godmode', 'GodMode', 'usedgod')
booster('jrs_admin:GoldenCores', 'golden_cores', 'GoldenCores', 'usedgoldcores')
booster('jrs_admin:InfiAmmo', 'infinite_ammo', 'InfiniteAmmo', 'usedinfinitammo')
booster('jrs_admin:NoClip', 'noclip', 'NoClip', 'usednoclip')

staffEvent('jrs_admin:HealSelf', 'selfheal', function(src, T)
    audit(src, Logs.BoosterLogs.SelfHeal, T.Webhooks.ActionBoosters.title, T.Webhooks.ActionBoosters.usedheal .. '\n> ' .. characterName(src))
    Core.Player.Heal(src)
end)

staffEvent('jrs_admin:ReviveSelf', 'selfrevive', function(src, T)
    audit(src, Logs.BoosterLogs.SelfRevive, T.Webhooks.ActionBoosters.title, T.Webhooks.ActionBoosters.usedrevive .. '\n> ' .. characterName(src))
    Core.Player.Revive(src)
end)

staffEvent('jrs_admin:announce', 'allow_announce', function(src, T, text)
    text = cleanText(text, 300)
    if text == '' then return end
    audit(src, Logs.AdminLogs.Announce, T.Webhooks.ActionsAdmin.title, T.Webhooks.ActionsAdmin.usedannounce .. '\n > ' .. text)
    for _, id in ipairs(GetPlayers()) do
        Core.NotifySimpleTop(tonumber(id), Translation.ForPlayer(id).Notify.announce, text, 10000)
    end
end)

-- ------------------------------------------------------------------ troll actions

-- event, permission, what the target's client runs
local trolls = {
    { 'ServerTrollKillPlayerHandler',      'troll_kill_player',        'ClientTrollKillPlayerHandler' },
    { 'ServerTrollInvisibleHandler',       'troll_invisible',          'ClientTrollInvisbleHandler' },
    { 'ServerTrollSetPlayerOnFireHandler', 'troll_set_player_on_fire', 'ClientTrollSetPlayerOnFireHandler' },
    { 'ServerTrollTPToHeavenHandler',      'troll_tp_to_heaven',       'ClientTrollTPToHeavenHandler' },
    { 'ServerTrollRagdollPlayerHandler',   'troll_ragdoll_player',     'ClientTrollRagdollPlayerHandler' },
    { 'ServerDrainPlayerStamHandler',      'troll_drain_player_stam',  'ClientDrainPlayerStamHandler' },
    { 'ServerHandcuffPlayerHandler',       'troll_handcuff_player',    'ClientHandcuffPlayerHandler' },
    { 'ServerTempHighPlayerHandler',       'troll_temp_high_player',   'ClientTempHighPlayerHandler' },
}

for _, t in ipairs(trolls) do
    staffEvent('jrs_admin:' .. t[1], t[2], function(_, _, who)
        who = target(who)
        if who then TriggerClientEvent('jrs_admin:' .. t[3], who) end
    end)
end

-- lightning is seen by everybody around, so it goes to all players
staffEvent('jrs_admin:ServerTrollLightningStrikePlayerHandler', 'troll_lightning_strike', function(_, _, who)
    who = target(who)
    if who then TriggerClientEvent('jrs_admin:ClientTrollLightningStrikePlayerHandler', -1, GetEntityCoords(GetPlayerPed(who))) end
end)

-- ------------------------------------------------------------------ reports and requests

RegisterNetEvent('jrs_admin:closeReport', function(id)
    local src = source
    if not may(src, 'view_reports_menu') then return end
    for _, report in ipairs(reports) do
        if report.id == tonumber(id) then report.closed = true end
    end
    say(src, 'reportClosed', 3000)
end)

local function tellStaff(compose)
    for _, raw in ipairs(GetPlayers()) do
        local staff = tonumber(raw)
        if isStaff(staff) then Core.NotifyRightTip(staff, compose(Translation.ForPlayer(staff).Notify), 4000) end
    end
end

RegisterNetEvent('jrs_admin:alertstaff', function(text)
    local src = source
    local T = Translation.ForPlayer(src)
    local user = Core.getUser(src)
    if not user or not user.getUsedCharacter then return end

    text = cleanText(text, 500)
    if #text < 3 or cooling(src) then return end

    lastReportId = lastReportId + 1
    reports[#reports + 1] = { id = lastReportId, source = src, name = characterName(src), text = text, created = os.date('%Y-%m-%d %H:%M'), closed = false }
    if #reports > 100 then table.remove(reports, 1) end
    say(src, 'reportSent', 4000)

    local who = characterName(src)
    tellStaff(function(N) return N.player .. who .. N.reportedToDiscord end)
    audit(src, Logs.ReportLogs.Reports, T.Webhooks.ActionScoreBoard.title, T.Webhooks.ActionScoreBoard.playerreported .. text)
end)

local requests = {
    new      = { note = 'new',              hook = 'RequestStaff', log = 'requeststaff_disc' },
    bug      = { note = 'foundBug',         hook = 'BugReport',    log = 'requeststaff_bug' },
    rules    = { note = 'someoneBrokerules', hook = 'RulesBroken', log = 'requeststaff_rulesbroke' },
    cheating = { note = 'someoneCheating',  hook = 'Cheating',     log = 'requeststaff_cheating' },
}

RegisterNetEvent('jrs_admin:requeststaff', function(kind)
    local src = source
    local T = Translation.ForPlayer(src)
    local user = Core.getUser(src)
    local request = requests[kind]
    if not request or not user or not user.getUsedCharacter or cooling(src) then return end

    say(src, 'requestSent', 4000)
    local who = characterName(src)
    tellStaff(function(N) return who .. ' ID: ' .. src .. N.requestingAssistance .. N[request.note] end)
    audit(src, Logs.ReportLogs[request.hook], T.Webhooks.ActionScoreBoard.title, T.Webhooks.ActionScoreBoard[request.log])
end)

-- ------------------------------------------------------------------ discord log

AddEventHandler('jrs_admin:logs', function(src, webhook, title, description)
    local identifier = tostring(GetPlayerIdentifier(src, 1) or GetPlayerIdentifier(src, 0) or 'none')
    local discord = GetPlayerIdentifierByType(src, 'discord')
    local discordId = discord and discord:sub(9) or 'no discord'
    local ip = GetPlayerEndpoint(src) or 'none'
    description = tostring(description or ''):gsub('`', "'")

    local message = ('**Steam name: **`%s`**\nIdentifier**`%s` \n**Discord:** <@%s>**\nIP: **`%s`\n `%s`'):format(
        cleanText(GetPlayerName(src) or 'unknown', 64), identifier, discordId, ip, description)
    Core.AddWebhook(title, webhook, message, Logs.webhookColor, Logs.name, Logs.logo, Logs.footerLogo, Logs.avatar)
end)

-- ------------------------------------------------------------------ who is online

local function registerPlayer(src)
    local user = Core.getUser(src)
    if not user then return end
    if Config.AllowedActions[groupOf(src)] then staffOnline[src] = true end
    snapshot[src] = card(user, src)
end

AddEventHandler('jrs:SelectedCharacter', function(src)
    if Config.DevMode then return print('^1DevMode is enabled, disable on live servers^7') end
    registerPlayer(src)
end)

if Config.DevMode then
    RegisterNetEvent('jrs_admin:getStaffInfo', function() registerPlayer(source) end)
end

AddEventHandler('playerDropped', function()
    local src = source
    staffOnline[src], snapshot[src], lastAlert[src] = nil, nil, nil
end)
