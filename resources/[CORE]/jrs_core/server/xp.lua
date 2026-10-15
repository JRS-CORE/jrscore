JRSXP = JRSXP or {}

local xpQueues = {}
local xpQueueBusy = {}

local function getXpTableName()
    local tableName = tostring(Config.XpTable or "jrs_characters_level")
    if not tableName:match("^[%w_]+$") then
        error("[jrs_core] Config.XpTable contains invalid characters")
    end
    return tableName
end

local function getCharacter(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then
        return nil, "invalid_player"
    end

    local user = jrsCore.getUser(playerSource)
    if not user or not user.getUsedCharacter then
        return nil, "player_not_loaded"
    end

    return user.getUsedCharacter
end

local function updateCharacterCache(character, totalXp, levelData)
    if not character then return end
    character.xp = totalXp
    character.level = levelData.level
end

local function sendXpUpdate(playerSource, levelData, changedAmount, previousLevel, reason)
    TriggerClientEvent(
        'jrs_core:xpUpdated',
        playerSource,
        levelData,
        tonumber(changedAmount) or 0,
        tonumber(previousLevel) or levelData.level,
        tostring(reason or "")
    )
end

local function finishQueueTask(charIdentifier)
    xpQueueBusy[charIdentifier] = nil

    local queue = xpQueues[charIdentifier]
    if queue and #queue > 0 then
        SetTimeout(0, function()
            JRSXP.ProcessQueue(charIdentifier)
        end)
    else
        xpQueues[charIdentifier] = nil
    end
end

local function persistXp(task, rowExists, newXp, callback)
    local tableName = getXpTableName()
    local query
    local params

    if rowExists then
        query = ("UPDATE `%s` SET XP = ? WHERE CharIdentifier = ?"):format(tableName)
        params = { newXp, task.charIdentifier }
    else
        query = ("INSERT INTO `%s` (CharIdentifier, XP) VALUES (?, ?)"):format(tableName)
        params = { task.charIdentifier, newXp }
    end

    exports.oxmysql:execute(query, params, function()
        callback(true)
    end)
end

function JRSXP.ProcessQueue(charIdentifier)
    charIdentifier = tonumber(charIdentifier)
    if not charIdentifier or xpQueueBusy[charIdentifier] then return end

    local queue = xpQueues[charIdentifier]
    if not queue or #queue == 0 then
        xpQueues[charIdentifier] = nil
        return
    end

    xpQueueBusy[charIdentifier] = true
    local task = table.remove(queue, 1)
    local tableName = getXpTableName()

    exports.oxmysql:fetch(
        ("SELECT XP FROM `%s` WHERE CharIdentifier = ? LIMIT 1"):format(tableName),
        { charIdentifier },
        function(result)
            local rowExists = result and result[1] ~= nil
            local oldXp = rowExists and math.max(0, math.floor(tonumber(result[1].XP) or 0)) or 0
            local oldData = Config.GetLevelData(oldXp)
            local maximumXp = Config.GetMaximumXp()
            local newXp

            if task.mode == "set" then
                newXp = math.floor(tonumber(task.amount) or 0)
            else
                newXp = oldXp + math.floor(tonumber(task.amount) or 0)
            end

            if newXp < 0 then newXp = 0 end
            if newXp > maximumXp then newXp = maximumXp end

            local newData = Config.GetLevelData(newXp)
            local changedAmount = newXp - oldXp

            persistXp(task, rowExists, newXp, function(success)
                if success then
                    updateCharacterCache(task.character, newXp, newData)
                    sendXpUpdate(task.playerSource, newData, changedAmount, oldData.level, task.reason)
                    if JRSPerks and JRSPerks.Refresh and task.playerSource then
                        JRSPerks.Refresh(task.playerSource, newData.level, oldData.level)
                    end
                end

                if task.callback then
                    task.callback(success, newData, oldData, changedAmount)
                end

                finishQueueTask(charIdentifier)
            end)
        end
    )
end

local function enqueueTask(playerSource, mode, amount, reason, callback)
    local character, errorCode = getCharacter(playerSource)
    if not character then
        if callback then callback(false, nil, nil, 0, errorCode) end
        return false
    end

    amount = math.floor(tonumber(amount) or 0)
    if mode == "add" and amount == 0 then
        if callback then callback(false, nil, nil, 0, "invalid_amount") end
        return false
    end

    local charIdentifier = tonumber(character.charIdentifier)
    if not charIdentifier then
        if callback then callback(false, nil, nil, 0, "invalid_character") end
        return false
    end

    xpQueues[charIdentifier] = xpQueues[charIdentifier] or {}
    table.insert(xpQueues[charIdentifier], {
        playerSource = tonumber(playerSource),
        charIdentifier = charIdentifier,
        character = character,
        mode = mode,
        amount = amount,
        reason = reason,
        callback = callback,
    })

    JRSXP.ProcessQueue(charIdentifier)
    return true
end

function JRSXP.Add(playerSource, amount, reason, callback)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(false, nil, nil, 0, "invalid_amount") end
        return false
    end

    -- Apply the global timed XP multiplier at the exact moment XP is awarded.
    -- Only positive XP gains are boosted; RemoveXP/SetXP keep their original behavior.
    if JRSDoubleXP and type(JRSDoubleXP.Apply) == "function" then
        amount = select(1, JRSDoubleXP.Apply(amount, reason))
    end

    -- jrs_servertag: Discord Server Tag XP bonus, skipped for admin/refund-style reasons.
    -- Security (2026-10-02): read from jrs_servertag on the server. The `jrsTag`
    -- state bag can be set by a cheater on himself (free XP multiplier).
    local okTag, tag = pcall(function()
        if GetResourceState('jrs_servertag') ~= 'started' then return nil end
        return exports.jrs_servertag:GetTagPerks(playerSource)
    end)
    if okTag and type(tag) == "table" and tag.active == true and (tonumber(tag.xp) or 0) > 0 then
        local skip = false
        local reasonText = tostring(reason or "")
        for _, prefix in ipairs({ "admin", "starter_origin", "refund", "tag_" }) do
            if reasonText:sub(1, #prefix) == prefix then skip = true break end
        end
        if not skip then
            amount = math.max(amount, math.floor(amount * (1 + tag.xp) + 0.5))
        end
    end

    return enqueueTask(playerSource, "add", amount, reason, callback)
end

function JRSXP.Remove(playerSource, amount, reason, callback)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(false, nil, nil, 0, "invalid_amount") end
        return false
    end
    return enqueueTask(playerSource, "add", -amount, reason, callback)
end

function JRSXP.Set(playerSource, amount, reason, callback)
    amount = math.floor(tonumber(amount) or 0)
    return enqueueTask(playerSource, "set", amount, reason, callback)
end

function JRSXP.SetLevel(playerSource, level, reason, callback)
    level = math.max(1, math.min(Config.MaxLevel, math.floor(tonumber(level) or 1)))
    local targetXp = Config.GetTotalXpForLevel(level)
    return enqueueTask(playerSource, "set", targetXp, reason or "admin_setlevel", callback)
end

function JRSXP.AddLevel(playerSource, levelDelta, reason, callback)
    levelDelta = math.floor(tonumber(levelDelta) or 0)
    if levelDelta == 0 then
        if callback then callback(false, nil, nil, 0, "invalid_amount") end
        return false
    end

    local curData, err = JRSXP.GetSync(playerSource)
    local curLevel = (curData and curData.level) or 1
    local newLevel = math.max(1, math.min(Config.MaxLevel, curLevel + levelDelta))
    local targetXp = Config.GetTotalXpForLevel(newLevel)
    return enqueueTask(playerSource, "set", targetXp, reason or "admin_addlevel", callback)
end

function JRSXP.RemoveLevel(playerSource, levelDelta, reason, callback)
    levelDelta = math.floor(tonumber(levelDelta) or 0)
    if levelDelta <= 0 then
        if callback then callback(false, nil, nil, 0, "invalid_amount") end
        return false
    end
    return JRSXP.AddLevel(playerSource, -levelDelta, reason or "admin_removelevel", callback)
end

function JRSXP.Get(playerSource, callback)
    local character, errorCode = getCharacter(playerSource)
    if not character then
        if callback then callback(nil, errorCode) end
        return false
    end

    local tableName = getXpTableName()
    exports.oxmysql:fetch(
        ("SELECT XP FROM `%s` WHERE CharIdentifier = ? LIMIT 1"):format(tableName),
        { character.charIdentifier },
        function(result)
            local rowExists = result and result[1] ~= nil
            local totalXp = rowExists and tonumber(result[1].XP) or 0
            local data = Config.GetLevelData(totalXp)

            local function finish()
                updateCharacterCache(character, data.totalXp, data)
                if JRSPerks and JRSPerks.Sync and playerSource then
                    JRSPerks.Sync(playerSource, data.level)
                end
                if callback then callback(data) end
            end

            if rowExists then
                finish()
                return
            end

            exports.oxmysql:execute(
                ("INSERT IGNORE INTO `%s` (CharIdentifier, XP) VALUES (?, 0)"):format(tableName),
                { character.charIdentifier },
                finish
            )
        end
    )
    return true
end

function JRSXP.GetSync(playerSource)
    local pending = promise.new()
    JRSXP.Get(playerSource, function(data, errorCode)
        pending:resolve({ data = data, error = errorCode })
    end)
    local result = Citizen.Await(pending)
    return result.data, result.error
end

-- The character object has no `xp`/`level` field of its own: `characters` has no
-- such column, so applyCharacterRow() cannot populate one and the fields only
-- ever exist because updateCharacterCache() writes them. Until now the ONLY
-- thing that ran on login was the HUD's `jrscore:getFrom` poll, and that loop is
-- gated on `Config.Hud.enabled and characterReady and not dead and not menuOpen`
-- - so a player who opened a menu first, died first, or plays with the HUD off
-- had `character.xp == nil`. Every reader that trusts the cache (the base menu's
-- LEVELS tab among them) then read 0 and reported level 1 no matter how much XP
-- the character actually had in `characters_level`.
--
-- Hydrating once at character-ready makes the cache authoritative from the
-- moment the character loads, and JRSXP.Get also inserts the missing row for a
-- brand new character.
AddEventHandler('jrs_core:server:characterReady', function(playerSource)
    local src = tonumber(playerSource)
    if not src or src <= 0 then return end
    JRSXP.Get(src, function(levelData)
        if not levelData then return end
        if Config.HudDebug then
            print(('^2[jrs_core:XP] hydrated cache for src=%s level=%s totalXP=%s^7')
                :format(src, levelData.level, levelData.totalXp))
        end
    end)
end)

-- Net event listeners for server-side cross-resource event triggers
AddEventHandler('jrs_core:setLevel', function(playerSource, level, reason, callback)
    JRSXP.SetLevel(playerSource, level, reason, callback)
end)
AddEventHandler('jrs_core:addLevel', function(playerSource, delta, reason, callback)
    JRSXP.AddLevel(playerSource, delta, reason, callback)
end)
AddEventHandler('jrs_core:removeLevel', function(playerSource, delta, reason, callback)
    JRSXP.RemoveLevel(playerSource, delta, reason, callback)
end)

exports('AddXP', function(playerSource, amount, reason, callback)
    return JRSXP.Add(playerSource, amount, reason, callback)
end)
exports('addXP', function(playerSource, amount, reason, callback)
    return JRSXP.Add(playerSource, amount, reason, callback)
end)
exports('addXp', function(playerSource, amount, reason, callback)
    return JRSXP.Add(playerSource, amount, reason, callback)
end)

exports('RemoveXP', function(playerSource, amount, reason, callback)
    return JRSXP.Remove(playerSource, amount, reason, callback)
end)
exports('removeXP', function(playerSource, amount, reason, callback)
    return JRSXP.Remove(playerSource, amount, reason, callback)
end)
exports('removeXp', function(playerSource, amount, reason, callback)
    return JRSXP.Remove(playerSource, amount, reason, callback)
end)

exports('SetXP', function(playerSource, amount, reason, callback)
    return JRSXP.Set(playerSource, amount, reason, callback)
end)
exports('setXP', function(playerSource, amount, reason, callback)
    return JRSXP.Set(playerSource, amount, reason, callback)
end)
exports('setXp', function(playerSource, amount, reason, callback)
    return JRSXP.Set(playerSource, amount, reason, callback)
end)

exports('GetXP', function(playerSource)
    return JRSXP.GetSync(playerSource)
end)
exports('getXP', function(playerSource)
    return JRSXP.GetSync(playerSource)
end)
exports('getXp', function(playerSource)
    return JRSXP.GetSync(playerSource)
end)

-- Stable direct level export for other server resources.
-- Prefer this over transporting a function reference inside getCoreApi().
exports('GetLevel', function(playerSource)
    local data, errorCode = JRSXP.GetSync(playerSource)
    if not data then
        return 1, nil, errorCode
    end

    return math.max(1, math.floor(tonumber(data.level) or 1)), data, nil
end)
exports('getLevel', function(playerSource)
    local data, errorCode = JRSXP.GetSync(playerSource)
    if not data then
        return 1, nil, errorCode
    end

    return math.max(1, math.floor(tonumber(data.level) or 1)), data, nil
end)

exports('SetLevel', function(playerSource, level, reason, callback)
    return JRSXP.SetLevel(playerSource, level, reason, callback)
end)
exports('setLevel', function(playerSource, level, reason, callback)
    return JRSXP.SetLevel(playerSource, level, reason, callback)
end)

exports('AddLevel', function(playerSource, levelDelta, reason, callback)
    return JRSXP.AddLevel(playerSource, levelDelta, reason, callback)
end)
exports('addLevel', function(playerSource, levelDelta, reason, callback)
    return JRSXP.AddLevel(playerSource, levelDelta, reason, callback)
end)

exports('RemoveLevel', function(playerSource, levelDelta, reason, callback)
    return JRSXP.RemoveLevel(playerSource, levelDelta, reason, callback)
end)
exports('removeLevel', function(playerSource, levelDelta, reason, callback)
    return JRSXP.RemoveLevel(playerSource, levelDelta, reason, callback)
end)

exports('GetLevelData', function(totalXp)
    return Config.GetLevelData(totalXp)
end)
exports('getLevelData', function(totalXp)
    return Config.GetLevelData(totalXp)
end)

exports('GetTotalXpForLevel', function(level)
    return Config.GetTotalXpForLevel(level)
end)
exports('getTotalXpForLevel', function(level)
    return Config.GetTotalXpForLevel(level)
end)
