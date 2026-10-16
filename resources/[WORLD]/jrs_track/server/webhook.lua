-- jrs_track | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_track | Discord log
-- Race events (tracks made or removed, races started, finished or reset, settings, database errors) are posted
-- as embeds. Posts are queued per webhook URL and spaced out, so a burst of events (everybody finishing
-- together) cannot hit Discord's rate limit. Nothing is sent unless Config.Webhook.enabled is true.

local queues = {}              -- url -> list of payloads waiting
local lastPost = {}            -- url -> game timer of the last post
local draining = {}            -- url -> true while its queue is being sent

local function isUrl(url) return type(url) == 'string' and url:find('^https?://') ~= nil end

local function post(url, payload, done)
    PerformHttpRequest(url, function(status, body)
        if status ~= 200 and status ~= 204 then
            print(('[jrs_track] Discord webhook post failed (HTTP %s): %s'):format(tostring(status), tostring(body)))
        end
        done()
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function drain(url)
    if draining[url] then return end
    draining[url] = true

    CreateThread(function()
        local spacing = (Config.Webhook and Config.Webhook.minIntervalMs) or 350
        while queues[url] and #queues[url] > 0 do
            local wait = spacing - (GetGameTimer() - (lastPost[url] or 0))
            if wait > 0 then Wait(wait) end

            local payload = table.remove(queues[url], 1)
            lastPost[url] = GetGameTimer()

            local finished = false
            post(url, payload, function() finished = true end)
            local waited = 0
            while not finished and waited < 5000 do
                Wait(50)
                waited = waited + 50
            end
        end
        draining[url] = nil
    end)
end

-- the url of an event: its own, else the shared one
local function urlFor(event)
    local cfg = Config.Webhook
    local own = cfg and cfg.events and cfg.events[event]
    if own and isUrl(own.url) then return own.url end
    if cfg and isUrl(cfg.url) then return cfg.url end
end

local function enabled(event)
    local cfg = Config.Webhook
    local own = cfg and cfg.enabled and cfg.events and cfg.events[event]
    return own ~= nil and own.enabled ~= false
end

-- fields = list of { name, value, inline }
function SendTrackWebhook(event, title, description, fields)
    if not enabled(event) then return end
    local url = urlFor(event)
    if not url then return end

    local cfg = Config.Webhook
    local payload = {
        username = cfg.botName or 'JRS-Track',
        embeds = { {
            title = title, description = description, fields = fields or {},
            color = (cfg.events[event] and cfg.events[event].color) or 3066993,
            footer = { text = cfg.footer or 'JRS-Track' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }
    if type(cfg.botAvatar) == 'string' and cfg.botAvatar ~= '' then payload.avatar_url = cfg.botAvatar end

    queues[url] = queues[url] or {}
    table.insert(queues[url], payload)
    drain(url)
end

-- the "Player" field used by several events
function WebhookPlayerField(name, src, charId)
    local text = ('%s (`%s`)'):format(name, src)
    if charId then text = text .. (' - `%s`'):format(charId) end
    return { name = 'Player', value = text, inline = false }
end

RegisterCommand('racewebhooktest', function(src)
    if src ~= 0 and not JRS.IsAdmin(src) then return end
    SendTrackWebhook('trackCreated', 'Webhook Test', 'If you can see this, jrs_track webhooks are configured correctly.', {
        { name = 'Triggered By', value = src == 0 and 'Server Console' or ('source %s'):format(src), inline = true },
    })
    print('[jrs_track] Test webhook queued. Check the configured Discord channel.')
end, false)
