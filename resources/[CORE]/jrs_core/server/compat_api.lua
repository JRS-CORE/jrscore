-- Extended Core API for the extra scripts (server).
-- exports.jrs_core:GetCore() returns the Core object these scripts expect; every call is
-- served by jrs_core underneath.

local JRS = nil
local function Jrs()
    if JRS == nil or type(JRS.getUser) == "nil" then
        local ok, api = pcall(function() return exports.jrs_core:getCoreApi() end)
        if ok and type(api) == "table" then JRS = api end
    end
    return JRS
end

local function JrsCharacter(source)
    source = tonumber(source)
    if not source then return nil end
    local api = Jrs()
    if not api then return nil end
    local ok, user = pcall(api.getUser, source)
    if ok and type(user) == "table" and type(user.getUsedCharacter) == "table" then
        return user.getUsedCharacter, user
    end
    return nil
end

local function JrsGroup(source, user)
    local api = Jrs()
    if api and api.getGroup then
        local ok, group = pcall(api.getGroup, source)
        if ok and group then return group end
    end
    if type(user) == "table" then
        if type(user.getGroup) == "function" then
            local ok, g = pcall(user.getGroup)
            if ok and g then return g end
        elseif user.getGroup then
            return user.getGroup
        end
        return user.group
    end
    return "user"
end

local REGISTERED_JOBS = {}

--- Character object (getUsedCharacter) backed by the live JRS character.
local function BuildCharacter(source)
    local char, user = JrsCharacter(source)
    if not char then return nil end

    local function live() return (JrsCharacter(source)) or char end
    local data = {}
    local fields = {
        identifier = function(c) return c.identifier end,
        charIdentifier = function(c) return c.charIdentifier end,
        group = function() return JrsGroup(source, user) end,
        job = function(c) return c.job end,
        jobLabel = function(c) return c.joblabel or c.job end,
        jobGrade = function(c) return tonumber(c.jobgrade) or 0 end,
        money = function(c) return tonumber(c.money) or 0 end,
        gold = function(c) return tonumber(c.gold) or 0 end,
        rol = function(c) return tonumber(c.rol) or 0 end,
        xp = function(c) return tonumber(c.xp) or 0 end,
        firstname = function(c) return c.firstname end,
        lastname = function(c) return c.lastname end,
        nickname = function(c) return c.nickname end,
        gender = function(c) return c.gender end,
        age = function(c) return c.age end,
        charDescription = function(c) return c.character_desc end,
        inventory = function(c) return c.inventory end,
        status = function(c) return c.status or '{}' end,
        coords = function(c) return c.coords end,
        isdead = function(c) return Player(source).state.isDead == true end,
        skin = function(c) return c.skin end,
        comps = function(c) return c.comp end,
        skills = function(c) return c.skills or {} end,
        multiJobs = function(c) return c.multijobs or {} end,
        invCapacity = function(c) return tonumber(c.slots) or 0 end,
        source = function() return source end,
    }

    data.addCurrency = function(currency, quantity)
        local c = live()
        return c.addCurrency(source, tonumber(currency) or 0, tonumber(quantity))
    end
    data.removeCurrency = function(currency, quantity)
        local c = live()
        return c.removeCurrency(source, tonumber(currency) or 0, tonumber(quantity))
    end
    data.setJob = function(job, flag)
        local api = Jrs()
        local grade = tonumber(live().jobgrade) or 0
        return api and api.setJob and api.setJob(source, job, grade)
    end
    data.setJobGrade = function(grade, flag)
        local api = Jrs()
        return api and api.setJobGrade and api.setJobGrade(source, tonumber(grade) or 0)
    end
    data.setJobLabel = function(label)
        live().joblabel = label
    end
    data.setGroup = function(group, flag)
        local api = Jrs()
        return api and api.setGroup and api.setGroup(source, group)
    end
    data.addXp = function(quantity) local c = live(); return c.addXP and c.addXP(quantity) end
    data.removeXp = function(quantity) local c = live(); return c.removeXP and c.removeXP(quantity) end
    data.setXp = function(quantity) local c = live(); return c.setXP and c.setXP(quantity) end
    data.setStatus = function(status) live().status = status end
    data.setSkills = function(skills) live().skills = skills end
    data.setMoney = function(value)
        local c, diff = live(), (tonumber(value) or 0) - (tonumber(live().money) or 0)
        if diff > 0 then c.addCurrency(source, 0, diff) elseif diff < 0 then c.removeCurrency(source, 0, -diff) end
    end
    data.setGold = function(value)
        local c, diff = live(), (tonumber(value) or 0) - (tonumber(live().gold) or 0)
        if diff > 0 then c.addCurrency(source, 1, diff) elseif diff < 0 then c.removeCurrency(source, 1, -diff) end
    end
    data.updateInvCapacity = function() end
    data.getMultiJobsCount = function()
        local n = 0
        for _ in pairs(live().multijobs or {}) do n = n + 1 end
        return n
    end
    data.setMultiJob = function() return false end
    data.removeMultiJob = function() return false end
    data.setFirstname = function(v) live().firstname = v end
    data.setLastname = function(v) live().lastname = v end

    -- The object leaves jrs_core through an export or an event, and a metatable does not survive
    -- that trip: every value has to be a real field (a snapshot, like the scripts expect).
    local current = live()
    for key, getter in pairs(fields) do
        local ok, value = pcall(getter, current)
        if ok and value ~= nil then data[key] = value end
    end

    return setmetatable(data, {
        __index = function(_, key)
            local getter = fields[key]
            if getter then return getter(live()) end
            return live()[key]
        end,
    })
end

local function BuildUser(source)
    local char, user = JrsCharacter(source)
    if not user then return nil end
    local identifier = char and char.identifier or GetPlayerIdentifierByType(tostring(source), 'steam')
    return {
        source = source,
        getGroup = JrsGroup(source, user),
        getUsedCharacter = BuildCharacter(source),
        getUserCharacters = {},
        getCharperm = 0,
        maxJobsAllowed = 0,
        getIdentifier = function() return identifier end,
        getPlayerwarnings = function() return 0 end,
        setPlayerWarnings = function() end,
        setGroup = function(group)
            local api = Jrs()
            return api and api.setGroup and api.setGroup(source, group)
        end,
        setCharperm = function() end,
        getNumOfCharacters = function() return 1 end,
    }
end

ExtCoreFunctions = {}

ExtCoreFunctions.maxCharacters = function(source)
    local ok, n = pcall(function() return exports.jrs_core:GetMaxCharacters(source) end)
    return ok and n or 1
end

ExtCoreFunctions.getUser = function(source)
    if not source then return nil end
    return BuildUser(tonumber(source))
end

ExtCoreFunctions.getUsers = function()
    local users = {}
    for _, id in ipairs(GetPlayers()) do
        local user = BuildUser(tonumber(id))
        if user then users[user.getIdentifier()] = { GetUser = function() return user end } end
    end
    return users
end

ExtCoreFunctions.getUserByCharId = function(charid)
    for _, id in ipairs(GetPlayers()) do
        local char = JrsCharacter(tonumber(id))
        if char and tonumber(char.charIdentifier) == tonumber(charid) then
            return BuildUser(tonumber(id))
        end
    end
    return nil
end

-- Notifications go to the client bridge, which shows them with jrs_core.
local function notify(event)
    return function(source, ...) TriggerClientEvent(event, source, ...) end
end
ExtCoreFunctions.NotifyTip = notify('jrs:Tip')
ExtCoreFunctions.NotifyLeft = notify('jrs:NotifyLeft')
ExtCoreFunctions.NotifyRightTip = notify('jrs:TipRight')
ExtCoreFunctions.NotifyObjective = notify('jrs:TipBottom')
ExtCoreFunctions.NotifyTop = notify('jrs:NotifyTop')
ExtCoreFunctions.NotifySimpleTop = notify('jrs:ShowTopNotification')
ExtCoreFunctions.NotifyAvanced = notify('jrs:ShowAdvancedRightNotification')
ExtCoreFunctions.NotifyAdvanced = ExtCoreFunctions.NotifyAvanced
ExtCoreFunctions.NotifyCenter = notify('jrs:ShowSimpleCenterText')
ExtCoreFunctions.NotifyBottomRight = notify('jrs:ShowBottomRight')
ExtCoreFunctions.NotifyFail = notify('jrs:failmissioNotifY')
ExtCoreFunctions.NotifyDead = notify('jrs:deadplayerNotifY')
ExtCoreFunctions.NotifyUpdate = notify('jrs:updatemissioNotify')
ExtCoreFunctions.NotifyWarning = notify('jrs:warningNotify')
ExtCoreFunctions.NotifyLeftRank = notify('jrs:LeftRank')
ExtCoreFunctions.NotifyThreeSimpleTop = notify('jrs:ThreeSimpleTop')
ExtCoreFunctions.NotifyOneSimpleTop = notify('jrs:OneSimpleTop')
ExtCoreFunctions.NotifyLeftInteractive = notify('jrs:LeftInteractive')

ExtCoreFunctions.dbUpdateAddTables = function() end
ExtCoreFunctions.dbUpdateAddUpdates = function() end

-- Discord webhook logs (Discord embed).
ExtCoreFunctions.AddWebhook = function(title, webhook, description, color, name, logo, footerlogo, avatar)
    if type(webhook) ~= "string" or not webhook:find("^https://") then return end
    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        username = name or "JRS",
        avatar_url = avatar,
        embeds = { {
            color = tonumber(color) or 16711680,
            title = title,
            description = description,
            thumbnail = logo and { url = logo } or nil,
            footer = { text = os.date("%d/%m/%Y %H:%M"), icon_url = footerlogo },
        } },
    }), { ['Content-Type'] = 'application/json' })
end
AddEventHandler('jrs_core:addWebhook', ExtCoreFunctions.AddWebhook)

ExtCoreFunctions.Callback = {
    Register = function(name, callback) ExtServerRPC.Callback.Register(name, callback) end,
    TriggerAsync = function(name, source, callback, ...) ExtServerRPC.Callback.TriggerAsync(name, source, callback, ...) end,
    TriggerAwait = function(name, source, ...) return ExtServerRPC.Callback.TriggerAwait(name, source, ...) end,
}
ExtCoreFunctions.addRpcCallback = ExtCoreFunctions.Callback.Register

-- JRS Core handles whitelisting itself; these keep jrs_admin working.
ExtCoreFunctions.Whitelist = {
    getEntry = function(identifier)
        local row = MySQL and MySQL.single.await('SELECT * FROM jrs_whitelist WHERE identifier = ? LIMIT 1', { identifier })
        return row
    end,
    whitelistUser = function(steam)
        if not steam then return end
        MySQL.insert.await('INSERT IGNORE INTO jrs_whitelist (identifier) VALUES (?)', { steam })
        return true
    end,
    unWhitelistUser = function(steam)
        if not steam then return end
        MySQL.update.await('DELETE FROM jrs_whitelist WHERE identifier = ?', { steam })
    end,
}

ExtCoreFunctions.Player = {
    Heal = function(source)
        if not source then return end
        TriggerEvent("jrs_core:Server:OnPlayerHeal", source)
        TriggerClientEvent("jrs_core:Client:OnPlayerHeal", source)
    end,
    Revive = function(source, param)
        if not source then return end
        TriggerEvent("jrs_core:Server:OnPlayerRevive", source, param)
        TriggerClientEvent("jrs_core:Client:OnPlayerRevive", source, param)
    end,
    Respawn = function(source, param)
        if not source then return end
        TriggerEvent("jrs_core:Server:OnPlayerRespawn", source, param)
        TriggerClientEvent("jrs_core:Client:OnPlayerRespawn", source, param)
    end,
}

ExtCoreFunctions.RegisterJobs = function(data, resourcename)
    if type(data) ~= "table" then return end
    for jobname, v in pairs(data) do
        REGISTERED_JOBS[jobname] = { RESOURCE = resourcename, PRIVATE_JOB = v.privateJob, GRADES = {}, GROUPS = {} }
        for grade, info in pairs(type(v.grades) == "table" and v.grades or {}) do
            REGISTERED_JOBS[jobname].GRADES[grade] = { LABEL = info.label or "Unknown", PRIVATE_GRADE = info.privateGrade }
        end
        for _, groupName in ipairs(type(v.groups) == "table" and v.groups or {}) do
            REGISTERED_JOBS[jobname].GROUPS[groupName] = true
        end
    end
end
ExtCoreFunctions.GetRegisteredJobs = function(job)
    if job then return REGISTERED_JOBS[job] end
    return REGISTERED_JOBS
end

exports('GetCore', function() return ExtCoreFunctions end)
exports('jrsAPI', function() return ExtCoreFunctions end)
AddEventHandler('getWhitelistTables', function(cb) cb(ExtCoreFunctions.Whitelist) end)
AddEventHandler('getCore', function(cb) if type(cb) == 'function' then cb(ExtCoreFunctions) end end)

-- Bans (server-side event only): status true = ban, false = unban.
-- id = jrs_whitelist id or an identifier, datetime = unix time the ban ends (0 = permanent).
-- Stored in jrs_bans (date = end of the ban, NULL = permanent); connection.lua refuses active bans.
AddEventHandler('jrsbans:addtodb', function(status, id, datetime)
    local identifier = type(id) == 'string' and id:find(':') and id or nil
    if not identifier and tonumber(id) then
        local row = MySQL.single.await('SELECT identifier FROM jrs_whitelist WHERE id = ? LIMIT 1', { tonumber(id) })
        identifier = row and row.identifier
    end
    if not identifier then return end
    MySQL.update.await('DELETE FROM jrs_bans WHERE identifier = ?', { identifier })
    if status ~= true then return end
    datetime = tonumber(datetime) or 0
    MySQL.insert.await('INSERT INTO jrs_bans (identifier, reason, date) VALUES (?, ?, ?)', {
        identifier, 'Banned by staff', datetime > 0 and os.date('%Y-%m-%d %H:%M:%S', math.floor(datetime)) or nil
    })
    for _, pid in ipairs(GetPlayers()) do
        for _, ident in ipairs(GetPlayerIdentifiers(pid)) do
            if ident == identifier then
                DropPlayer(pid, datetime > 0 and ('Banned until ' .. os.date('%d/%m/%Y %H:%M', math.floor(datetime))) or 'Banned')
                break
            end
        end
    end
end)

-- Internal: a client in the death screen asked to respawn.
-- Only a dead player can respawn (otherwise it is a free heal + teleport), once per 10 s.
local lastRespawn = {}
RegisterNetEvent('jrs_core:PlayerRespawnInternal', function()
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) > 0 then return end
    if lastRespawn[src] and os.time() - lastRespawn[src] < 10 then return end
    lastRespawn[src] = os.time()
    ExtCoreFunctions.Player.Respawn(src, true)
end)
AddEventHandler('playerDropped', function() lastRespawn[source] = nil end)

JRSExtBridge = { BuildUser = BuildUser, JrsCharacter = JrsCharacter, JrsGroup = JrsGroup }
