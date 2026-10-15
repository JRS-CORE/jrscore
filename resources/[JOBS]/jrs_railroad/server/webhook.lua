--[[
    jrs_railroad Discord webhook logging.

    Usage from any other server file:
        Webhook.Send('economy', {
            title       = 'Train Purchased',
            description = 'Someone bought a train.',
            type        = 'success', -- 'success' | 'error' | 'info' | 'warn'
            fields      = {
                { name = 'Player',  value = 'John Marston', inline = true },
                { name = 'Cost',    value = '$350',         inline = true },
            },
        })

    Sends are queued and drained on a timer so a burst of events (e.g. a
    company being sold + all its employees/supplies cleaned up) never
    fires more than one HTTP request every 300ms, which keeps this well
    under Discord's per-webhook rate limit (~30 requests/minute).
]]

Webhook = {}

local queue = {}
local processing = false

local function GetWebhookUrl(category)
    local cfg = Config.Webhooks
    if not cfg or not cfg.Enabled then return nil end
    local url = cfg.URLs and cfg.URLs[category]
    if not url or url == '' then
        -- fall back to the admin webhook if the category has no URL of its own
        url = cfg.URLs and cfg.URLs.admin
    end
    if not url or url == '' then return nil end
    return url
end

local function ProcessQueue()
    if processing then return end
    processing = true

    CreateThread(function()
        while #queue > 0 do
            local job = table.remove(queue, 1)
            PerformHttpRequest(job.url, function(statusCode, response, headers)
                if statusCode ~= 200 and statusCode ~= 204 then
                    print(('[jrs_railroad] Webhook send failed (status %s): %s'):format(tostring(statusCode), tostring(response)))
                end
            end, 'POST', json.encode(job.payload), { ['Content-Type'] = 'application/json' })
            Wait(300)
        end
        processing = false
    end)
end

-- category: one of Config.Webhooks.URLs keys ('economy' | 'robbery' | 'employees' | 'admin')
-- data: { title, description, type, fields = {{name, value, inline}, ...}, footer }
function Webhook.Send(category, data)
    local url = GetWebhookUrl(category)
    if not url then return end

    local cfg = Config.Webhooks
    local color = (cfg.Colors and cfg.Colors[data.type or 'info']) or 3447003

    local embed = {
        title       = data.title or 'JRS Railroad',
        description = data.description,
        color       = color,
        fields      = data.fields or {},
        footer      = { text = data.footer or 'jrs_railroad' },
        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }

    local payload = {
        username   = cfg.BotName or 'JRS Railroad',
        avatar_url = (cfg.BotAvatar ~= '' and cfg.BotAvatar) or nil,
        embeds     = { embed },
    }

    table.insert(queue, { url = url, payload = payload })
    ProcessQueue()
end

-- Convenience wrapper: builds the {name, value, inline} field list for you.
-- fieldPairs = { {'Player', name}, {'Cost', '$350'}, ... }
function Webhook.SendFields(category, title, fieldPairs, wtype, description)
    local fields = {}
    for _, pair in ipairs(fieldPairs) do
        table.insert(fields, { name = pair[1], value = tostring(pair[2]), inline = true })
    end
    Webhook.Send(category, {
        title       = title,
        description = description,
        type        = wtype or 'info',
        fields      = fields,
    })
end

-- Small helper used everywhere below to get "Firstname Lastname" safely.
function GetPlayerFullName(Player)
    if not Player then return 'Unknown' end
    local ci = Player.PlayerData.charinfo or {}
    return (ci.firstname or '') .. ' ' .. (ci.lastname or '')
end
