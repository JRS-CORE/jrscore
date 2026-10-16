-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | client: the shop window (NUI), the blips and what the two pet scripts share

local blips = {}

-- 'dog', 'bird' or nil: which pet the player has out right now
ActivePetType = nil

function HasActivePet() return ActivePetType ~= nil end

-- ------------------------------------------------------------------ messages

local KINDS <const> = { ERROR = 'error', SUCCESS = 'success', TIP = 'inform', WARNING = 'warning' }

function Notify(title, message, template, duration)
    JRS.NotifyT({
        title = title, description = message, duration = duration or 5000,
        type = KINDS[template] or (template and template:lower()) or 'inform',
    })
end

-- ------------------------------------------------------------------ texts for the page

local UI_KEYS <const> = {
    'ui_back', 'ui_close', 'ui_header_title', 'ui_header_subtitle', 'ui_tab_shop', 'ui_tab_mypets',
    'ui_wallet_cash', 'ui_purchase_pet_title', 'ui_gold', 'ui_pet_name_label', 'ui_pet_name_placeholder',
    'ui_cancel', 'ui_buy', 'ui_animations_title', 'ui_put_dog_away', 'ui_commands_title',
    'ui_dogs_title', 'ui_dogs_desc', 'ui_birds_desc', 'ui_no_pets_available', 'ui_shelf_empty',
    'ui_no_pets_owned', 'ui_no_animations_available', 'ui_no_animations_for_pet', 'ui_no_commands_for_pet',
    'ui_type_dog', 'ui_type_bird', 'ui_type_xp', 'ui_hunting_dog', 'ui_hunting_bird', 'ui_dead',
    'ui_active', 'ui_select_pet', 'ui_selected', 'ui_condition_title', 'ui_health', 'ui_hunger', 'ui_thirst',
    'ui_actions_title', 'ui_call_flee', 'ui_call_pet', 'ui_feeding', 'ui_drinking', 'ui_carrying',
    'ui_commands', 'ui_follow_unfollow', 'ui_transfer', 'ui_follow_position_title', 'ui_forward',
    'ui_left', 'ui_right', 'ui_carry_anim', 'ui_take_shoulder', 'ui_please_select_pet',
    'ui_toast_success', 'ui_toast_error', 'ui_toast_notice', 'ui_dog_actions_title', 'ui_stop_animation',
}

local uiTexts
function GetUiLocale()
    if not uiTexts then
        uiTexts = {}
        for _, key in ipairs(UI_KEYS) do uiTexts[key] = L(key) end
    end
    return uiTexts
end

-- model -> display name, and model .. '_img' -> picture file, for the "My pets" tab
local names = {}

local function fileName(path)
    local image = path or 'missing.png'
    return image:find('/') and image:match('[^/]+$') or image
end

local function dogName(dog) return dog.Name or dog.Text:gsub('%$%d+ %- ', '') end

for _, dog in ipairs(Config.Dogs) do
    names[dog.Param.Model] = dogName(dog)
    names[dog.Param.Model .. '_img'] = dog.img
end
for _, category in ipairs(Config.Birds) do
    for _, variant in ipairs(category.variants) do
        local model = tostring(variant.model)
        names[model] = variant.name
        names[model .. '_img'] = fileName(variant.image)
    end
end

-- ------------------------------------------------------------------ opening the shop

local function isOpen()
    if Config.AlwaysOpen then return true end
    local hour = GetClockHours()
    return hour >= Config.OpenTime and hour < Config.CloseTime
end

local function shopDogs()
    local list = {}
    for _, dog in ipairs(Config.Dogs) do
        list[#list + 1] = { name = dogName(dog), desc = dog.Desc, img = dog.img, model = dog.Param.Model, price = dog.Param.Price }
    end
    return list
end

local function shopBirds()
    local list, categories, seen = {}, {}, {}
    for _, category in ipairs(Config.Birds) do
        if not seen[category.name] then
            seen[category.name] = true
            categories[#categories + 1] = category.name
        end
        for _, variant in ipairs(category.variants) do
            list[#list + 1] = {
                name = variant.name, category = category.name, img = fileName(variant.image), price = variant.price,
                type = variant.type, desc = L('birdtypedesc_' .. tostring(variant.type):lower()),
                model = tostring(variant.model), preset = variant.preset,
            }
        end
    end
    return list, categories
end

local function openShop()
    if not isOpen() then return Notify(L('notif_title_pets'), L('notif_shop_closed', Config.OpenTime), 'ERROR') end

    JRS.TriggerCallback('jrs_huntingpets:server:getShopData', function(data)
        if not data then return end

        local birds, categories = shopBirds()
        local scavenger, fish = {}, {}
        for _, v in ipairs(Config.ScavengerItems) do scavenger[#scavenger + 1] = { name = v.name, xp = v.xp, xpreq = v.xpreq } end
        for _, v in ipairs(Config.FishItems) do fish[#fish + 1] = { name = tostring(v.model), xp = v.xp, xpreq = v.xpreq } end

        SendNUIMessage({
            action = 'open',
            dogs = shopDogs(), birds = birds, birdCategories = categories,
            ownedDogs = data.ownedDogs or {}, ownedBirds = data.ownedBirds or {},
            activePet = ActivePetType == 'dog' and 'Dog (Active)' or ActivePetType == 'bird' and 'Bird (Active)' or 'None',
            modelNames = names, scavengerItems = scavenger, fishItems = fish,
            selectedDog = data.selectedDog, selectedBird = data.selectedBird, ui = GetUiLocale(),
        })
        SetNuiFocus(true, true)
    end)
end

RegisterNetEvent('jrs_huntingpets:client:openShop', openShop)

-- ------------------------------------------------------------------ page callbacks

-- an NUI callback that closes the window, answers, then runs `act(data)`
local function leaving(name, act)
    RegisterNUICallback(name, function(data, done)
        SetNuiFocus(false, false)
        done('ok')
        act(data)
    end)
end

RegisterNUICallback('close', function(_, done)
    SetNuiFocus(false, false)
    done('ok')
end)

-- bring a pet out (only one at a time)
local function summon(event)
    return function(data)
        if HasActivePet() then return Notify(L('notif_title_pets'), L('notif_send_pet_home_first'), 'ERROR') end
        TriggerServerEvent(event, data.id)
    end
end

leaving('callDog', summon('jrs_huntingpets:server:callDog'))
leaving('callBird', summon('jrs_huntingpets:server:callBird'))
leaving('sellDog', function(data) TriggerServerEvent('jrs_huntingpets:server:sellDog', data.id) end)
leaving('sellBird', function(data) TriggerServerEvent('jrs_huntingpets:server:sellBird', data.id) end)

leaving('spawnPet', function(data)
    if HasActivePet() then return Notify(L('notif_title_pets'), L('notif_send_pet_home_first'), 'ERROR') end
    TriggerServerEvent(data.pet.type == 'dog' and 'jrs_huntingpets:server:callDog' or 'jrs_huntingpets:server:callBird', data.pet.id)
end)

-- the price on the page is only decoration, the server uses the configured price
RegisterNUICallback('buyPet', function(data, done)
    SetNuiFocus(false, false)
    done('ok')
    if data.category == 'dogs' then
        TriggerServerEvent('jrs_huntingpets:server:buyDog', data.model)
    else
        TriggerServerEvent('jrs_huntingpets:server:buyBird', data.model, tonumber(data.preset) or 0)
    end
    SendNUIMessage({ action = 'close' })
end)

-- the page shows "selected" only after the server saved it
local function selecting(name, callback)
    RegisterNUICallback(name, function(data, done)
        JRS.TriggerCallback(callback, function(ok) done({ success = ok == true }) end, data.id)
    end)
end
selecting('selectDog', 'jrs_huntingpets:server:selectDog')
selecting('selectBird', 'jrs_huntingpets:server:selectBird')

RegisterNUICallback('getPetData', function(data, done)
    JRS.TriggerCallback('jrs_huntingpets:server:getPetData', function(info) done(info) end, data.index)
end)

RegisterNUICallback('showPet', function(data, done)
    done('ok')
    if data.pet then
        TriggerServerEvent(data.pet.type == 'dog' and 'jrs_huntingpets:server:callDog' or 'jrs_huntingpets:server:callBird', data.pet.id)
    end
end)

RegisterNUICallback('follow', function(data, done)
    done('ok')
    if data.followDistance then Config.DogPetAttributes.FollowDistance = data.followDistance end
end)

RegisterNUICallback('transferPet', function(_, done)
    done('ok')
    Notify(L('notif_title_pets'), L('notif_transfer_not_implemented'), 'TIP')
end)

RegisterNUICallback('startanim', function(_, done)
    done('ok')
    TriggerEvent('jrs_huntingpets:client:dogAnimations')
end)

-- panels the page asks for that have nothing to show yet
for _, name in ipairs({ 'feedPet', 'docommand' }) do RegisterNUICallback(name, function(_, done) done('ok') end) end
for _, name in ipairs({ 'getCommands', 'getAnimations' }) do RegisterNUICallback(name, function(_, done) done({}) end) end

RegisterNUICallback('getMoney', function(_, done)
    local me = JRS.Me(true) or {}
    done({ cash = me.money or 0, gold = me.gold or 0 })
end)

-- ------------------------------------------------------------------ blips

CreateThread(function()
    for _, shop in ipairs(Config.Shops) do
        if shop.showblip then
            local blip = BlipAddForCoords(1664425300, shop.Coords)
            SetBlipSprite(blip, Config.Blip.blipSprite, true)
            SetBlipScale(blip, Config.Blip.blipScale)
            SetBlipName(blip, Config.Blip.blipName)
            blips[#blips + 1] = blip
        end
    end
end)

local function colourBlips()
    local colour = joaat(isOpen() and 'BLIP_MODIFIER_MP_COLOR_8' or 'BLIP_MODIFIER_MP_COLOR_2')
    for _, blip in ipairs(blips) do BlipAddModifier(blip, colour) end
end

RegisterNetEvent('jrs:SelectedCharacter', colourBlips)
CreateThread(function()
    while true do
        colourBlips()
        Wait(60000)
    end
end)

-- the server sold the bird that is out: send it home
RegisterNetEvent('jrs_huntingpets:client:birdSold', function()
    if ActivePetType ~= 'bird' then return end
    if CalledBird ~= nil then SendBirdHome(1) end
    ActivePetType = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
end)
