JRSBridge = JRSBridge or {}

local function isCallable(fn)
    local t = type(fn)
    if t == 'function' or t == 'userdata' then return true end
    if t == 'table' then
        local mt = getmetatable(fn)
        if mt and mt.__call then return true end
        if rawget(fn, '__cfx_functionReference') ~= nil then return true end
    end
    return false
end

local function cleanJobString(val)
    if not val then return nil end
    local s = tostring(val):match('^%s*(.-)%s*$')
    if s and s ~= '' then return string.lower(s) end
    return nil
end

local function getCore()
    if not coreApi and GetResourceState('jrs_core') == 'started' then
        local ok, api = pcall(function() return exports.jrs_core:getCoreApi() end)
        if ok and type(api) == 'table' then
            coreApi = api
        end
    end
    return coreApi
end

function JRSBridge.GetCharacter(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    if GetResourceState('jrs_core') == 'started' then
        local ok, char = pcall(function()
            return exports.jrs_core:GetCharacter(src)
        end)
        if ok and char then return char end
    end

    local core = getCore()
    if core and isCallable(core.getCharacter) then
        local ok, char = pcall(function() return core.getCharacter(src) end)
        if ok and char then return char end
    end

    return nil
end

function JRSBridge.GetIdentifier(src)
    src = tonumber(src)
    if not src or src <= 0 then return 'unknown' end

    local char = JRSBridge.GetCharacter(src)
    if char then
        local charId = char.charIdentifier or char.charid or char.charId
        local ident = char.identifier
        if ident and charId then
            return tostring(ident) .. ':' .. tostring(charId)
        elseif charId then
            return 'char:' .. tostring(charId)
        end
    end

    local player = Player(src)
    if player and player.state then
        local charId = player.state.CharacterId or player.state.charId
        local ident = player.state.CharacterIdentifier
        if ident and charId then
            return tostring(ident) .. ':' .. tostring(charId)
        elseif charId then
            return 'char:' .. tostring(charId)
        end
    end

    if GetPlayerIdentifierByType then
        local license = GetPlayerIdentifierByType(src, 'license')
        if license then return license end
    end

    local ids = GetPlayerIdentifiers(src)
    return (ids and ids[1]) or ('src:' .. tostring(src))
end

function JRSBridge.GetJob(src)
    src = tonumber(src)
    if not src or src <= 0 then return 'unemployed' end

    -- 1. Check Player State Bag (synced by jrs_core Character.setJob)
    local player = Player(src)
    if player and player.state then
        local stateJob = cleanJobString(player.state.Job)
        if stateJob and stateJob ~= 'unemployed' then
            return stateJob
        end
    end

    -- 2. Core API serverApi.getJob(src)
    local core = getCore()
    if core and isCallable(core.getJob) then
        local ok, job = pcall(function() return core.getJob(src) end)
        if ok and job then
            local clean = cleanJobString(job)
            if clean and clean ~= 'unemployed' then return clean end
        end
    end

    -- 3. JRS Character object
    local char = JRSBridge.GetCharacter(src)
    if char then
        local job = char.job or (isCallable(char.getJob) and char.getJob())
        if type(job) == 'table' then job = job.name or job.job end
        local clean = cleanJobString(job)
        if clean and clean ~= 'unemployed' then return clean end
    end

    -- 4. Direct database lookup fallback
    if char then
        local charId = char.charIdentifier or char.charid or char.charId
        if charId then
            local okDb, row = pcall(function()
                return MySQL.single.await('SELECT job FROM jrs_characters WHERE charidentifier = ? LIMIT 1', { charId })
            end)
            if okDb and row and row.job then
                local clean = cleanJobString(row.job)
                if clean and clean ~= 'unemployed' then return clean end
            end
        end
    end

    return 'unemployed'
end

function JRSBridge.GetLevel(src)
    src = tonumber(src)
    if not src or src <= 0 then return 1 end

    local bestLevel = 1

    -- 1. Direct export from jrs_core (authoritative across Red Empire server)
    if GetResourceState('jrs_core') == 'started' then
        local ok, lvl = pcall(function()
            return exports.jrs_core:GetLevel(src)
        end)
        if ok and lvl and tonumber(lvl) and tonumber(lvl) > bestLevel then
            bestLevel = math.floor(tonumber(lvl))
        end

        -- Also check Job Level for 'chicken' if per-job leveling is used
        local okJob, jlvl = pcall(function()
            return exports.jrs_core:GetJobLevel(src, 'chicken')
        end)
        if okJob and jlvl and tonumber(jlvl) and tonumber(jlvl) > bestLevel then
            bestLevel = math.floor(tonumber(jlvl))
        end
    end

    -- 2. Character object cache (instant in-memory check)
    local char = JRSBridge.GetCharacter(src)
    if char then
        if char.level and tonumber(char.level) and tonumber(char.level) > bestLevel then
            bestLevel = math.floor(tonumber(char.level))
        end
        if char.character and tonumber(char.character.level) and tonumber(char.character.level) > bestLevel then
            bestLevel = math.floor(tonumber(char.character.level))
        end
    end

    -- 3. Player state bag (populated by jrs_core)
    local ply = Player(src)
    if ply and ply.state then
        if ply.state.level and tonumber(ply.state.level) and tonumber(ply.state.level) > bestLevel then
            bestLevel = math.floor(tonumber(ply.state.level))
        end
        if ply.state.Level and tonumber(ply.state.Level) and tonumber(ply.state.Level) > bestLevel then
            bestLevel = math.floor(tonumber(ply.state.Level))
        end
    end

    -- 4. Direct database lookup fallback if still <= 1
    if bestLevel <= 1 and char then
        local charId = char.charIdentifier or char.charid or char.charId
        if charId then
            local ok, row = pcall(function()
                return MySQL.single.await('SELECT XP FROM jrs_characters_level WHERE CharIdentifier = ? LIMIT 1', { charId })
            end)
            if not ok or not row then
                pcall(function()
                    row = MySQL.single.await('SELECT XP FROM characters_level WHERE CharIdentifier = ? LIMIT 1', { charId })
                end)
            end
            if row and row.XP then
                local xp = tonumber(row.XP) or 0
                local okMath, data = pcall(function()
                    return exports.jrs_core:GetLevelData(xp)
                end)
                if okMath and data and data.level and tonumber(data.level) > bestLevel then
                    bestLevel = math.floor(tonumber(data.level))
                end
            end
        end
    end

    -- 5. Core API fallback
    if bestLevel <= 1 then
        local core = getCore()
        if core and type(core.getLevel) == 'function' then
            local ok, lvl = pcall(function() return core.getLevel(src) end)
            if ok and lvl and tonumber(lvl) and tonumber(lvl) > bestLevel then
                bestLevel = math.floor(tonumber(lvl))
            end
        end
    end

    return math.max(1, bestLevel)
end

function JRSBridge.HasRequiredJob(src)
    if not Config.JobCheck or not Config.JobCheck.enabled then return true end

    local currentJob = JRSBridge.GetJob(src)
    local requiredJob = cleanJobString(Config.JobCheck.job or 'chicken') or 'chicken'

    if currentJob ~= requiredJob then
        print(('[jrs_chicken_job] Job requirement not met for player %s: current=%s required=%s'):format(src, currentJob, requiredJob))
        return false, 'job', currentJob, requiredJob
    end

    local minLevel = tonumber(Config.JobCheck.minLevel) or 0
    if minLevel > 1 then
        local playerLevel = JRSBridge.GetLevel(src)
        if playerLevel < minLevel then
            print(('[jrs_chicken_job] Level requirement not met for player %s: current=%s required=%s'):format(src, playerLevel, minLevel))
            return false, 'level', playerLevel, minLevel
        end
    end

    return true, nil, currentJob, requiredJob
end

function JRSBridge.AddMoney(src, amount)
    src = tonumber(src)
    amount = tonumber(amount) or 0
    amount = tonumber(string.format('%.2f', amount)) or 0
    if not src or amount <= 0 then return true end

    -- Primary: jrs_core getCoreApi().addMoney(src, 0, amount)
    local core = getCore()
    if core and isCallable(core.addMoney) then
        local ok, success = pcall(function()
            return core.addMoney(src, 0, amount)
        end)
        if ok and success then return true end
    end

    -- Secondary: character object addCurrency(src, 0, amount)
    local char = JRSBridge.GetCharacter(src)
    if char and isCallable(char.addCurrency) then
        local ok, success = pcall(function()
            return char.addCurrency(src, 0, amount)
        end)
        if ok and (success == true or success == nil) then return true end
    end

    print(('[jrs_chicken_job] WARNING: could not pay player %s $%s'):format(src, amount))
    return false
end

function JRSBridge.AddItem(src, item, amount)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 or not item then return true end

    local ok, success = pcall(function()
        return exports.jrs_inventory:addItem(src, tostring(item), tonumber(amount), {})
    end)
    if ok and (success == true or success == nil) then
        return true
    end

    print(('[jrs_chicken_job] WARNING: could not add %sx %s to player %s'):format(amount, item, src))
    return false
end

function JRSBridge.AddXP(src, key)
    src = tonumber(src)
    if not src or src <= 0 then return end

    local xpCfg = Config.XP or Config.RakanLevel
    if not xpCfg then return end
    if xpCfg.Enabled == false or xpCfg.enabled == false then return end

    local rewards = xpCfg.Rewards or xpCfg.xp or {}
    local amount = tonumber(rewards[key]) or tonumber(xpCfg.Default) or 0
    if amount <= 0 then return end

    local mult = tonumber(xpCfg.Multiplier) or 1.0
    amount = math.max(0, math.floor(amount * mult))
    if amount <= 0 then return end

    local jobKey = tostring(xpCfg.Job or (Config.JobCheck and Config.JobCheck.job) or 'chicken')

    -- 1. Primary: jrs_core AddJobXP (awards to 'chicken' in jrs_job_levels + feeds core share + UI feedback)
    local okJob = false
    if GetResourceState('jrs_core') == 'started' then
        pcall(function()
            if exports.jrs_core and exports.jrs_core.AddJobXP then
                exports.jrs_core:AddJobXP(src, jobKey, amount, 'chicken_job_' .. tostring(key))
                okJob = true
            end
        end)
    end

    if not okJob then
        local core = getCore()
        if core and type(core.addXP) == 'function' then
            pcall(function()
                core.addXP(src, amount, 'chicken_job_' .. tostring(key))
            end)
            return
        end
        TriggerEvent('jrs_core:server:addXP', src, amount, 'chicken_job_' .. tostring(key))
    end
end

function JRSBridge.Discord(title, description)
    local wh = Config.Webhook
    if not wh or not wh.enabled or not wh.url or wh.url == '' then return end

    PerformHttpRequest(wh.url, function() end, 'POST', json.encode({
        username = wh.botName or 'JRS Chicken Job',
        embeds = {{
            title = title,
            description = description,
            color = wh.color or 16753920,
            footer = { text = os.date('%Y-%m-%d %H:%M:%S') }
        }}
    }), { ['Content-Type'] = 'application/json' })
end
