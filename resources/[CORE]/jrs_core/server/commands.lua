local function notifyCommandSource(source, message, duration, isError, icon)
    message = tostring(message or "Unknown result")
    duration = tonumber(duration) or 5000

    if tonumber(source) == 0 then
        local prefix = isError and "[jrs_core][ERROR] " or "[jrs_core] "
        print(prefix .. message)
        return
    end

    TriggerClientEvent(
        'jrsCore:notify',
        tonumber(source),
        isError and 'COMMAND FAILED' or 'COMMAND SUCCESS',
        message,
        tostring(icon or 'placeholder'),
        duration
    )
end

local function notifyCommandTarget(target, message, duration, isError, icon)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return end
    TriggerClientEvent(
        'jrsCore:notify',
        target,
        isError and 'SERVER ACTION FAILED' or 'SERVER ACTION',
        tostring(message or ''),
        tostring(icon or 'placeholder'),
        tonumber(duration) or 5000
    )
end

function isAdminOrConsole(source, commandKey)
    if source == 0 then return true end

    local playerSource = tonumber(source)
    local user = jrsCore.getUser(playerSource)
    local allowed = user ~= nil and Config.CanUseCommand(user.group, commandKey)
    if not allowed then
        notifyCommandSource(playerSource, _Up(playerSource, 'command_permission_denied'), 4000, true)
        return false
    end
    return true
end

local adminCommandSuggestions = {
    {
        key = 'addwhitelist',
        help = 'suggest_addwh',
        params = {
            { name = 'suggest_param_discord_id', help = 'suggest_param_discord_id_help' },
        },
    },
    {
        key = 'removewhitelist',
        help = 'suggest_removewh',
        params = {
            { name = 'suggest_param_discord_id', help = 'suggest_param_discord_id_help' },
        },
    },
    {
        key = 'checkwhitelist',
        help = 'suggest_checkwh',
        params = {
            { name = 'suggest_param_discord_id', help = 'suggest_param_discord_id_help' },
        },
    },
    {
        key = 'setjob',
        help = 'suggest_setjob',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_job', help = 'suggest_param_job_help' },
            { name = 'suggest_param_grade', help = 'suggest_param_grade_help' },
        },
    },
    {
        key = 'setchar',
        help = 'suggest_setchar',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_char_count', help = 'suggest_param_char_count_help' },
        },
    },
    {
        key = 'delchar',
        help = 'suggest_delchar',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
        },
    },
    {
        key = 'setgroup',
        help = 'suggest_setgroup',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_group', help = 'suggest_param_group_help' },
        },
    },
    {
        key = 'giveitem',
        help = 'suggest_giveitem',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_item', help = 'suggest_param_item_help' },
            { name = 'suggest_param_count', help = 'suggest_param_count_help' },
        },
    },
    {
        key = 'giveweapon',
        help = 'suggest_giveweapon',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_weapon', help = 'suggest_param_weapon_help' },
            { name = 'suggest_param_ammo', help = 'suggest_param_ammo_help' },
        },
    },
    {
        key = 'givemoney',
        help = 'suggest_givemoney',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_currency', help = 'suggest_param_currency_help' },
            { name = 'suggest_param_amount', help = 'suggest_param_amount_help' },
        },
    },
    {
        key = 'revive',
        help = 'suggest_revive',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
        },
    },
    {
        key = 'addxp',
        help = 'suggest_addxp',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_amount', help = 'suggest_param_amount_help' },
            { name = 'suggest_param_reason', help = 'suggest_param_reason_help' },
        },
    },
    {
        key = 'removexp',
        help = 'suggest_removexp',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_amount', help = 'suggest_param_amount_help' },
            { name = 'suggest_param_reason', help = 'suggest_param_reason_help' },
        },
    },
    {
        key = 'setxp',
        help = 'suggest_setxp',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_amount', help = 'suggest_param_amount_help' },
        },
    },
    {
        key = 'doublexp',
        help = 'suggest_doublexp',
        params = {
            { name = 'suggest_param_multiplier', help = 'suggest_param_multiplier_help' },
            { name = 'suggest_param_minutes', help = 'suggest_param_minutes_help' },
        },
    },
    {
        key = 'tpm',
        help = 'suggest_tpm',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_optional_id_help' },
        },
    },
    {
        key = 'setlang',
        help = 'suggest_setlang',
        params = {
            { name = 'suggest_param_player_id', help = 'suggest_param_player_id_help' },
            { name = 'suggest_param_language', help = 'suggest_param_language_help' },
        },
    },
    {
        key = 'language',
        help = 'suggest_language',
        params = {
            { name = 'suggest_param_language', help = 'suggest_param_language_help' },
        },
    },
}

function RefreshAdminCommandSuggestions(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource then return end

    local user = jrsCore.getUser(playerSource)
    for _, suggestion in ipairs(adminCommandSuggestions) do
        local commandName = Config.Commands[suggestion.key]
        if commandName then
            TriggerClientEvent('chat:removeSuggestion', playerSource, '/' .. commandName)
        end
    end

    if not user then return end

    local suggestions = {}
    for _, suggestion in ipairs(adminCommandSuggestions) do
        local commandName = Config.Commands[suggestion.key]
        if commandName and Config.CanUseCommand(user.group, suggestion.key) then
            local params = {}
            for _, param in ipairs(suggestion.params or {}) do
                params[#params + 1] = {
                    name = _Up(playerSource, param.name),
                    help = _Up(playerSource, param.help),
                }
            end
            suggestions[#suggestions + 1] = {
                name = '/' .. commandName,
                help = _Up(playerSource, suggestion.help),
                params = params,
            }
        end
    end

    if #suggestions > 0 then
        TriggerClientEvent('chat:addSuggestions', playerSource, suggestions)
    end
end

RegisterNetEvent('jrs_core:requestCommandSuggestions')
AddEventHandler('jrs_core:requestCommandSuggestions', function()
    RefreshAdminCommandSuggestions(source)
end)

local function resolveTargetIdentifier(input)
    local raw = tostring(input or ''):gsub('%s+', '')
    if raw == '' then return nil end

    local targetServerId = tonumber(raw)
    if targetServerId and targetServerId > 0 and GetPlayerName(targetServerId) then
        for _, id in ipairs(GetPlayerIdentifiers(targetServerId)) do
            if id:sub(1, 8) == "discord:" then
                return id
            end
        end
        for _, id in ipairs(GetPlayerIdentifiers(targetServerId)) do
            if id:sub(1, 6) == "steam:" then
                return id
            end
        end
    end

    if raw:match('^%d+$') then
        return 'discord:' .. raw
    end
    return raw
end

RegisterCommand(Config.Commands.addwhitelist, function(source, args)
    if not isAdminOrConsole(source, 'addwhitelist') then return end
    if not args[1] then
        notifyCommandSource(source, _Up(source, 'usage_addwh', Config.Commands.addwhitelist), 5000, true)
        return
    end

    local identifier = resolveTargetIdentifier(args[1])
    if not identifier then
        notifyCommandSource(source, _Up(source, 'usage_addwh', Config.Commands.addwhitelist), 5000, true)
        return
    end

    local pName = (source == 0) and "Console" or GetPlayerName(source) or "Admin"
    MySQL.query.await("INSERT IGNORE INTO jrs_discord_whitelist (`identifier`, `added_by`) VALUES (?, ?)", { identifier, pName })
    MySQL.query.await("INSERT IGNORE INTO jrs_whitelist (`identifier`) VALUES (?)", { identifier })

    local message = ("تمت إضافة %s إلى القائمة البيضاء بنجاح."):format(identifier)
    notifyCommandSource(source, message, 5000, false)
    if Config.Info_print then jrsCore.Debug(message) end
end)

RegisterCommand(Config.Commands.removewhitelist, function(source, args)
    if not isAdminOrConsole(source, 'removewhitelist') then return end
    if not args[1] then
        notifyCommandSource(source, _Up(source, 'usage_removewh', Config.Commands.removewhitelist), 5000, true)
        return
    end

    local identifier = resolveTargetIdentifier(args[1])
    if not identifier then
        notifyCommandSource(source, _Up(source, 'usage_removewh', Config.Commands.removewhitelist), 5000, true)
        return
    end

    MySQL.query.await("DELETE FROM jrs_discord_whitelist WHERE identifier = ?", { identifier })
    MySQL.query.await("DELETE FROM jrs_whitelist WHERE identifier = ?", { identifier })

    local message = ("تمت إزالة %s من القائمة البيضاء بنجاح."):format(identifier)
    notifyCommandSource(source, message, 5000, false)
    if Config.Info_print then jrsCore.Debug(message) end
end)

RegisterCommand(Config.Commands.checkwhitelist, function(source, args)
    if not isAdminOrConsole(source, 'checkwhitelist') then return end
    if not args[1] then
        notifyCommandSource(source, "الاستخدام: /" .. Config.Commands.checkwhitelist .. " [discord:id / steam:id / ID]", 5000, true)
        return
    end

    local identifier = resolveTargetIdentifier(args[1])
    if not identifier then
        notifyCommandSource(source, "معرّف غير صالح.", 5000, true)
        return
    end

    local row = MySQL.single.await("SELECT identifier FROM jrs_discord_whitelist WHERE identifier = ? UNION SELECT identifier FROM jrs_whitelist WHERE identifier = ? LIMIT 1", { identifier, identifier })
    if row and row.identifier then
        notifyCommandSource(source, ("المعرّف %s مسجل في القائمة البيضاء."):format(identifier), 5000, false)
    else
        notifyCommandSource(source, ("المعرّف %s غير مسجل في القائمة البيضاء."):format(identifier), 5000, true)
    end
end)

RegisterCommand(Config.Commands.setjob, function(source, args)
    if source == 0 then
        local targetId = args[1]
        local jobName = args[2]
        local jobGrade = args[3]

        if targetId and jobName and jobGrade then
            local targetUser = jrsCore.getUser(targetId)
            if targetUser then
                local changed = targetUser.getUsedCharacter.setJob(targetId, jobName, jobGrade)
                notifyCommandSource(source, changed and _Up(source, 'cmd_set_player_job_to_grade', targetId, jobName, jobGrade) or _Up(source, 'player_not_found'), 5000, changed ~= true)
                if changed then notifyCommandTarget(targetId, _Up(targetId, 'cmdt_your_job_was_set_to_grade', jobName, jobGrade), 5000, false) end
            else
                notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
            end
        else
            notifyCommandSource(source, _Up(source, 'usage_setjob'), 5000, true)
        end
        return
    end

    if not isAdminOrConsole(source, 'setjob') then return end

    local targetId = args[1]
    local jobName = args[2]
    local jobGrade = args[3]

    if targetId and jobName and jobGrade then
        local targetUser = jrsCore.getUser(targetId)
        if targetUser then
            local changed = targetUser.getUsedCharacter.setJob(targetId, jobName, jobGrade)
            if changed then
                notifyCommandSource(source, _Up(source, 'cmd_set_player_job_to_grade', targetId, jobName, jobGrade), 5000, false)
                notifyCommandTarget(targetId, _Up(targetId, 'cmdt_your_job_was_set_to_grade', jobName, jobGrade), 5000, false)
            else
                notifyCommandSource(source, _Up(source, 'cmd_the_job_change_failed'), 5000, true)
            end
        else
            notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        end
    else
        notifyCommandSource(source, _Up(source, 'usage_setjob'), 5000, true)
    end
end)

RegisterCommand(Config.Commands.setchar, function(source, args)
    if not isAdminOrConsole(source, 'setchar') then return end

    local targetSource = tonumber(args[1])
    local charCount = tonumber(args[2])

    if not targetSource or not charCount or charCount < 1 or not GetPlayerName(targetSource) then
        notifyCommandSource(source, _Up(source, 'usage_setchar'), 5000, true)
        return
    end

    local steamHex = GetPlayerIdentifierByType(targetSource, 'steam') or GetPlayerIdentifier(targetSource)
    if not steamHex then
        notifyCommandSource(source, _Up(source, 'cmd_target_player_identifier_was_not_found'), 5000, true)
        return
    end

    if LoadedUsers[steamHex] then
        LoadedUsers[steamHex].chars = charCount
    end
    if UserBySource and UserBySource[targetSource] then
        UserBySource[targetSource].chars = charCount
    end

    if charCount == Config.Char_Count then
        -- Setting the default value removes the personal override
        exports.oxmysql:execute(
            "UPDATE jrs_users SET `chars` = @chars, `chars_override` = NULL WHERE identifier = @identifier",
            { identifier = steamHex, chars = charCount }
        )
    else
        exports.oxmysql:execute(
            "UPDATE jrs_users SET `chars` = @chars, `chars_override` = @chars WHERE identifier = @identifier",
            { identifier = steamHex, chars = charCount }
        )
    end

    if Config.Info_print then
        jrsCore.Debug("Player ID " .. targetSource .. " character count set to " .. charCount)
    end
    notifyCommandSource(source, _Up(source, 'cmd_player_character_slots_set_to', targetSource, charCount), 5000, false)
    notifyCommandTarget(targetSource, _Up(targetSource, 'cmdt_your_character_slots_were_set_to', charCount), 5000, false)
end)

RegisterCommand(Config.Commands.delchar, function(source, args)
    if not isAdminOrConsole(source, 'delchar') then return end

    local targetSource = tonumber(args[1])
    if not targetSource or not GetPlayerName(targetSource) then
        notifyCommandSource(source, _Up(source, 'usage_delchar'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetSource)
    local character = targetUser and targetUser.getUsedCharacter
    if not character or not character.charIdentifier then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    local charId = tonumber(character.charIdentifier)
    exports.oxmysql:execute(
        "DELETE FROM jrs_characters WHERE charidentifier = @charidentifier",
        { charidentifier = charId },
        function(affectedRows)
            if not affectedRows or affectedRows < 1 then
                notifyCommandSource(source, _Up(source, 'cmd_character_deletion_failed_for_player', targetSource), 5000, true)
                return
            end

            local xpTable = tostring(Config.XpTable or "jrs_characters_level")
            if xpTable:match("^[%w_]+$") then
                exports.oxmysql:execute(
                    ("DELETE FROM `%s` WHERE CharIdentifier = @charidentifier"):format(xpTable),
                    { charidentifier = charId }
                )
            end

            for index, cachedCharacter in ipairs(AllCharacters) do
                if tonumber(cachedCharacter.charIdentifier) == charId then
                    table.remove(AllCharacters, index)
                    break
                end
            end

            PlayerData[targetSource] = nil
            PlayerTable[targetSource] = nil

            -- Same announcement jrs_character makes, so owned data is wiped (jrs_charwipe).
            TriggerEvent('jrs_core:server:characterDeleted', charId, character.identifier)

            if Config.Info_print then
                jrsCore.Debug("Active character for Player ID " .. targetSource .. " deleted")
            end

            notifyCommandSource(source, _Up(source, 'cmd_deleted_the_active_character_for_player', targetSource), 5000, false)
            DropPlayer(targetSource, "Your active character was deleted by an administrator.")
        end
    )
end)

RegisterCommand(Config.Commands.setgroup, function(source, args)
    if not isAdminOrConsole(source, 'setgroup') then return end

    local targetId = args[1]
    local groupName = args[2]

    if targetId and groupName then
        local targetUser = jrsCore.getUser(targetId)
        if targetUser then
            local changed = targetUser.setGroup(source, targetId, groupName)
            if changed then
                RefreshAdminCommandSuggestions(tonumber(targetId))
                notifyCommandSource(source, _Up(source, 'cmd_set_player_group_to', targetId, groupName), 5000, false)
                notifyCommandTarget(targetId, _Up(targetId, 'cmdt_your_permission_group_was_set_to', groupName), 5000, false)
            else
                notifyCommandSource(source, _Up(source, 'cmd_the_group_change_failed'), 5000, true)
            end
        else
            notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        end
    else
        notifyCommandSource(source, _Up(source, 'usage_setgroup'), 5000, true)
    end
end)

RegisterCommand(Config.Commands.getplayers, function(source, args)
    if source ~= 0 then
        notifyCommandSource(source, _Up(source, 'cmd_this_command_is_available_from_the'), 5000, true)
        return
    end
    local players = GetPlayers()
    for _, id in pairs(players) do
        print("ID: " .. id .. " | Steam: " .. GetPlayerIdentifier(id) .. " | Name: " .. GetPlayerName(id))
    end
    notifyCommandSource(source, _Up(source, 'cmd_listed_connected_players', #players), 5000, false)
end)

RegisterCommand(Config.Commands.listPlayers, function(source, args)
    if not Config.DevMode then
        notifyCommandSource(source, _Up(source, 'cmd_developer_mode_is_disabled'), 5000, true)
        return
    end
    local count = 0
    print("Connected players:")
    for playerId, data in pairs(connectedPlayers) do
        count = count + 1
        print("ID: " .. playerId .. " | Steam: " .. (data.steam or "Unknown") .. " | License: " .. (data.license or "Unknown") .. " | Last Active: " .. os.date("%Y-%m-%d %H:%M:%S", data.lastActive))
    end
    notifyCommandSource(source, _Up(source, 'cmd_listed_connected_players_in_the_server', count), 5000, false)
end, true)

RegisterCommand(Config.Commands.giveitem, function(source, args)
    if not isAdminOrConsole(source, 'giveitem') then return end

    local targetId = tonumber(args[1])
    local itemName = args[2]
    local count = math.floor(tonumber(args[3]) or 1)

    if not targetId or not itemName or count <= 0 then
        notifyCommandSource(source, _Up(source, 'usage_giveitem'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    if GetResourceState('jrs_inventory') ~= 'started' then
        notifyCommandSource(source, _Up(source, 'cmd_jrs_inventory_must_be_started_before'), 6000, true)
        return
    end

    local success, reason, data = exports['jrs_inventory']:addItem(targetId, itemName, count, nil)
    data = type(data) == 'table' and data or {}
    if success ~= true then
        local reasons = {
            full = _Up(source, 'cmd_item_inventory_full'),
            invalid_item = _Up(source, 'cmd_item_unknown', tostring(itemName)),
            invalid_count = _Up(source, 'cmd_item_count_invalid'),
            player_not_found = _Up(source, 'player_not_found'),
            not_processed = _Up(source, 'cmd_item_not_processed'),
        }
        notifyCommandSource(source, reasons[tostring(reason)] or _Up(source, 'cmd_item_give_failed', tostring(reason or 'unknown')), 6000, true, itemName)
        return
    end

    local label = _UItem(source, itemName, data.label)
    notifyCommandSource(source, _Up(source, 'cmd_gave_x_to_player', count, label, targetId), 5000, false, itemName)

    if Config.Info_print then
        jrsCore.Debug("Admin gave " .. count .. "x " .. label .. " to player " .. targetId)
    end
end)

RegisterCommand(Config.Commands.giveweapon, function(source, args)
    if not isAdminOrConsole(source, 'giveweapon') then return end

    local targetId = tonumber(args[1])
    local weaponName = args[2]
    local ammo = tonumber(args[3]) or 100

    if not targetId or not weaponName then
        notifyCommandSource(source, _Up(source, 'usage_giveweapon'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser or not targetUser.getUsedCharacter then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    if GetResourceState('jrs_inventory') ~= 'started' then
        notifyCommandSource(source, _Up(source, 'giveweapon_inventory_not_started'), 6000, true)
        return
    end

    -- The inventory export completes asynchronously and reports the real result
    -- only after the weapon limit check and database insert have finished.
    local callbackWasCalled = false
    local accepted = exports['jrs_inventory']:createWeaponOwned(
        targetId,
        weaponName,
        ammo,
        {},
        function(success, reason, data)
            callbackWasCalled = true
            data = type(data) == 'table' and data or {}

            if success then
                local serialText = data.serial_number and _Up(source, 'cmd_weapon_serial_suffix', tostring(data.serial_number)) or ''
                notifyCommandSource(source, _Up(source, 'giveweapon_success', tostring(data.weapon or weaponName), targetId) .. serialText,
                    5000,
                    false,
                    tostring(data.weapon or weaponName)
                )
                if Config.Info_print then
                    jrsCore.Debug(
                        "Admin added weapon " .. tostring(data.weapon or weaponName) ..
                        " to player " .. targetId .. " inventory slot " .. tostring(data.slot or '?')
                    )
                end
                return
            end

            if reason == 'full' then
                notifyCommandSource(source, _Up(source, 
                        'giveweapon_inventory_full',
                        targetId,
                        tonumber(data.count) or 0,
                        tonumber(data.maxWeapons) or 0
                    ),
                    6500,
                    true
                )
            elseif reason == 'invalid_weapon' then
                notifyCommandSource(source, _Up(source, 'giveweapon_invalid_weapon', tostring(weaponName)), 6000, true)
            elseif reason == 'player_not_found' then
                notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
            elseif reason == 'database_error' then
                notifyCommandSource(source, _Up(source, 'giveweapon_database_error'), 6000, true)
            else
                notifyCommandSource(source, _Up(source, 'giveweapon_failed', tostring(reason or 'unknown')), 6000, true)
            end
        end
    )

    -- Immediate validation errors can return false before asynchronous work starts.
    -- Most of them already invoke the callback; this fallback covers older inventory builds.
    if accepted == false and not callbackWasCalled then
        notifyCommandSource(source, _Up(source, 'giveweapon_failed', 'request rejected'), 6000, true)
    end
end)

RegisterCommand(Config.Commands.givemoney, function(source, args)
    if not isAdminOrConsole(source, 'givemoney') then return end

    local targetId = tonumber(args[1])
    local currencyType = tonumber(args[2])
    local amount = tonumber(args[3])

    if not targetId or currencyType == nil or not amount or amount <= 0 or currencyType < 0 or currencyType > 3 then
        notifyCommandSource(source, _Up(source, 'usage_givemoney'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    local added = Character.addCurrency(targetId, currencyType, amount)
    if added ~= true then
        notifyCommandSource(source, _Up(source, 'cmd_the_currency_could_not_be_added'), 5000, true)
        return
    end

    -- Resolved once per audience: the admin and the target may be reading in
    -- different languages.
    local currencyKeys = { [0] = 'currency_money', [1] = 'currency_gold', [2] = 'currency_rol', [3] = 'currency_dirty' }
    local currencyKey = currencyKeys[currencyType]
    local function currencyFor(who)
        if currencyKey then return _Up(who, currencyKey) end
        return _Up(who, 'currency_unknown', tostring(currencyType))
    end
    notifyCommandSource(source, _Up(source, 'cmd_gave_to_player', amount, currencyFor(source), targetId), 5000, false, 'money')
    notifyCommandTarget(targetId, _Up(targetId, 'cmdt_you_received_from_an_administrator', amount, currencyFor(targetId)), 5000, false, 'money')

    if Config.Info_print then
        jrsCore.Debug("Admin gave " .. amount .. " type " .. currencyType .. " to player " .. targetId)
    end
end)

RegisterCommand(Config.Commands.revive, function(source, args)
    if not isAdminOrConsole(source, 'revive') then return end

    local targetId = tonumber(args[1])
    if not targetId then
        notifyCommandSource(source, _Up(source, 'usage_revive'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    TriggerClientEvent('jrs_character:revive_player', targetId, 1)
    TriggerClientEvent('jrs_metabolism:AdminRevive', targetId)
    notifyCommandSource(source, _Up(source, 'cmd_revived_player', targetId), 5000, false, 'heart')
    if tonumber(source) ~= targetId then
        notifyCommandTarget(targetId, _Up(targetId, 'cmdt_you_were_revived_by_an_administrator'), 5000, false, 'heart')
    end

    if Config.Info_print then
        jrsCore.Debug("Admin revived player " .. targetId)
    end
end)

local function getXpCommandReason(args, startIndex, fallback)
    if type(args) ~= "table" then return fallback end

    local parts = {}
    for index = startIndex, #args do
        local value = tostring(args[index] or "")
        if value ~= "" then
            parts[#parts + 1] = value
        end
    end

    if #parts == 0 then return fallback end
    return table.concat(parts, " ")
end

local function runXpChangeCommand(source, args, commandKey, operation)
    if not isAdminOrConsole(source, commandKey) then return end

    local targetId = tonumber(args[1])
    local amount = math.floor(tonumber(args[2]) or 0)

    if not targetId or amount <= 0 then
        notifyCommandSource(source, _Up(source, commandKey == 'addxp' and 'usage_addxp' or 'usage_removexp'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser or not targetUser.getUsedCharacter then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    local reason = getXpCommandReason(args, 3, commandKey == 'addxp' and 'admin_addxp' or 'admin_removexp')
    local xpFunction = operation == 'add' and JRSXP.Add or JRSXP.Remove

    xpFunction(targetId, amount, reason, function(success, levelData, oldData, changedAmount, errorCode)
        if not success or not levelData then
            notifyCommandSource(
                source,
                _Up(source, 'cmd_unable_to_xp', operation, tostring(errorCode or "database_error")),
                5000,
                true
            )
            return
        end

        local actualAmount = math.abs(math.floor(tonumber(changedAmount) or 0))
        local pastTense = operation == 'add' and 'added to' or 'removed from'
        local targetText = operation == 'add' and 'added to your account' or 'removed from your account'

        if actualAmount == 0 then
            local limitMessage = operation == 'add'
                and ("Player %s is already at the maximum XP (Level %s)."):format(targetId, levelData.level)
                or ("Player %s already has 0 XP."):format(targetId)
            notifyCommandSource(source, limitMessage, 5000, true)
            return
        end

        notifyCommandSource(
            source,
            _Up(source, 'cmd_xp_player_total_xp_level', actualAmount,
                pastTense,
                targetId,
                levelData.totalXp,
                levelData.level),
            5000,
            false
        )

        notifyCommandTarget(
            targetId,
            _Up(targetId, 'cmdt_xp_was_total_xp_level', actualAmount,
                targetText,
                levelData.totalXp,
                levelData.level),
            5000,
            false,
            'placeholder'
        )

        if Config.Info_print then
            jrsCore.Debug(("Admin XP command: %s %s XP for player %s. Total XP: %s, Level: %s, Reason: %s"):format(
                operation,
                actualAmount,
                targetId,
                levelData.totalXp,
                levelData.level,
                reason
            ))
        end
    end)
end

RegisterCommand(Config.Commands.addxp, function(source, args)
    runXpChangeCommand(source, args, 'addxp', 'add')
end)

RegisterCommand(Config.Commands.removexp, function(source, args)
    runXpChangeCommand(source, args, 'removexp', 'remove')
end)

RegisterCommand(Config.Commands.setxp, function(source, args)
    if not isAdminOrConsole(source, 'setxp') then return end

    local targetId = tonumber(args[1])
    local amount = tonumber(args[2])

    if not targetId or not amount or amount < 0 then
        notifyCommandSource(source, _Up(source, 'usage_setxp'), 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser or not targetUser.getUsedCharacter then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    JRSXP.Set(targetId, amount, "admin_setxp", function(success, levelData, oldData, changedAmount, errorCode)
        if not success or not levelData then
            notifyCommandSource(source, _Up(source, 'cmd_unable_to_set_xp', tostring(errorCode or "database_error")), 5000, true)
            return
        end

        notifyCommandSource(
            source,
            _Up(source, 'cmd_player_xp_set_to_level', targetId, levelData.totalXp, levelData.level),
            5000,
            false
        )

        notifyCommandTarget(
            targetId,
            _Up(targetId, 'cmdt_your_xp_was_set_to_current', levelData.totalXp, levelData.level),
            5000,
            false,
            'placeholder'
        )

        if Config.Info_print then
            jrsCore.Debug(("Admin set XP to %s for player %s (Level %s)"):format(
                levelData.totalXp,
                targetId,
                levelData.level
            ))
        end
    end)
end)

RegisterCommand(Config.Commands.setlevel or 'setlevel', function(source, args)
    if not isAdminOrConsole(source, 'setlevel') then return end

    local targetId = tonumber(args[1])
    local level = tonumber(args[2])

    if not targetId or not level or level < 1 then
        notifyCommandSource(source, _Up(source, 'usage_setlevel') or "Usage: /setlevel [id] [level 1-100]", 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser or not targetUser.getUsedCharacter then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    JRSXP.SetLevel(targetId, level, "admin_setlevel", function(success, levelData, oldData, changedAmount, errorCode)
        if not success or not levelData then
            notifyCommandSource(source, _Up(source, 'cmd_unable_to_set_level', tostring(errorCode or "database_error")), 5000, true)
            return
        end

        notifyCommandSource(
            source,
            _Up(source, 'cmd_player_level_set_to_total_xp', targetId, levelData.level, levelData.totalXp),
            5000,
            false
        )

        notifyCommandTarget(
            targetId,
            _Up(targetId, 'cmdt_your_level_was_set_to_total', levelData.level, levelData.totalXp),
            5000,
            false,
            'placeholder'
        )

        if Config.Info_print then
            jrsCore.Debug(("Admin set Level to %s for player %s (Total XP: %s)"):format(
                levelData.level,
                targetId,
                levelData.totalXp
            ))
        end
    end)
end)

RegisterCommand(Config.Commands.addlevel or 'addlevel', function(source, args)
    if not isAdminOrConsole(source, 'addlevel') then return end

    local targetId = tonumber(args[1])
    local amount = tonumber(args[2])

    if not targetId or not amount or amount == 0 then
        notifyCommandSource(source, _Up(source, 'usage_addlevel') or "Usage: /addlevel [id] [amount]", 5000, true)
        return
    end

    local targetUser = jrsCore.getUser(targetId)
    if not targetUser or not targetUser.getUsedCharacter then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 5000, true)
        return
    end

    JRSXP.AddLevel(targetId, amount, "admin_addlevel", function(success, levelData, oldData, changedAmount, errorCode)
        if not success or not levelData then
            notifyCommandSource(source, _Up(source, 'cmd_unable_to_add_level', tostring(errorCode or "database_error")), 5000, true)
            return
        end

        notifyCommandSource(
            source,
            _Up(source, 'cmd_level_s_added_to_player_current', amount, targetId, levelData.level, levelData.totalXp),
            5000,
            false
        )

        notifyCommandTarget(
            targetId,
            _Up(targetId, 'cmdt_level_s_added_to_your_character', amount, levelData.level, levelData.totalXp),
            5000,
            false,
            'placeholder'
        )

        if Config.Info_print then
            jrsCore.Debug(("Admin added %s Level(s) to player %s. Current Level: %s (Total XP: %s)"):format(
                amount,
                targetId,
                levelData.level,
                levelData.totalXp
            ))
        end
    end)
end)


local function formatDoubleXpMultiplier(value)
    local multiplier = tonumber(value) or 1.0
    if math.floor(multiplier) == multiplier then
        return tostring(math.floor(multiplier))
    end
    return string.format('%.2f', multiplier):gsub('0+$', ''):gsub('%.$', '')
end

local function formatDoubleXpRemaining(totalSeconds)
    totalSeconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    if hours > 0 then
        return ('%02d:%02d:%02d'):format(hours, minutes, seconds)
    end
    return ('%02d:%02d'):format(minutes, seconds)
end

RegisterCommand(Config.Commands.doublexp, function(source, args)
    if not isAdminOrConsole(source, 'doublexp') then return end

    local action = string.lower(tostring(args[1] or ''))

    if action == 'status' then
        local state = JRSDoubleXP and JRSDoubleXP.GetState and JRSDoubleXP.GetState() or { active = false }
        if state.active ~= true then
            notifyCommandSource(source, _Up(source, 'cmd_xp_boost_is_currently_inactive'), 5000, false)
            return
        end

        notifyCommandSource(
            source,
            _Up(source, 'cmd_x_xp_is_active_time_remaining', formatDoubleXpMultiplier(state.multiplier),
                formatDoubleXpRemaining(state.remainingSeconds)),
            6000,
            false
        )
        return
    end

    if action == 'stop' or action == 'off' or action == '0' then
        local stopped = JRSDoubleXP and JRSDoubleXP.Stop and JRSDoubleXP.Stop('admin_command') or false
        if stopped then
            notifyCommandSource(source, _Up(source, 'cmd_xp_boost_stopped'), 5000, false)
        else
            notifyCommandSource(source, _Up(source, 'cmd_xp_boost_is_already_inactive'), 5000, true)
        end
        return
    end

    local multiplier = tonumber(args[1])
    local minutes = math.floor(tonumber(args[2]) or 0)
    local maximumMultiplier = tonumber(Config.DoubleXP and Config.DoubleXP.maxMultiplier) or 10.0
    local maximumMinutes = math.floor(tonumber(Config.DoubleXP and Config.DoubleXP.maxDurationMinutes) or 10080)

    if not multiplier or multiplier <= 1.0 or multiplier > maximumMultiplier or minutes <= 0 or minutes > maximumMinutes then
        notifyCommandSource(
            source,
            _Up(source, 'cmd_usage_multiplier_1_up_to_minutes', tostring(Config.Commands.doublexp or 'doublexp'),
                formatDoubleXpMultiplier(maximumMultiplier),
                maximumMinutes),
            7000,
            true
        )
        return
    end

    local startedBy = source == 0 and 'console' or (GetPlayerName(source) or ('player:' .. tostring(source)))
    local accepted, errorCode = JRSDoubleXP.Start(multiplier, minutes, startedBy, function(success, asyncError, state)
        if not success then
            notifyCommandSource(source, _Up(source, 'cmd_unable_to_start_xp_boost', tostring(asyncError or 'database_error')), 6000, true)
            return
        end

        notifyCommandSource(
            source,
            _Up(source, 'cmd_started_x_xp_for_minute', formatDoubleXpMultiplier(state and state.multiplier or multiplier),
                minutes,
                minutes == 1 and '' or 's'),
            6000,
            false
        )
    end)

    if accepted == false then
        notifyCommandSource(source, _Up(source, 'cmd_unable_to_start_xp_boost', tostring(errorCode or 'invalid_settings')), 6000, true)
    end
end)

-- Admin teleport commands
local pendingAdminTeleports = {}


RegisterCommand(Config.Commands.tpm, function(source, args)
    if source == 0 or not isAdminOrConsole(source, 'tpm') then return end

    -- Without an ID, /tpm works as an alias for /tpw.
    if not args[1] then
        TriggerClientEvent('jrs_core:adminTeleportToWaypoint', source)
        return
    end

    local targetId = tonumber(args[1])
    if not targetId then
        notifyCommandSource(source, _Up(source, 'usage_tpm'), 4000, true)
        return
    end

    if not GetPlayerName(targetId) then
        notifyCommandSource(source, _Up(source, 'player_not_found'), 4000, true)
        return
    end

    local request = { requester = source }
    pendingAdminTeleports[targetId] = request
    TriggerClientEvent('jrs_core:getCoords', targetId)

    SetTimeout(5000, function()
        if pendingAdminTeleports[targetId] == request then
            pendingAdminTeleports[targetId] = nil
            if GetPlayerName(source) then
                notifyCommandSource(source, _Up(source, 'teleport_target_timeout'), 4000, true)
            end
        end
    end)
end, false)

AddEventHandler('jrs_core:returnCoords', function(coords)
    local targetId = source
    local request = pendingAdminTeleports[targetId]
    if not request then return end
    pendingAdminTeleports[targetId] = nil

    local requester = request.requester
    if not GetPlayerName(requester) or type(coords) ~= 'table' then return end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    local heading = tonumber(coords.heading) or 0.0
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then return end

    TriggerClientEvent('jrs_core:teleportToCoords', requester, x, y, z, heading)
    notifyCommandSource(requester, _Up(requester, 'teleport_success'), 3000, false)
end)

-- RDO Currency Commands (/gold, /cash)
RegisterCommand('gold', function(source)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    local user = jrsCore and jrsCore.getUser and jrsCore.getUser(src)
    local character = user and user.getUsedCharacter
    if not character then return end
    local gold = tonumber(character.gold) or 0.0
    TriggerClientEvent('jrs_core:sendRightTipNotification', src,
        string.format("Gold Bars: %.2f 𝕲", gold), 5000)
end, false)

RegisterCommand('cash', function(source)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    local user = jrsCore and jrsCore.getUser and jrsCore.getUser(src)
    local character = user and user.getUsedCharacter
    if not character then return end
    local money = tonumber(character.money) or 0.0
    local gold = tonumber(character.gold) or 0.0
    TriggerClientEvent('jrs_core:sendRightTipNotification', src,
        string.format("Cash: $%.2f | Gold: %.2f 𝕲", money, gold), 5000)
end, false)
