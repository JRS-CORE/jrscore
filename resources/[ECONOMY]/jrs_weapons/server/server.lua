-- jrs_weapons | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local Core = exports.jrs_core:GetCore()
local inventory = exports.jrs_inventory

-- Everything (item, materials, price, location, job) is taken from the config on the server;
-- the client only says which recipe / which weapon it wants.

local busy = {}
local function guard(src, seconds)
    local now = os.clock()
    if busy[src] and now - busy[src] < (seconds or 1.0) then return false end
    busy[src] = now
    return true
end
AddEventHandler("playerDropped", function() busy[source] = nil end)

local function near(src, locations, radius)
    local coords = GetEntityCoords(GetPlayerPed(src))
    for _, loc in pairs(locations or {}) do
        local p = loc.Pos
        if p and #(coords - vector3(p.x, p.y, p.z)) <= (radius or 6.0) then return true end
    end
    return false
end

local function inList(list, value)
    for _, v in pairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- station access: Config.General.jobonly + minimum grade
local function stationAllowed(character, minGrade)
    if not Config.General.jobonly then return true end
    return inList(Config.General.job, character.job) and (tonumber(character.jobGrade) or 0) >= (minGrade or 0)
end

local function recipeAllowed(character, recipe)
    if not recipe or not recipe.letcraft then return false end
    if recipe.jobonly and not inList(recipe.jobs, character.job) then return false end
    return true
end

local function hasMaterials(src, materials)
    for _, v in pairs(materials or {}) do
        if (inventory:getItemCount(src, nil, v.name) or 0) < v.amount then return false end
    end
    return true
end

local function takeMaterials(src, materials)
    for _, v in pairs(materials or {}) do
        inventory:subItem(src, v.name, v.amount)
    end
end

local function payCraft(character, recipe)
    if not Config.General.craftingcost then return true end
    local cost = tonumber(recipe.craftcost) or 0
    if cost <= 0 then return true end
    if character.money < cost then return false end
    character.removeCurrency(0, cost)
    return true
end

-- customization prices (same table the client shows)
local COMPS = json.decode(LoadResourceFile(GetCurrentResourceName(), 'wepcomps.json') or "{}") or {}
local METAL = {
    ["Gold"] = "gold", ["Silver"] = "silver", ["Blued Steel"] = "bluesteel", ["Browned Steel"] = "brownsteel",
    ["Blackened Steel"] = "blacksteel", ["Copper"] = "copper", ["Nickel"] = "nickle", ["Brass"] = "brass", ["Iron"] = "iron",
}
local PARTS = { barrel = true, trigger = true, cylinder = true, frontsight = true, frame = true, scope = true }

local function compPrice(l)
    local P = Config.General.price
    if l.comp == "variant" then return P.variant end
    if l.comp == "gripbody" then return P.griptype end
    if l.comp == "grip" then return P.gripdecal end
    if l.comp == "decal" then
        if l.type == "cylinder" then return P.decalextra end
        if l.type == "frame" then return P.decalframe end
        if l.type == "barrel" then return P.decalbarrel end
    end
    if l.comp == "wrapcolor" then return P.wrapcolor end
    if l.comp == "comp" then
        if l.type == "scope" then return P.sight end
        if l.type == "rifling" then return P.rifling end
        if l.type == "other" then return P.barrel end
        if l.type == "wrap" then return P.wrap end
    end
    if PARTS[l.comp] or l.comp == "decalcolor" then
        local key = METAL[l.label]
        return key and P[key] or 0
    end
    return 0
end

local function findComp(weaponName, compName)
    for _, l in ipairs(COMPS[weaponName] or {}) do
        if l.confirmed == 1 and l.name == compName then return l end
    end
    return nil
end

-- buy the selected mods: weapon must be the player's, every mod must exist for that weapon
RegisterServerEvent("jrs_weapons:checkmoney", function(_, weaponid, added)
    local _source = source
    if not guard(_source, 2.0) then return end
    local user = Core.getUser(_source)
    if not user then return end
    local Character = user.getUsedCharacter

    local fail = function(msg)
        TriggerClientEvent("jrs_weapons:nomods", _source)
        if msg then Core.NotifyRightTip(_source, msg, 3000) end
    end

    if not stationAllowed(Character, Config.General.jobrankcustomization) or not near(_source, Config.General.customizationLocations, 8.0) then
        return fail()
    end
    weaponid = tonumber(weaponid)
    if not weaponid or type(added) ~= "table" or #added > 40 then return fail() end

    local row = MySQL.single.await("SELECT name FROM jrs_weaponloadout WHERE id = ? AND charidentifier = ? LIMIT 1",
        { weaponid, Character.charIdentifier })
    if not row then return fail() end

    local sum, clean = 0, {}
    for _, a in ipairs(added) do
        local l = type(a) == "table" and findComp(row.name, tonumber(a.name))
        if not l then return fail() end
        sum = sum + (tonumber(compPrice(l)) or 0)
        clean[#clean + 1] = { label = l.label, model = l.model, comp = l.comp, type = l.type, name = l.name }
    end

    local gold = Config.General.customizationcurrency == 1
    local balance = gold and Character.gold or Character.money
    if balance < sum then return fail(Config.Language.cantafford) end

    if sum > 0 then Character.removeCurrency(gold and 1 or 0, sum) end
    MySQL.update("UPDATE jrs_weaponloadout SET comps = ? WHERE id = ? AND charidentifier = ?",
        { json.encode(clean), weaponid, Character.charIdentifier })
    Core.NotifyRightTip(_source, Config.Language.craftingwepmods, 5000)
    TriggerClientEvent("jrs_weapons:applymods", _source)
end)

-- kept for old clients: mods are saved by checkmoney now
RegisterServerEvent("jrs_weapons:addcomp", function() end)

RegisterServerEvent("syn_weapons:weaponused", function(data)
    local _source = source
    if type(data) ~= "table" then return end
    local user = Core.getUser(_source)
    if not user then return end
    local id = tonumber(data.id)
    MySQL.query('SELECT comps FROM jrs_weaponloadout WHERE id = ? AND charidentifier = ?', { id, user.getUsedCharacter.charIdentifier }, function(result)
        if result[1] then
            local components = json.decode(result[1].comps)
            TriggerClientEvent("jrs_weapons:givecomp", _source, components, id, data.hash)
        end
    end)
end)

Core.Callback.Register("jrs_weapons:getjob", function(source, cb)
    local User = Core.getUser(source)
    if not User then return cb({}) end
    local Character = User.getUsedCharacter
    return cb({ Character.job, Character.jobGrade })
end)

CreateThread(function()
    for _, value in pairs(Config.ammo) do
        for _, m in pairs(value) do
            -- adds ammo to the gunbelt
            inventory:registerUsableItem(m.item, function(data)
                local _source = data.source
                local ammo = inventory:getUserAmmo(_source)
                local count = ammo[m.key] or 0
                if count >= m.maxammo or (m.qt + count) > m.maxammo then
                    return Core.NotifyObjective(_source, "cant use more ammo, max allowed reached", 5000)
                end

                local result = inventory:addBullets(_source, m.key, m.qt)
                if result then
                    inventory:subItemById(_source, data.item.id)
                end
            end, GetCurrentResourceName())
        end
    end
end)

function SendWebhookMessage(webhook, message)
    if webhook ~= nil and webhook ~= "" and webhook ~= 0 then
        PerformHttpRequest(webhook, function() end, 'POST', json.encode({ content = message }),
            { ['Content-Type'] = 'application/json' })
    end
end

local function crafterCheck(_source, recipe)
    local user = Core.getUser(_source)
    if not user then return nil end
    local Character = user.getUsedCharacter
    if not stationAllowed(Character, Config.General.jobrankcrafting) or not near(_source, Config.General.craftinglocation, 8.0)
        or not recipeAllowed(Character, recipe) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return nil
    end
    return Character
end

-- craft ammo: (category, name) from Config.ammo
RegisterServerEvent("jrs_weapons:itemscheck", function(category, name)
    local _source = source
    if not guard(_source, 2.0) then return end
    local recipe = type(Config.ammo[category]) == "table" and Config.ammo[category][name] or nil
    local Character = crafterCheck(_source, recipe)
    if not Character then return end

    if not inventory:canCarryItem(_source, recipe.item, 1) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.cantcarryitem, 3000)
    end
    if not hasMaterials(_source, recipe.materials) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.nomaterial, 3000)
    end
    if not payCraft(Character, recipe) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.nomoneycraft, 3000)
    end

    takeMaterials(_source, recipe.materials)
    inventory:addItem(_source, recipe.item, 1)
    TriggerClientEvent("jrs_weapons:itemcheckpassed", _source)
    Core.NotifyRightTip(_source, Config.Language.crafting, 3000)
    SendWebhookMessage("", Config.Language.jrs_weapons .. Character.firstname .. ' ' .. Character.lastname .. Config.Language.crafted .. recipe.item)
end)

-- craft a weapon: (category, name) from Config.weapons
RegisterServerEvent("jrs_weapons:itemscheck2", function(category, name)
    local _source = source
    if not guard(_source, 2.0) then return end
    local recipe = type(Config.weapons[category]) == "table" and Config.weapons[category][name] or nil
    local Character = crafterCheck(_source, recipe)
    if not Character then return end

    local item = recipe.hashname
    if not inventory:canCarryWeapons(_source, 1, nil, item:upper()) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.cantcarrywep, 3000)
    end
    if not hasMaterials(_source, recipe.materials) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.nomaterial, 3000)
    end
    if not payCraft(Character, recipe) then
        TriggerClientEvent("jrs_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.nomoneycraft, 5000)
    end

    takeMaterials(_source, recipe.materials)
    inventory:createWeapon(_source, item, { ["nothing"] = 0 }, { ["nothing"] = 0 })
    TriggerClientEvent("jrs_weapons:itemcheckpassed2", _source)
    Core.NotifyRightTip(_source, Config.Language.crafting, 5000)
    SendWebhookMessage("", Config.Language.jrs_weapons .. Character.firstname .. ' ' .. Character.lastname .. Config.Language.crafted .. name)
end)
