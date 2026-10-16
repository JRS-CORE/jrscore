-- jrs_radialmenu | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_radialmenu | client
-- A radial menu built from Config.MenuItems, a job section (law / medic) and options other resources add
-- with the AddOption export. Items may carry functions; only plain data goes to the page, and what the page
-- reports back is looked up in our own tree again, never trusted.

local open = false
local lastId = 0
local added = {}                    -- options from other resources
local tree = {}                     -- the tree of the last menu we built (keeps the functions)
local job, jobAsked = nil, 0

-- ------------------------------------------------------------------ building the tree

local function allowed(item)
    if not item.canOpen then return true end
    local ok, result = pcall(item.canOpen)
    return ok and result and true or false
end

-- the visible part of a list, titles translated; a submenu without visible items disappears
local function visible(list)
    local out = {}
    for _, item in ipairs(list) do
        if type(item) == 'table' and allowed(item) then
            local copy = {}
            for key, value in pairs(item) do copy[key] = value end
            copy.title = L(item.title or '')

            local keep = true
            if item.items then
                copy.items = visible(item.items)
                keep = #copy.items > 0
            end
            if keep then out[#out + 1] = copy end
        end
    end
    return out
end

-- the same tree without functions, for the page
local function plain(list)
    local out = {}
    for i, item in ipairs(list) do
        local copy = {}
        for key, value in pairs(item) do
            if type(value) ~= 'function' and key ~= 'items' then copy[key] = value end
        end
        if item.items then copy.items = plain(item.items) end
        out[i] = copy
    end
    return out
end

local function lookup(list, id, event)
    for _, item in ipairs(list) do
        if item.items then
            local found = lookup(item.items, id, event)
            if found then return found end
        elseif item.id == id and (item.action or item.event == event) then
            return item
        end
    end
end

local function jobSection()
    if GetGameTimer() > jobAsked then
        jobAsked = GetGameTimer() + 30000
        job = JRS.Await('jrs_radialmenu:job')
    end
    if job and Config.LawJobs[job] then return Config.JobInteractions.law end
    if job and Config.MedicJobs[job] then return Config.JobInteractions.medic end
end

local function build()
    local list = { table.unpack(Config.MenuItems) }
    local work = jobSection()
    if work and #work > 0 then
        list[#list + 1] = { id = 'work', title = 'menu_work', icon = 'briefcase', items = work }
    end
    for _, item in pairs(added) do list[#list + 1] = item end
    tree = visible(list)
end

exports('AddOption', function(data, id)
    if type(data) ~= 'table' then return end
    if not id then
        lastId = lastId + 1
        id = lastId
    end
    added[id] = data
    return id
end)

exports('RemoveOption', function(id)
    if id then added[id] = nil end
end)

-- ------------------------------------------------------------------ opening and closing

local function usable()
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedCuffed(ped) and not IsPauseMenuActive()
        and LocalPlayer.state.jrs_robbery_cuffed ~= true
end

local function show(on)
    if on then
        build()
        TriggerEvent('jrs_radialmenu:client:onRadialmenuOpen')
        SendNUIMessage({ action = 'ui', radial = true, items = plain(tree) })
        SetCursorLocation(0.5, 0.5)
    else
        TriggerEvent('jrs_radialmenu:client:onRadialmenuClose')
    end
    SetNuiFocus(on, on)
    open = on
end

CreateThread(function()
    local pressed = Config.HoldToOpen and IsControlJustPressed or IsControlJustReleased
    while true do
        Wait(0)
        if not open and pressed(0, Config.Key) and usable() then show(true) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

RegisterNUICallback('closeRadial', function(_, done)
    if open then show(false) end
    done('ok')
end)

local runners = {
    client  = function(item) TriggerEvent(item.event, item) end,
    server  = function(item) TriggerServerEvent(item.event, item) end,
    command = function(item) ExecuteCommand(item.event) end,
}

RegisterNUICallback('selectItem', function(body, done)
    done('ok')
    local picked = type(body) == 'table' and type(body.itemData) == 'table' and body.itemData
    if not picked or not usable() then return end

    local item = lookup(tree, picked.id, picked.event)
    if not item then return end
    if item.action then item.action(item)
    elseif runners[item.type] then runners[item.type](item) end
end)
