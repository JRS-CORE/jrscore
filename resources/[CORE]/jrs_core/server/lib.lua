-- ---------------------------------------------------------------------------
-- jrs_lib -> jrs_core : server player-data API
-- ---------------------------------------------------------------------------
-- Ported from jrs_lib/server/server_Jrs.lua.
--
-- The standalone resource resolved both of its dependencies at file load:
--
--     local jrsCore = exports.jrs_core:getCoreApi()
--     Inventory     = exports.jrs_inventory:jrs_inventoryApi()
--
-- server.cfg started jrs_lib *before* jrs_core and jrs_inventory, so both of
-- those threw on load and the whole API was dead. Living inside jrs_core the
-- core half is local, and jrs_inventory is resolved lazily on first use so a
-- boot-order change can never kill the file again.
--
-- Public surface is unchanged: TriggerEvent('jrs_lib:getApi', cb) still hands
-- back the same table, now from jrs_core.
-- ---------------------------------------------------------------------------

local apiSrv = {}

RegisterServerEvent('jrs_lib:getApi')
AddEventHandler('jrs_lib:getApi', function(cb)
    cb(apiSrv)
end)

exports('getLibServerApi', function()
    return apiSrv
end)

local function libConfig()
    return (Config and Config.Lib) or {}
end

--- jrs_core's own unified server API. Resolved lazily: server/api.lua registers
--- getCoreApi and this file loads after it, but a lazy read costs nothing and
--- survives any future reordering.
local coreApi
local function Core()
    if not coreApi then
        coreApi = exports.jrs_core:getCoreApi()
    end
    return coreApi
end

--- jrs_inventory starts after jrs_core, so this must not run at load time.
local inventoryApi
local function Inv()
    if not inventoryApi and GetResourceState('jrs_inventory') == 'started' then
        inventoryApi = exports.jrs_inventory:jrs_inventoryApi()
    end
    return inventoryApi
end

function apiSrv.registerItem(itemId, callback)
    local Inventory = Inv()
    if not Inventory then return false end
    Inventory.RegisterUsableItem(itemId, callback)
    return true
end

function apiSrv.CharacterTable()
    return libConfig().CharacterTable or 'Characters'
end

function apiSrv.JobColumn()
    return libConfig().JobColumn or 'job'
end

function apiSrv.JobGradeColumn()
    return libConfig().JobGradeColumn or 'jobgrade'
end

function apiSrv.SteamColumn()
    return libConfig().SteamColumn or 'identifier'
end

function apiSrv.CharIdColumn()
    return libConfig().CharIdColumn or 'charidentifier'
end

function apiSrv.notify(source, title, message, image, time)
    TriggerClientEvent("jrsCore:notify", source, title, message, image, time)
end

function apiSrv.getFramework()
    return "jrs_core"
end

local function sendDiscordMessage(webhookLink, title, descriptionsString, color, steamHex, charIdentifier, firstName,
                                  lastName)
    local cleanSteamHex = string.sub(steamHex or '', 7)
    local footer = ""
    if type(descriptionsString) == 'table' then
        for _, line in ipairs(descriptionsString) do
            footer = footer .. line .. "\n"
        end
    else
        footer = tostring(descriptionsString or '')
    end

    local embed = { {
        ["color"] = color,
        ["title"] = title,
        ["description"] = footer,
        ["fields"] = { {
            ["name"] = _U('lib_info'),
            ["value"] = _U('lib_steam') .. " " .. cleanSteamHex .. "\n" .. _U('lib_char_id') .. " " .. tostring(charIdentifier),
            ["inline"] = true
        }, {
            ["name"] = _U('lib_name'),
            ["value"] = _U('lib_firstname') .. " " .. tostring(firstName) .. "\n" .. _U('lib_lastname') .. " " .. tostring(lastName),
            ["inline"] = true
        } }
    } }

    PerformHttpRequest(webhookLink, function() end, 'POST',
        json.encode({ username = "JRS", embeds = embed }), { ['Content-Type'] = 'application/json' })
end

apiSrv.sendDiscordMessage = sendDiscordMessage

function apiSrv.getInformation(source, cb)
    local _source = source
    local User = Core().getUser(_source)
    if not User then
        cb(nil)
        return
    end

    local Character = User.getUsedCharacter
    local player = {}

    player.getGroup = function()
        return User.group
    end
    player.getItemNames = function()
        local globalTable = {}
        exports.oxmysql:execute('SELECT * FROM jrs_items', {}, function(result)
            if result ~= nil then globalTable = result end
        end)
        Citizen.Wait(100)
        return globalTable
    end
    player.getFirstname = function() return Character.firstname end
    player.getLastname = function() return Character.lastname end
    player.getSteamIdentifier = function() return Character.identifier end
    player.getCharIdentifier = function() return Character.charIdentifier end
    player.getMoney = function() return Character.money end
    player.getGold = function() return Character.gold end
    player.getJob = function() return Character.job end
    player.getGrade = function() return Character.jobGrade end
    player.getCountItem = function(id)
        local Inventory = Inv()
        if not Inventory then return 0 end
        return Inventory.getItemCount(tonumber(_source), id)
    end
    player.removeMoney = function(amount)
        Character.removeCurrency(_source, 0, amount)
    end
    player.addMoney = function(amount)
        Character.addCurrency(_source, 0, amount)
    end
    player.setJob = function(job, grade, arg)
        Character.setJob(tonumber(_source), job, grade, arg)
    end
    player.setGrade = function(amount)
        Character.setJobGrade(amount)
    end
    player.removeGold = function(amount)
        Character.removeCurrency(_source, 1, amount)
    end
    player.addGold = function(amount)
        Character.addCurrency(_source, 1, amount)
    end
    player.removeItem = function(id, amount)
        local Inventory = Inv()
        if Inventory then Inventory.subItem(_source, id, amount) end
    end
    player.removeItemId = function(id, amount)
        local Inventory = Inv()
        if Inventory then Inventory.subItemByID(_source, id, amount) end
    end
    player.addItem = function(id, amount, metadata)
        local Inventory = Inv()
        if Inventory then Inventory.addItem(_source, id, amount, metadata) end
    end
    player.chanceSkin = function(skin)
        local clothes = type(skin) == 'table' and skin or json.decode(skin or '{}')
        if GetResourceState('jrs_clothing') == 'started' and type(clothes) == 'table' then
            local saved = exports.jrs_clothing:SetCharacterClothes(Character.charIdentifier, clothes, 0)
            if saved then TriggerClientEvent('jrs_clothes:reloadCurrentClothes', _source) end
            return saved
        end
        return false
    end
    player.createStorage = function(id, size)
        TriggerEvent("jrsCore:registerstorage", _source, id, size)
    end
    player.openStorage = function(id, label)
        TriggerEvent("jrsCore:openstorage", _source, id, label)
    end
    player.updateStorage = function(id, size)
        TriggerEvent("jrsCore:updatestorage", _source, id, size)
    end
    player.canCarryItem = function(id, count)
        local canCarry = false
        TriggerEvent("jrsCore:canCarryItem", tonumber(_source), id, tonumber(count), function(result)
            canCarry = result
        end)
        return canCarry
    end
    player.canCarryWeapon = function(_, count)
        -- jrs_lib leaked this result into a global. Kept local here.
        local canCarry = false
        TriggerEvent("jrsCore:canCarryWeapons", tonumber(_source), tonumber(count), function(result)
            canCarry = result
        end)
        return canCarry
    end
    player.createWeapon = function(weapon, ammo)
        local Inventory = Inv()
        if Inventory then Inventory.createWeapon(tonumber(_source), weapon, ammo) end
    end
    player.giveWeapon = function(id, playerId)
        local Inventory = Inv()
        if Inventory then Inventory.giveWeapon(tonumber(_source), tonumber(id), playerId) end
    end
    player.closeInv = function()
        TriggerClientEvent("jrs_inventory:CloseInv", tonumber(_source))
    end
    player.discord = function(webhookLink, imageUrl, description, color, steamHex, charIdentifier, firstName, lastName)
        sendDiscordMessage(webhookLink, imageUrl, description, color, steamHex, charIdentifier, firstName, lastName)
    end
    player.getMetadata = function(id)
        local Inventory = Inv()
        if not Inventory then return nil, nil end
        local itemId = Inventory.getLastUsedID(_source)
        local typeMeta = Inventory.getMetaTypeById(_source, itemId, id)
        return typeMeta, itemId
    end
    player.getInventory = function()
        local Inventory = Inv()
        if not Inventory then return {} end
        return Inventory.getUserInventory(tonumber(_source))
    end

    cb(player)
end
