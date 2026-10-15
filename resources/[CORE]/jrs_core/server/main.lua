RegisterServerEvent('jrscore:getFrom', function()
    local playerSource = source
    local character = jrsCore.GetCharacter(tonumber(playerSource))
    if not character then
        if Config.HudDebug then
            print("^1[jrs_core:HUD] ERROR: Character is not ready for source " .. tostring(playerSource))
        end
        return
    end

    local requestedIdentifier = tostring(character.identifier)
    local requestedCharId = tostring(character.charIdentifier)

    if Config.HudDebug then
        print(("^2[jrs_core:HUD] Request from %s - Gold=%s Money=%s job=%s"):format(
            playerSource,
            tostring(character.gold),
            tostring(character.money),
            tostring(character.job)
        ))
    end

    JRSXP.Get(playerSource, function(levelData)
        if not levelData then return end
        if GetPlayerPing(playerSource) <= 0 then return end

        local activeCharacter = jrsCore.GetCharacter(tonumber(playerSource))
        if not activeCharacter
            or tostring(activeCharacter.identifier) ~= requestedIdentifier
            or tostring(activeCharacter.charIdentifier) ~= requestedCharId then
            return
        end

        if Config.HudDebug then
            print(("^2[jrs_core:HUD] Sending level=%s totalXP=%s progress=%s/%s"):format(
                levelData.level,
                levelData.totalXp,
                levelData.currentXp,
                levelData.requiredXp
            ))
        end

        TriggerClientEvent(
            'jrscore:sett',
            playerSource,
            activeCharacter.money,
            activeCharacter.gold,
            activeCharacter.dirtymoney or 0,
            activeCharacter.job,
            activeCharacter.jobgrade,
            levelData
        )
    end)
end)
