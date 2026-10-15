-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | the database section: pick a player, then give or take things

local T = Translation.Current()

function DataBase()
    local players = JRS.Callback.TriggerAwait('jrs_admin:Callback:getplayersinfo', { search = 'all' })
    if not players then return end

    local rows = {}
    for _, info in pairs(players) do
        rows[#rows + 1] = {
            label = info.PlayerName,
            value = 'players',
            desc = Kit.playerCard(info),
            gate = 'open_database_menu',
            data = info,
            go = function(self) DatabasePlayers(self.data) end,
        }
    end
    Kit.open('DataBase', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleDatabase, back = 'OpenMenu', items = rows })
end

function DatabasePlayers(player)
    local O = T.Menus.MainDatabaseOptions
    Kit.open('DatabasePlayers', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleDatabase,
        back = 'DataBase',
        items = {
            { label = O.give, value = 'give', gate = 'give_items_menu', desc = O.give_desc, go = function() GivePlayers(player) end },
            { label = O.remove, value = 'remove', gate = 'remove_items_menu', desc = O.remove_desc, go = function() RemovePlayers(player) end },
        },
    })
end

-- ------------------------------------------------------------------ giving

local function give(player, kind, a, b, c, log)
    TriggerServerEvent('jrs_admin:givePlayer', player.serverId, kind, a, b, c, log, player.PlayerName)
end

function GivePlayers(player)
    local O = T.Menus.SubDatabaseGiveOptions
    local id = player.serverId

    local function row(key, value, go)
        return { label = O[key], value = value, desc = O[key .. '_desc'] .. Kit.green(player.PlayerName), info = id, go = go }
    end

    Kit.open('GivePlayers', {
        sub = Kit.green(player.PlayerName),
        back = 'DataBase',
        items = {
            row('showInventory', 'inventory', function()
                MenuData.CloseAll()
                TriggerServerEvent('jrs_admin:openInventory', id)
            end),
            row('giveItem', 'addItem', function()
                Kit.ask(O.GiveItemInput, '[A-Za-z0-9_ ]{3,60}', function(answer)
                    local w = Kit.words(answer)
                    give(player, 'item', w[1], tonumber(w[2]) or 1, nil, 'jrs.staff.Giveitems')
                end, { empty = 4000 })
            end),
            row('giveWeapon', 'addWeapon', function()
                Kit.ask(O.GiveWeaponInput, '[A-Za-z_ ]{5,60}', function(weapon)
                    give(player, 'weapon', weapon, nil, nil, 'jrs.staff.GiveWeapons')
                end, { empty = 4000 })
            end),
            row('giveMoneyOrGold', 'addMoneygold', function()
                Kit.ask(O.GiveCurrencyInput, '[01] +[0-9]+(?:[.][0-9]+)?', function(answer)
                    local w = Kit.words(answer)
                    local currency, amount = tonumber(w[1]), tonumber(w[2])
                    if currency and amount then give(player, 'moneygold', currency, amount, nil, 'jrs.staff.GiveCurrency')
                    else TriggerEvent('jrs:TipRight', T.Notify.missingArgument, 4000) end
                end, { empty = 4000 })
            end),
            row('giveHorse', 'addHorse', function()
                -- "<model> <name...> <sex>"
                Kit.ask(O.GiveHorseInput, '.{3,150}', function(answer)
                    local w = Kit.words(answer)
                    local sex = tonumber(w[#w])
                    local name = #w >= 3 and table.concat(w, ' ', 2, #w - 1) or ''
                    if w[1] and name ~= '' and sex then give(player, 'horse', w[1], name, sex, 'jrs.staff.GiveHorse')
                    else TriggerEvent('jrs:TipRight', T.Notify.missingArgument, 4000) end
                end, { empty = 4000 })
            end),
            row('giveWagon', 'addWagon', function()
                -- "<model> <name...>"
                Kit.ask(O.GiveWagonInput, '.{3,150}', function(answer)
                    local w = Kit.words(answer)
                    local name = #w >= 2 and table.concat(w, ' ', 2) or ''
                    if w[1] and name ~= '' then give(player, 'wagon', w[1], name, nil, 'jrs.staff.GiveWagons')
                    else TriggerEvent('jrs:TipRight', T.Notify.missingArgument, 4000) end
                end, { empty = 4000 })
            end),
        },
    })
end

-- ------------------------------------------------------------------ taking

function RemovePlayers(player)
    local O = T.Menus.SubDatabaseRemoveOptions
    local id, name = player.serverId, player.PlayerName

    local function row(key, value, go)
        return { label = O[key], value = value, desc = O[key .. '_desc'] .. Kit.green(name), info = id, go = go }
    end

    Kit.open('RemovePlayers', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleDatabase,
        back = 'DataBase',
        items = {
            row('showInventory', 'showinventory', function()
                TriggerServerEvent('jrs_admin:checkInventory', id, 'jrs.staff.ShowInvRemove')
            end),
            row('removeMoney', 'clearmoney', function()
                TriggerServerEvent('jrs_admin:ClearCurrency', id, 'money', 'jrs.staff.RemoveAllMoney', name)
            end),
            row('removeGold', 'cleargold', function()
                TriggerServerEvent('jrs_admin:ClearCurrency', id, 'gold', 'jrs.staff.RemoveAllGold', name)
            end),
            row('clearAllItems', 'clearitems', function()
                Kit.confirm(O.RemoveAllItemInput, function()
                    TriggerServerEvent('jrs_admin:ClearAllItems', 'items', id, 'jrs.staff.RemoveAllItems', name)
                end)
            end),
            row('clearAllWeapons', 'clearweapons', function()
                Kit.confirm(O.RemoveAllWeaponInput, function()
                    TriggerServerEvent('jrs_admin:ClearAllItems', 'weapons', id, 'jrs.staff.RemoveAllWeapons', name)
                end)
            end),
        },
    })
end

-- the inventory of another player, read only
function OpenInventory(contents)
    local rows = {}
    for _, item in pairs(contents or {}) do
        local shown = tostring(item.label or item.name or item.item or 'Item')
        rows[#rows + 1] = {
            label = shown .. " <span style='margin-left:10px; color: Yellow;'>" .. item.count .. '</span>',
            value = 'none',
            desc = item.label,
        }
    end
    Kit.open('OpenInventory', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleDatabase, back = 'DataBase', items = rows })
end
