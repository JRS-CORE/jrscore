local Core = exports.jrs_core:GetCore()

CreateThread(function()
    if Core.RegisterJobs then
        local jobsData <const> = {}

        local function addJobs(jobList)
            if type(jobList) == "string" then
                if jobList ~= "" then
                    jobsData[jobList] = {}
                end
                return
            end

            if type(jobList) ~= "table" then
                return
            end

            for _, value in pairs(jobList) do
                local jobName <const> = value
                if type(jobName) == "string" and jobName ~= "" then
                    jobsData[jobName] = {}
                end
            end
        end

        addJobs(Config.CampfireJobLock)

        for _, location in ipairs(Config.Locations) do
            addJobs(location.Job)
        end

        for _, category in ipairs(Config.Categories) do
            addJobs(category.Job)
        end

        for _, crafting in ipairs(Config.Crafting) do
            addJobs(crafting.Job)
        end

        if next(jobsData) then
            Core.RegisterJobs(jobsData, GetCurrentResourceName())
        end
    else
        -- wait for some time to print this
        -- print("^1jrs_crafting: server: RegisterJobs not found update jrs core to the latest version^7")
    end
end)

CreateThread(function()
    local item = Config.CampFireItem
    exports.jrs_inventory:registerUsableItem(item, function(data)
        exports.jrs_inventory:subItemById(data.source, data.item.id)
        TriggerClientEvent("jrs:campfire", data.source)
    end)
end)

Core.Callback.Register("jrs_crafting:GetJob", function(source, cb)
    local Character = Core.getUser(source).getUsedCharacter
    local job = Character.job
    cb(job)
end)

RegisterNetEvent('jrs:openInv', function()
    local _source = source
    exports.jrs_inventory:openInventory(_source)
end)

local crafting_busy = {}
AddEventHandler("playerDropped", function() crafting_busy[source] = nil end)

local function failed(src, key)
    Core.NotifyObjective(src, _U(key), 5000)
    TriggerClientEvent('jrs_crafting:failed', src)
end

local function stationById(id)
    for _, loc in ipairs(Config.Locations) do if loc.id == id then return loc end end
end

RegisterNetEvent('jrs:startcrafting', function(craftable, countz, locationId)
    local _source = source
    -- whole number of crafts only (negative / 0 / fractions used to pass the material check)
    countz = math.floor(tonumber(countz) or 0)
    if countz < 1 or countz > 50 or type(craftable) ~= "table" then return end
    if crafting_busy[_source] and os.clock() - crafting_busy[_source] < 1.5 then return end
    crafting_busy[_source] = os.clock()
    local user = Core.getUser(_source)
    if not user then return end
    local Character = user.getUsedCharacter

    local Webhook = '' -- Set your webhook URL here
    local function getServerCraftable()
        local crafting = nil
        for _, v in ipairs(Config.Crafting) do
            if v.Text == craftable.Text then
                crafting = v
                break
            end
        end

        return crafting
    end

    local crafting = getServerCraftable()

    if not crafting then
        return TriggerClientEvent('jrs_crafting:failed', _source)
    end

    -- a station recipe needs the player at that station; campfires / props are
    -- client-side objects, so only the recipe's location list is checked there
    local station = type(locationId) == 'string' and stationById(locationId) or nil
    if station and #(GetEntityCoords(GetPlayerPed(_source)) - vector3(station.x, station.y, station.z)) > (Config.Distances.locations + 3.0) then
        return TriggerClientEvent('jrs_crafting:failed', _source)
    end
    -- the recipe category must be one this kind of station can craft
    local kind = station and station.StationType
    if not station then
        for _, prop in ipairs(Config.CraftingProps or {}) do
            if type(locationId) == 'string' and prop.title:lower() == locationId then kind = prop.StationType end
        end
        if not kind then return TriggerClientEvent('jrs_crafting:failed', _source) end
    end
    local cats = kind and Config.StationTypes and Config.StationTypes[kind]
    if cats then
        local ok = false
        for _, c in ipairs(cats) do if c == crafting.Category then ok = true end end
        if not ok then return TriggerClientEvent('jrs_crafting:failed', _source) end
    end
    if crafting.StationType and kind and crafting.StationType ~= kind then
        return TriggerClientEvent('jrs_crafting:failed', _source)
    end

    if crafting.Location and crafting.Location ~= 0 then
        local ok = false
        for _, l in pairs(crafting.Location) do if l == locationId then ok = true end end
        if not ok then return TriggerClientEvent('jrs_crafting:failed', _source) end
    end

    local playerjob = Character.job
    local job = crafting.Job
    local craft = false

    if job == 0 then
        craft = true
    end

    if job ~= 0 then
        for _, v in pairs(job) do
            if v == playerjob then
                craft = true
            end
        end
    end

    if not craft then
        return failed(_source, 'NotJob')
    end

    if not crafting then
        return
    end

    local reward = crafting.Reward
    local itemsToRemove = {}
    local requiredItems = {}


    for _, item in ipairs(crafting.Items) do
        requiredItems[item.name] = {
            required = item.count * countz,
            found = 0,
            canUseDecay = item.canUseDecay,
            take = item.take
        }
    end

    local inventory = exports.jrs_inventory:getUserInventoryItems(_source)
    if not inventory then return end

    for _, value in pairs(inventory) do
        local reqItem = requiredItems[value.name]
        if reqItem then
            if reqItem.canUseDecay then
                if value.isDegradable then
                    if value.percentage >= reqItem.canUseDecay then
                        reqItem.found = reqItem.found + value.count
                        if reqItem.take == nil or reqItem.take == true then
                            local left = reqItem.required - (reqItem.taken or 0)
                            if left > 0 then
                                local n = math.min(value.count, left)
                                reqItem.taken = (reqItem.taken or 0) + n
                                table.insert(itemsToRemove, { data = value, count = n })
                            end
                        end
                    end
                else
                    reqItem.found = reqItem.found + value.count
                    if reqItem.take == nil or reqItem.take == true then
                        local left = reqItem.required - (reqItem.taken or 0)
                            if left > 0 then
                                local n = math.min(value.count, left)
                                reqItem.taken = (reqItem.taken or 0) + n
                                table.insert(itemsToRemove, { data = value, count = n })
                            end
                    end
                end
            else
                reqItem.found = reqItem.found + value.count
                if reqItem.take == nil or reqItem.take == true then
                    local left = reqItem.required - (reqItem.taken or 0)
                            if left > 0 then
                                local n = math.min(value.count, left)
                                reqItem.taken = (reqItem.taken or 0) + n
                                table.insert(itemsToRemove, { data = value, count = n })
                            end
                end
            end
        end
    end


    local craftcheck = true
    for itemName, data in pairs(requiredItems) do
        if data.found < data.required then
            craftcheck = false
            break
        end
    end

    if not craftcheck then
        return failed(_source, 'NotEnough')
    end

    -- Differentiate between items and weapons
    if crafting.Type == "weapon" then
        local ammo = { ["nothing"] = 0 }
        local components = {}

        for index, v in ipairs(reward) do
            local canCarry = exports.jrs_inventory:canCarryWeapons(_source, v.count * countz, nil, v.name)
            if not canCarry then
                return failed(_source, 'WeaponsFull')
            end
        end

        if #itemsToRemove > 0 then
            for _, value in ipairs(itemsToRemove) do
                exports.jrs_inventory:subItemById(_source, value.data.id, nil, nil, value.count)
            end
        end

        for _ = 1, countz do
            for _, v in ipairs(reward) do
                for _ = 1, v.count do
                    exports.jrs_inventory:createWeapon(_source, v.name, ammo, components)
                    Core.AddWebhook(GetPlayerName(_source), Webhook, _U('WebhookWeapon') .. ' ' .. v.name)
                end
            end
        end

        TriggerClientEvent("jrs:crafting", _source, crafting.Animation)
    elseif crafting.Type == "item" then
        local addcount = 0
        local cancarry = false

        if not crafting.UseCurrencyMode then
            for _, rwd in ipairs(reward) do
                local counta = rwd.count * countz
                addcount     = addcount + counta
                cancarry     = exports.jrs_inventory:canCarryItem(_source, rwd.name, counta)
            end
        end

        if crafting.UseCurrencyMode or cancarry then
            if #itemsToRemove > 0 then
                for _, value in ipairs(itemsToRemove) do
                    exports.jrs_inventory:subItemById(_source, value.data.id, nil, nil, value.count)
                end
            end

            for _, v in ipairs(crafting.Reward) do
                local countx = v.count * countz
                if crafting.UseCurrencyMode ~= nil and crafting.CurrencyType ~= nil and crafting.UseCurrencyMode then
                    Character.addCurrency(crafting.CurrencyType, countx)
                else
                    exports.jrs_inventory:addItem(_source, v.name, countx)
                    Core.AddWebhook(GetPlayerName(_source), Webhook, _U('WebhookItem') .. ' x' .. countx .. ' ' .. v.name)
                end
            end

            TriggerClientEvent("jrs:crafting", _source, crafting.Animation)
        else
            failed(_source, 'TooFull')
        end
    end
end)

-- item labels for the recipe menu (sent once per client, cached here)
local labelCache = {}
JRS.Callback('jrs_crafting:labels', function(_, arabic)
    local key = arabic and 'ar' or 'en'
    if labelCache[key] then return labelCache[key] end
    local out = {}
    for _, recipe in ipairs(Config.Crafting) do
        for _, list in ipairs({ recipe.Items or {}, recipe.Reward or {} }) do
            for _, it in ipairs(list) do
                if it.name and not out[it.name] then
                    local def = exports.jrs_inventory:getItemDB(it.name)
                    out[it.name] = def and ((arabic and def.label_ar) or def.label) or it.name
                end
            end
        end
    end
    labelCache[key] = out
    return out
end)
