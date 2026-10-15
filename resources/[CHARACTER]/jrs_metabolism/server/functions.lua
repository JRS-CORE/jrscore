JRSMetabolism = { sessions = {}, loading = {}, saveQueues = {}, ready = false }
PlayersStatus = {}
function JRSMetabolism.number(value, default, minimum, maximum)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default end
    return math.min(maximum, math.max(minimum, n))
end
function JRSMetabolism.character(src)
    src = tonumber(src)
    if not src or src <= 0 or GetResourceState('jrs_core') ~= 'started' then return end
    local ok, character = pcall(function() return exports.jrs_core:getCoreApi().GetCharacter(src) end)
    local id = ok and type(character) == 'table' and tonumber(character.charIdentifier)
    if id and id > 0 and character.identifier then return character, id end
end
function JRSMetabolism.session(src)
    src = tonumber(src)
    local session = src and JRSMetabolism.sessions[src]
    if not session then return end
    local character, id = JRSMetabolism.character(src)
    if character and id == session.charId and character.identifier == session.identifier then return session end
end
function CreateStatusByDatabaseData(row)
    row = type(row) == 'table' and row or {}
    local n = JRSMetabolism.number
    return {
        hunger = n(row.statHunger, 0, 0, 100), thirst = n(row.statThirst, 0, 0, 100),
        health = { core = n(row.statHealthCore, 100, 0, 100), normal = n(row.statHealth, 200, 0, 1000) },
        stamina = { core = n(row.statStaminaCore, 100, 0, 100), normal = n(row.statStamina, 1, 0, 1) },
    }
end
local saveSQL = [[UPDATE character_rpg_stats SET statHunger=?, statThirst=?, statHealth=?,
    statHealthCore=?, statStamina=?, statStaminaCore=? WHERE personaId=?]]
-- Serialize writes for each character, including logout snapshots.
function JRSMetabolism.save(session)
    if not session or not session.status or not session.charId then return end
    local status = session.status
    local parameters = { status.hunger, status.thirst, status.health.normal,
        status.health.core, status.stamina.normal, status.stamina.core, session.charId }
    local queues = JRSMetabolism.saveQueues
    local key = session.charId
    if queues[key] then queues[key].next = parameters; return end
    local queue = {}
    queues[key] = queue
    local function write(params)
        MySQL.update(saveSQL, params, function()
            if queue.next then
                local nextParams = queue.next
                queue.next = nil
                write(nextParams)
            else
                queues[key] = nil
            end
        end)
    end
    write(parameters)
end
function JRSMetabolism.send(src, initial)
    local session = JRSMetabolism.session(src)
    if not session then return end
    if initial then
        TriggerClientEvent('metabolism.UpdateStatus', src, session.status, session.charId)
    else
        TriggerClientEvent('metabolism.update', src, session.status.hunger, session.status.thirst, session.charId)
    end
end
function JRSMetabolism.vary(src, field, amount)
    if field ~= 'hunger' and field ~= 'thirst' then return false end
    local n = tonumber(amount)
    if not n or n ~= n or n == math.huge or n == -math.huge then return false end
    local session = JRSMetabolism.session(src)
    if not session then return false end
    session.status[field] = math.floor(JRSMetabolism.number(session.status[field] + n, 0, 0, 100) * 1000 + 0.5) / 1000
    JRSMetabolism.send(src)
    return true
end
function varyHunger(src, amount) return JRSMetabolism.vary(tonumber(src), 'hunger', amount) end
function varyThirst(src, amount) return JRSMetabolism.vary(tonumber(src), 'thirst', amount) end
exports('varyHunger', varyHunger)
exports('varyThirst', varyThirst)
exports('GetStatus', function(src)
    local session = JRSMetabolism.session(src)
    return session and json.decode(json.encode(session.status)) or nil
end)
