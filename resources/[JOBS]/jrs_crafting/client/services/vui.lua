-- Crafting menu on the JRS core menu (mouse + keyboard):
-- categories -> recipes -> amount slider -> craft. After a craft finishes the
-- recipe list of the same category opens again.
uiopen = false

VUI = {}

local current = { location = nil, category = nil }

local function allowed(list, value)
    if list == nil or list == 0 then return true end
    if type(list) ~= 'table' then return list == value end
    for _, v in pairs(list) do if v == value then return true end end
    return false
end

local function myJob()
    local char = LocalPlayer.state.Character
    return char and char.Job or nil
end

local AR = Config.defaultlang == 'ar_lang'
local Labels = {}   -- item name -> label (filled once from the server)

local function tr(en, ar) if AR and ar and ar ~= '' then return ar end return en end
local function recipeLabel(r) return tr(r.LabelEn or r.Label or r.Text, r.Label) end
local function recipeDesc(r) return tr(r.DescEn or r.Desc, r.Desc) or '' end
local function recipeSub(r) return tr(r.SubTextEn or r.SubText, r.SubText) or '' end
local function catLabel(c) return tr(c.text, c.text_ar) end
local function itemLabel(name) return Labels[name] or name end

-- categories a station may craft: its StationType list, else Categories, else all
local function stationCategories(location)
    local st = location.StationType and Config.StationTypes and Config.StationTypes[location.StationType]
    if st then return st end
    return location.Categories
end

local function categoriesFor(location)
    local job, out = myJob(), {}
    local cats = stationCategories(location)
    for _, cat in ipairs(Config.Categories) do
        local inLocation = cats == nil or cats == 0 or allowed(cats, cat.ident)
        if inLocation and allowed(cat.Job, job) and allowed(cat.Location, location.id) then out[#out + 1] = cat end
    end
    return out
end

local function recipesFor(location, ident)
    local job, out = myJob(), {}
    for _, c in ipairs(Config.Crafting) do
        local stationOk = not c.StationType or not location.StationType or c.StationType == location.StationType
        if c.Category == ident and stationOk and allowed(c.Job, job) and allowed(c.Location, location.id) then out[#out + 1] = c end
    end
    return out
end

local function close()
    uiopen = false
    if Config.KneelingAnimation then Animations.forceRestScenario(false) end
end

local function list(items, key)
    local parts = {}
    for _, it in ipairs(items or {}) do parts[#parts + 1] = ('%sx %s'):format(it.count or 1, itemLabel(it[key] or it.name or '?')) end
    return table.concat(parts, ', ')
end

local openCategories, openRecipes

local function openRecipe(location, cat, recipe)
    local amounts = {}
    for i = 1, Config.MaxCraftAmount or 10 do amounts[i] = tostring(i) end
    local desc = ('<b>%s:</b> %s<br><b>%s:</b> %s'):format(_U('Ingredients'), list(recipe.Items, 'name'), _U('Rewards'), list(recipe.Reward, 'name'))
    if recipeDesc(recipe) ~= '' then desc = recipeDesc(recipe) .. '<br>' .. desc end

    JRS.OpenMenu('jrs_craft_recipe', recipeLabel(recipe), recipeSub(recipe) ~= '' and recipeSub(recipe) or catLabel(cat), {
        { label = _U('CraftNow'), type = 'slider', options = amounts, value = 0, desc = _U('AmountDesc') .. '<br>' .. desc },
        { label = _U('BackButton'), value = 'back', desc = '' },
    }, function(el, menu)
        if el.value == 'back' then menu.close() return openRecipes(location, cat) end
        local count = (tonumber(el.value) or 0) + 1
        menu.close()
        current.location, current.category = location, cat
        TriggerServerEvent('jrs:startcrafting', { Text = recipe.Text }, count, location.id)
    end, function() openRecipes(location, cat) end)
end

openRecipes = function(location, cat)
    local recipes = recipesFor(location, cat.ident)
    local elements = {}
    for i, r in ipairs(recipes) do
        local sub = recipeSub(r)
        elements[#elements + 1] = { label = recipeLabel(r), value = i, desc = recipeDesc(r) .. (sub ~= '' and ('<br>' .. sub) or '') }
    end
    if #elements == 0 then elements[1] = { label = _U('NothingHere'), value = 'none', disabled = true, desc = '' } end
    elements[#elements + 1] = { label = _U('BackButton'), value = 'back', desc = '' }

    JRS.OpenMenu('jrs_craft_list', _U('CraftHeader'), catLabel(cat), elements, function(el, menu)
        if el.value == 'none' then return end
        menu.close()
        if el.value == 'back' then return openCategories(location) end
        openRecipe(location, cat, recipes[el.value])
    end, function() openCategories(location) end)
end

openCategories = function(location)
    uiopen = true
    local cats = categoriesFor(location)
    local elements = {}
    for i, c in ipairs(cats) do elements[#elements + 1] = { label = catLabel(c), value = i, desc = '' } end
    if #elements == 0 then elements[1] = { label = _U('NothingHere'), value = 'none', disabled = true, desc = '' } end
    elements[#elements + 1] = { label = _U('ExitButton'), value = 'exit', desc = '' }

    JRS.OpenMenu('jrs_craft', _U('CraftHeader'), location.name or '', elements, function(el, menu)
        if el.value == 'none' then return end
        menu.close()
        if el.value == 'exit' then return close() end
        openRecipes(location, cats[el.value])
    end, function() close() end)
end

VUI.OpenUI = function(location)
    if not next(Labels) then Labels = JRS.Await('jrs_crafting:labels', AR) or {} end
    if Config.KneelingAnimation then Animations.forceRestScenario(true) end
    openCategories(location)
end

-- crafting started: the menu stays closed while the progress bar runs
VUI.Animate = function()
    JRS.CloseMenu()
end

-- crafting finished: back to the recipe list of the same category
VUI.Refocus = function()
    if current.location and current.category then
        openRecipes(current.location, current.category)
    else
        close()
    end
end

-- the server refused the craft (materials, job, full inventory): show the list again
RegisterNetEvent('jrs_crafting:failed', function() VUI.Refocus() end)
