-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_admin | client | small helpers every menu file builds on
-- A menu is a name, a subtitle, a way back and a list of rows. A row carries its own `go` function and,
-- optionally, the permission it needs (`gate`); the helper checks the permission before running it.

Kit = {}

local T = Translation.Current()

local GREEN = '<span style=color:MediumSeaGreen;>%s</span>'
local GOLD = '<span style=color:Gold;>%s</span>'

function Kit.green(text) return GREEN:format(tostring(text)) end
function Kit.gold(text) return GOLD:format(tostring(text)) end

-- "text <name>" description used under actions that target one player
function Kit.about(text, name)
    return text .. ' ' .. Kit.green(name)
end

-- opens one menu. opts: sub, back, items, align, itemHeight
function Kit.open(name, opts)
    MenuData.CloseAll()
    MenuData.Open('default', GetCurrentResourceName(), name, {
        title      = T.Menus.DefaultsMenusTitle.menuTitle,
        subtext    = opts.sub,
        align      = opts.align or Config.AlignMenu,
        elements   = opts.items,
        lastmenu   = opts.back,
        itemHeight = opts.itemHeight,
    }, function(data)
        local row = data.current
        if type(row) ~= 'table' or not row.go then return end
        if row.gate and not IsAdminAllowed(row.gate) then return end
        row.go(row)
    end, function(menu) menu.close() end)
end

-- builds the text input description the NUI expects
function Kit.field(kind, spec, pattern, inputType)
    return Inputs(kind or 'input', T.Menus.DefaultsInputs.confirm, spec.placeholder, spec.title, inputType or 'text', spec.errorMsg, pattern)
end

-- asks for a value; `done` gets a non-empty string, an empty answer shows the "empty" notice
function Kit.ask(spec, pattern, done, opts)
    opts = opts or {}
    AdminInput(Kit.field(opts.kind, spec, pattern, opts.type), function(answer)
        answer = tostring(answer or '')
        if answer == '' then return JRS.NotifyObjective(T.Notify.empty, opts.empty or 5000) end
        done(answer)
    end)
end

-- asks "yes / no" and runs `done` only on a yes
function Kit.confirm(spec, done)
    Kit.ask(spec, 'yes|no|نعم|لا', function(answer)
        if answer:lower() == 'yes' or answer == 'نعم' then done() else TriggerEvent('jrs:TipRight', T.Notify.actionCancell, 4000) end
    end, { empty = 4000 })
end

function Kit.words(text)
    local list = {}
    for word in text:gmatch('%S+') do list[#list + 1] = word end
    return list
end

-- the multi-line player card used by the player lists
function Kit.playerCard(p)
    local S = T.Menus.MainPlayerStatus
    local rows = {
        { S.playerSteamName, p.name or '', false },
        { S.playerServerID, p.serverId or 0, false },
        { S.playerGroup, p.Group or '', false },
        { S.playerJob, p.Job or '', false },
        { S.playerGrade, p.Grade or '', false },
        { S.playerIdentifier, p.SteamId or '', false },
        { S.playerMoney, p.Money or 0, false },
        { S.playerGold, p.Gold or 0, true },
        { S.playerWhitelist, p.WLstatus or '', true },
    }
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row[1] .. ' ' .. (row[3] and Kit.gold(row[2]) or Kit.green(row[2]))
    end
    return table.concat(out, '<br>')
end

function Kit.playerRow(p)
    return {
        label = p.PlayerName .. '<br>' .. T.Menus.MainPlayerStatus.playerServerID .. p.serverId,
        value = 'players' .. p.serverId,
        desc = Kit.playerCard(p),
        info = p,
    }
end
