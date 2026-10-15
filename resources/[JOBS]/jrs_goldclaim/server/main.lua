

local PropsLoaded      = false
local ProcessingRockers = {} -- [propid] = citizenid of the player running it
local PendingOutputs   = {} -- [propid] = { cid = citizenid, gold = n, paydirt = n } (server-authoritative)
local Cooldowns        = {} -- [src] = { [key] = GetGameTimer() expiry }


---------------------------------------------
-- helpers
---------------------------------------------
local function Notify(src, title, description, nType, icon, duration)
    JRS.Notify(src, description and (title .. ': ' .. description) or title, duration or Config.NotifyDuration)
end

-- webhooks are not shipped with the JRS edition
local Webhook = { Log = function() end, Suspicious = function() end }

local function Debug(...)
    if Config.Debug then print('[jrs_goldclaim]', ...) end
end

--- returns true if the action is still on cooldown (and should be rejected)
local function OnCooldown(src, key, ms)
    Cooldowns[src] = Cooldowns[src] or {}
    local now = GetGameTimer()
    if (Cooldowns[src][key] or 0) > now then return true end
    Cooldowns[src][key] = now + ms
    return false
end

local function AddItem(src, item, amount)
    if not JRS.CanCarry(src, item, amount) then
        Notify(src, L('rocker_inventory_full'), nil, 'error', 'circle-xmark')
        return false
    end
    return exports.jrs_inventory:addItem(src, item, amount) == true
end

local function RemoveItem(src, item, amount)
    if JRS.Count(src, item) < amount then return false end
    return JRS.Remove(src, item, amount)
end

-- Player here is the JRS character; .src is attached by GetPlayer below
local function GetItemCount(Player, item)
    return JRS.Count(Player.src, item)
end

local function GetPlayer(src)
    local char = JRS.Char(src)
    if not char then return nil end
    return { src = src, citizenid = tostring(char.charIdentifier), firstname = char.firstname or '', lastname = char.lastname or '', job = char.job }
end

local function GetRockerPropById(propid)
    for i = 1, #Config.PlayerProps do
        if Config.PlayerProps[i].id == propid then
            return Config.PlayerProps[i], i
        end
    end
end

local function GetPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function IsNearCoords(src, coords, radius)
    local pos = GetPlayerCoords(src)
    return pos ~= nil and #(pos - coords) <= radius
end

local function IsNearProp(src, propData, radius)
    if not propData then return false end
    return IsNearCoords(src, vector3(propData.x, propData.y, propData.z), radius or Config.InteractDistance)
end

--- validates player + rocker + proximity; returns Player, propData
local function ValidateRockerAction(src, propid, radius)
    local Player = GetPlayer(src)
    if not Player then return end
    propid = tonumber(propid)
    if not propid then return end
    local propData = GetRockerPropById(propid)
    if not propData then return end
    if not IsNearProp(src, propData, radius) then
        Notify(src, L('rocker_too_far'), nil, 'error', 'circle-xmark')
        local pos = GetPlayerCoords(src)
        local dist = pos and #(pos - vector3(propData.x, propData.y, propData.z)) or -1
        if dist > (radius or Config.InteractDistance) * 5 then -- way beyond any desync = likely exploit
            Webhook.Suspicious(src, L('wh_reason_far_event'), {
                { L('wh_event'), L('wh_rocker_action') },
                { L('wh_rocker_id'), propid }, { L('wh_distance'), ('%.1fm'):format(dist) },
            })
        end
        return
    end
    return Player, propData, propid
end

-- oxmysql returns tinyint(1) as a boolean, normalise to 0/1
local function ToFlag(v)
    return (v == true or v == 1) and 1 or 0
end

local function RockerUpdateProps(target)
    TriggerClientEvent('jrs_goldclaim:rocker:client:updatePropData', target or -1, Config.PlayerProps)
end

--- removes a rocker from memory, the world and the database
local function RemoveRocker(propid)
    local _, index = GetRockerPropById(propid)
    if index then table.remove(Config.PlayerProps, index) end
    ProcessingRockers[propid] = nil
    PendingOutputs[propid] = nil
    TriggerClientEvent('jrs_goldclaim:rocker:client:removePropObject', -1, propid)
    MySQL.update('DELETE FROM jrs_goldrockers WHERE propid = ?', { propid })
end

local function LoadProps()
    Config.PlayerProps = {}
    local result = MySQL.query.await('SELECT properties, licensed, claimname FROM jrs_goldrockers')
    for i = 1, #(result or {}) do
        local propData = json.decode(result[i].properties)
        if propData then
            propData.licensed  = ToFlag(result[i].licensed)
            propData.claimname = result[i].claimname
            propData.hash      = Config.GoldRocker
            Config.PlayerProps[#Config.PlayerProps + 1] = propData
            Debug('loaded rocker', propData.id)
        end
    end
end

---------------------------------------------
-- startup
---------------------------------------------
CreateThread(function()
    LoadProps()
    PropsLoaded = true
    RockerUpdateProps()
end)

JRS.Callback('jrs_goldclaim:server:getprops', function()
    while not PropsLoaded do Wait(100) end
    return Config.PlayerProps
end)

--- unclaimed outputs for this character (so they survive a relog)
JRS.Callback('jrs_goldclaim:server:getpending', function(source)
    local Player = GetPlayer(source)
    if not Player then return {} end
    local cid, list = Player.citizenid, {}
    for propid, p in pairs(PendingOutputs) do
        if p.cid == cid then list[#list + 1] = { propid = propid, gold = p.gold, paydirt = p.paydirt } end
    end
    return list
end)

AddEventHandler('playerDropped', function()
    local src = source
    Cooldowns[src] = nil
end)

---------------------------------------------
-- useable items
---------------------------------------------
JRS.Usable('goldrocker', function(source)
    TriggerClientEvent('jrs_goldclaim:rocker:client:createprop', source)
end)

JRS.Usable('rocker_shovel', function(source)
    TriggerClientEvent('jrs_goldclaim:rocker:client:useshovel', source)
end)

JRS.Usable('rocker_bucket', function(source)
    TriggerClientEvent('jrs_goldclaim:rocker:client:usebucket', source)
end)

---------------------------------------------
-- gathering: dig paydirt / fill bucket
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:digpaydirt', function()
    local src = source
    local Player = GetPlayer(src)
    if not Player then return end
    if OnCooldown(src, 'gather', Config.ShovelDigTime - 500) then return end
    if GetItemCount(Player, 'rocker_shovel') < 1 then return end

    AddItem(src, 'paydirt', 1, 'jrs_goldclaim:dig')
end)

RegisterNetEvent('jrs_goldclaim:rocker:server:fillbucket', function()
    local src = source
    local Player = GetPlayer(src)
    if not Player then return end
    if OnCooldown(src, 'gather', Config.BucketFillTime - 500) then return end
    if GetItemCount(Player, 'rocker_bucket') < 1 then return end

    if RemoveItem(src, 'rocker_bucket', 1, 'jrs_goldclaim:fillbucket') then
        if not AddItem(src, 'rocker_bucket_full', 1, 'jrs_goldclaim:fillbucket') then
            AddItem(src, 'rocker_bucket', 1, 'jrs_goldclaim:refund')
        end
    end
end)

---------------------------------------------
-- callbacks
---------------------------------------------
JRS.Callback('jrs_goldclaim:server:countprops', function(source)
    local Player = GetPlayer(source)
    if not Player then return 0 end
    local cid, count = Player.citizenid, 0
    for _, v in pairs(Config.PlayerProps) do
        if v.builder == cid then count = count + 1 end
    end
    return count
end)

JRS.Callback('jrs_goldclaim:server:getrockerdata', function(source, propid)
    propid = tonumber(propid)
    local propData = propid and GetRockerPropById(propid)
    if not propData or not IsNearProp(source, propData, Config.ClaimZoneRadius) then return nil end
    local result = MySQL.single.await('SELECT propid, citizenid, owner, licensed, claimname, paydirt, water, quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    if result then
        result.processing = ProcessingRockers[propid] ~= nil
        result.licensed = ToFlag(result.licensed)
    end
    return result
end)

---------------------------------------------
-- place a new rocker
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:newProp', function(location, heading)
    local src = source
    local Player = GetPlayer(src)
    if not Player then return end
    if OnCooldown(src, 'place', 3000) then return end

    if type(location) ~= 'vector3' and (type(location) ~= 'table' or type(location.x) ~= 'number') then return end
    location = vector3(location.x + 0.0, location.y + 0.0, location.z + 0.0)
    heading = (tonumber(heading) or 0.0) % 360.0

    if not IsNearCoords(src, location, Config.PlaceMaxDistance) then
        Notify(src, L('rocker_too_far'), nil, 'error', 'circle-xmark')
        Webhook.Suspicious(src, L('wh_reason_far_place'), {
            { L('wh_requested_coords'), ('%.2f, %.2f, %.2f'):format(location.x, location.y, location.z) },
        })
        return
    end

    local citizenid = Player.citizenid
    local count = 0
    for _, v in pairs(Config.PlayerProps) do
        if v.builder == citizenid then count = count + 1 end
        if #(location - vector3(v.x, v.y, v.z)) < Config.MinRockerSpacing then
            Notify(src, L('rocker_too_close_other'), nil, 'error', 'circle-xmark')
            return
        end
    end
    if count >= Config.MaxGoldRockers then
        Notify(src, L('rocker_max_equipment'), nil, 'error', 'circle-xmark')
        return
    end

    if not RemoveItem(src, 'goldrocker', 1, 'jrs_goldclaim:place') then return end

    local owner = ('%s %s'):format(Player.firstname, Player.lastname)
    local licensed, claimname = 0, nil

    if GetItemCount(Player, Config.LicenseItem) > 0 and RemoveItem(src, Config.LicenseItem, 1, 'jrs_goldclaim:license') then
        licensed = 1
        claimname = L('rocker_claim_default_name', owner)
    end

    local propId
    repeat propId = math.random(111111, 999999) until not GetRockerPropById(propId)

    local PropData = {
        id        = propId,
        proptype  = 'goldrocker',
        x         = location.x,
        y         = location.y,
        z         = location.z,
        h         = heading,
        hash      = Config.GoldRocker,
        builder   = citizenid,
        buildtime = os.time(),
        licensed  = licensed,
        claimname = claimname,
    }

    Config.PlayerProps[#Config.PlayerProps + 1] = PropData
    MySQL.insert('INSERT INTO jrs_goldrockers (properties, propid, citizenid, owner, proptype, licensed, claimname) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        json.encode(PropData), propId, citizenid, owner, 'goldrocker', licensed, claimname,
    })
    RockerUpdateProps()

    local coordsText = ('%.2f, %.2f, %.2f'):format(location.x, location.y, location.z)
    Webhook.Log('rocker_placed', src, L('wh_title_placed'), {
        { L('wh_rocker_id'), propId }, { L('wh_licensed'), licensed == 1 and L('wh_yes') or L('wh_no') },
        { L('wh_claim_name'), claimname or L('wh_na') }, { L('wh_rocker_coords'), coordsText },
        { L('wh_rockers_owned'), ('%s/%s'):format(count + 1, Config.MaxGoldRockers) },
    })
    if licensed == 0 then
        Webhook.Log('illegal_placed', src, L('wh_title_illegal_placed'), {
            { L('wh_rocker_id'), propId }, { L('wh_rocker_coords'), coordsText },
        })
        Notify(src, L('rocker_unlicensed_notice_title'), L('rocker_unlicensed_notice_desc'), 'warning', 'triangle-exclamation', 10000)
    end
end)

---------------------------------------------
-- pack up (owner only, returns the rocker)
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:destroyProp', function(propid)
    local src = source
    local Player, propData
    Player, propData, propid = ValidateRockerAction(src, propid)
    if not Player then return end
    if propData.builder ~= Player.citizenid then return end

    if OnCooldown(src, 'packup', 2000) then return end

    local row = MySQL.single.await('SELECT quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    -- re-check after the await: a second request could have removed it meanwhile (item dupe)
    if not GetRockerPropById(propid) then return end
    if not row or row.quality < 100 then
        Notify(src, L('rocker_needs_repair'), nil, 'error', 'circle-xmark')
        return
    end
    if not JRS.CanCarry(src, 'goldrocker', 1) then
        Notify(src, L('rocker_inventory_full'), nil, 'error', 'circle-xmark')
        return
    end

    RemoveRocker(propid)
    AddItem(src, 'goldrocker', 1, 'jrs_goldclaim:packup')
    Webhook.Log('rocker_packed', src, L('wh_title_packed'), {
        { L('wh_rocker_id'), propid }, { L('wh_claim_name'), propData.claimname or L('wh_na') },
    })
    Notify(src, L('rocker_packed_up'), nil, 'success', 'circle-check')
end)

---------------------------------------------
-- LEO destroy illegal claim (confiscate as evidence)
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:leodestroy', function(propid)
    local src = source
    local Player, propData
    Player, propData, propid = ValidateRockerAction(src, propid)
    if not Player then return end

    local job = { name = Player.job, label = Player.job }
    if not Config.LeoJobs[Player.job or ''] then
        Webhook.Suspicious(src, L('wh_reason_non_leo'), { { L('wh_rocker_id'), propid }, { L('wh_job'), job and job.name or L('wh_none') } })
        return
    end
    if propData.licensed == 1 then return end

    RemoveRocker(propid)
    AddItem(src, 'goldrocker', 1, 'jrs_goldclaim:confiscate')
    Webhook.Log('leo_destroyed', src, L('wh_title_leo_destroyed'), {
        { L('wh_rocker_id'), propid }, { L('wh_owner_citizenid'), propData.builder },
        { L('wh_officer_job'), tostring(job.name) },
    })
    Notify(src, L('rocker_claim_destroyed'), L('rocker_evidence_collected'), 'success', 'circle-check')
end)

---------------------------------------------
-- add paydirt / water
---------------------------------------------
local function AddResource(src, propid, column, max, item, fullMsg, okMsg, returnItem, actionTime)
    local Player, _
    Player, _, propid = ValidateRockerAction(src, propid)
    if not Player then return end
    if OnCooldown(src, 'load', actionTime - 1000) then return end -- matches the client action time
    if GetItemCount(Player, item) < 1 then return end

    local row = MySQL.single.await(('SELECT %s AS amount FROM jrs_goldrockers WHERE propid = ?'):format(column), { propid })
    if not row then return end
    if row.amount >= max then
        Notify(src, L(fullMsg), nil, 'error', 'circle-xmark')
        return
    end

    if not RemoveItem(src, item, 1, 'jrs_goldclaim:load') then return end
    -- conditional atomic increment: if another player filled it meanwhile, refund instead of losing the item
    local affected = MySQL.update.await(('UPDATE jrs_goldrockers SET %s = %s + 1 WHERE propid = ? AND %s < ?'):format(column, column, column), { propid, max })
    if not affected or affected < 1 then
        AddItem(src, item, 1, 'jrs_goldclaim:refund')
        Notify(src, L(fullMsg), nil, 'error', 'circle-xmark')
        return
    end
    if returnItem then AddItem(src, returnItem, 1, 'jrs_goldclaim:load') end
    Notify(src, L(okMsg), L('rocker_level', math.min(row.amount + 1, max), max), 'success', 'circle-check', 3000)
end

RegisterNetEvent('jrs_goldclaim:rocker:server:addpaydirt', function(propid)
    AddResource(source, propid, 'paydirt', Config.MaxPaydirt, 'paydirt', 'rocker_paydirt_full', 'rocker_paydirt_added', nil, Config.AddPaydirtTime)
end)

RegisterNetEvent('jrs_goldclaim:rocker:server:addwater', function(propid)
    AddResource(source, propid, 'water', Config.MaxWater, 'rocker_bucket_full', 'rocker_water_full', 'rocker_water_added', 'rocker_bucket', Config.AddWaterTime)
end)

---------------------------------------------
-- process rocker (server-driven, one cycle per Config.ProcessingTime)
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:processrocker', function(propid)
    local src = source
    local Player, propData
    Player, propData, propid = ValidateRockerAction(src, propid)
    if not Player then return end

    local cid = Player.citizenid
    if Config.OwnerOnlyProcessing and propData.builder ~= cid then
        Notify(src, L('rocker_not_owner'), nil, 'error', 'circle-xmark')
        return
    end
    if ProcessingRockers[propid] then
        Notify(src, L('rocker_already_processing_title'), L('rocker_already_processing_desc'), 'error', 'circle-xmark')
        return
    end

    -- lock before the await so two rapid requests can't start two parallel processing loops
    ProcessingRockers[propid] = cid
    local row = MySQL.single.await('SELECT water, paydirt, quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    local fail
    if not row or not GetRockerPropById(propid) then fail = true
    elseif row.quality <= 0 then fail = 'rocker_needs_repair'
    elseif row.water <= 0 then fail = 'rocker_processing_no_water'
    elseif row.paydirt <= 0 then fail = 'rocker_processing_no_paydirt' end
    if fail then
        ProcessingRockers[propid] = nil
        if fail ~= true then Notify(src, L(fail), nil, 'error', 'circle-xmark') end
        return
    end
    Notify(src, L('rocker_processing_started'), L('rocker_processing_will_run', math.min(row.water, row.paydirt)), 'inform', 'coins')
    Webhook.Log('processing_started', src, L('wh_title_processing'), {
        { L('wh_rocker_id'), propid }, { L('wh_cycles'), math.min(row.water, row.paydirt) },
        { L('wh_water_paydirt'), ('%s / %s'):format(row.water, row.paydirt) }, { L('wh_condition'), row.quality .. '%' },
    })

    CreateThread(function()
        while true do
            Wait(Config.ProcessingTime)

            -- stop if the rocker was removed or the player left / switched character
            -- (checked before consuming, so nothing is lost when a cycle is interrupted)
            local p = GetPlayer(src)
            if not GetRockerPropById(propid) or not p or p.citizenid ~= cid then break end

            -- consume one unit of each atomically; abort if either ran out or the rocker broke
            local affected = MySQL.update.await('UPDATE jrs_goldrockers SET water = water - 1, paydirt = paydirt - 1 WHERE propid = ? AND water > 0 AND paydirt > 0 AND quality > 0', { propid })
            if not affected or affected < 1 then break end

            local resultType = math.random(1, 100) <= Config.GoldChance and 'gold' or 'paydirt'
            local pending = PendingOutputs[propid]
            if not pending or pending.cid ~= cid then
                pending = { cid = cid, gold = 0, paydirt = 0 }
                PendingOutputs[propid] = pending
            end
            pending[resultType] = pending[resultType] + 1
            TriggerClientEvent('jrs_goldclaim:rocker:client:spawnoutputprop', src, propid, resultType)
        end

        ProcessingRockers[propid] = nil
        if GetPlayerPed(src) ~= 0 then
            TriggerClientEvent('jrs_goldclaim:rocker:client:processingcomplete', src, propid)
        end
    end)
end)

---------------------------------------------
-- pick up outputs (only honoured if the server produced them for this player)
---------------------------------------------
local function ConsumePending(src, propid, resultType)
    local Player, _
    Player, _, propid = ValidateRockerAction(src, propid, Config.PickupDistance)
    if not Player then return end
    local pending = PendingOutputs[propid]
    if not pending or pending.cid ~= Player.citizenid or pending[resultType] < 1 then return end
    pending[resultType] = pending[resultType] - 1
    return Player, propid, pending
end

RegisterNetEvent('jrs_goldclaim:rocker:server:pickupgold', function(propid)
    local src = source
    local Player, pending
    Player, propid, pending = ConsumePending(src, propid, 'gold')
    if not Player then return end

    local ore = Config.GoldOreItem
    local amount = math.random(Config.GoldOreAmount.min, Config.GoldOreAmount.max)

    if AddItem(src, ore, amount, 'jrs_goldclaim:pickupgold') then
        TriggerClientEvent('jrs_goldclaim:rocker:client:goldpickupresult', src, amount)
        Webhook.Log('gold_pickup', src, L('wh_title_gold'), {
            { L('wh_rocker_id'), propid }, { L('wh_item'), JRS.ItemLabel(ore) }, { L('wh_amount'), amount },
        })
    else
        pending.gold = pending.gold + 1 -- inventory full: keep it claimable and respawn the prop
        TriggerClientEvent('jrs_goldclaim:rocker:client:spawnoutputprop', src, propid, 'gold', true)
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:server:pickuppaydirt', function(propid)
    local src = source
    local Player, pending
    Player, propid, pending = ConsumePending(src, propid, 'paydirt')
    if not Player then return end
    if not AddItem(src, 'paydirt', 1, 'jrs_goldclaim:pickuppaydirt') then
        pending.paydirt = pending.paydirt + 1
        TriggerClientEvent('jrs_goldclaim:rocker:client:spawnoutputprop', src, propid, 'paydirt', true)
        return
    end
    Webhook.Log('paydirt_pickup', src, L('wh_title_paydirt'), { { L('wh_rocker_id'), propid } })
end)

---------------------------------------------
-- repair rocker
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:repairrocker', function(propid)
    local src = source
    local Player, _
    Player, _, propid = ValidateRockerAction(src, propid)
    if not Player then return end
    if OnCooldown(src, 'repair', Config.RepairTime - 1000) then return end

    local row = MySQL.single.await('SELECT quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    if not row or row.quality >= 100 then return end
    if GetItemCount(Player, 'wood') < Config.RepairWoodAmount then
        Notify(src, L('rocker_not_enough_wood', Config.RepairWoodAmount), nil, 'error', 'circle-xmark')
        return
    end

    if RemoveItem(src, 'wood', Config.RepairWoodAmount, 'jrs_goldclaim:repair') then
        MySQL.update('UPDATE jrs_goldrockers SET quality = 100 WHERE propid = ?', { propid })
        Notify(src, L('rocker_repaired'), nil, 'success', 'circle-check')
    end
end)

---------------------------------------------
-- rename claim (licensed owner only)
---------------------------------------------
RegisterNetEvent('jrs_goldclaim:rocker:server:renameclaim', function(propid, newname)
    local src = source
    local Player, propData
    Player, propData, propid = ValidateRockerAction(src, propid, Config.ClaimZoneRadius)
    if not Player then return end
    if propData.builder ~= Player.citizenid or propData.licensed ~= 1 then return end
    if OnCooldown(src, 'rename', 5000) then return end

    if type(newname) ~= 'string' then return end
    newname = newname:gsub('[%c<>]', ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if #newname < 3 or #newname > Config.MaxClaimNameLength then
        Notify(src, L('rocker_rename_invalid', Config.MaxClaimNameLength), nil, 'error', 'circle-xmark')
        return
    end

    MySQL.update('UPDATE jrs_goldrockers SET claimname = ? WHERE propid = ?', { newname, propid })
    Webhook.Log('claim_renamed', src, L('wh_title_renamed'), {
        { L('wh_rocker_id'), propid }, { L('wh_old_name'), propData.claimname or L('wh_na') }, { L('wh_new_name'), newname },
    })
    propData.claimname = newname
    TriggerClientEvent('jrs_goldclaim:rocker:client:refreshclaim', -1, propid, newname)
    Notify(src, L('rocker_claim_renamed'), newname, 'success', 'circle-check')
end)

---------------------------------------------
-- equipment degradation cron
---------------------------------------------
local function DegradeRockers()
    -- remove broken rockers first (they had a full cycle at 0% to be repaired)
    local broken = MySQL.query.await('SELECT propid, owner, citizenid FROM jrs_goldrockers WHERE quality <= 0') or {}
    for i = 1, #broken do
        local row = broken[i]
        RemoveRocker(row.propid)
        Webhook.Log('rocker_lost', nil, L('wh_title_lost'), {
            { L('wh_rocker_id'), row.propid }, { L('wh_owner'), row.owner }, { L('wh_citizenid'), row.citizenid },
        }, { description = L('wh_lost_desc') })
    end

    -- independent roll per rocker, done in a single query
    MySQL.update('UPDATE jrs_goldrockers SET quality = quality - 1 WHERE quality > 0 AND RAND() * 100 < ?', { Config.DegradeChance })

    if #broken > 0 then RockerUpdateProps() end
    Debug('degradation cron ran')
end

CreateThread(function()
    while true do
        Wait(Config.DegradeEvery * 60000)
        DegradeRockers()
    end
end)

---------------------------------------------
-- small client helpers (character id / job / item check)
---------------------------------------------
JRS.Callback('jrs_goldclaim:server:me', function(src)
    local p = GetPlayer(src)
    return p and { id = p.citizenid, job = p.job } or nil
end)

JRS.Callback('jrs_goldclaim:server:hasitem', function(src, item, amount)
    if type(item) ~= 'string' then return false end
    return JRS.Count(src, item) >= (tonumber(amount) or 1)
end)
