-----------------------------------------------------------------------
-- jrs_track Discord webhook logging
--
-- Every race-lifecycle event that matters to admins (tracks created or
-- deleted, races started/finished/reset, lap/marker settings changed,
-- database failures) is posted to Discord as an embed. Nothing here
-- trusts client input directly -- server.lua only calls SendTrackWebhook
-- with data it has already validated, and this file just formats and
-- ships it.
--
-- All posting is queued and rate-limited per URL so a burst of events
-- (e.g. every rider finishing within the same second) can't trip
-- Discord's webhook rate limit or block the resource waiting on HTTP.
-----------------------------------------------------------------------

-- queues[url] = { {payload=...}, {payload=...}, ... }
local queues = {}
-- lastSentAt[url] = GetGameTimer() of the last successful/attempted post
local lastSentAt = {}
-- draining[url] = true while a queue's drain loop is already running
local draining = {}

local function isHttpUrl(url)
    return type(url) == 'string' and (url:find('^https?://') ~= nil)
end

local function postNow(url, payload, onDone)
    PerformHttpRequest(url, function(statusCode, response, headers)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(('[jrs_track] Discord webhook post failed (HTTP %s): %s'):format(
                tostring(statusCode), tostring(response)
            ))
        end
        if onDone then onDone() end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function drainQueue(url)
    if draining[url] then return end
    draining[url] = true

    Citizen.CreateThread(function()
        while queues[url] and #queues[url] > 0 do
            local minInterval = (Config.Webhook and Config.Webhook.minIntervalMs) or 350
            local since = GetGameTimer() - (lastSentAt[url] or 0)
            if since < minInterval then
                Citizen.Wait(minInterval - since)
            end

            local job = table.remove(queues[url], 1)
            lastSentAt[url] = GetGameTimer()

            local done = false
            postNow(url, job, function() done = true end)

            -- PerformHttpRequest's callback is async; give it a moment to
            -- return before picking up the next queued job so we don't
            -- fire everything back-to-back regardless of minIntervalMs.
            local waited = 0
            while not done and waited < 5000 do
                Citizen.Wait(50)
                waited = waited + 50
            end
        end
        draining[url] = nil
    end)
end

local function enqueue(url, payload)
    queues[url] = queues[url] or {}
    table.insert(queues[url], payload)
    drainQueue(url)
end

local function resolveUrl(eventKey)
    local cfg = Config.Webhook
    if not cfg then return nil end
    local ev = cfg.events and cfg.events[eventKey]
    if ev and isHttpUrl(ev.url) then return ev.url end
    if isHttpUrl(cfg.url) then return cfg.url end
    return nil
end

local function eventEnabled(eventKey)
    local cfg = Config.Webhook
    if not cfg or not cfg.enabled then return false end
    local ev = cfg.events and cfg.events[eventKey]
    if not ev then return false end
    return ev.enabled ~= false
end

local function eventColor(eventKey, fallback)
    local ev = Config.Webhook.events and Config.Webhook.events[eventKey]
    return (ev and ev.color) or fallback or 3066993
end

--- Post an embed for `eventKey` to whichever webhook URL that event resolves
--- to. Silently no-ops when webhooks are disabled, the event is disabled,
--- or no URL is configured (so this is always safe to call unconditionally
--- from server.lua).
---
--- @param eventKey string   key from Config.Webhook.events
--- @param title string      embed title
--- @param description string|nil  embed description (short summary line)
--- @param fields table|nil  array of { name = ..., value = ..., inline = true/false }
function SendTrackWebhook(eventKey, title, description, fields)
    if not eventEnabled(eventKey) then return end

    local url = resolveUrl(eventKey)
    if not url then return end

    local embed = {
        title = title,
        description = description,
        color = eventColor(eventKey),
        fields = fields or {},
        footer = { text = (Config.Webhook.footer or 'JRS-Track') },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }

    local payload = {
        username = Config.Webhook.botName or 'JRS-Track',
        embeds = { embed },
    }
    if type(Config.Webhook.botAvatar) == 'string' and Config.Webhook.botAvatar ~= '' then
        payload.avatar_url = Config.Webhook.botAvatar
    end

    enqueue(url, payload)
end

--- Shorthand for a single-field "Player" embed used by several events.
--- @param name string
--- @param src number
--- @param citizenid string|nil
function WebhookPlayerField(name, src, citizenid)
    local value = ('%s (`%s`)'):format(name, src)
    if citizenid then value = value .. (' — `%s`'):format(citizenid) end
    return { name = 'Player', value = value, inline = false }
end

RegisterCommand('racewebhooktest', function(source)
    local src = source
    if src ~= 0 then
        -- Console-only by default; server.lua's own admin gate covers
        -- in-game commands. This is a quick way for a server owner to
        -- confirm the webhook URL/format works without racing anyone.
        if not JRS.IsAdmin(src) then return end
    end
    SendTrackWebhook('trackCreated', 'Webhook Test', 'If you can see this, jrs_track webhooks are configured correctly.', {
        { name = 'Triggered By', value = src == 0 and 'Server Console' or ('source %s'):format(src), inline = true },
    })
    print('[jrs_track] Test webhook queued. Check the configured Discord channel.')
end, false)
