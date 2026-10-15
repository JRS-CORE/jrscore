local Core = exports.jrs_core:GetCore()
local CooldownData = {}
local DevModeActive = Config.devMode

local function DebugPrint(message)
    if DevModeActive then
        print('^1[DEV MODE] ^4' .. message)
    end
end


local function LogToDiscord() end -- no Discord log in the light edition

local function SetPlayerCooldown(type, charid)
    CooldownData[type .. tostring(charid)] = os.time()
end

Core.Callback.Register('jrs_stables:BuyHorse', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local charid = character.charIdentifier

    local maxHorses = data.isTrainer and tonumber(Config.maxTrainerHorses) or tonumber(Config.maxPlayerHorses)

    local horseCount = MySQL.query.await('SELECT COUNT(*) as count FROM `player_horses` WHERE `charid` = ? AND `dead` = ?', { charid, 0 })[1].count
    if horseCount >= maxHorses then
        Core.NotifyRightTip(src, _Up(src, 'horseLimit') .. maxHorses .. _Up(src, 'horses'), 4000)
        return cb(false)
    end

    local model = data.ModelH
    local colorCfg = nil

    for _, horseCfg in pairs(Horses) do
        if horseCfg.colors[model] then
            colorCfg = horseCfg.colors[model]
            break
        end
    end

    if not colorCfg then
        print('Horse model not found in the configuration')
        return cb(false)
    end

    if data.IsCash then
        if character.money >= colorCfg.cashPrice then
            cb(true)
        else
            Core.NotifyRightTip(src, _Up(src, 'shortCash'), 4000)
            cb(false)
        end
    else
        if character.gold >= colorCfg.goldPrice then
            cb(true)
        else
            Core.NotifyRightTip(src, _Up(src, 'shortGold'), 4000)
            cb(false)
        end
    end
end)

Core.Callback.Register('jrs_stables:RegisterHorse', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local charid = character.charIdentifier

    local maxHorses = data.isTrainer and tonumber(Config.maxTrainerHorses) or tonumber(Config.maxPlayerHorses)

    local horseCount = MySQL.query.await('SELECT COUNT(*) as count FROM `player_horses` WHERE `charid` = ? AND `dead` = ?', { charid, 0 })[1].count
    if horseCount >= maxHorses then
        Core.NotifyRightTip(src, _Up(src, 'horseLimit') .. maxHorses .. _Up(src, 'horses'), 4000)
        return cb(false)
    end

    if data.IsCash and data.origin == 'tameHorse' then
        if character.money >= Config.regCost then
            return cb(true)
        else
            Core.NotifyRightTip(src, _Up(src, 'shortCash'), 4000)
            return cb(false)
        end
    end

    cb(false)
end)

local TackLocks = {}
Core.Callback.Register('jrs_stables:BuyTack', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user or type(data) ~= 'table' then return cb(false) end
    local character = user.getUsedCharacter
    local key = character.identifier .. ':' .. tostring(character.charIdentifier)
    if TackLocks[key] then return cb(false) end
    TackLocks[key] = true
    local charged, currencyType = 0, tonumber(data.currencyType)
    local ok, saved = pcall(function()
        local id = tonumber(data.horseId)
        local site = type(data.site)=='string' and Stables[data.site]
        local ped = GetPlayerPed(src)
        if not id or id%1~=0 or id<=0 or not site or not ped or ped==0 or not DoesEntityExist(ped) then return false end
        if #(GetEntityCoords(ped)-site.npc.coords)>8 then return false end
        if currencyType~=0 and currencyType~=1 then return false end
        if Config.currencyType~=2 and currencyType~=Config.currencyType then return false end
        local row = MySQL.single.await('SELECT * FROM player_horses WHERE id = ? AND identifier = ? AND charid = ? LIMIT 1',
            {id,character.identifier,character.charIdentifier})
        if not row or tonumber(row.dead)==1 or tonumber(row.writhe)==1 or type(data.components)~='table' then return false end
        local owned = {}
        for _, hash in ipairs(StableTack.List(row.components)) do owned[StableTack.Hash(hash)]=true end
        local count = 0
        for _, value in pairs(data.components) do
            count=count+1
            local hash=StableTack.Hash(value)
            if count>64 or not hash or not StableTack.items[hash] and not owned[hash] then return false end
        end
        local components = StableTack.List(data.components)
        local price = 0
        for _, hash in ipairs(components) do
            local value=StableTack.Hash(hash)
            if not owned[value] then
                local item=StableTack.items[value].item
                price=price+(tonumber(item[currencyType==0 and 'cashPrice' or 'goldPrice']) or 0)
            end
        end
        local balance=currencyType==0 and character.money or character.gold
        if price>0 and balance<price then
            Core.NotifyRightTip(src,_Up(src,currencyType==0 and 'shortCash' or 'shortGold'),4000)
            return false
        end
        local encoded=json.encode(components)
        if encoded==row.components then return true end
        if price>0 then
            if character.removeCurrency(currencyType,price)==false then return false end
            charged=price
        end
        -- A concurrent sale/transfer/edit cannot charge for a horse that no longer matches.
        local changed=MySQL.update.await('UPDATE player_horses SET components = ? WHERE id = ? AND identifier = ? AND charid = ? AND components = ?',
            {encoded,id,character.identifier,character.charIdentifier,row.components})
        if changed~=1 then return false end
        charged=0
        Core.NotifyRightTip(src,_Up(src,price>0 and 'purchaseSuccessful' or 'tackSaved'),4000)
        return true
    end)
    if charged>0 then character.addCurrency(currencyType,charged) end
    TackLocks[key]=nil
    if not ok or not saved then Core.NotifyRightTip(src,_Up(src,'tackSaveFailed'),4000) end
    cb(ok and saved==true)
end)

Core.Callback.Register('jrs_stables:SaveNewHorse', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier
    local name = data.name
    local model = data.ModelH
    local gender = data.gender
    local captured = data.captured
    local isCash = data.IsCash
    local currencyType = isCash and 0 or 1
    local priceKey = isCash and 'cashPrice' or 'goldPrice'
    local currency = isCash and character.money or character.gold
    local notification = isCash and _Up(src, 'shortCash') or _Up(src, 'shortGold')

    for _, horseCfg in pairs(Horses) do
        local colorCfg = horseCfg.colors[model]
        if colorCfg then
            if currency >= colorCfg[priceKey] then
                character.removeCurrency(currencyType, colorCfg[priceKey])

                MySQL.query.await('INSERT INTO `player_horses` (identifier, charid, name, model, gender, captured) VALUES (?, ?, ?, ?, ?, ?)',
                { identifier, charid, name, model, gender, captured })

                LogToDiscord(charid, _U('discordHorsePurchased'))
                return cb(true)
            else
                Core.NotifyRightTip(src, notification, 4000)
                return cb(false)
            end
        end
    end

    cb(false)
end)

Core.Callback.Register('jrs_stables:SaveTamedHorse', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier
    local regCost = Config.regCost
    local name = data.name
    local model = data.ModelH
    local gender = data.gender
    local captured = data.captured

    if data.IsCash and data.origin == 'tameHorse' then
        if character.money < regCost then
            Core.NotifyRightTip(src, _Up(src, 'shortCash'), 4000)
            return cb(false)
        end
        character.removeCurrency(0, regCost)
    end

    MySQL.query.await('INSERT INTO `player_horses` (identifier, charid, name, model, gender, captured) VALUES (?, ?, ?, ?, ?, ?)',
    { identifier, charid, name, model, gender, captured })

    LogToDiscord(charid, _U('discordTamedPurchased'))
    cb(true)
end)

Core.Callback.Register('jrs_stables:UpdateHorseName', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier
    local newName = data.name
    local horseId = data.horseId

    MySQL.query.await('UPDATE `player_horses` SET `name` = ? WHERE `id` = ? AND `identifier` = ? AND `charid` = ?',
    { newName, horseId, identifier, charid })

    cb(true)
end)

RegisterNetEvent('jrs_stables:UpdateHorseXp', function(Xp, horseId)
    if Config.HorseTraining.enabled then return end -- Ability XP is awarded by the server training course.
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier

    Xp = math.floor(tonumber(Xp) or -1)
    if Xp < 0 or Xp > 100000 then return end
    MySQL.query.await('UPDATE `player_horses` SET `xp` = ? WHERE `id` = ? AND `identifier` = ? AND `charid` = ?',
    { Xp, horseId, identifier, charid })

    LogToDiscord(charid, _U('discordHorseXPGain'))
end)

RegisterNetEvent('jrs_stables:SaveHorseStatsToDb', function(health, stamina, id)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier
    local horseHealth = math.max(0, math.min(100, tonumber(health) or 100))
    local horseStamina = math.max(0, math.min(100, tonumber(stamina) or 100))
    local horseId = tonumber(id)

    print("Saving horse stats to DB:", horseId, horseHealth, horseStamina)
    MySQL.query.await('UPDATE `player_horses` SET `health` = ?, `stamina` = ? WHERE id = ? AND `identifier` = ? AND `charid` = ?',
    { horseHealth, horseStamina, horseId, identifier, charid })
end)

RegisterNetEvent('jrs_stables:SelectHorse', function(data)
    if Config.HorseTraining.enabled then return end -- Use the validated horse:select callback.
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier
    local selectedHorseId = data.horseId

    -- Deselect all horses for the character
    MySQL.query.await('UPDATE `player_horses` SET `selected` = ? WHERE `charid` = ? AND `identifier` = ? AND `dead` = ?',
    { 0, charid, identifier, 0 })

    -- Select the specified horse
    MySQL.query.await('UPDATE `player_horses` SET `selected` = ? WHERE `id` = ? AND `charid` = ? AND `identifier` = ?',
    { 1, selectedHorseId, charid, identifier })
end)

RegisterNetEvent('jrs_stables:SetHorseWrithe', function(horseId)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier

    MySQL.query.await('UPDATE `player_horses` SET `writhe` = ? WHERE `id` = ? AND `identifier` = ? AND `charid` = ?',
    { 1, horseId, identifier, charid })
end)

-- Update Horse Selected and Dead Status After Death Event
RegisterNetEvent('jrs_stables:UpdateHorseStatus', function(horseId, action)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier

    local current = MySQL.single.await('SELECT selected, dead, writhe FROM player_horses WHERE id = ? AND identifier = ? AND charid = ?', {horseId,identifier,charid})
    if not current then return end
    if action~=nil and action~='dead' and action~='deselect' then return end
    if Config.HorseTraining.enabled and action == nil then
        if tonumber(current.dead) == 1 then return end
        if tonumber(current.writhe) == 1 and not HorseCare.CanClearWrithe(src, horseId) then return end
    end
    local selected = (action == 'dead' or action == 'deselect') and 0 or tonumber(current.selected) or 0
    local dead = action == 'dead' and 1 or tonumber(current.dead) or 0
    local writhe = tonumber(current.writhe) or 0
    if action=='dead' or action==nil then writhe=0 end

    MySQL.query.await('UPDATE `player_horses` SET `selected` = ?, `writhe` = ?, `dead` = ? WHERE `id` = ? AND `identifier` = ? AND `charid` = ?',
    { selected, writhe, dead, horseId, identifier, charid })
end)

Core.Callback.Register('jrs_stables:GetHorseData', function(source, cb)
    local src = source
    local user = Core.getUser(src)

    if not user then
        DebugPrint('User not found for source: ' .. tostring(src))
        return cb(false)
    end

    local character = user.getUsedCharacter

    local horses = MySQL.query.await('SELECT * FROM `player_horses` WHERE `charid` = ? AND `identifier` = ? AND `dead` = ?',
    { character.charIdentifier, character.identifier, 0 })

    if #horses == 0 then
        Core.NotifyRightTip(src, _Up(src, 'noHorses'), 4000)
        return cb(false)
    end

    local selectedHorse = nil
    for _, horse in ipairs(horses) do
        if horse.selected == 1 then
            selectedHorse = horse
            break
        end
    end

    if selectedHorse and (tonumber(selectedHorse.dead)==1 or tonumber(selectedHorse.writhe)==1) then
        Core.NotifyRightTip(src, HorseText('horseNeedRevive',src),4000)
        return cb(false)
    end
    if not selectedHorse then
        Core.NotifyRightTip(src, _Up(src, 'noSelectedHorse'), 4000)
        return cb(false)
    end

    cb({
        model = selectedHorse.model,
        name = selectedHorse.name,
        components = json.encode(StableTack.List(selectedHorse.components)),
        id = selectedHorse.id,
        gender = selectedHorse.gender,
        xp = selectedHorse.xp,
        captured = selectedHorse.captured,
        health = selectedHorse.health,
        stamina = selectedHorse.stamina,
        writhe = selectedHorse.writhe,
        training = HorseCare.Decorate(selectedHorse).training
    })
end)

Core.Callback.Register('jrs_stables:GetMyHorses', function(source, cb)
    local src = source
    local user = Core.getUser(src)

    -- Check if the user exists
    if not user then
        DebugPrint('User not found for source: ' .. tostring(src))
        return cb(false)
    end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier

    local horses = MySQL.query.await('SELECT * FROM `player_horses` WHERE `charid` = ? AND `identifier` = ? ORDER BY id', { charid, identifier }) or {}
    for _, horse in ipairs(horses) do HorseCare.Decorate(horse) end
    cb(horses)
end)

-- Tack changes use BuyTack so payment and persistence cannot get separated.
Core.Callback.Register('jrs_stables:UpdateComponents', function(source, cb)
    cb(false)
end)

Core.Callback.Register('jrs_stables:SellMyHorse', function(source, cb, data)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charid = character.charIdentifier
    local model = nil
    local horseId = tonumber(data.horseId)
    local captured = data.captured
    local matchFound = false

    -- Fetch the horse data
    local horses = MySQL.query.await('SELECT `id`, `model`, `captured` FROM `player_horses` WHERE `charid` = ? AND `identifier` = ? AND `dead` = ?',
    { charid, identifier, 0 })

    -- Find the horse and delete it
    for i = 1, #horses do
        if tonumber(horses[i].id) == horseId then
            matchFound = true
            model = horses[i].model

            captured = tonumber(horses[i].captured) == 1
            local removed = MySQL.update.await('DELETE FROM `player_horses` WHERE `id` = ? AND `charid` = ? AND `identifier` = ?',
            { horseId, charid, identifier })
            if not removed or removed < 1 then return cb(false) end
            HorseCare.Forget(horseId)

            LogToDiscord(charid, _U('discordHorseSold'))
            break
        end
    end

    if not matchFound then return cb(false) end

    -- Determine the sell price
    for _, horseCfg in pairs(Horses) do
        local colorCfg = horseCfg.colors[model]
        if colorCfg then
            local sellPrice = captured and (Config.tamedSellPrice * colorCfg.cashPrice) or (Config.sellPrice * colorCfg.cashPrice)
            character.addCurrency(0, sellPrice)
            Core.NotifyRightTip(src, _Up(src, 'soldHorse') .. sellPrice, 4000)
            return cb(true)
        end
    end

    cb(false)
end)

RegisterNetEvent('jrs_stables:SellTamedHorse', function(hash)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    if not Config.allowSale then return end

    local character = user.getUsedCharacter
    local charid = character.charIdentifier
    local sellPriceMultiplier = Config.tamedSellPrice

    -- the cooldown is enforced here, not only asked for by the client
    local lastSale = CooldownData['sellTame' .. tostring(charid)]
    if lastSale and os.difftime(os.time(), lastSale) < (Config.cooldown.sellTame or 0) * 60 then return end
    -- must really be sitting on a horse of that model
    local mount = GetMount(GetPlayerPed(src))
    if not mount or mount == 0 or GetEntityModel(mount) ~= hash then return end

    for _, horseCfg in pairs(Horses) do
        for color, colorCfg in pairs(horseCfg.colors) do
            local colorHash = joaat(color)
            if colorHash == hash then
                local sellPrice = (sellPriceMultiplier * colorCfg.cashPrice)
                character.addCurrency(0, math.ceil(sellPrice))
                Core.NotifyRightTip(src, _Up(src, 'soldHorse') .. sellPrice, 4000)
                SetPlayerCooldown('sellTame', charid)
                LogToDiscord(charid, _U('discordTamedSold'))
                return
            end
        end
    end
end)

RegisterNetEvent('jrs_stables:SaveHorseTrade', function(serverId, horseId)
    -- Current Owner
    local src = source
    local curUser = Core.getUser(src)
    if not curUser then return end

    local curOwner = curUser.getUsedCharacter
    local curOwnerId = curOwner.identifier
    local curOwnerCharId = curOwner.charIdentifier
    local curOwnerName = curOwner.firstname .. " " .. curOwner.lastname
    -- New Owner
    local newUser = Core.getUser(serverId)
    if not newUser then return end

    local newOwner = newUser.getUsedCharacter
    local newOwnerId = newOwner.identifier
    local newOwnerCharId = newOwner.charIdentifier
    local newOwnerName = newOwner.firstname .. " " .. newOwner.lastname

    -- Fetch the horse
    local horse = MySQL.query.await('SELECT * FROM `player_horses` WHERE `id` = ? AND `charid` = ? AND `identifier` = ? AND `dead` = ?',
    { horseId, curOwnerCharId, curOwnerId, 0 })

    if horse and #horse > 0 then
        -- Update the horse ownership
        MySQL.query.await('UPDATE `player_horses` SET `identifier` = ?, `charid` = ?, `selected` = ? WHERE `id` = ?',
        { newOwnerId, newOwnerCharId, 0, horseId })

        -- Notify both parties
        Core.NotifyRightTip(src, _Up(src, 'youGave') .. newOwnerName .. _Up(src, 'aHorse'), 4000)
        Core.NotifyRightTip(serverId, curOwnerName .._Up(serverId, 'gaveHorse'), 4000)

        LogToDiscord(curOwnerName, _U('discordTraded') .. newOwnerName)
    end
end)

RegisterNetEvent('jrs_stables:RegisterInventory', function(id, model)
    local src = source
    local idStr = 'horse_' .. tostring(id)
    local isRegistered = exports.jrs_inventory:isCustomInventoryRegistered(idStr)

    for _, horseCfg in pairs(Horses) do
        if horseCfg.colors[model] then
            local colorCfg = horseCfg.colors[model]
            local data = {
                id = idStr,
                name = _Up(src, 'horseInv'),
                limit = tonumber(colorCfg.invLimit),
                acceptWeapons = Config.allowWeapons,
                shared = Config.shareInventory,
                ignoreItemStackLimit = Config.ignoreItemStackLimit or true,
                whitelistItems =  Config.useWhiteList or false,
                UsePermissions = Config.usePermissions or false,
                UseBlackList = Config.useBlackList or false,
                whitelistWeapons = Config.whitelistWeapons or false
            }

            if isRegistered then
                exports.jrs_inventory:updateCustomInventoryData(idStr, data)
            else
                exports.jrs_inventory:registerInventory(data)
            end

            if data.UsePermissions then
                for _, permission in ipairs(Config.permissions.allowedJobsTakeFrom) do
                    exports.jrs_inventory:AddPermissionTakeFromCustom(idStr, permission.name, permission.grade)
                end
                for _, permission in ipairs(Config.permissions.allowedJobsMoveTo) do
                    exports.jrs_inventory:AddPermissionMoveToCustom(idStr, permission.name, permission.grade)
                end
            end

            if data.whitelistItems then
                for _, item in ipairs(Config.itemsLimitWhiteList) do
                    exports.jrs_inventory:setCustomInventoryItemLimit(idStr, item.name, item.limit)
                end
            end

            if data.whitelistWeapons then
                for _, weapon in ipairs(Config.weaponsLimitWhiteList) do
                    exports.jrs_inventory:setCustomInventoryWeaponLimit(idStr, weapon.name, weapon.limit)
                end
            end

            if data.UseBlackList then
                for _, item in ipairs(Config.itemsBlackList) do
                    exports.jrs_inventory:BlackListCustomAny(idStr, item)
                end
            end
            break
        end
    end
end)

RegisterNetEvent('jrs_stables:OpenInventory', function(id)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    id = tonumber(id)
    if not id then return end
    if not Config.shareInventory then
        local character = user.getUsedCharacter
        local owned = MySQL.scalar.await('SELECT 1 FROM `player_horses` WHERE `id` = ? AND `charid` = ? AND `identifier` = ? LIMIT 1',
            { id, character.charIdentifier, character.identifier })
        if not owned then return end
    end

    local idStr = 'horse_' .. tostring(id)
    exports.jrs_inventory:openInventory(src, idStr)
end)

-- Iterate over each item in the Config.horseFood array to register them as usable items
for _, item in ipairs(Config.horseFood) do
    exports.jrs_inventory:registerUsableItem(item, function(data)
        local src = data.source
        exports.jrs_inventory:closeInventory(src)

        TriggerClientEvent('jrs_stables:FeedHorse', src, item)
    end)
end

if Config.flamingHooves.active then
    exports.jrs_inventory:registerUsableItem(Config.flamingHooves.item, function(data)
        local src = data.source
        local user = Core.getUser(src)
        if not user then return end

        local item = exports.jrs_inventory:getItem(src, Config.flamingHooves.item)
        exports.jrs_inventory:closeInventory(src)

        if Config.flamingHooves.durability then
            local maxDurability = Config.flamingHooves.maxDurability or 100
            local useDurability = Config.flamingHooves.durabilityPerUse or 1
            local itemMetadata = item.metadata
            local currentDurability = itemMetadata.durability

            -- Initialize durability if it doesn't exist
            if not currentDurability then
                currentDurability = maxDurability
                local newData = {
                    description = _Up(src, 'flameHooveDesc') .. '</br>' .. _Up(src, 'durability') .. currentDurability .. '%',
                    durability = currentDurability,
                    id = item.id
                }
                exports.jrs_inventory:setItemMetadata(src, item.id, newData, 1)
            end

            -- Check if durability is below the usage threshold
            if currentDurability < useDurability then
                exports.jrs_inventory:subItemID(src, item.id)
                Core.NotifyRightTip(src, _Up(src, 'itemBroke'), 4000)
                return
            end
        end

        TriggerClientEvent('jrs_stables:FlamingHooves', src)
    end)

    RegisterNetEvent('jrs_stables:FlamingHoovesDurability', function()
        local src = source
        local user = Core.getUser(src)
        if not user then return end

        local item = exports.jrs_inventory:getItem(src, Config.flamingHooves.item)
        local useDurability = Config.flamingHooves.durabilityPerUse or 1
        local itemMetadata = item.metadata
        local newDurability = itemMetadata.durability - useDurability

        -- Check if durability is below the usage threshold or update the durability
        if newDurability < useDurability then
            exports.jrs_inventory:subItemID(src, item.id)
            Core.NotifyRightTip(src, _Up(src, 'itemBroke'), 4000)
        else
            local newData = {
                description = _Up(src, 'flameHooveDesc') .. '</br>' .. _Up(src, 'durability') .. newDurability .. '%',
                durability = newDurability,
                id = item.id
            }
            exports.jrs_inventory:setItemMetadata(src, item.id, newData, 1)
        end
    end)
end

RegisterNetEvent('jrs_stables:RemoveItem', function(item)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    exports.jrs_inventory:subItem(src, item, 1)
end)

exports.jrs_inventory:registerUsableItem(Config.horsebrush.item, function(data)
    local src = data.source
    local user = Core.getUser(src)
    if not user then return end

    local item = exports.jrs_inventory:getItem(src, Config.horsebrush.item)
    exports.jrs_inventory:closeInventory(src)

    if Config.horsebrush.durability then
        local maxDurability = Config.horsebrush.maxDurability or 100
        local useDurability = Config.horsebrush.durabilityPerUse or 1
        local itemMetadata = item.metadata
        local currentDurability = itemMetadata.durability

        -- Initialize durability if it doesn't exist
        if not currentDurability then
            currentDurability = maxDurability
            local newData = {
                description = _Up(src, 'horsebrushDesc') .. '</br>' .. _Up(src, 'durability') .. currentDurability .. '%',
                durability = currentDurability,
                id = item.id
            }
            exports.jrs_inventory:setItemMetadata(src, item.id, newData, 1)
        end

        -- Check if durability is below the usage threshold
        if currentDurability < useDurability then
            exports.jrs_inventory:subItemID(src, item.id)
            Core.NotifyRightTip(src, _Up(src, 'itemBroke'), 4000)
            return
        end
    end

    TriggerClientEvent('jrs_stables:BrushHorse', src)
end)

RegisterNetEvent('jrs_stables:HorseBrushDurability', function()
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local item = exports.jrs_inventory:getItem(src, Config.horsebrush.item)
    local useDurability = Config.horsebrush.durabilityPerUse or 1
    local itemMetadata = item.metadata
    local newDurability = itemMetadata.durability - useDurability

    -- Check if durability is below the usage threshold or update the durability
    if newDurability < useDurability then
        exports.jrs_inventory:subItemID(src, item.id)
        Core.NotifyRightTip(src, _Up(src, 'itemBroke'), 4000)
    else
        local newData = {
            description = _Up(src, 'horsebrushDesc') .. '</br>' .. _Up(src, 'durability') .. newDurability .. '%',
            durability = newDurability,
            id = item.id
        }
        exports.jrs_inventory:setItemMetadata(src, item.id, newData, 1)
    end
end)

exports.jrs_inventory:registerUsableItem(Config.lantern.item, function(data)
    local src = data.source
    local user = Core.getUser(src)
    if not user then return end

    local item = exports.jrs_inventory:getItem(src, Config.lantern.item)
    exports.jrs_inventory:closeInventory(src)

    if Config.lantern.durability then
        local maxDurability = Config.lantern.maxDurability or 100
        local useDurability = Config.lantern.durabilityPerUse or 1
        local itemMetadata = item.metadata
        local currentDurability = itemMetadata.durability

        -- Initialize durability if it doesn't exist
        if not currentDurability then
            currentDurability = maxDurability
            local newData = {
                description = _Up(src, 'lanternDesc') .. '</br>' .. _Up(src, 'durability') .. currentDurability .. '%',
                durability = currentDurability,
                id = item.id
            }
            exports.jrs_inventory:setItemMetadata(src, item.id, newData, 1)
        end

        -- Check if durability is below the usage threshold
        if currentDurability < useDurability then
            exports.jrs_inventory:subItemID(src, item.id)
            Core.NotifyRightTip(src, _Up(src, 'itemBroke'), 4000)
            return
        end
    end

    TriggerClientEvent('jrs_stables:UseLantern', src)
end)

RegisterNetEvent('jrs_stables:LanternDurability', function()
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    local item = exports.jrs_inventory:getItem(src, Config.lantern.item)
    local useDurability = Config.lantern.durabilityPerUse or 1
    local itemMetadata = item.metadata
    local newDurability = itemMetadata.durability - useDurability

    -- Check if durability is below the usage threshold or update the durability
    if newDurability < useDurability then
        exports.jrs_inventory:subItemID(src, item.id)
        Core.NotifyRightTip(src, _Up(src, 'itemBroke'), 4000)
    else
        local newData = {
            description = _Up(src, 'lanternDesc') .. '</br>' .. _Up(src, 'durability') .. newDurability .. '%',
            durability = newDurability,
            id = item.id
        }
        exports.jrs_inventory:setItemMetadata(src, item.id, newData, 1)
    end
end)

Core.Callback.Register('jrs_stables:HorseReviveItem', function(source, cb)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local reviveItem = Config.reviver
    local hasItem = exports.jrs_inventory:getItem(src, reviveItem)

    if not hasItem then
        return cb(false)
    end

    if Config.HorseTraining.enabled and not HorseCare.AuthorizeItemRevive(src) then return cb(false) end
    if exports.jrs_inventory:subItem(src, reviveItem, 1) == false then return cb(false) end
    cb(true)
end)

Core.Callback.Register('jrs_stables:CheckPlayerCooldown', function(source, cb, type)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local cooldown = Config.cooldown[type]
    local typeId = type .. tostring(character.charIdentifier)
    local currentTime = os.time()
    local lastTime = CooldownData[typeId]

    if lastTime then
        if os.difftime(currentTime, lastTime) >= cooldown * 60 then
            cb(false) -- Not on Cooldown
        else
            cb(true) -- On Cooldown
        end
    else
        cb(false) -- Not on Cooldown
    end
end)

Core.Callback.Register('jrs_stables:CheckJob', function(source, cb, trainer, site)
    local src = source
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local character = user.getUsedCharacter
    local jobConfig = trainer and Config.trainerJob or Stables[site].shop.jobs

    local hasJob = false
    for _, job in pairs(jobConfig) do
        if (character.job == job.name) and (tonumber(character.jobGrade) >= tonumber(job.grade)) then
            hasJob = true
            break
        end
    end

    cb({hasJob, character.job})
end)

RegisterNetEvent('jrs_core:instanceplayers', function(setRoom)
    local src = source
    local user = Core.getUser(src)
    if not user then return end

    if setRoom == 0 then
        Wait(3000)
        TriggerClientEvent('jrs_stables:UpdateMyHorseEntity', src)
    end
end)

--- Check if properly downloaded
function file_exists(name)
    local f = LoadResourceFile(GetCurrentResourceName(), name)
    return f ~= nil
end


