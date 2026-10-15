local J = JRSMetabolism
local rates = {}
function J.unload(src)
    src = tonumber(src)
    if not src then return end
    J.loading[src] = nil
    local old = J.sessions[src]
    J.sessions[src], PlayersStatus[src], rates[src] = nil, nil, nil
    if old then J.save(old) end
end
function J.load(src)
    src = tonumber(src)
    if not src or not J.ready then return end
    local character, charId = J.character(src)
    if not character then return end
    if J.session(src) then J.send(src, true); return end
    if J.loading[src] and J.loading[src].charId == charId then return end
    J.unload(src)
    local token = { charId = charId, identifier = character.identifier }
    J.loading[src] = token
    CreateThread(function()
        local ok, err = pcall(function()
            local deadline = GetGameTimer() + 10000
            while J.saveQueues[charId] and GetGameTimer() < deadline do Wait(50) end
            if J.saveQueues[charId] then return end
            local row = MySQL.single.await([[SELECT statHunger,statThirst,statHealth,statHealthCore,
                statStamina,statStaminaCore FROM character_rpg_stats WHERE personaId=?]], { charId })
            if not row then
                MySQL.insert.await([[INSERT IGNORE INTO character_rpg_stats
                    (personaId,statHunger,statThirst,statHealth,statHealthCore,statStamina,statStaminaCore)
                    VALUES (?,0,0,200,100,1,100)]], { charId })
            end
            local current, currentId = J.character(src)
            if J.loading[src] ~= token or not current or currentId ~= charId or current.identifier ~= token.identifier then return end
            local status = CreateStatusByDatabaseData(row)
            J.sessions[src] = { charId = charId, identifier = token.identifier, status = status }
            PlayersStatus[src] = status
            J.send(src, true)
        end)
        if J.loading[src] == token then J.loading[src] = nil end
        if not ok then print(('[jrs_metabolism] Could not load character state: %s'):format(err)) end
    end)
end
local function allowed(src, key, interval)
    local now = GetGameTimer()
    rates[src] = rates[src] or {}
    if rates[src][key] and now - rates[src][key] < interval then return false end
    rates[src][key] = now
    return true
end
RegisterNetEvent('jrs_metabolism:server:initialize', function()
    local src = tonumber(source)
    if src and allowed(src, 'initialize', 1500) then J.load(src) end
end)
AddEventHandler('hud:server:loadStatusAgain', function(src) J.load(src) end)
AddEventHandler('jrs_core:server:characterLoaded', function(src) J.load(src) end)
AddEventHandler('jrs_core:server:characterUnloaded', function(src) J.unload(src) end)
AddEventHandler('playerDropped', function() J.unload(source) end)
-- Deficit values: 0 is full, 100 is empty.
for _, event in ipairs({ 'hud.increase', 'hud.decrease' }) do
    local name = event
    RegisterNetEvent(name, function(field, amount)
        local src = tonumber(source)
        if field ~= 'hunger' and field ~= 'thirst' then return end
        local value = J.number(amount, nil, -100, 100)
        if not src or not value or not allowed(src, name..field, 500) then return end
        J.vary(src, field, name == 'hud.decrease' and -value or value)
    end)
end
RegisterNetEvent('metabolism.vary', function(field, amount)
    local src = tonumber(source)
    if field ~= 'hunger' and field ~= 'thirst' then return end
    local value = J.number(amount, nil, 0, 5)
    if src and value and allowed(src, 'movement'..field, 4000) then J.vary(src, field, value) end
end)
RegisterNetEvent('hud:server:UpdateHealthSistem', function(data, charId)
    local src = tonumber(source)
    local session = src and J.session(src)
    if not session or tonumber(charId) ~= session.charId or type(data) ~= 'table' or not allowed(src, 'health', 4000) then return end
    for _, field in ipairs({ 'health', 'stamina' }) do
        local value = data[field]
        if type(value) == 'table' then
            session.status[field].core = J.number(value.core, session.status[field].core, 0, 100)
            session.status[field].normal = J.number(value.normal, session.status[field].normal, 0, field == 'health' and 1000 or 1)
        end
    end
end)
local function restore(src)
    src = tonumber(src)
    if not src or not allowed(src, 'restore', 1500) then return end
    local session = J.session(src)
    if not session then return end
    session.status.hunger, session.status.thirst = 0, 0
    J.send(src)
    J.save(session)
end
RegisterNetEvent('metabolism.restoreAll', function() restore(source) end)
AddEventHandler('jrs_metabolism:server:restore', restore)
exports('RestoreNeeds', restore)
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await(LoadResourceFile(GetCurrentResourceName(), 'db.sql'))
        local columns = MySQL.query.await([[SHOW COLUMNS FROM character_rpg_stats
            WHERE Field IN ('statHunger','statThirst','statStamina')]]) or {}
        local changes = {}
        for _, column in ipairs(columns) do
            local defaults = {statHunger = 0, statThirst = 0, statStamina = 1}
            if defaults[column.Field] ~= nil and tostring(column.Type):lower():find('int', 1, true) then
                changes[#changes + 1] = ('MODIFY COLUMN `%s` DECIMAL(7,3) NOT NULL DEFAULT %d'):format(column.Field, defaults[column.Field])
            end
        end
        -- Retain existing rows while allowing fractional needs to survive a restart.
        if #changes > 0 then MySQL.query.await('ALTER TABLE character_rpg_stats '..table.concat(changes, ', ')) end
    end)
    if not ok then print(('[jrs_metabolism] Database initialization failed: %s'):format(err)); return end
    J.ready = true
    for _, src in ipairs(GetPlayers()) do J.load(tonumber(src)) end
end)
CreateThread(function()
    while true do
        Wait(Config.DrainInterval)
        for src in pairs(J.sessions) do
            local session = J.session(src)
            if session then
                local ped = GetPlayerPed(src)
                if ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityHealth(ped) > 0 then
                    J.vary(src, 'hunger', Config.HungerDrain)
                    J.vary(src, 'thirst', Config.ThirstDrain)
                end
            else J.unload(src) end
        end
    end
end)
CreateThread(function()
    while true do
        Wait(Config.SaveInterval)
        for _, session in pairs(J.sessions) do J.save(session) end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'jrs_core' then
        for src in pairs(J.sessions) do J.unload(src) end
    end
end)
