-- jrs_weapons | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_weapons | client
-- Two stations: the customization bench (look at your equipped gun on a stand and try parts on it, then buy)
-- and the crafting bench (craft guns and ammo). The menus use WarMenu; every purchase and craft is
-- validated on the server, this file only shows choices.

local Core = exports.jrs_core:GetCore()
local progressbar = exports.jrs_progressbar:initiate()

local Cfg = Config.General
local L = Config.Language

-- ------------------------------------------------------------------ state

local allParts = {}                 -- weapon name -> list of parts, from wepcomps.json
local parts = {}                    -- parts that fit the weapon that is on the bench
local picked = {}                   -- parts chosen so far: { label, model, comp, type, name, price }
local weaponId, weaponHash          -- the equipped gun this session of customization is about
local stand, standTurned            -- the 3D copy of the gun, and whether it exists
local standHeading, standRoll = 0.0, 0.0
local crafting = false              -- the crafting menu is up
local craftCategory, craftName      -- current choice in the crafting menus
local crafterJob                    -- job of the player, fetched when the crafting menus need it
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local prompt

-- ------------------------------------------------------------------ small helpers

local function giveComponent(entity, component, weapon, immediate)
    return Citizen.InvokeNative(0x74C9090FDD1BB48E, entity, component, weapon, immediate)
end

local function takeComponent(ped, component, weapon)
    return Citizen.InvokeNative(0x19F70C4D80494FF8, ped, component, weapon)
end

local function loadModel(model)
    if not IsModelInCdimage(model) then return false end
    RequestModel(model, false)
    while not HasModelLoaded(model) do Wait(0) end
    return true
end

-- runs `fn` with a component's model streamed in (when it has one)
local function withModel(part, fn)
    local hasModel = part.model ~= 0
    if hasModel then loadModel(part.model) end
    fn()
    if hasModel then SetModelAsNoLongerNeeded(part.model) end
end

local function listHas(list, value)
    for _, item in pairs(list or {}) do
        if item == value then return true end
    end
    return false
end

-- is there a part of `comp` (and `kind`, nil meaning "no kind") in the list?
local function hasPart(list, comp, kind)
    for _, p in pairs(list) do
        if p.comp == comp and p.type == kind then return true end
    end
    return false
end

local function hasComp(list, comp)
    for _, p in pairs(list) do
        if p.comp == comp then return true end
    end
    return false
end

local function resetCraft()
    crafting, craftCategory, craftName, crafterJob = false, nil, nil, nil
    FreezeEntityPosition(PlayerPedId(), false)
end

local function resetBench()
    picked, parts = {}, {}
    weaponId, weaponHash = nil, nil
    standTurned = false
    if stand then DeleteEntity(stand) end
    FreezeEntityPosition(PlayerPedId(), false)
end

-- plays a work scenario for 20 s with a progress bar
local function work(scenario, text)
    TaskStartScenarioInPlaceHash(PlayerPedId(), joaat(scenario), 20000, true, 0, 0, false)
    progressbar.start(text, 20000, function() end)
    Wait(20000)
    ClearPedTasksImmediately(PlayerPedId())
end

local function nearestOtherPlayer()
    local me, here = PlayerId(), GetEntityCoords(PlayerPedId())
    local best, bestDistance = nil, nil
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local distance = #(here - GetEntityCoords(GetPlayerPed(player)))
            if not bestDistance or distance < bestDistance then best, bestDistance = player, distance end
        end
    end
    return best, bestDistance
end

-- ------------------------------------------------------------------ prices and parts of the equipped weapon

local METAL_PRICE = {
    ['Gold'] = 'gold', ['Silver'] = 'silver', ['Blued Steel'] = 'bluesteel', ['Browned Steel'] = 'brownsteel',
    ['Blackened Steel'] = 'blacksteel', ['Copper'] = 'copper', ['Nickel'] = 'nickle', ['Brass'] = 'brass', ['Iron'] = 'iron',
}
local MATERIAL_PARTS = { barrel = true, trigger = true, cylinder = true, frontsight = true, frame = true, scope = true, decalcolor = true }
local FIXED_PRICE = { variant = 'variant', gripbody = 'griptype', grip = 'gripdecal', wrapcolor = 'wrapcolor' }
local DECAL_PRICE = { cylinder = 'decalextra', frame = 'decalframe', barrel = 'decalbarrel' }
local COMP_PRICE = { scope = 'sight', rifling = 'rifling', other = 'barrel', wrap = 'wrap' }

local function priceOf(part)
    local price = Cfg.price
    local key = FIXED_PRICE[part.comp]
        or (part.comp == 'decal' and DECAL_PRICE[part.type])
        or (part.comp == 'comp' and COMP_PRICE[part.type])
        or (MATERIAL_PARTS[part.comp] and METAL_PRICE[part.label])
    return key and price[key] or 0
end

local function loadCatalogue()
    allParts = json.decode(LoadResourceFile(GetCurrentResourceName(), 'wepcomps.json')) or {}
    for _, list in pairs(allParts) do
        for _, part in pairs(list) do
            if part.confirmed == 1 then part.price = priceOf(part) end
        end
    end
end

-- the parts that fit the weapon in the hand
local function loadPartsOfHeldWeapon()
    local _, held = GetCurrentPedWeapon(PlayerPedId(), true, 0, true)
    parts = {}
    for name, list in pairs(allParts) do
        if joaat(name) == held then
            for _, p in pairs(list) do
                parts[#parts + 1] = { label = p.label, model = p.model, name = p.name, type = p.type, comp = p.comp, confirmed = p.confirmed, price = p.price }
            end
        end
    end
end

local function totalPrice()
    local sum = 0
    for _, p in ipairs(picked) do
        for _, known in ipairs(parts) do
            if known.name == p.name then sum = sum + (known.price or 0) end
        end
    end
    return sum
end

RegisterNetEvent('jrs_weapons:initalizing', loadCatalogue)
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then loadCatalogue() end
end)

RegisterNetEvent('jrs:SelectedCharacter')
AddEventHandler('jrs:SelectedCharacter', function()
    loadCatalogue()
    Wait(1000)
    RemoveAllPedWeapons(PlayerPedId(), true, true)
end)

-- ------------------------------------------------------------------ the gun on the stand

local function dropFromPicked(match)
    for i = #picked, 1, -1 do
        if match(picked[i]) then table.remove(picked, i) end
    end
end

local function showOnStand(part)
    withModel(part, function() giveComponent(stand, part.name, -1, true) end)
end

local function spawnStand(at, hash)
    if standTurned then return end
    stand = Citizen.InvokeNative(0x9888652B8BA77F73, hash, 0, at.x, at.y, at.z, true, 1.0)
    standHeading = GetEntityHeading(stand)
    standRoll = GetEntityRotation(stand, 1).x
    for _, p in ipairs(picked) do RemoveWeaponComponentFromWeaponObject(stand, p.name) end
    for _, p in ipairs(picked) do showOnStand(p) end
    standTurned = true
end

-- the player takes a part (it replaces whatever is in the same slot)
local function choose(part)
    dropFromPicked(function(p) return p.name == part.name or (p.comp == part.comp and p.type == part.type) end)
    picked[#picked + 1] = { label = part.label, model = part.model, comp = part.comp, type = part.type, name = part.name, price = part.price }
    for _, known in ipairs(parts) do
        if known.comp == part.comp and known.type == part.type then RemoveWeaponComponentFromWeaponObject(stand, known.name) end
    end
    showOnStand(part)
end

-- the player clears a slot
local function clear(match)
    for _, p in ipairs(picked) do
        if match(p) then RemoveWeaponComponentFromWeaponObject(stand, p.name) end
    end
    dropFromPicked(match)
end

-- the bench keys turn the stand
CreateThread(function()
    repeat Wait(1000) until LocalPlayer.state.IsInSession
    local function say(text, y)
        SetTextScale(0.3, 0.2)
        BgSetTextColor(255, 255, 255, 255)
        SetTextCentre(true)
        SetTextDropshadow(1, 0, 0, 0, 255)
        Citizen.InvokeNative(0xADA9255D, 10)
        BgDisplayText(VarString(10, 'LITERAL_STRING', text, Citizen.ResultAsLong()), 0.25, y)
    end
    local function turn(dh, dr)
        standHeading, standRoll = standHeading + dh, standRoll + dr
        SetEntityRotation(stand, standRoll % 360, 0, standHeading % 360, 1, true)
    end
    local pressed = function(key) return Citizen.InvokeNative(0x580417101DDB492F, 0, key) end

    while true do
        local wait = 1000
        if standTurned then
            wait = 0
            say(L.rotateitem1, 0.74); say(L.rotateitem2, 0.76); say(L.rotateitem3, 0.78); say(L.rotateitem4, 0.80)
            HasStreamedTextureDictLoaded('menu_textures')
            DrawSprite('menu_textures', 'translate_bg_1a', 0.25, 0.78, 0.14, 0.12, 1.8, 0, 0, 0, 255, true)
            if pressed(Cfg.keys['1']) then turn(10, 0) end
            if pressed(Cfg.keys['2']) then turn(-10, 0) end
            if pressed(Cfg.keys['3']) then turn(0, -20) end
            if pressed(Cfg.keys['4']) then turn(0, 20) end
        end
        Wait(wait)
    end
end)

-- ------------------------------------------------------------------ stations

local function nearStation(spots, radius)
    local here = GetEntityCoords(PlayerPedId())
    for _, spot in pairs(spots) do
        if #(here - vec3(spot.Pos.x, spot.Pos.y, spot.Pos.z)) < radius then return spot end
    end
end

-- does the player's job and grade let them use a station?
local function allowed(minGrade)
    if not Cfg.jobonly then return true end
    local result = Core.Callback.TriggerAwait('jrs_weapons:getjob')
    return listHas(Cfg.job, result[1]) and (tonumber(result[2]) or 0) >= minGrade
end

local function openCustomization(spot)
    if not allowed(Cfg.jobrankcustomization) then
        return TriggerEvent('jrs:TipBottom', L.wrongjobcuztom, 4000)
    end

    local other, away = nearestOtherPlayer()
    if other and away <= 2.0 then return TriggerEvent('jrs:TipBottom', L.tooclose, 4000) end

    local ped = PlayerPedId()
    local _, held = GetCurrentPedWeapon(ped, true, 0, true)
    local entity = GetCurrentPedWeaponEntityIndex(ped, 0)
    if weaponId == nil or weaponHash ~= held or not entity or entity == 0 then
        return TriggerEvent('jrs:TipBottom', L.pleaserequip, 4000)
    end

    loadPartsOfHeldWeapon()
    Wait(1000)
    WarMenu.OpenMenu('wepcomp')
    TaskStandStill(ped, -1)
    spawnStand(spot.Pos2, weaponHash)
end

CreateThread(function()
    repeat Wait(1000) until LocalPlayer.state.IsInSession

    prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, Cfg.keys['G'])
    UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', 'Press'))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    UiPromptSetStandardMode(prompt, true)
    UiPromptSetGroup(prompt, promptGroup, 0)
    UiPromptRegisterEnd(prompt)

    while true do
        local wait = 1000
        if not standTurned and not crafting then
            local custom = nearStation(Cfg.customizationLocations, 1.0)
            local craft = not custom and nearStation(Cfg.craftinglocation, 1.0)
            if custom or craft then
                wait = 0
                UiPromptSetActiveGroupThisFrame(promptGroup, VarString(10, 'LITERAL_STRING', custom and L.presstobuy or L.presstocraft), 0, 0, 0, 0)
                if Citizen.InvokeNative(0xC92AC953F0A982AE, prompt) then
                    if custom then
                        openCustomization(custom)
                    elseif allowed(Cfg.jobrankcrafting) then
                        crafting = true
                        WarMenu.OpenMenu('crafting')
                    else
                        Core.NotifyObjective(L.wrongjobcrafting, 5000)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ------------------------------------------------------------------ server -> client

-- the server hands over the parts saved for the weapon that was just equipped
RegisterNetEvent('jrs_weapons:givecomp', function(components, id, hash)
    weaponHash, weaponId, picked = hash, id, components
    loadPartsOfHeldWeapon()
    local ped = PlayerPedId()
    for _, p in ipairs(parts) do takeComponent(ped, p.name, weaponHash) end
    Wait(500)
    for _, p in ipairs(components) do
        withModel(p, function() giveComponent(ped, p.name, weaponHash, true) end)
    end
end)

-- a purchase went through: put the parts on the real weapon
RegisterNetEvent('jrs_weapons:applymods', function()
    local ped = PlayerPedId()
    local heading = GetHeadingFromVector_2d(GetEntityCoords(stand, true).x - GetEntityCoords(ped, true).x,
                                            GetEntityCoords(stand, true).y - GetEntityCoords(ped, true).y)
    SetEntityHeading(ped, heading)
    work(Cfg.customizationanimation, L.customloading)

    TriggerServerEvent('jrs_weapons:addcomp', weaponId, picked)
    ped = PlayerPedId()
    for _, p in ipairs(parts) do takeComponent(ped, p.name, weaponHash) end
    for _, p in ipairs(picked) do
        withModel(p, function() giveComponent(ped, p.name, weaponHash, true) end)
    end
    resetBench()
end)

RegisterNetEvent('jrs_weapons:nomods', resetBench)

RegisterNetEvent('jrs_weapons:itemcheckpassed', function()
    work('WORLD_HUMAN_CROUCH_INSPECT', L.craftingloading)
    resetCraft()
end)

RegisterNetEvent('jrs_weapons:itemcheckpassed2', function()
    work(Cfg.craftinganimations, L.craftingloading)
    resetCraft()
end)

RegisterNetEvent('jrs_weapons:itemcheckfailed', resetCraft)

RegisterNetEvent('jrs_weapons:wepcomp', loadPartsOfHeldWeapon)

-- ------------------------------------------------------------------ the menus

-- every customization page that lists the parts of one slot
-- comp/type pick the parts, `next` is the page the menu returns to after a choice, `remove` says whether
-- the page has a "remove" row
local slotPages = {
    other        = { comp = 'comp', type = 'other',  next = 'comp', remove = true },
    wrap         = { comp = 'comp', type = 'wrap',   next = 'comp', remove = true },
    scope        = { comp = 'comp', type = 'scope',  next = 'comp', remove = true },
    rifling      = { comp = 'comp', type = 'rifling', next = 'comp', remove = true },
    barrel2      = { comp = 'decalcolor', type = 'barrel',   remove = true },
    frame2       = { comp = 'decalcolor', type = 'frame',    remove = true },
    cylinder2    = { comp = 'decalcolor', type = 'cylinder', remove = true },
    decalbarrel  = { comp = 'decal', type = 'barrel',   remove = true },
    decalframe   = { comp = 'decal', type = 'frame',    remove = true },
    decalcylinder = { comp = 'decal', type = 'cylinder', remove = true },
    grip         = { comp = 'grip',       remove = true, anyType = true },
    scopecolor   = { comp = 'scope',      remove = true, anyType = true },
    wrapcolor    = { comp = 'wrapcolor',  remove = true, anyType = true },
    gripbody     = { comp = 'gripbody',   remove = false, anyType = true },
    cylinder     = { comp = 'cylinder',   remove = true, anyType = true },
    frontsight   = { comp = 'frontsight', remove = true, anyType = true },
    frame        = { comp = 'frame',      remove = true, anyType = true },
    trigger      = { comp = 'trigger',    remove = true, anyType = true },
    variant      = { comp = 'variant',    remove = true, anyType = true },
    barrel       = { comp = 'barrel',     remove = true, anyType = true },
}

local function fits(def, part)
    return part.confirmed == 1 and part.comp == def.comp and (def.anyType or part.type == def.type)
end

local function slotPage(def)
    return function()
        if def.remove and WarMenu.Button(L.remove) then
            clear(function(p) return p.comp == def.comp and (def.anyType or p.type == def.type) end)
        end
        for _, part in ipairs(parts) do
            if fits(def, part) then
                local text = L.label .. part.label .. L.price .. part.price .. L.dollar
                local chosen
                if def.next then chosen = WarMenu.MenuButton(text, def.next) else chosen = WarMenu.Button(text) end
                if chosen then choose(part) end
            end
        end
    end
end

-- a page that only links to other pages; a link shows when its condition holds
local function linkPage(links)
    return function()
        for _, link in ipairs(links) do
            if not link.when or link.when() then WarMenu.MenuButton(link.text, link.page) end
        end
    end
end

local pages = {}

pages.wepcomp = function()
    WarMenu.MenuButton(L.customization, 'confirmed')
    WarMenu.Button(L.total .. totalPrice() .. L.dollar)
    WarMenu.MenuButton(L.buyselect, 'confirmbuy')
    WarMenu.MenuButton(L.exitmenu, 'confirmexit')
end

pages.confirmed = linkPage({
    { text = L.variant,    page = 'variant',    when = function() return hasPart(parts, 'variant', nil) end },
    { text = L.comps,      page = 'comp' },
    { text = L.barrel,     page = 'barrel',     when = function() return hasPart(parts, 'barrel', nil) end },
    { text = L.trigger,    page = 'trigger',    when = function() return hasPart(parts, 'trigger', nil) end },
    { text = L.frame,      page = 'frame',      when = function() return hasPart(parts, 'frame', nil) end },
    { text = L.frontsight, page = 'frontsight', when = function() return hasPart(parts, 'frontsight', nil) end },
    { text = L.cylinder,   page = 'cylinder',   when = function() return hasPart(parts, 'cylinder', nil) end },
    { text = L.gripbody,   page = 'gripbody',   when = function() return hasPart(parts, 'gripbody', nil) end },
    { text = L.grip,       page = 'grip',       when = function() return hasPart(parts, 'grip', nil) end },
    { text = L.decal,      page = 'decal',      when = function() return hasComp(parts, 'decal') end },
    { text = L.decalcolor, page = 'decalcolor', when = function() return hasComp(parts, 'decalcolor') and hasComp(picked, 'decal') end },
    { text = L.scopecolor, page = 'scopecolor' },
    { text = L.wrapcolor,  page = 'wrapcolor',  when = function() return hasPart(picked, 'comp', 'wrap') end },
})

pages.comp = linkPage({
    { text = L.sights,  page = 'scope',   when = function() return hasPart(parts, 'comp', 'scope') end },
    { text = L.rifling, page = 'rifling', when = function() return hasPart(parts, 'comp', 'rifling') end },
    { text = L.other,   page = 'other',   when = function() return hasPart(parts, 'comp', 'other') end },
    { text = L.wrap,    page = 'wrap',    when = function() return hasPart(parts, 'comp', 'wrap') end },
})

local function decalLinks(parent, pageFor, needsPicked)
    local links = {}
    for _, kind in ipairs({ 'cylinder', 'frame', 'barrel' }) do
        links[#links + 1] = {
            text = L[pageFor[kind][1]], page = pageFor[kind][2],
            when = function()
                return hasPart(parts, parent, kind) and (not needsPicked or hasPart(picked, 'decal', kind))
            end,
        }
    end
    return linkPage(links)
end

pages.decal = decalLinks('decal', { cylinder = { 'decalcylinder', 'decalcylinder' }, frame = { 'decalframe', 'decalframe' }, barrel = { 'decalbarrel', 'decalbarrel' } })
pages.decalcolor = decalLinks('decalcolor', { cylinder = { 'cylinder2', 'cylinder2' }, frame = { 'frame2', 'frame2' }, barrel = { 'barrel2', 'barrel2' } }, true)

for id, def in pairs(slotPages) do pages[id] = slotPage(def) end

-- leaving and buying
local function yesNo(onYes, backTo)
    return function()
        if WarMenu.Button(L.yes) then onYes() end
        WarMenu.MenuButton(L.no, backTo)
    end
end

pages.confirmbuy = yesNo(function()
    TriggerServerEvent('jrs_weapons:checkmoney', totalPrice(), weaponId, picked)
    WarMenu.CloseMenu()
    Wait(500)
end, 'wepcomp')

pages.confirmexit = yesNo(function()
    resetBench()
    WarMenu.CloseMenu()
end, 'wepcomp')

pages.confirmexit2 = yesNo(function()
    resetCraft()
    WarMenu.CloseMenu()
end, 'crafting')

-- crafting: the same three pages for guns and for ammo
pages.crafting = function()
    WarMenu.MenuButton(L.weaponcrafting, 'wepcraft')
    WarMenu.MenuButton(L.ammocrafting, 'ammocraft')
    WarMenu.MenuButton(L.exitmenu, 'confirmexit2')
end

local recipeBooks = {
    wepcraft  = { book = Config.weapons, list = 'wepcraft2',  detail = 'wepcraft3',  event = 'jrs_weapons:itemscheck2' },
    ammocraft = { book = Config.ammo,    list = 'ammocraft2', detail = 'ammocraft3', event = 'jrs_weapons:itemscheck' },
}

local function visibleRecipe(recipe)
    if not recipe.letcraft then return false end
    if not recipe.jobonly then return true end
    return listHas(recipe.jobs, crafterJob)
end

for categoryPage, kind in pairs(recipeBooks) do
    pages[categoryPage] = function()
        for category in pairs(kind.book) do
            if WarMenu.MenuButton(category, kind.list) then craftCategory = category end
        end
    end

    pages[kind.list] = function()
        if not crafterJob then crafterJob = Core.Callback.TriggerAwait('jrs_weapons:getjob')[1] end
        for name, recipe in pairs(kind.book[craftCategory] or {}) do
            if visibleRecipe(recipe) and WarMenu.MenuButton(name, kind.detail) then craftName = name end
        end
    end

    pages[kind.detail] = function()
        if WarMenu.Button(L.craft) then
            TriggerServerEvent(kind.event, craftCategory, craftName)
            WarMenu.CloseMenu()
            crafterJob = nil
        end
        local recipe = (kind.book[craftCategory] or {})[craftName]
        if not recipe then return end
        if Cfg.craftingcost then WarMenu.Button(L.craftcost .. recipe.craftcost .. '$') end
        for _, material in pairs(recipe.materials) do
            WarMenu.Button(material.name .. ' / ' .. L.count .. material.amount)
        end
    end
end

-- menu registration and the draw loop
CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession

    WarMenu.CreateMenu('wepcomp', L.customization)
    WarMenu.CreateMenu('crafting', L.crafting)

    local children = {
        crafting = { wepcraft = L.weaponcrafting, wepcraft2 = L.weaponcrafting, wepcraft3 = L.weaponcrafting,
                     ammocraft = L.ammocrafting, ammocraft2 = L.ammocrafting, ammocraft3 = L.ammocrafting, confirmexit2 = L.areusureexit },
        wepcomp = { confirmed = L.customization, comp = L.comps, confirmexit = L.areusureexit, confirmbuy = L.buyselect,
                    decal = L.decal, decalcolor = L.decalcolor },
    }
    for parent, subs in pairs(children) do
        for id, title in pairs(subs) do WarMenu.CreateSubMenu(id, parent, title) end
    end
    local slotTitles = {
        scope = L.sights, rifling = L.rifling, other = L.other, scopecolor = L.scopecolor, wrap = L.wrap, wrapcolor = L.wrapcolor,
        barrel = L.barrel, trigger = L.trigger, variant = L.variant, frame = L.frame, frontsight = L.frontsight, cylinder = L.cylinder,
        gripbody = L.gripbody, grip = L.grip, decalcylinder = L.decalcylinder, decalframe = L.decalframe, decalbarrel = L.decalbarrel,
        cylinder2 = L.cylinder2, frame2 = L.frame2, barrel2 = L.barrel2,
    }
    for id, title in pairs(slotTitles) do WarMenu.CreateSubMenu(id, 'wepcomp', title) end

    while true do
        for id, draw in pairs(pages) do
            if WarMenu.IsMenuOpened(id) then
                draw()
                break
            end
        end
        WarMenu.Display()
        Wait(0)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    FreezeEntityPosition(PlayerPedId(), false)
    if prompt then UiPromptDelete(prompt) end
    if standTurned and stand then DeleteEntity(stand) end
end)
