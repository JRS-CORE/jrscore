-- ===================================================================
-- JRS CORE | Native Player Class & State Manager
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local Players = {}
JRSPlayer = {}
JRSPlayer.__index = JRSPlayer

--- Instantiates a new JRSPlayer object for a connected source.
function JRSPlayer.New(source, charData, userData)
    local self = setmetatable({}, JRSPlayer)
    self.source = tonumber(source)
    self.identifier = tostring(charData.identifier or '')
    self.charId = tonumber(charData.charIdentifier or charData.charidentifier) or 0
    self.firstname = tostring(charData.firstname or '')
    self.lastname = tostring(charData.lastname or '')
    self.charData = charData
    self.userData = userData or {}
    return self
end

function JRSPlayer:GetSource() return self.source end
function JRSPlayer:GetIdentifier() return self.identifier end
function JRSPlayer:GetCharId() return self.charId end
function JRSPlayer:GetFirstName() return self.firstname end
function JRSPlayer:GetLastName() return self.lastname end
function JRSPlayer:GetName() return ('%s %s'):format(self.firstname, self.lastname):match('^%s*(.-)%s*$') end

function JRSPlayer:GetJob() return tostring(self.charData.job or 'unemployed') end
function JRSPlayer:GetJobGrade() return tonumber(self.charData.jobgrade) or 0 end
function JRSPlayer:GetJobLabel() return tostring(self.charData.joblabel or self.charData.job or 'Unemployed') end

function JRSPlayer:SetJob(jobName, grade)
    jobName = tostring(jobName or 'unemployed')
    grade = tonumber(grade) or 0
    local changed, reason = Character.setJob(self.source, jobName, grade)
    if changed then
        self.charData.job = jobName
        self.charData.jobgrade = grade
        self:SyncState()
        TriggerEvent('jrs_core:server:onJobChange', self.source, jobName, grade)
        TriggerClientEvent('jrs_core:client:onJobChange', self.source, jobName, grade)
    end
    return changed, reason
end

function JRSPlayer:GetGroup()
    return (jrsCore.GetGroup and jrsCore.GetGroup(self.source)) or self.userData.group or 'user'
end

function JRSPlayer:SetGroup(groupName)
    groupName = tostring(groupName or 'user')
    local changed = jrsCore.SetGroup(self.source, groupName)
    if changed then
        self.userData.group = groupName
        self:SyncState()
        TriggerEvent('jrs_core:server:onGroupChange', self.source, groupName)
        TriggerClientEvent('jrs_core:client:onGroupChange', self.source, groupName)
    end
    return changed
end

function JRSPlayer:IsAdmin()
    local g = self:GetGroup()
    return Config.IsAdminGroup and Config.IsAdminGroup(g) == true
end

function JRSPlayer:GetMoney() return tonumber(self.charData.money) or 0.0 end
function JRSPlayer:AddMoney(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Character.addCurrency(self.source, 0, amount) == true
end
function JRSPlayer:RemoveMoney(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Character.removeCurrency(self.source, 0, amount) == true
end

function JRSPlayer:GetGold() return tonumber(self.charData.gold) or 0.0 end
function JRSPlayer:AddGold(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Character.addCurrency(self.source, 1, amount) == true
end
function JRSPlayer:RemoveGold(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Character.removeCurrency(self.source, 1, amount) == true
end

function JRSPlayer:GetRol() return tonumber(self.charData.rol) or 0.0 end
function JRSPlayer:AddRol(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Character.addCurrency(self.source, 2, amount) == true
end
function JRSPlayer:RemoveRol(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Character.removeCurrency(self.source, 2, amount) == true
end

function JRSPlayer:GetXP() return tonumber(self.charData.xp) or 0 end
function JRSPlayer:GetLevel() return tonumber(self.charData.level) or 1 end
function JRSPlayer:AddXP(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return JRSXP.Add(self.source, amount, reason or 'JRSPlayer:AddXP')
end
function JRSPlayer:RemoveXP(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return JRSXP.Remove(self.source, amount, reason or 'JRSPlayer:RemoveXP')
end

function JRSPlayer:Notify(text, duration)
    TriggerClientEvent('jrs_core:sendRightTipNotification', self.source, tostring(text), tonumber(duration) or 4000)
end

function JRSPlayer:SyncState()
    local s = self.source
    if not GetPlayerName(s) then return end

    local snapshot = {
        charId = self.charId,
        identifier = self.identifier,
        firstname = self.firstname,
        lastname = self.lastname,
        name = self:GetName(),
        job = self:GetJob(),
        jobGrade = self:GetJobGrade(),
        jobLabel = self:GetJobLabel(),
        group = self:GetGroup(),
        money = self:GetMoney(),
        gold = self:GetGold(),
        rol = self:GetRol(),
        xp = self:GetXP(),
        level = self:GetLevel(),
    }

    local p = Player(s)
    p.state:set('jrsPlayer', snapshot, true)
    p.state:set('IsInSession', true, true)
end

-- ===================================================================
-- Global Management Functions
-- ===================================================================

local function getPlayer(source)
    local src = tonumber(source)
    if not src or src <= 0 then return nil end

    if Players[src] then return Players[src] end

    local char = jrsCore.GetCharacter and jrsCore.GetCharacter(src)
    if not char then return nil end

    local user = UserBySource and UserBySource[src]
    local player = JRSPlayer.New(src, char, user)
    Players[src] = player
    player:SyncState()
    return player
end

local function getPlayerByCharId(charId)
    charId = tonumber(charId)
    if not charId then return nil end
    for src, player in pairs(Players) do
        if player.charId == charId then return player end
    end
    for _, src in ipairs(GetPlayers()) do
        local p = getPlayer(tonumber(src))
        if p and p.charId == charId then return p end
    end
    return nil
end

local function getAllPlayers()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        local p = getPlayer(tonumber(src))
        if p then list[#list + 1] = p end
    end
    return list
end

AddEventHandler('jrs_core:server:characterReady', function(source)
    local p = getPlayer(source)
    if p then
        p:SyncState()
        TriggerEvent('jrs_core:server:onPlayerLoaded', source, p)
        TriggerClientEvent('jrs_core:client:onPlayerLoaded', source)
    end
end)

AddEventHandler('jrs_core:server:characterUnloaded', function(source)
    local src = tonumber(source)
    if src then
        Players[src] = nil
        if GetPlayerName(src) then
            Player(src).state:set('jrsPlayer', nil, true)
            Player(src).state:set('IsInSession', false, true)
        end
        TriggerEvent('jrs_core:server:onPlayerUnload', src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then
        Players[src] = nil
    end
end)

-- Public Server Exports
exports('GetPlayer', getPlayer)
exports('GetPlayerByCharId', getPlayerByCharId)
exports('GetAllPlayers', getAllPlayers)
