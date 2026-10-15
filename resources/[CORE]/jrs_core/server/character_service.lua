
-- ============================================================================
-- JRS Character Service
-- Unified character lifecycle / state bags / offline API / multijob / skills /
-- duty / appearance facade. Keeps the existing JRS database authoritative.
-- ============================================================================
JRSCharacterService = JRSCharacterService or {}
local Service = JRSCharacterService

local deleteHooks = {}
local starterHooks = {}
local switchCooldown = {}
local schemaReady = false

local function srcOf(value)
    local src = tonumber(value)
    if not src or src <= 0 then return nil end
    return src
end

local function awaitExecute(query, params)
    local p = promise.new()
    exports.oxmysql:execute(query, params or {}, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end

local function firstRow(query, params)
    local rows = awaitExecute(query, params)
    return type(rows) == 'table' and rows[1] or nil
end

local function decode(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, data = pcall(json.decode, value)
    return ok and type(data) == 'table' and data or fallback
end

local function encode(value)
    local ok, data = pcall(json.encode, type(value) == 'table' and value or {})
    return ok and data or '{}'
end

local function liveCharacter(source)
    source = srcOf(source)
    if not source then return nil end
    if jrsCore and type(jrsCore.GetCharacter) == 'function' then
        return jrsCore.GetCharacter(source)
    end
    return nil
end

local function charIdOf(reference)
    -- Numeric values are treated as character ids. This avoids a subtle collision
    -- where character id 5 could be mistaken for online server id 5.
    -- To resolve from a player source, pass { source = src }.
    if type(reference) == 'table' then
        local explicit = tonumber(reference.charIdentifier or reference.charidentifier or reference.characterId)
        if explicit then return explicit end
        local source = srcOf(reference.source or reference.playerSource)
        local character = source and liveCharacter(source) or nil
        return character and tonumber(character.charIdentifier) or nil
    end
    return tonumber(reference)
end

local function charIdFromSource(source)
    local src = srcOf(source)
    local character = src and liveCharacter(src) or nil
    return character and tonumber(character.charIdentifier) or nil
end

local function setState(source, key, value)
    source = srcOf(source)
    if not source then return end
    local player = Player(source)
    if player and player.state then player.state:set(key, value, true) end
end

local function cleanText(value, maxLength)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' ')
    text = text:match('^%s*(.-)%s*$') or ''
    maxLength = math.max(1, tonumber(maxLength) or 128)
    if #text > maxLength then text = text:sub(1, maxLength) end
    return text
end

local function normalizeRow(row)
    if type(row) ~= 'table' then return nil end
    row.charIdentifier = tonumber(row.charidentifier or row.charIdentifier)
    row.charidentifier = row.charIdentifier
    row.jobgrade = tonumber(row.jobgrade or row.jobGrade) or 0
    row.onduty = (row.onduty == true or tonumber(row.onduty) == 1)
    row.multijobs = decode(row.multijobs, {})
    row.skills = decode(row.skills, {})
    row.meta = decode(row.meta, {})
    return row
end

local function syncLiveFields(character, row)
    if type(character) ~= 'table' or type(row) ~= 'table' then return character end
    character.multijobs = decode(row.multijobs, type(character.multijobs) == 'table' and character.multijobs or {})
    character.skills = decode(row.skills, type(character.skills) == 'table' and character.skills or {})
    character.onduty = (row.onduty == true or tonumber(row.onduty) == 1)
    character.nickname = row.nickname or character.nickname or ''
    character.occupation = row.occupation or character.occupation or ''
    character.dateofbirth = row.dateofbirth or character.dateofbirth
    character.character_desc = row.character_desc or character.character_desc or ''
    character.gender = row.gender or character.gender
    character.last_played = row.last_played or character.last_played
    character.appearance_version = tonumber(row.appearance_version) or tonumber(character.appearance_version) or 1
    return character
end

local function syncState(source, character, row)
    source = srcOf(source)
    if not source or type(character) ~= 'table' then return end
    row = row or character
    setState(source, 'CharacterId', tonumber(character.charIdentifier) or character.charIdentifier)
    setState(source, 'CharacterIdentifier', tostring(character.identifier or ''))
    setState(source, 'FirstName', tostring(character.firstname or ''))
    setState(source, 'LastName', tostring(character.lastname or ''))
    setState(source, 'Job', tostring(character.job or 'unemployed'))
    setState(source, 'JobGrade', tonumber(character.jobgrade or character.jobGrade) or 0)
    setState(source, 'JobLabel', tostring(character.joblabel or row.joblabel or character.job or 'unemployed'))
    setState(source, 'Group', tostring((jrsCore.GetGroup and jrsCore.GetGroup(source)) or 'user'))
    setState(source, 'OnDuty', character.onduty == true)
    setState(source, 'Gender', tostring(character.gender or row.gender or ''))
    setState(source, 'Nickname', tostring(character.nickname or row.nickname or ''))
end

local function ensureSkill(skillName, data)
    data = type(data) == 'table' and data or {}
    local cfg = Config.CharacterService and Config.CharacterService.Skills
    cfg = type(cfg) == 'table' and cfg[skillName] or nil
    local xpPerLevel = math.max(1, tonumber(cfg and cfg.xpPerLevel) or 100)
    local maxLevel = math.max(1, math.floor(tonumber(cfg and cfg.maxLevel) or 100))
    local xp = math.max(0, math.floor(tonumber(data.xp or data.Exp) or 0))
    local level = math.min(maxLevel, math.floor(xp / xpPerLevel) + 1)
    return {
        xp = xp,
        level = level,
        maxLevel = maxLevel,
        nextLevelXp = level >= maxLevel and xp or (level * xpPerLevel),
        label = data.label or data.Label or tostring(skillName),
    }
end

local function persistJsonColumn(character, column, value)
    if type(character) ~= 'table' or not character.identifier or not character.charIdentifier then return false end
    local encoded = encode(value)
    awaitExecute(
        ('UPDATE jrs_characters SET `%s`=@value WHERE identifier=@identifier AND charidentifier=@charid'):format(column),
        { value = encoded, identifier = character.identifier, charid = character.charIdentifier }
    )
    character[column] = value
    return true
end

local migrations = {
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `multijobs` LONGTEXT NULL",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `skills` LONGTEXT NULL",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `onduty` TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `character_desc` VARCHAR(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT ''",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `gender` VARCHAR(16) NULL DEFAULT NULL",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `last_played` TIMESTAMP NULL DEFAULT NULL",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `appearance_version` INT NOT NULL DEFAULT 1",
    "ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `health_state` LONGTEXT NULL",
}

CreateThread(function()
    for _, query in ipairs(migrations) do
        pcall(awaitExecute, query, {})
    end
    schemaReady = true
    TriggerEvent('jrs_core:server:characterSchemaReady')
end)

function Service.IsSchemaReady() return schemaReady end
function Service.Get(source) return liveCharacter(source) end

function Service.GetData(source)
    local src = srcOf(source)
    local character = src and liveCharacter(src) or nil
    if not character then return nil end
    local row = firstRow('SELECT * FROM jrs_characters WHERE identifier=@identifier AND charidentifier=@charid LIMIT 1', {
        identifier = character.identifier,
        charid = character.charIdentifier,
    })
    if row then syncLiveFields(character, row) end
    local meta = type(character.meta) == 'table' and character.meta or decode(character.meta, {})
    return {
        source = src,
        identifier = character.identifier,
        charIdentifier = tonumber(character.charIdentifier) or character.charIdentifier,
        firstname = character.firstname,
        lastname = character.lastname,
        nickname = character.nickname or '',
        occupation = character.occupation or '',
        dateofbirth = character.dateofbirth,
        gender = character.gender,
        description = character.character_desc or '',
        job = character.job,
        jobGrade = tonumber(character.jobgrade or character.jobGrade) or 0,
        jobLabel = character.joblabel or character.job,
        onDuty = character.onduty == true,
        group = (jrsCore.GetGroup and jrsCore.GetGroup(src)) or 'user',
        multijobs = type(character.multijobs) == 'table' and character.multijobs or decode(character.multijobs, {}),
        skills = type(character.skills) == 'table' and character.skills or decode(character.skills, {}),
        metadata = meta,
        money = tonumber(character.money) or 0,
        gold = tonumber(character.gold) or 0,
        rol = tonumber(character.rol) or 0,
        dirtymoney = tonumber(character.dirtymoney) or 0,
        xp = tonumber(character.xp) or 0,
        lastPlayed = character.last_played,
    }
end

function Service.GetOfflineById(characterId)
    characterId = tonumber(characterId)
    if not characterId then return nil end
    return normalizeRow(firstRow('SELECT * FROM jrs_characters WHERE charidentifier=@charid LIMIT 1', { charid = characterId }))
end

function Service.GetById(characterId)
    characterId = tonumber(characterId)
    if not characterId then return nil end
    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        local character = src and liveCharacter(src)
        if character and tonumber(character.charIdentifier) == characterId then
            return character, src, true
        end
    end
    return Service.GetOfflineById(characterId), nil, false
end

function Service.GetByIdentifier(identifier)
    identifier = tostring(identifier or '')
    if identifier == '' then return {} end
    local limit = math.max(1, math.min(200, tonumber(Config.CharacterService.OfflineLookupLimit) or 50))
    local rows = awaitExecute(('SELECT * FROM jrs_characters WHERE identifier=@identifier ORDER BY charidentifier ASC LIMIT %d'):format(limit), { identifier = identifier })
    local out = {}
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do out[#out + 1] = normalizeRow(row) end
    return out
end

function Service.FindByName(firstname, lastname)
    firstname = cleanText(firstname, 50)
    lastname = cleanText(lastname, 50)
    if firstname == '' then return {} end
    local limit = math.max(1, math.min(200, tonumber(Config.CharacterService.OfflineLookupLimit) or 50))
    local sql, params
    if lastname ~= '' then
        sql = ('SELECT * FROM jrs_characters WHERE firstname=@firstname AND lastname=@lastname ORDER BY last_played DESC LIMIT %d'):format(limit)
        params = { firstname = firstname, lastname = lastname }
    else
        sql = ('SELECT * FROM jrs_characters WHERE firstname=@firstname ORDER BY last_played DESC LIMIT %d'):format(limit)
        params = { firstname = firstname }
    end
    local rows = awaitExecute(sql, params)
    local out = {}
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do out[#out + 1] = normalizeRow(row) end
    return out
end

function Service.GetCount(source)
    local src = srcOf(source)
    if not src then return 0 end
    local identifier = GetPlayerIdentifierByType(src, 'steam') or GetPlayerIdentifier(src)
    if not identifier then return 0 end
    local row = firstRow('SELECT COUNT(*) AS total FROM jrs_characters WHERE identifier=@identifier', { identifier = identifier })
    return tonumber(row and (row.total or row['COUNT(*)'])) or 0
end

function Service.GetMaxCharacters(source)
    local src = srcOf(source)
    if not src then return tonumber(Config.Char_Count) or 1 end
    local user = jrsCore.getUser and jrsCore.getUser(src) or nil
    return math.max(1, tonumber(user and user.chars) or tonumber(Config.Char_Count) or 1)
end

function Service.CanCreate(source)
    return Service.GetCount(source) < Service.GetMaxCharacters(source)
end

function Service.SetMaxCharacters(source, count)
    local src = srcOf(source)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if not src then return false end
    local user = jrsCore.getUser and jrsCore.getUser(src) or nil
    if not user or not user.identifier then return false end
    awaitExecute('UPDATE jrs_users SET chars=@count, chars_override=@count WHERE identifier=@identifier', { count = count, identifier = user.identifier })
    user.chars = count
    if LoadedUsers and LoadedUsers[user.identifier] then
        LoadedUsers[user.identifier].chars = count
    end
    if UserBySource and UserBySource[src] then
        UserBySource[src].chars = count
    end
    return true
end

function Service.GetMetadata(source, key, default)
    local character = liveCharacter(source)
    if not character then return default end
    local meta = type(character.meta) == 'table' and character.meta or decode(character.meta, {})
    if key == nil then return meta end
    local value = meta[tostring(key)]
    return value == nil and default or value
end

function Service.SetMetadata(source, key, value)
    local character = liveCharacter(source)
    if not character then return false end
    local meta = type(character.meta) == 'table' and character.meta or decode(character.meta, {})
    meta[tostring(key)] = value
    character.meta = meta
    awaitExecute('UPDATE jrs_characters SET meta=@meta WHERE identifier=@identifier AND charidentifier=@charid', {
        meta = encode(meta), identifier = character.identifier, charid = character.charIdentifier
    })
    TriggerEvent('jrs_core:server:metadataChanged', tonumber(source), tostring(key), value)
    return true
end

function Service.AddMetadata(source, key, amount)
    local current = tonumber(Service.GetMetadata(source, key, 0)) or 0
    return Service.SetMetadata(source, key, current + (tonumber(amount) or 0))
end

function Service.RemoveMetadata(source, key, amount)
    local current = tonumber(Service.GetMetadata(source, key, 0)) or 0
    return Service.SetMetadata(source, key, current - (tonumber(amount) or 0))
end

function Service.GetJobs(source)
    local character = liveCharacter(source)
    if not character then return {} end
    local jobs = type(character.multijobs) == 'table' and character.multijobs or decode(character.multijobs, {})
    local active = tostring(character.job or 'unemployed')
    if jobs[active] == nil then
        jobs[active] = { grade = tonumber(character.jobgrade) or 0, label = character.joblabel or active }
    end
    character.multijobs = jobs
    return jobs
end

function Service.AddJob(source, job, grade, label)
    local character = liveCharacter(source)
    job = cleanText(job, 64)
    if not character or job == '' then return false, 'invalid_job' end
    local jobs = Service.GetJobs(source)
    local count = 0
    for _ in pairs(jobs) do count = count + 1 end
    local maxJobs = math.floor(tonumber(Config.CharacterService.MaxJobs) or 0)
    if jobs[job] == nil and maxJobs > 0 and count >= maxJobs then
        return false, 'max_jobs'
    end
    jobs[job] = { grade = math.max(0, math.floor(tonumber(grade) or 0)), label = cleanText(label or job, 80) }
    persistJsonColumn(character, 'multijobs', jobs)
    TriggerEvent('jrs_core:server:multiJobChanged', tonumber(source), jobs)
    return true
end

function Service.RemoveJob(source, job)
    local character = liveCharacter(source)
    job = cleanText(job, 64)
    if not character or job == '' then return false end
    if tostring(character.job) == job then return false, 'active_job' end
    local jobs = Service.GetJobs(source)
    if jobs[job] == nil then return false, 'not_found' end
    jobs[job] = nil
    persistJsonColumn(character, 'multijobs', jobs)
    TriggerEvent('jrs_core:server:multiJobChanged', tonumber(source), jobs)
    return true
end

function Service.SwitchJob(source, job)
    local src = srcOf(source)
    local character = src and liveCharacter(src)
    job = cleanText(job, 64)
    if not character or job == '' then return false, 'invalid_job' end
    local jobs = Service.GetJobs(src)
    local entry = jobs[job]
    if not entry then return false, 'job_not_owned' end
    local now = os.time()
    local last = tonumber(switchCooldown[src]) or 0
    local cd = math.max(0, tonumber(Config.CharacterService.JobSwitchCooldownSeconds) or 0)
    if now - last < cd then return false, 'cooldown' end
    local ok, reason = Character.setJob(src, job, tonumber(entry.grade) or 0)
    if ok ~= true then return false, reason or 'set_job_failed' end
    switchCooldown[src] = now
    Service.SetDuty(src, false)
    return true
end

function Service.SetDuty(source, state)
    local src = srcOf(source)
    local character = src and liveCharacter(src)
    if not character then return false end
    state = state == true
    character.onduty = state
    awaitExecute('UPDATE jrs_characters SET onduty=@duty WHERE identifier=@identifier AND charidentifier=@charid', {
        duty = state and 1 or 0, identifier = character.identifier, charid = character.charIdentifier
    })
    setState(src, 'OnDuty', state)
    TriggerEvent('jrs_core:server:dutyChanged', src, state, character.job)
    TriggerClientEvent('jrs_core:client:dutyChanged', src, state, character.job)
    return true
end

function Service.ToggleDuty(source)
    local character = liveCharacter(source)
    if not character then return false end
    local value = character.onduty ~= true
    Service.SetDuty(source, value)
    return value
end

function Service.GetDutyPlayers(job)
    job = tostring(job or '')
    local list = {}
    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        local character = src and liveCharacter(src)
        if character and tostring(character.job) == job and character.onduty == true then
            list[#list + 1] = src
        end
    end
    return list, #list
end

function Service.GetSkills(source)
    local character = liveCharacter(source)
    if not character then return {} end
    local skills = type(character.skills) == 'table' and character.skills or decode(character.skills, {})
    character.skills = skills
    return skills
end

function Service.GetSkill(source, skillName)
    skillName = tostring(skillName or '')
    if skillName == '' then return nil end
    local skills = Service.GetSkills(source)
    local normalized = ensureSkill(skillName, skills[skillName])
    skills[skillName] = normalized
    return normalized
end

function Service.SetSkillXP(source, skillName, xp)
    local character = liveCharacter(source)
    skillName = tostring(skillName or '')
    if not character or skillName == '' then return false end
    local skills = Service.GetSkills(source)
    local before = ensureSkill(skillName, skills[skillName])
    skills[skillName] = ensureSkill(skillName, { xp = math.max(0, math.floor(tonumber(xp) or 0)), label = before.label })
    persistJsonColumn(character, 'skills', skills)
    if skills[skillName].level ~= before.level then
        TriggerEvent('jrs_core:server:skillLevelChanged', tonumber(source), skillName, skills[skillName].level, before.level)
        TriggerClientEvent('jrs_core:client:skillLevelChanged', tonumber(source), skillName, skills[skillName].level, before.level)
    end
    return true, skills[skillName]
end

function Service.AddSkillXP(source, skillName, amount)
    local current = Service.GetSkill(source, skillName)
    if not current then return false end
    return Service.SetSkillXP(source, skillName, current.xp + (tonumber(amount) or 0))
end

function Service.GetAppearance(sourceOrCharId)
    local charid = charIdOf(sourceOrCharId)
    if not charid then return nil end
    local row = firstRow('SELECT skinPlayer, compPlayer, appearance_version FROM jrs_characters WHERE charidentifier=@charid LIMIT 1', { charid = charid })
    if not row then return nil end
    local appearance = {
        charIdentifier = charid,
        skin = decode(row.skinPlayer, {}),
        components = decode(row.compPlayer, {}),
        version = tonumber(row.appearance_version) or 1,
    }
    if GetResourceState('jrs_clothing') == 'started' then
        local ok, clothes, outfit, hidden = pcall(function() return exports.jrs_clothing:GetCharacterClothes(charid) end)
        if ok and type(clothes) == 'table' and next(clothes) ~= nil then
            appearance.components, appearance.outfitId, appearance.hiddenCategories = clothes, outfit, hidden
        end
    end
    if GetResourceState('jrs_barber') == 'started' then
        local ok, barber = pcall(function() return exports.jrs_barber:GetCharacterBarber(charid) end)
        if ok and type(barber) == 'table' then appearance.barber = barber end
    end
    return appearance
end

function Service.SaveAppearance(sourceOrCharId, data)
    if type(data) ~= 'table' then return false, 'invalid_data' end
    local charid = charIdOf(sourceOrCharId)
    if not charid then return false, 'character_not_found' end
    local updates, params = {}, { charid = charid }
    if type(data.skin) == 'table' then
        updates[#updates + 1] = 'skinPlayer=@skin'
        params.skin = encode(data.skin)
    end
    if type(data.components) == 'table' then
        updates[#updates + 1] = 'compPlayer=@components'
        params.components = encode(data.components)
    end
    updates[#updates + 1] = 'appearance_version=appearance_version+1'
    if #updates > 0 then
        awaitExecute('UPDATE jrs_characters SET ' .. table.concat(updates, ', ') .. ' WHERE charidentifier=@charid', params)
    end

    if type(data.components) == 'table' and GetResourceState('jrs_clothing') == 'started' then
        pcall(function() exports.jrs_clothing:SetCharacterClothes(charid, data.components, data.outfitId) end)
    end
    if type(data.barber) == 'table' and GetResourceState('jrs_barber') == 'started' then
        local b = data.barber
        pcall(function()
            exports.jrs_barber:SetCharacterBarber(charid, b.hairstyle or {}, b.overlays or {}, b.permanentoverlay or {}, b.outfit_id or b.outfitId)
        end)
    end

    local character, liveSource = Service.GetById(charid)
    if liveSource and type(character) == 'table' then
        if type(data.skin) == 'table' then character.skin = encode(data.skin) end
        if type(data.components) == 'table' then character.comp = encode(data.components) end
        TriggerEvent('jrs_core:server:appearanceChanged', liveSource, charid, data)
    end
    return true
end

function Service.RefreshAppearanceCache(sourceOrCharId)
    local charid = charIdOf(sourceOrCharId)
    if not charid then return false, 'character_not_found' end
    local appearance = Service.GetAppearance(charid)
    if not appearance then return false, 'appearance_not_found' end
    local character, liveSource = Service.GetById(charid)
    if liveSource and type(character) == 'table' then
        character.skin = encode(appearance.skin or {})
        character.comp = encode(appearance.components or {})
        character.components = character.comp
        character.appearance_version = tonumber(appearance.version) or tonumber(character.appearance_version) or 1
        TriggerEvent('jrs_core:server:appearanceChanged', liveSource, charid, appearance)
        TriggerClientEvent('jrs_core:client:appearanceChanged', liveSource, charid, appearance.version)
    end
    return true, appearance
end

function Service.SaveHealthState(source, healthState)
    local character = liveCharacter(source)
    if not character or type(healthState) ~= 'table' then return false end
    awaitExecute('UPDATE jrs_characters SET health_state=@state WHERE identifier=@identifier AND charidentifier=@charid', {
        state = encode(healthState), identifier = character.identifier, charid = character.charIdentifier
    })
    character.healthState = healthState
    return true
end

function Service.GetHealthState(sourceOrCharId)
    local charid = charIdOf(sourceOrCharId)
    if not charid then return nil end
    local row = firstRow('SELECT health_state FROM jrs_characters WHERE charidentifier=@charid LIMIT 1', { charid = charid })
    return row and decode(row.health_state, {}) or {}
end

function Service.GetAppearanceForSource(source)
    local charid = charIdFromSource(source)
    return charid and Service.GetAppearance(charid) or nil
end

function Service.RefreshAppearanceForSource(source)
    local charid = charIdFromSource(source)
    if not charid then return false, 'character_not_found' end
    return Service.RefreshAppearanceCache(charid)
end

function Service.GetHealthStateForSource(source)
    local charid = charIdFromSource(source)
    return charid and Service.GetHealthState(charid) or nil
end

function Service.Save(source)
    local src = srcOf(source)
    local character = src and liveCharacter(src)
    if not character then return false end
    awaitExecute([[
        UPDATE jrs_characters
        SET firstname=@firstname, lastname=@lastname, job=@job, jobgrade=@jobgrade,
            onduty=@onduty, multijobs=@multijobs, skills=@skills, meta=@meta,
            last_played=CURRENT_TIMESTAMP
        WHERE identifier=@identifier AND charidentifier=@charid
    ]], {
        firstname = character.firstname or '',
        lastname = character.lastname or '',
        job = character.job or 'unemployed',
        jobgrade = tonumber(character.jobgrade) or 0,
        onduty = character.onduty == true and 1 or 0,
        multijobs = encode(Service.GetJobs(src)),
        skills = encode(Service.GetSkills(src)),
        meta = encode(type(character.meta) == 'table' and character.meta or decode(character.meta, {})),
        identifier = character.identifier,
        charid = character.charIdentifier,
    })
    TriggerEvent('jrs_core:server:characterSaved', src, character)
    return true
end

function Service.RegisterDeleteHook(name, callback)
    name = tostring(name or '')
    if name == '' or type(callback) ~= 'function' then return false end
    deleteHooks[name] = callback
    return true
end

function Service.RunDeleteHooks(characterId, identifier, phase)
    local okAll = true
    for name, callback in pairs(deleteHooks) do
        local ok, result = pcall(callback, tonumber(characterId), identifier, phase or 'before')
        if not ok or result == false then
            okAll = false
            print(('^1[jrs_core] character delete hook %s failed: %s^0'):format(name, tostring(result)))
        end
    end
    TriggerEvent('jrs_core:server:characterDeleteHook', tonumber(characterId), identifier, phase or 'before')
    return okAll
end

function Service.RegisterStarterHook(name, callback)
    name = tostring(name or '')
    if name == '' or type(callback) ~= 'function' then return false end
    starterHooks[name] = callback
    return true
end

function Service.RunStarterHooks(source, characterId)
    for name, callback in pairs(starterHooks) do
        local ok, err = pcall(callback, tonumber(source), tonumber(characterId))
        if not ok then print(('^1[jrs_core] starter hook %s failed: %s^0'):format(name, tostring(err))) end
    end
    TriggerEvent('jrs_core:server:firstCharacterSetup', tonumber(source), tonumber(characterId))
end

function Service.GetPlayer(source)
    local src = srcOf(source)
    if not src then return nil end
    return {
        source = src,
        PlayerData = Service.GetData(src),
        Character = liveCharacter(src),
        Functions = {
            AddMoney = function(amount) return jrsCore.addAccount(src, 0, amount) end,
            RemoveMoney = function(amount) return jrsCore.removeAccount(src, 0, amount) end,
            GetMoney = function() return jrsCore.getAccount(src, 0) end,
            SetJob = function(job, grade)
                if type(Character) == 'table' and type(Character.setJob) == 'function' then
                    return Character.setJob(src, job, tonumber(grade) or 0)
                end
                return false, 'set_job_unavailable'
            end,
            SetDuty = function(state) return Service.SetDuty(src, state) end,
            ToggleDuty = function() return Service.ToggleDuty(src) end,
            GetMetadata = function(key, default) return Service.GetMetadata(src, key, default) end,
            SetMetadata = function(key, value) return Service.SetMetadata(src, key, value) end,
            AddSkillXP = function(skill, amount) return Service.AddSkillXP(src, skill, amount) end,
            Save = function() return Service.Save(src) end,
        }
    }
end

-- Refresh extended fields and state bags only after the core has accepted the
-- selected character. No fixed Wait() is required by dependent resources.
AddEventHandler('jrs_core:server:characterReady', function(source, character)
    local src = srcOf(source)
    if not src or type(character) ~= 'table' then return end
    local row = firstRow('SELECT * FROM jrs_characters WHERE identifier=@identifier AND charidentifier=@charid LIMIT 1', {
        identifier = character.identifier, charid = character.charIdentifier
    })
    if row then syncLiveFields(character, row) end
    awaitExecute('UPDATE jrs_characters SET last_played=CURRENT_TIMESTAMP WHERE identifier=@identifier AND charidentifier=@charid', {
        identifier = character.identifier, charid = character.charIdentifier
    })
    syncState(src, character, row)
end)

AddEventHandler('jrs_core:server:characterUnloaded', function(source, character)
    local src = srcOf(source)
    if src then
        switchCooldown[src] = nil
        setState(src, 'OnDuty', false)
        setState(src, 'Job', false)
        setState(src, 'JobGrade', false)
        setState(src, 'FirstName', false)
        setState(src, 'LastName', false)
    end
end)

AddEventHandler('playerDropped', function()
    switchCooldown[tonumber(source)] = nil
end)

-- Stable direct exports
exports('GetPlayerObject', Service.GetPlayer)
exports('GetOfflineCharacter', Service.GetOfflineById)
exports('GetCharacterById', Service.GetById)
exports('GetCharactersByIdentifier', Service.GetByIdentifier)
exports('FindCharactersByName', Service.FindByName)
exports('GetCharacterCount', Service.GetCount)
exports('GetMaxCharacters', Service.GetMaxCharacters)
exports('CanCreateCharacter', Service.CanCreate)
exports('SetMaxCharacters', Service.SetMaxCharacters)
exports('GetMetadata', Service.GetMetadata)
exports('SetMetadata', Service.SetMetadata)
exports('AddMetadata', Service.AddMetadata)
exports('RemoveMetadata', Service.RemoveMetadata)
exports('GetJobs', Service.GetJobs)
exports('AddJob', Service.AddJob)
exports('RemoveJob', Service.RemoveJob)
exports('SwitchJob', Service.SwitchJob)
exports('SetDuty', Service.SetDuty)
exports('ToggleDuty', Service.ToggleDuty)
exports('GetDutyPlayers', Service.GetDutyPlayers)
exports('GetSkill', Service.GetSkill)
exports('GetSkills', Service.GetSkills)
exports('SetSkillXP', Service.SetSkillXP)
exports('AddSkillXP', Service.AddSkillXP)
exports('GetAppearance', Service.GetAppearance)
exports('GetAppearanceForSource', Service.GetAppearanceForSource)
exports('SaveAppearance', Service.SaveAppearance)
exports('RefreshAppearanceCache', Service.RefreshAppearanceCache)
exports('RefreshAppearanceForSource', Service.RefreshAppearanceForSource)
exports('RegisterCharacterDeleteHook', Service.RegisterDeleteHook)
exports('RegisterCharacterStarterHook', Service.RegisterStarterHook)
exports('SaveCharacter', Service.Save)
exports('SaveHealthState', Service.SaveHealthState)
exports('GetHealthState', Service.GetHealthState)
exports('GetHealthStateForSource', Service.GetHealthStateForSource)
exports('RunCharacterDeleteHooks', Service.RunDeleteHooks)
exports('RunStarterHooks', Service.RunStarterHooks)
