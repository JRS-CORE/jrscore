-- ===========================================================================
-- Ground Drops
-- ===========================================================================

-- Pending secure weapon operations prevent duplicate clicks while the server
-- verifies ownership and updates weaponloadout.
local pendingWeaponPickups = {}
local pendingItemPickups = {}
local pendingWeaponDrops = {}
local pendingGroundDrop = false
local GROUND_INTERACTION_DISTANCE = tonumber(Config.GroundInteractionDistance) or 1.0

local function isTrue(value)
    return value == true or value == 1 or value == "1" or tostring(value):lower() == "true"
end

local function getDropCoords(drop)
    -- Use the authoritative server coordinates first. Ground props can be moved
    -- slightly by PlaceObjectOnGroundProperly, which previously made nearby
    -- drops disappear from the Ground list at the one-metre boundary.
    if drop.x ~= nil and drop.y ~= nil and drop.z ~= nil then
        return vector3(tonumber(drop.x) or 0.0, tonumber(drop.y) or 0.0, tonumber(drop.z) or 0.0)
    end
    if drop.entity and drop.entity ~= 0 and DoesEntityExist(drop.entity) then
        return GetEntityCoords(drop.entity)
    end
    return nil
end

function GetGroundDropDistance(drop)
    local dropCoords = getDropCoords(drop)
    if not dropCoords then return math.huge end
    return #(GetEntityCoords(PlayerPedId()) - dropCoords)
end

function GetNearbyGroundDrops()
    local nearbyDrops = {}
    local ordered = {}

    for _, drop in pairs(dropped_items_entity or {}) do
        table.insert(ordered, drop)
    end

    table.sort(ordered, function(a, b)
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)

    for _, drop in ipairs(ordered) do
        local distance = GetGroundDropDistance(drop)
        if distance <= GROUND_INTERACTION_DISTANCE then
            local weaponDrop = isTrue(drop.weapon)
            table.insert(nearbyDrops, {
                id = tonumber(drop.id),
                item = drop.item,
                count = tonumber(drop.count) or 1,
                weapon = weaponDrop,
                weapon_model = weaponDrop and tostring(drop.weapon_model or "") or "none",
                serial_number = drop.serial_number,
                itemId = drop.itemId,
                metaData = drop.metaData,
                slot = #nearbyDrops + 1
            })
        end
    end
    return nearbyDrops
end

function RefreshGroundUI()
    local nearbyDrops = GetNearbyGroundDrops()
    SendNUIMessage({
        type = "updateGround",
        ground = nearbyDrops
    })
end

-- Ground UI is intentionally event-driven. It is refreshed when the inventory
-- opens and when the server reports a ground-drop change. Do not poll here:
-- frequent polling makes NUI slots re-render while the player is dragging them.

function PickupGroundDrop(v, k)
    local dropId = tonumber(v.id)
    if not dropId then return end

    if v.weapon then
        if pendingWeaponPickups[dropId] then return end
        pendingWeaponPickups[dropId] = true
        TriggerServerEvent("jrs_inventory:pickupGroundWeapon", dropId, NewInventoryOperationId("pickup_ground_weapon"))
        return
    end

    if pendingItemPickups[dropId] then return end
    pendingItemPickups[dropId] = true
    TriggerServerEvent("jrs_inventory:pickupGroundItem", dropId, NewInventoryOperationId("pickup_ground_item"))
end

RegisterNetEvent('jrs_inventory:groundItemPickupResult')
AddEventHandler('jrs_inventory:groundItemPickupResult', function(success, dropId)
    dropId = tonumber(dropId)
    if dropId then pendingItemPickups[dropId] = nil end
    if not success then
        if guiEnabled then RefreshGroundUI() end
        return
    end

    playAnim(
        Config.Animations.itemPickupGround.dict,
        Config.Animations.itemPickupGround.name,
        Config.Animations.itemPickupGround.duration,
        1
    )
    if guiEnabled then
        Citizen.SetTimeout(80, RefreshGroundUI)
    end
end)

RegisterNetEvent('jrs_inventory:weaponPickupResult')
AddEventHandler('jrs_inventory:weaponPickupResult', function(success, dropId)
    dropId = tonumber(dropId)
    if dropId then pendingWeaponPickups[dropId] = nil end
    if not success then
        if guiEnabled then RefreshGroundUI() end
        return
    end

    playAnim(
        Config.Animations.itemPickupGround.dict,
        Config.Animations.itemPickupGround.name,
        Config.Animations.itemPickupGround.duration,
        1
    )
    if guiEnabled then
        Citizen.SetTimeout(80, RefreshGroundUI)
    end
end)

RegisterNetEvent('jrs_inventory:weaponDropResult')
AddEventHandler('jrs_inventory:weaponDropResult', function(success, weaponId)
    weaponId = tonumber(weaponId)
    if weaponId then pendingWeaponDrops[weaponId] = nil end
    if not success then
        if guiEnabled then RefreshGroundUI() end
        return
    end

    playAnim(
        Config.Animations.itemDropGround.dict,
        Config.Animations.itemDropGround.name,
        Config.Animations.itemDropGround.duration,
        1
    )
    if guiEnabled then
        Citizen.SetTimeout(80, RefreshGroundUI)
    end
end)

RegisterNetEvent('jrs_inventory:groundDropResult')
AddEventHandler('jrs_inventory:groundDropResult', function(success)
    pendingGroundDrop = false
    if not success then
        if guiEnabled then RefreshGroundUI() end
        return
    end

    playAnim(
        Config.Animations.itemDropGround.dict,
        Config.Animations.itemDropGround.name,
        Config.Animations.itemDropGround.duration,
        1
    )
    if guiEnabled then
        Citizen.SetTimeout(80, RefreshGroundUI)
    end
end)

-- ===========================================================================
-- Ground Events
-- ===========================================================================

local function hashModel(model)
    if type(model) == "number" then return model end
    if type(model) ~= "string" or model == "" then return nil end
    if joaat then return joaat(model) end
    return GetHashKey(model)
end

local function tryCreateGroundProp(models, x, y, z)
    for _, model in ipairs(models or {}) do
        local modelHash = hashModel(model)
        if modelHash and IsModelValid(modelHash) then
            RequestModel(modelHash)
            local timeout = GetGameTimer() + 2000
            while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
                Citizen.Wait(0)
            end

            if HasModelLoaded(modelHash) then
                local entity = CreateObject(modelHash, x, y, z, false, false, false)
                SetModelAsNoLongerNeeded(modelHash)
                if entity and entity ~= 0 and DoesEntityExist(entity) then
                    PlaceObjectOnGroundProperly(entity)
                    FreezeEntityPosition(entity, true)
                    Citizen.InvokeNative(0x7DFB49BCDB73089A, entity, true)
                    SetEntityCollision(entity, false, false)
                    return entity
                end
            end
        end
    end
    return 0
end

local function getGroundPropModels(drop)
    local itemName = tostring(drop.item or ""):lower()
    local weaponDrop = isTrue(drop.weapon)

    if weaponDrop then
        return { Config.Props.droppedWeapon, Config.Props.droppedItem }
    elseif itemName == "money" then
        return { Config.Props.droppedMoney, Config.Props.droppedItem }
    elseif itemName == "gold" then
        return { Config.Props.droppedGold, Config.Props.droppedMoney, Config.Props.droppedItem }
    elseif itemName == "dirtymoney" then
        return { Config.Props.droppedDirtyMoney, Config.Props.droppedMoney, Config.Props.droppedItem }
    end

    return { Config.Props.droppedItem }
end

local function spawnGroundPropForDrop(drop)
    if Config.GroundSpawnWorldProps ~= true or not drop then return 0 end
    if drop.entity and drop.entity ~= 0 and DoesEntityExist(drop.entity) then return drop.entity end
    if drop.x == nil or drop.y == nil or drop.z == nil then return 0 end

    local entity = tryCreateGroundProp(
        getGroundPropModels(drop),
        tonumber(drop.x) or 0.0,
        tonumber(drop.y) or 0.0,
        tonumber(drop.z) or 0.0
    )
    drop.entity = entity or 0
    return drop.entity
end

local function shouldStreamGroundProp(drop)
    if Config.GroundSpawnWorldProps ~= true or not drop then return false end
    local coords = getDropCoords(drop)
    if not coords then return false end
    local streamDistance = tonumber(Config.GroundPropStreamDistance) or 35.0
    return #(GetEntityCoords(PlayerPedId()) - coords) <= streamDistance
end

local function createClientGroundDrop(v)
    local itemName = tostring(v.item or ""):lower()
    local weaponDrop = isTrue(v.weapon)

    local drop = {
        id = v.id,
        metaData = v.metaData,
        itemId = v.itemid,
        entity = 0,
        x = v.x,
        y = v.y,
        z = v.z,
        item = itemName,
        count = v.count,
        weapon = weaponDrop,
        weapon_model = weaponDrop and tostring(v.weapon_model or "") or "none",
        serial_number = v.serial_number
    }

    table.insert(dropped_items_entity, drop)
    if shouldStreamGroundProp(drop) then
        spawnGroundPropForDrop(drop)
    end
end

-- Props are local visual shells around server-authoritative drop records.
-- Stream them only near the player so many drops do not create unnecessary entities.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(math.max(500, tonumber(Config.GroundPropStreamRefreshMs) or 1000))

        if Config.GroundSpawnWorldProps == true and inventoryCharacterReady then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local streamDistance = tonumber(Config.GroundPropStreamDistance) or 35.0
            local despawnDistance = math.max(streamDistance + 5.0, tonumber(Config.GroundPropDespawnDistance) or 45.0)

            for _, drop in pairs(dropped_items_entity or {}) do
                local coords = getDropCoords(drop)
                if coords then
                    local distance = #(playerCoords - coords)
                    local hasEntity = drop.entity and drop.entity ~= 0 and DoesEntityExist(drop.entity)

                    if distance <= streamDistance and not hasEntity then
                        spawnGroundPropForDrop(drop)
                    elseif distance >= despawnDistance and hasEntity then
                        DeleteEntity(drop.entity)
                        drop.entity = 0
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('jrs_inventory:drop_list')
AddEventHandler('jrs_inventory:drop_list', function(drop_list, updateReason)
    if Config.Debug then print("DROP LIST RECEIVED:", drop_list and #drop_list or "false") end

    -- Server compatibility still sends the authoritative full list, but do not
    -- destroy and recreate every world prop after one item changes. Reuse any
    -- unchanged drop entity and only create/delete the actual delta.
    local existingById = {}
    for _, drop in pairs(dropped_items_entity or {}) do
        local id = tonumber(drop.id)
        if id then existingById[id] = drop end
    end

    local nextDrops = {}
    dropped_items_entity = nextDrops
    dropped_items = {}

    if drop_list ~= false and type(drop_list) == "table" then
        for _, v in pairs(drop_list) do
            local id = tonumber(v.id)
            local itemName = tostring(v.item or ""):lower()
            local weaponDrop = isTrue(v.weapon)
            local weaponModel = weaponDrop and tostring(v.weapon_model or "") or "none"
            local existing = id and existingById[id] or nil
            local canReuse = false

            if existing then
                local sameVisual = tostring(existing.item or "") == itemName
                    and isTrue(existing.weapon) == weaponDrop
                    and tostring(existing.weapon_model or "none") == weaponModel
                local dx = math.abs((tonumber(existing.x) or 0.0) - (tonumber(v.x) or 0.0))
                local dy = math.abs((tonumber(existing.y) or 0.0) - (tonumber(v.y) or 0.0))
                local dz = math.abs((tonumber(existing.z) or 0.0) - (tonumber(v.z) or 0.0))
                canReuse = sameVisual and dx < 0.02 and dy < 0.02 and dz < 0.02
                    and existing.entity and existing.entity ~= 0 and DoesEntityExist(existing.entity)
            end

            if canReuse then
                existing.metaData = v.metaData
                existing.itemId = v.itemid
                existing.count = v.count
                existing.serial_number = v.serial_number
                existing.x, existing.y, existing.z = v.x, v.y, v.z
                nextDrops[#nextDrops + 1] = existing
            else
                if existing and existing.entity and existing.entity ~= 0 and DoesEntityExist(existing.entity) then
                    DeleteEntity(existing.entity)
                end
                createClientGroundDrop(v)
            end

            if id then existingById[id] = nil end
        end
    end

    -- Anything left in the old map no longer exists on the server.
    for _, oldDrop in pairs(existingById) do
        if oldDrop.entity and oldDrop.entity ~= 0 and DoesEntityExist(oldDrop.entity) then
            DeleteEntity(oldDrop.entity)
        end
    end

    if guiEnabled then
        RefreshGroundUI()
    end

    inventoryGroundReady = true
    if TryOpenInventoryWhenReady then
        TryOpenInventoryWhenReady()
    end
end)

-- ===========================================================================
-- Ground NUI Callbacks
-- ===========================================================================

RegisterNUICallback("pickup_ground", function(data, cb)
    local dropId = tonumber(data.id)
    local found = false

    for k, v in pairs(dropped_items_entity or {}) do
        if tonumber(v.id) == dropId then
            found = true
            if GetGroundDropDistance(v) <= GROUND_INTERACTION_DISTANCE then
                PickupGroundDrop(v, k)
                cb("ok")
            else
                RefreshGroundUI()
                cb("too_far")
            end
            return
        end
    end

    if not found then
        RefreshGroundUI()
    end
    cb("not_found")
end)

RegisterNUICallback('drop_item', function(data, cb)
    if pendingGroundDrop then
        cb("busy")
        return
    end

    local count = tonumber(data.count)
    if not count or count < 1 or count ~= math.floor(count) then
        exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('wrong_value'), 'bag', 2000)
        cb("invalid_count")
        return
    end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.65, 0.0)

    if data.is_weapon ~= "item" then
        if count ~= 1 then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('wrong_value'), 'bag', 2000)
            cb("invalid_count")
            return
        end

        local weaponId = tonumber(data.item)
        for _, weapon in pairs(weapon_table or {}) do
            if tonumber(weapon.id) == weaponId then
                if Config.IsPersonalItem(weapon.name) then
                    exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
                    cb("blocked")
                    return
                end
                if tonumber(weapon.used) == 1 then
                    exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('cant_drop_equiped_weapon'), 'bag', 2000)
                    cb("equipped")
                    return
                end
                if pendingWeaponDrops[weaponId] then
                    cb("busy")
                    return
                end

                pendingWeaponDrops[weaponId] = true
                TriggerServerEvent("jrs_inventory:dropGroundWeapon", weaponId, {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z
                }, NewInventoryOperationId("drop_ground_weapon"))
                cb("ok")
                return
            end
        end

        cb("not_found")
        return
    end

    local dropKind = tostring(data.item or "")
    local reference = 0

    if dropKind == "money" then
        if Config.AllowMoneyGroundDrop == false then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('money_ground_drop_disabled'), 'bag', 2500)
            cb("disabled")
            return
        end
        if tonumber(money_state) < count then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('not_enough_money'), 'bag', 2000)
            cb("not_enough")
            return
        end
    elseif dropKind == "gold" then
        if Config.AllowGoldGroundDrop == false then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('gold_ground_drop_disabled'), 'bag', 2500)
            cb("disabled")
            return
        end
        if tonumber(gold_state) < count then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('not_enough_gold'), 'bag', 2000)
            cb("not_enough")
            return
        end
    elseif dropKind == "dirtymoney" then
        if Config.AllowDirtyMoneyGroundDrop == false then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('dirtymoney_ground_drop_disabled'), 'bag', 2500)
            cb("disabled")
            return
        end
        if tonumber(dirtymoney_state) < count then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('not_enough_dirtymoney'), 'bag', 2000)
            cb("not_enough")
            return
        end
    else
        dropKind = "item"
        reference = tonumber(data.item)
        local inventoryItem
        for _, item in pairs(inventory_table or {}) do
            if tonumber(item.itemId) == reference then
                inventoryItem = item
                break
            end
        end

        if not inventoryItem or (tonumber(inventoryItem.count) or 0) < count then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('not_enough_count_alt'), 'bag', 2000)
            cb("not_enough")
            return
        end
        if Config.IsPersonalItem(inventoryItem.item) then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
            cb("blocked")
            return
        end
        if Config.IsNoTransferItem(inventoryItem.item) then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('resource_item_locked'), 'bag', 3500)
            cb("blocked")
            return
        end
    end

    pendingGroundDrop = true
    TriggerServerEvent("jrs_inventory:dropGroundItem", dropKind, reference, count, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }, NewInventoryOperationId("drop_ground_item"))
    cb("ok")
end)

