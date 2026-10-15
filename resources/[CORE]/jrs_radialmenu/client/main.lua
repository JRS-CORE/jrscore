local inRadialMenu = false
local nextOptionId = 0
local DynamicMenuItems = {}
local MenuItems = {}   -- live tree (keeps action/canOpen functions) used for lookups
local myJob, jobCheckedAt = nil, 0

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------
local function isVisible(item)
    if not item.canOpen then return true end
    local ok, result = pcall(item.canOpen)
    return ok and result and true or false
end

-- filtered copy of the tree (canOpen honoured, titles translated)
local function filterItems(items)
    local out = {}
    for _, item in ipairs(items) do
        if type(item) == 'table' and isVisible(item) then
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy.title = L(item.title or '')
            if item.items then
                copy.items = filterItems(item.items)
                if #copy.items == 0 then copy = nil end
            end
            if copy then out[#out + 1] = copy end
        end
    end
    return out
end

-- strips functions so the tree can be sent to the NUI
local function toNui(items)
    local out = {}
    for i, item in ipairs(items) do
        local copy = {}
        for k, v in pairs(item) do
            if type(v) ~= 'function' and k ~= 'items' then copy[k] = v end
        end
        if item.items then copy.items = toNui(item.items) end
        out[i] = copy
    end
    return out
end

local function findItem(items, id, event)
    for _, v in ipairs(items) do
        if v.items then
            local found = findItem(v.items, id, event)
            if found then return found end
        elseif v.id == id and (v.action or v.event == event) then
            return v
        end
    end
end

---------------------------------------------------------------------
-- dynamic options (exports, same as before)
---------------------------------------------------------------------
local function AddOption(data, id)
    if type(data) ~= 'table' then return end
    if not id then
        nextOptionId = nextOptionId + 1
        id = nextOptionId
    end
    DynamicMenuItems[id] = data
    return id
end

local function RemoveOption(id)
    if id then DynamicMenuItems[id] = nil end
end

local function jobItems()
    if GetGameTimer() > jobCheckedAt then
        jobCheckedAt = GetGameTimer() + 30000
        myJob = JRS.Await('jrs_radialmenu:job')
    end
    if myJob and Config.LawJobs[myJob] then return Config.JobInteractions.law end
    if myJob and Config.MedicJobs[myJob] then return Config.JobInteractions.medic end
end

local function BuildMenu()
    local all = {}
    for _, v in ipairs(Config.MenuItems) do all[#all + 1] = v end
    local work = jobItems()
    if work and #work > 0 then
        all[#all + 1] = { id = 'work', title = 'menu_work', icon = 'briefcase', items = work }
    end
    for _, v in pairs(DynamicMenuItems) do all[#all + 1] = v end
    MenuItems = filterItems(all)
end

---------------------------------------------------------------------
-- open / close
---------------------------------------------------------------------
local function canUseMenu()
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedCuffed(ped) and not IsPauseMenuActive()
        and LocalPlayer.state.jrs_robbery_cuffed ~= true
end

local function setRadialState(open)
    if open then
        BuildMenu()
        TriggerEvent('jrs_radialmenu:client:onRadialmenuOpen')
        SendNUIMessage({ action = 'ui', radial = true, items = toNui(MenuItems) })
        SetCursorLocation(0.5, 0.5)
    else
        TriggerEvent('jrs_radialmenu:client:onRadialmenuClose')
    end
    SetNuiFocus(open, open)
    inRadialMenu = open
end

CreateThread(function()
    local activated = Config.HoldToOpen and IsControlJustPressed or IsControlJustReleased
    while true do
        Wait(0)
        if not inRadialMenu and activated(0, Config.Key) and canUseMenu() then
            setRadialState(true)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and inRadialMenu then SetNuiFocus(false, false) end
end)

---------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------
RegisterNUICallback('closeRadial', function(_, cb)
    if inRadialMenu then setRadialState(false) end
    cb('ok')
end)

RegisterNUICallback('selectItem', function(inData, cb)
    cb('ok')
    if not canUseMenu() or type(inData) ~= 'table' or type(inData.itemData) ~= 'table' then return end
    -- only run items that exist in our own tree; never trust NUI payloads
    local item = findItem(MenuItems, inData.itemData.id, inData.itemData.event)
    if not item then return end
    if item.action then
        item.action(item)
    elseif item.type == 'client' then
        TriggerEvent(item.event, item)
    elseif item.type == 'server' then
        TriggerServerEvent(item.event, item)
    elseif item.type == 'command' then
        ExecuteCommand(item.event)
    end
end)

exports('AddOption', AddOption)
exports('RemoveOption', RemoveOption)
