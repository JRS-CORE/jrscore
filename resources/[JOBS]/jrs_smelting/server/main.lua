-- jrs_smelting | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- source -> { smelter, recipe, amount, readyAt }
local pending = {}

local function nearSmelter(src, index)
    local s = Config.Smelters[index]
    return s and JRS.Near(src, s.coords, Config.UseDistance + 2.5)
end

local function inputsText(recipe, amount)
    local parts = {}
    for _, inp in ipairs(recipe.inputs) do
        parts[#parts + 1] = ('%dx %s'):format(inp.amount * (amount or 1), JRS.ItemLabel(inp.item))
    end
    return table.concat(parts, ', ')
end

-- recipe list with labels for the menu
JRS.Callback('jrs_smelting:recipes', function()
    local list = {}
    for i, r in ipairs(Config.Recipes) do
        list[i] = { index = i, label = JRS.ItemLabel(r.output), needs = inputsText(r, 1) }
    end
    return list
end)

JRS.Callback('jrs_smelting:start', function(src, smelter, recipeIndex, amount)
    smelter, recipeIndex, amount = tonumber(smelter), tonumber(recipeIndex), math.floor(tonumber(amount) or 0)
    local recipe = recipeIndex and Config.Recipes[recipeIndex]
    if pending[src] then return { ok = false, msg = L('busy') } end
    if not recipe or amount < 1 or amount > Config.MaxBatch then return { ok = false, msg = L('bad_amount') } end
    if not smelter or not nearSmelter(src, smelter) then return { ok = false, msg = L('too_far') } end
    if Config.Job and JRS.Job(src) ~= Config.Job then return { ok = false, msg = L('wrong_job', Config.Job) } end
    for _, inp in ipairs(recipe.inputs) do
        if not JRS.Has(src, inp.item, inp.amount * amount) then
            return { ok = false, msg = L('not_enough', JRS.ItemLabel(inp.item)) }
        end
    end
    if not JRS.CanCarry(src, recipe.output, amount) then return { ok = false, msg = L('no_space') } end

    local duration = recipe.time * amount
    pending[src] = { smelter = smelter, recipe = recipe, amount = amount, readyAt = GetGameTimer() + duration - 1000 }
    return { ok = true, duration = duration, label = JRS.ItemLabel(recipe.output) }
end)

-- Nothing is taken until the smelt finishes: no refunds, nothing lost on a disconnect.
RegisterNetEvent('jrs_smelting:server:finish', function(completed)
    local src = source
    local job = pending[src]
    pending[src] = nil
    if not job or completed ~= true then return end
    if GetGameTimer() < job.readyAt then return end
    if not nearSmelter(src, job.smelter) then return JRS.Notify(src, L('too_far')) end

    local recipe, amount = job.recipe, job.amount
    for _, inp in ipairs(recipe.inputs) do
        if not JRS.Has(src, inp.item, inp.amount * amount) then
            return JRS.Notify(src, L('not_enough', JRS.ItemLabel(inp.item)))
        end
    end
    if not JRS.CanCarry(src, recipe.output, amount) then return JRS.Notify(src, L('no_space')) end

    local taken = {}
    for _, inp in ipairs(recipe.inputs) do
        local total = inp.amount * amount
        if not JRS.Remove(src, inp.item, total) then
            for _, t in ipairs(taken) do exports.jrs_inventory:addItem(src, t.item, t.total) end
            return
        end
        taken[#taken + 1] = { item = inp.item, total = total }
    end
    if not exports.jrs_inventory:addItem(src, recipe.output, amount) then
        for _, t in ipairs(taken) do exports.jrs_inventory:addItem(src, t.item, t.total) end
        return JRS.Notify(src, L('no_space'))
    end
    JRS.Notify(src, L('done', amount, JRS.ItemLabel(recipe.output)))
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)
