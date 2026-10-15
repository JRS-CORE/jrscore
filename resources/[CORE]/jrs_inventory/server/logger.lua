-- ============================================================================
-- JRS Inventory - Discord logger
-- ============================================================================

local webhookQueues = {}
local queueWorkers = {}

local function logConfig()
    return type(DiscordLogConfig) == "table" and DiscordLogConfig or {}
end

local function trimText(value, maxLength)
    local text = tostring(value == nil and "N/A" or value)
    if text == "" then text = "N/A" end
    text = text:gsub("```", "''' ")
    maxLength = tonumber(maxLength) or 1024
    if #text > maxLength then
        text = text:sub(1, math.max(1, maxLength - 3)) .. "..."
    end
    return text
end

local function safeJson(value, maxLength)
    if value == nil then return "N/A" end
    local text
    if type(value) == "table" then
        local ok, encoded = pcall(json.encode, value)
        text = ok and encoded or "<metadata encode failed>"
    else
        text = tostring(value)
    end
    return trimText(text, maxLength)
end

local function getWebhook(category)
    local cfg = logConfig()
    if cfg.Enabled ~= true then return nil end
    local webhooks = type(cfg.Webhooks) == "table" and cfg.Webhooks or {}
    local webhook = webhooks[tostring(category or "Default")] or webhooks.Default
    if type(webhook) ~= "string" or webhook == "" then return nil end
    return webhook
end

local function characterData(playerId)
    playerId = tonumber(playerId)
    local User = playerId and jrsCore and jrsCore.getUser and jrsCore.getUser(playerId)
    local Character = User and User.getUsedCharacter
    return User, Character
end

local function valueFromCharacter(Character, keys)
    if not Character then return nil end
    for _, key in ipairs(keys) do
        local value = Character[key]
        if value ~= nil and tostring(value) ~= "" then return value end
    end
    return nil
end

function JRSInventoryPlayerSummary(playerId)
    playerId = tonumber(playerId)
    if not playerId then return "Unknown player" end

    local User, Character = characterData(playerId)
    local firstName = valueFromCharacter(Character, { "firstname", "firstName", "first_name" })
    local lastName = valueFromCharacter(Character, { "lastname", "lastName", "last_name" })
    local characterName = ((firstName and tostring(firstName) or "") .. " " .. (lastName and tostring(lastName) or "")):gsub("^%s+", ""):gsub("%s+$", "")
    if characterName == "" then characterName = "Unknown character" end

    local playerName = GetPlayerName(playerId) or "Unknown"
    local charId = valueFromCharacter(Character, { "charIdentifier", "charidentifier", "charid" }) or "N/A"
    local job = valueFromCharacter(Character, { "job", "jobName" }) or "N/A"
    if type(job) == "table" then job = job.name or job.label or job.id or "N/A" end
    local group = (Character and Character.group) or (User and User.group) or "N/A"

    return trimText(("**%s** (`%s`)\nCharacter: **%s**\nChar ID: `%s` | Job: `%s` | Group: `%s`")
        :format(playerName, playerId, characterName, tostring(charId), tostring(job), tostring(group)), 1024)
end

local function identifierText(playerId)
    local cfg = logConfig()
    if cfg.IncludePlayerIdentifiers ~= true then return nil end
    playerId = tonumber(playerId)
    if not playerId then return nil end

    local identifiers = GetPlayerIdentifiers(playerId) or {}
    if #identifiers == 0 then return "None" end
    return trimText(table.concat(identifiers, "\n"), 1024)
end

function JRSInventoryMetadataText(metadata)
    local cfg = logConfig()
    if cfg.IncludeMetadata ~= true then return "Metadata logging disabled" end
    return safeJson(metadata or {}, tonumber(cfg.MaxMetadataLength) or 900)
end

local function normalizeFields(playerId, fields)
    local output = {
        {
            name = "Player",
            value = JRSInventoryPlayerSummary(playerId),
            inline = false,
        }
    }

    local identifiers = identifierText(playerId)
    if identifiers then
        output[#output + 1] = {
            name = "Identifiers",
            value = identifiers,
            inline = false,
        }
    end

    for _, field in ipairs(type(fields) == "table" and fields or {}) do
        if type(field) == "table" and field.name ~= nil and field.value ~= nil then
            output[#output + 1] = {
                name = trimText(field.name, 256),
                value = trimText(field.value, 1024),
                inline = field.inline == true,
            }
            if #output >= 25 then break end
        end
    end
    return output
end

local function startQueueWorker(webhook)
    if queueWorkers[webhook] then return end
    queueWorkers[webhook] = true

    Citizen.CreateThread(function()
        while true do
            local queue = webhookQueues[webhook]
            if not queue or #queue == 0 then
                queueWorkers[webhook] = nil
                return
            end

            local payload = table.remove(queue, 1)
            PerformHttpRequest(webhook, function(statusCode)
                if tonumber(statusCode) and tonumber(statusCode) >= 400 and logConfig().Debug == true then
                    print(("[jrs_inventory][DISCORD] webhook returned HTTP %s"):format(tostring(statusCode)))
                end
            end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })

            Citizen.Wait(math.max(250, tonumber(logConfig().QueueIntervalMs) or 500))
        end
    end)
end

local function enqueue(webhook, payload)
    webhookQueues[webhook] = webhookQueues[webhook] or {}
    local queue = webhookQueues[webhook]
    local maxQueued = math.max(10, tonumber(logConfig().MaxQueuedLogs) or 500)
    if #queue >= maxQueued then
        table.remove(queue, 1)
    end
    queue[#queue + 1] = payload
    startQueueWorker(webhook)
end

function JRSInventoryLog(category, title, playerId, fields, options)
    category = tostring(category or "Default")
    local webhook = getWebhook(category)
    if not webhook then return false end

    options = type(options) == "table" and options or {}
    local cfg = logConfig()
    local colors = type(cfg.Colors) == "table" and cfg.Colors or {}
    local mention = ""
    if category == "Security" and cfg.MentionRoleOnSecurity == true and tostring(cfg.SecurityRoleId or "") ~= "" then
        mention = "<@&" .. tostring(cfg.SecurityRoleId) .. ">"
    end

    local embed = {
        title = trimText(title or ("Inventory " .. category), 256),
        description = options.description and trimText(options.description, 4096) or nil,
        color = tonumber(options.color) or tonumber(colors[category]) or tonumber(colors.Default) or 5793266,
        fields = normalizeFields(playerId, fields),
        footer = { text = trimText(options.footer or "JRS Inventory Audit Log", 2048) },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    enqueue(webhook, {
        username = trimText(cfg.BotName or "JRS Inventory Logs", 80),
        avatar_url = tostring(cfg.AvatarUrl or ""),
        content = mention,
        allowed_mentions = { parse = {}, roles = mention ~= "" and { tostring(cfg.SecurityRoleId) } or {} },
        embeds = { embed },
    })
    return true
end

function JRSInventoryLogAction(category, title, playerId, details)
    details = type(details) == "table" and details or {}
    local fields = {}
    local options = details.options

    local orderedKeys = {
        { "target", "Target Player" },
        { "item", "Item" },
        { "itemId", "Item ID" },
        { "weapon", "Weapon" },
        { "weaponId", "Weapon ID" },
        { "serial", "Weapon Serial" },
        { "amount", "Amount" },
        { "storage", "Storage" },
        { "dropId", "Ground Drop ID" },
        { "operationId", "Operation ID" },
        { "coordinates", "Coordinates" },
        { "reason", "Reason" },
        { "sourceResource", "Source Resource" },
    }

    local consumed = { options = true }
    for _, mapping in ipairs(orderedKeys) do
        local key, label = mapping[1], mapping[2]
        if details[key] ~= nil then
            local value = details[key]
            if key == "target" and tonumber(value) then value = JRSInventoryPlayerSummary(tonumber(value)) end
            fields[#fields + 1] = { name = label, value = tostring(value), inline = key ~= "target" }
            consumed[key] = true
        end
    end

    if details.metadata ~= nil then
        fields[#fields + 1] = { name = "Metadata", value = JRSInventoryMetadataText(details.metadata), inline = false }
        consumed.metadata = true
    end

    for key, value in pairs(details) do
        if not consumed[key] and value ~= nil then
            fields[#fields + 1] = { name = tostring(key), value = safeJson(value, 1024), inline = false }
        end
    end

    return JRSInventoryLog(category, title, playerId, fields, options)
end

function JRSInventorySecurityLog(playerId, reason, details, strikes)
    return JRSInventoryLogAction("Security", "Blocked Inventory Security Event", playerId, {
        reason = reason or "unknown",
        details = details or "none",
        strikes = strikes or 0,
    })
end

exports("sendInventoryLog", function(category, title, playerId, fields, options)
    return JRSInventoryLog(category, title, playerId, fields, options)
end)
