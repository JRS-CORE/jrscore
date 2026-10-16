-- jrs_railroad | server: Discord logging and two helpers every server file uses
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
--
--   Webhook.Send('economy', { title = 'Train Purchased', description = '...', type = 'success', fields = { { name = 'Cost', value = '$350', inline = true } } })
--   Webhook.SendFields('economy', 'Train Purchased', { { 'Player', name }, { 'Cost', '$350' } }, 'success')
--
-- Posts wait in a queue and go out one every 300 ms, so a burst (a company sold with all its staff and
-- stock) stays well under Discord's rate limit.

Webhook = {}

local queue, draining = {}, false

-- a notification on one player's screen (the client resource registers '<resource>:notify')
function Say(src, text, kind, duration, title)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, {
        title = title or L('notify_title'), description = text, type = kind or 'inform', duration = duration or 5000,
    })
end

-- "Firstname Lastname" of a framework player object
function GetPlayerFullName(player)
    if not player then return 'Unknown' end
    local info = player.PlayerData.charinfo or {}
    return (info.firstname or '') .. ' ' .. (info.lastname or '')
end

-- the URL of a category, falling back to the admin channel
local function urlFor(category)
    local cfg = Config.Webhooks
    if not cfg or not cfg.Enabled or not cfg.URLs then return nil end
    local url = cfg.URLs[category]
    if not url or url == '' then url = cfg.URLs.admin end
    if url and url ~= '' then return url end
end

local function drain()
    if draining then return end
    draining = true

    CreateThread(function()
        while #queue > 0 do
            local job = table.remove(queue, 1)
            PerformHttpRequest(job.url, function(status, body)
                if status ~= 200 and status ~= 204 then
                    print(('[jrs_railroad] webhook failed (status %s): %s'):format(tostring(status), tostring(body)))
                end
            end, 'POST', json.encode(job.payload), { ['Content-Type'] = 'application/json' })
            Wait(300)
        end
        draining = false
    end)
end

-- category is a key of Config.Webhooks.URLs; data = { title, description, type, fields, footer }
function Webhook.Send(category, data)
    local url = urlFor(category)
    if not url then return end

    local cfg = Config.Webhooks
    queue[#queue + 1] = {
        url = url,
        payload = {
            username = cfg.BotName or 'JRS Railroad',
            avatar_url = (cfg.BotAvatar ~= '' and cfg.BotAvatar) or nil,
            embeds = { {
                title = data.title or 'JRS Railroad',
                description = data.description,
                color = (cfg.Colors and cfg.Colors[data.type or 'info']) or 3447003,
                fields = data.fields or {},
                footer = { text = data.footer or 'jrs_railroad' },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            } },
        },
    }
    drain()
end

-- same, but from { { name, value }, ... } pairs
function Webhook.SendFields(category, title, pairList, kind, description)
    local fields = {}
    for i, pair in ipairs(pairList) do fields[i] = { name = pair[1], value = tostring(pair[2]), inline = true } end
    Webhook.Send(category, { title = title, description = description, type = kind or 'info', fields = fields })
end
