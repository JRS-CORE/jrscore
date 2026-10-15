-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | the menu every player gets: reports, staff requests, scoreboard, small commands

local T = Translation.Current()
local uiHidden = false

function OpenUsersMenu()
    local O = T.Menus.MainUserOptions
    local items = {
        { label = O.playerReport, value = 'report', desc = O.playerReport_desc, go = function()
            if Config.useQWreports then TriggerEvent('jrs_admin:CreateReport') else Report() end
        end },
        { label = O.playerRequestStaff, value = 'requeststaff', desc = O.playerRequestStaff_desc, go = function() RequestStaff() end },
        { label = O.selfShowInfo, value = 'showinfo', desc = O.selfShowInfo_desc, go = function() ShowOwnInfo() end },
        { label = O.playerCommands, value = 'commands', desc = O.playerCommands_desc, go = function() OpenCommands() end },
        { label = O.playerWalkAndClothesStyle, value = 'menu', desc = O.playerWalkAndClothesStyle_desc, go = function(_, menu)
            TriggerEvent('jrs_walkanim:OpenMenu')
            MenuData.CloseAll()
        end },
    }
    if Config.EnablePlayerlist then
        local board = T.Menus.DefaultsMenusTitle.menuSubTitleScoreboard
        items[#items + 1] = { label = board, value = 'scoreboard', desc = board, go = function() ScoreBoard() end }
    end
    Kit.open('OpenUsersMenu', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleScoreboard, items = items })
end

-- ------------------------------------------------------------------ scoreboard

-- what the scoreboard shows about each player, chosen by Config.showUsersInfo
local boardFields = {
    showAll   = { { 'playerServerID', 'serverId' }, { 'playerGroup', 'Group' }, { 'playerJob', 'Job' } },
    showJob   = { { 'playerJob', 'Job' } },
    showGroup = { { 'playerGroup', 'Group' } },
    showID    = { { 'playerServerID', 'serverId' } },
}

function ScoreBoard()
    local players = JRS.Callback.TriggerAwait('jrs_admin:Callback:getplayersinfo', { search = 'all' })
    if not players then return end

    local S = T.Menus.MainPlayerStatus
    local fields = boardFields[Config.showUsersInfo] or {}
    local rows = {}
    for _, info in pairs(players) do
        local lines = { '' }
        for _, f in ipairs(fields) do
            lines[#lines + 1] = S[f[1]] .. ' ' .. Kit.green(info[f[2]])
        end
        rows[#rows + 1] = { label = info.PlayerName, value = 'players', desc = table.concat(lines, '<br>') }
    end
    Kit.open('ScoreBoard', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleScoreboard, back = 'OpenUsersMenu', items = rows })
end

-- ------------------------------------------------------------------ reporting

function Report()
    local spec = T.Menus.MainUserOptions.ReportInput
    AdminInput(Inputs('textarea', T.Menus.DefaultsInputs.confirm, spec.placeholder, spec.title, 'text', spec.errorMsg, '[\\s\\S]{3,500}'), function(text)
        if text ~= '' then TriggerServerEvent('jrs_admin:alertstaff', text) end
    end)
end

function RequestStaff()
    local O = T.Menus.SubUserOptions
    local items = {}
    for _, f in ipairs({ { 'needHelp', 'new' }, { 'foundBug', 'bug' }, { 'rulesBroken', 'rules' }, { 'someoneCheating', 'cheating' } }) do
        items[#items + 1] = { label = O[f[1]], value = f[2], desc = O[f[1] .. '_desc'], go = function(row) TriggerServerEvent('jrs_admin:requeststaff', row.value) end }
    end
    Kit.open('RequestStaff', { sub = T.Menus.DefaultsMenusTitle.menuSubTitleRequestStaff, back = 'OpenUsersMenu', items = items })
end

-- ------------------------------------------------------------------ small commands

function DelHorse()
    local ped = PlayerPedId()
    if IsPedOnMount(ped) then DeleteEntity(GetMount(ped)) else TriggerEvent('jrs:TipRight', T.Notify.youNeedtoSeatead, 3000) end
end

function Delwagon()
    local wagon = GetVehiclePedIsIn(PlayerPedId(), true)
    if wagon ~= 0 and DoesEntityExist(wagon) then
        DeleteVehicle(wagon)
        DeleteEntity(wagon)
        TriggerEvent('jrs:TipRight', T.Notify.youDeletedWagon, 3000)
    else
        TriggerEvent('jrs:TipRight', T.Notify.youNeedtoSeatead, 3000)
    end
end

local function showHud(visible)
    DisplayRadar(visible)
    DisplayHud(visible)
    TriggerEvent('syn_displayrange', visible)
    TriggerEvent('jrs_hud:busy', 'jrs_admin:userhide', not visible)
end

function HideUI()
    uiHidden = not uiHidden
    showHud(not uiHidden)
end

function OpenCommands()
    local O = T.Menus.SubUserOptions
    Kit.open('OpenCommands', {
        sub = T.Menus.DefaultsMenusTitle.menuSubTitleCommands,
        back = 'OpenUsersMenu',
        items = {
            { label = O.delHorse, value = 'delhorse', desc = O.delHorse_desc, go = DelHorse },
            { label = O.delWagon, value = 'delwagon', desc = O.delWagon_desc, go = Delwagon },
            { label = O.hideUi, value = 'hideui', desc = O.hideUi_desc, go = HideUI },
            { label = O.cancelAnimation, value = 'cancelanim', desc = O.cancelAnimation_desc, go = function() ClearPedTasksImmediately(PlayerPedId()) end },
        },
    })
end

-- ------------------------------------------------------------------ own information

function ShowOwnInfo()
    local info = JRS.Callback.TriggerAwait('jrs_admin:getSelfInfo')
    if type(info) ~= 'table' then return end

    local rows = {}
    for _, f in ipairs({ { 'playerName', 'PlayerName' }, { 'playerServerID', 'serverId' }, { 'playerJob', 'Job' },
                         { 'playerGrade', 'Grade' }, { 'playerMoney', 'Money' }, { 'playerGold', 'Gold' } }) do
        rows[#rows + 1] = { label = T.Menus.MainPlayerStatus[f[1]], desc = tostring(info[f[2]] or ''), disabled = true }
    end
    Kit.open('ShowOwnInfo', { sub = T.Menus.MainUserOptions.selfShowInfo, back = 'OpenUsersMenu', items = rows })
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and uiHidden then showHud(true) end
end)
