-- Discord webhook (server side only, never sent to clients). Empty = console log only.
local WEBHOOK = GetConvar('jrs_death_logs_webhook', '')

local last = {}

local function describe(src)
    local c = JRS.Char(src)
    local name = c and ('%s %s'):format(c.firstname or '', c.lastname or '') or '?'
    return ('%s [%s] (char %s, id %d)'):format(name, GetPlayerName(src) or '?', c and c.charIdentifier or '?', src)
end

RegisterNetEvent('jrs_death_logs:server:died', function(reason, killer, weapon)
    local src = source
    if not JRS.Char(src) then return end
    -- one log per death; a client cannot spam the channel
    if last[src] and os.time() - last[src] < 10 then return end
    last[src] = os.time()

    reason = type(reason) == 'string' and reason:sub(1, 16) or 'DIED'
    weapon = type(weapon) == 'string' and weapon:sub(1, 48) or '?'
    killer = tonumber(killer)
    local line = ('%s - %s'):format(describe(src), reason)
    if killer and GetPlayerName(killer) then
        line = line .. (' by %s with %s'):format(describe(killer), weapon)
    end
    print('^3[jrs_death_logs]^7 ' .. line)

    if WEBHOOK ~= '' then
        PerformHttpRequest(WEBHOOK, function() end, 'POST', json.encode({
            username = 'JRS Death Logs',
            embeds = { { title = reason, description = line, color = 10038562, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
        }), { ['Content-Type'] = 'application/json' })
    end
end)

AddEventHandler('playerDropped', function() last[source] = nil end)
