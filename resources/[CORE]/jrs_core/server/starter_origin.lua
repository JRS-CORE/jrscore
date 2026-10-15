-- ============================================================================
-- JRS CORE — STARTER ORIGIN & BACKGROUND SELECTION SERVER HANDLER
-- ============================================================================
-- Validates, applies, and persists character origin selections (Hunter, Farmer,
-- Miner, Outlaw, Trader, Laborer). Applies starting money, starter equipment,
-- and profession bonus XP.
-- ============================================================================

local StarterOriginServer = {}

RegisterNetEvent('jrs_core:server:requestStarterOriginMenu', function()
    local sourceId = source
    local user = jrsCore.getUser(sourceId)
    local character = user and user.getUsedCharacter
    if not character or not character.charIdentifier then return end

    local charId = tonumber(character.charIdentifier)
    MySQL.query("SELECT meta FROM jrs_characters WHERE charidentifier = ? LIMIT 1", { charId }, function(result)
        local metaStr = result and result[1] and result[1].meta or "{}"
        local meta = json.decode(metaStr) or {}

        if meta.origin_selected == true then
            TriggerClientEvent('jrs_core:client:starterOriginAlreadySet', sourceId)
            return
        end

        TriggerClientEvent('jrs_core:client:openStarterOriginMenu', sourceId, Config.Economy.StarterOrigins.Origins)
    end)
end)

local selectingOrigin = {}

RegisterNetEvent('jrs_core:server:selectStarterOrigin', function(originId)
    local sourceId = source
    local originIdStr = tostring(originId or ''):lower()
    local originConfig = Config.Economy.StarterOrigins and Config.Economy.StarterOrigins.Origins[originIdStr]
    if not originConfig then return end

    local user = jrsCore.getUser(sourceId)
    local character = user and user.getUsedCharacter
    if not character or not character.charIdentifier then return end

    local charId = tonumber(character.charIdentifier)
    if not charId or selectingOrigin[charId] then return end
    selectingOrigin[charId] = true

    MySQL.query("SELECT meta FROM jrs_characters WHERE charidentifier = ? LIMIT 1", { charId }, function(result)
        local metaStr = result and result[1] and result[1].meta or "{}"
        local meta = json.decode(metaStr) or {}

        if meta.origin_selected == true then
            selectingOrigin[charId] = nil
            TriggerClientEvent('jrs_core:client:starterOriginAlreadySet', sourceId)
            return
        end

        -- Mark Origin Selected
        meta.origin_selected = true
        meta.origin = originIdStr
        local updatedMetaStr = json.encode(meta)

        -- Synchronize memory representation so logout / dropped does not overwrite it
        character.meta = updatedMetaStr
        if user and user.getUsedCharacter then
            user.getUsedCharacter.meta = updatedMetaStr
        end

        -- Update character meta in database
        MySQL.update("UPDATE jrs_characters SET meta = ? WHERE charidentifier = ?", { updatedMetaStr, charId })

        -- 1. Apply Origin Cash Balance
        if originConfig.money and originConfig.money > 0 then
            jrsCore.setMoney(sourceId, originConfig.money)
        end

        -- 2. Grant Starter Equipment Items into Inventory
        if type(originConfig.items) == 'table' then
            for _, itemData in ipairs(originConfig.items) do
                if itemData.item and itemData.count then
                    exports.jrs_inventory:addItem(sourceId, itemData.item, itemData.count, {})
                end
            end
        end

        -- 3. Award Profession Bonus XP
        if type(originConfig.jobXP) == 'table' and originConfig.jobXP.job then
            exports.jrs_core:AddJobXP(sourceId, originConfig.jobXP.job, originConfig.jobXP.xp or 100, "starter_origin_bonus")
        elseif originConfig.coreXP and originConfig.coreXP > 0 then
            exports.jrs_core:AddXP(sourceId, originConfig.coreXP, "starter_origin_bonus")
        end

        -- Log Origin Selection
        if exports.jrs_core and type(exports.jrs_core.LogEconomyEvent) == 'function' then
            exports.jrs_core:LogEconomyEvent(charId, "STARTER_ORIGIN_SET", originConfig.money or 0, "0", { origin = originIdStr })
        end

        TriggerClientEvent('jrs_core:client:starterOriginCompleted', sourceId, originConfig)
        selectingOrigin[charId] = nil
    end)
end)

local startersInProgress = {}
local startersGranted = {}
local newlyCreatedCharacters = {}

-- Track characters newly created in this session
AddEventHandler('jrs_core:server:characterCreated', function(sourceId, charId, identifier)
    if charId then
        newlyCreatedCharacters[tonumber(charId)] = true
    end
end)

-- Explicitly mark existing character when selected from selector
AddEventHandler('jrs_core:server:characterSelected', function(sourceId, charId)
    if charId then
        local id = tonumber(charId)
        startersGranted[id] = true
        newlyCreatedCharacters[id] = nil
    end
end)

exports('MarkCharacterAsNew', function(charId)
    if charId then
        newlyCreatedCharacters[tonumber(charId)] = true
    end
end)

exports('MarkCharacterAsExisting', function(charId)
    if charId then
        local id = tonumber(charId)
        startersGranted[id] = true
        newlyCreatedCharacters[id] = nil
    end
end)

-- Auto-prompt origin selection & grant Red Dead Online starter weapons ONCE on newly created characters ONLY
AddEventHandler('jrs_core:server:characterReady', function(sourceId, character)
    sourceId = tonumber(sourceId)
    if not sourceId or type(character) ~= 'table' then return end

    local charId = tonumber(character.charIdentifier)
    if not charId then return end

    -- Synchronously prevent multiple event triggers from queuing concurrent grants
    if startersGranted[charId] or startersInProgress[charId] then
        return
    end

    -- If this character was not newly created in this session, it is an existing (old) character.
    -- Old characters must NEVER receive starter weapons, provisions, or the welcome notification.
    if not newlyCreatedCharacters[charId] then
        startersGranted[charId] = true
        return
    end

    startersInProgress[charId] = true
    newlyCreatedCharacters[charId] = nil

    SetTimeout(1500, function()
        -- Ensure player is still active and valid with the same character
        local user = jrsCore.getUser(sourceId)
        local curChar = user and user.getUsedCharacter
        if not curChar or tonumber(curChar.charIdentifier) ~= charId then
            startersInProgress[charId] = nil
            return
        end

        MySQL.query("SELECT meta FROM jrs_characters WHERE charidentifier = ? LIMIT 1", { charId }, function(result)
            local metaStr = result and result[1] and result[1].meta or "{}"
            local meta = json.decode(metaStr) or {}

            -- If starter has already been received, exit immediately
            if meta.starter_received or meta.rdo_starter_weapons_given or startersGranted[charId] then
                startersGranted[charId] = true
                startersInProgress[charId] = nil
                return
            end

            -- Immediately flag in memory and in DB before creating items
            startersGranted[charId] = true
            startersInProgress[charId] = nil
            meta.starter_received = true
            meta.rdo_starter_weapons_given = true
            meta.is_new_character = nil

            local updatedMetaStr = json.encode(meta)
            character.meta = updatedMetaStr
            curChar.meta = updatedMetaStr

            MySQL.update("UPDATE jrs_characters SET meta = ? WHERE charidentifier = ?", { updatedMetaStr, charId }, function()
                -- Check existing weapons in database to guarantee no duplicate weapon is created
                MySQL.query("SELECT name FROM jrs_weaponloadout WHERE charidentifier = ?", { charId }, function(weaponRows)
                    local ownedWeapons = {}
                    if type(weaponRows) == 'table' then
                        for _, row in ipairs(weaponRows) do
                            if row.name then
                                ownedWeapons[string.upper(row.name)] = true
                            end
                        end
                    end

                    if Config.StartWeapons and type(Config.StartWeapons) == 'table' then
                        for _, w in ipairs(Config.StartWeapons) do
                            local weaponUpper = string.upper(tostring(w.name or ''))
                            if not ownedWeapons[weaponUpper] then
                                ownedWeapons[weaponUpper] = true
                                pcall(function()
                                    exports.jrs_inventory:createWeapon(sourceId, w.name, w.ammo or 0)
                                end)
                            end
                        end
                    end

                    -- Welcome notification sent ONLY ONCE upon character creation
                    TriggerClientEvent('jrs_core:sendRightTipNotification', sourceId,
                        _Up(sourceId, 'welcome_starter_pack'), 8000)

                    if not meta.origin_selected and Config.Economy and Config.Economy.StarterOrigins then
                        TriggerClientEvent('jrs_core:client:openStarterOriginMenu', sourceId, Config.Economy.StarterOrigins.Origins)
                    end
                end)
            end)
        end)
    end)
end)
