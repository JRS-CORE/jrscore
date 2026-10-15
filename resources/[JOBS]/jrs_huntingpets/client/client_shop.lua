-- jrs_huntingpets: Shop Client (rewritten)
local SpawnedPetshopBlips = {}

-- ═══════════════════════════════════════════════════════════
-- SHARED STATE
-- ═══════════════════════════════════════════════════════════
ActivePetType = nil  -- 'dog' or 'bird' or nil

function HasActivePet()
    return ActivePetType ~= nil
end

-- ═══════════════════════════════════════════════════════════
-- NOTIFICATION HELPER (the JRS kit)
-- ═══════════════════════════════════════════════════════════
local TypeMap = {
    ERROR = 'error',
    SUCCESS = 'success',
    TIP = 'inform',
    WARNING = 'warning',
}

function Notify(title, message, template, duration)
    local notifyType = TypeMap[template] or (template and template:lower()) or 'inform'
    JRS.NotifyT({
        title = title,
        description = message,
        duration = duration or 5000,
        type = notifyType,
    })
end

-- ═══════════════════════════════════════════════════════════
-- NUI LOCALE BUNDLE
-- Every static/generated string the NUI (html/script.js) needs, resolved
-- through the JRS kit's L() so the shop UI follows the server's language
-- (set via the 'ox:locale' convar) instead of being hardcoded in English.
-- ═══════════════════════════════════════════════════════════
local UiLocaleKeys = {
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

local CachedUiLocale = nil
function GetUiLocale()
    if CachedUiLocale then return CachedUiLocale end
    local bundle = {}
    for _, key in ipairs(UiLocaleKeys) do
        bundle[key] = L(key)
    end
    CachedUiLocale = bundle
    return bundle
end

-- ═══════════════════════════════════════════════════════════
-- MODEL NAME + IMAGE MAPS (for My Pets tab in NUI)
-- ═══════════════════════════════════════════════════════════
local ModelNames = {}

-- Build name/image maps from config
local function BuildModelMaps()
    -- Dogs
    for _, dog in ipairs(Config.Dogs) do
        local model = dog.Param.Model
        local name = dog.Name or dog.Text:gsub('%$%d+ %- ', '')
        ModelNames[model] = name
        ModelNames[model .. '_img'] = dog.img
    end
    -- Birds (from Config.Birds categories/variants)
    for _, category in ipairs(Config.Birds) do
        for _, variant in ipairs(category.variants) do
            local model = tostring(variant.model)
            ModelNames[model] = variant.name
            local imgFile = variant.image or 'missing.png'
            if imgFile:find('/') then imgFile = imgFile:match('[^/]+$') end
            ModelNames[model .. '_img'] = imgFile
        end
    end
end
BuildModelMaps()

-- ═══════════════════════════════════════════════════════════
-- OPEN SHOP
-- ═══════════════════════════════════════════════════════════
local function IsShopOpen()
    if Config.AlwaysOpen then return true end
    local hour = GetClockHours()
    return hour >= Config.OpenTime and hour < Config.CloseTime
end

local function OpenShop()
    if not IsShopOpen() then
        Notify(L('notif_title_pets'), L('notif_shop_closed', Config.OpenTime), 'ERROR')
        return
    end

    JRS.TriggerCallback('jrs_huntingpets:server:getShopData', function(data)
        if not data then return end

        -- Build shop dog list
        local dogs = {}
        for _, dog in ipairs(Config.Dogs) do
            dogs[#dogs + 1] = {
                name = dog.Name or dog.Text:gsub('%$%d+ %- ', ''),
                desc = dog.Desc,
                img = dog.img,
                model = dog.Param.Model,
                price = dog.Param.Price,
            }
        end

        -- Build shop bird list
        local birds = {}
        local birdCategories = {}
        local catMap = {}
        for _, category in ipairs(Config.Birds) do
            if not catMap[category.name] then
                catMap[category.name] = true
                birdCategories[#birdCategories + 1] = category.name
            end
            for _, variant in ipairs(category.variants) do
                local imgFile = variant.image or 'missing.png'
                if imgFile:find('/') then imgFile = imgFile:match('[^/]+$') end
                birds[#birds + 1] = {
                    name = variant.name,
                    category = category.name,
                    img = imgFile,
                    price = variant.price,
                    type = variant.type,
                    desc = L('birdtypedesc_' .. tostring(variant.type):lower()),
                    model = tostring(variant.model),
                    preset = variant.preset,
                }
            end
        end

        -- Active pet name
        local activePet = 'None'
        if ActivePetType == 'dog' then activePet = 'Dog (Active)'
        elseif ActivePetType == 'bird' then activePet = 'Bird (Active)' end

        -- Build scavenger/fish info for Pet Info tab
        local scavengerItems = {}
        for _, v in ipairs(Config.ScavengerItems) do
            scavengerItems[#scavengerItems + 1] = { name = v.name, xp = v.xp, xpreq = v.xpreq }
        end
        local fishItems = {}
        for _, v in ipairs(Config.FishItems) do
            -- FishItems use model hash, convert to string name
            local modelStr = tostring(v.model)
            fishItems[#fishItems + 1] = { name = modelStr, xp = v.xp, xpreq = v.xpreq }
        end

        SendNUIMessage({
            action = 'open',
            dogs = dogs,
            birds = birds,
            birdCategories = birdCategories,
            ownedDogs = data.ownedDogs or {},
            ownedBirds = data.ownedBirds or {},
            activePet = activePet,
            modelNames = ModelNames,
            scavengerItems = scavengerItems,
            fishItems = fishItems,
            selectedDog = data.selectedDog,
            selectedBird = data.selectedBird,
            ui = GetUiLocale(),
        })
        SetNuiFocus(true, true)
    end)
end

-- ═══════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Call dog (from My Pets tab)
RegisterNUICallback('callDog', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
    if HasActivePet() then
        Notify(L('notif_title_pets'), L('notif_send_pet_home_first'), 'ERROR')
        return
    end
    TriggerServerEvent('jrs_huntingpets:server:callDog', data.id)
end)

-- Call bird (from My Pets tab)
RegisterNUICallback('callBird', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
    if HasActivePet() then
        Notify(L('notif_title_pets'), L('notif_send_pet_home_first'), 'ERROR')
        return
    end
    TriggerServerEvent('jrs_huntingpets:server:callBird', data.id)
end)

-- Sell dog (from My Pets tab)
RegisterNUICallback('sellDog', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
    TriggerServerEvent('jrs_huntingpets:server:sellDog', data.id)
end)

-- Sell bird (from My Pets tab)
RegisterNUICallback('sellBird', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
    TriggerServerEvent('jrs_huntingpets:server:sellBird', data.id)
end)

-- Select dog (from My Pets tab). Waits for the server to confirm ownership
-- and save the selection before telling the NUI whether it succeeded, so
-- the "Selected" state it shows always matches what's actually saved.
RegisterNUICallback('selectDog', function(data, cb)
    JRS.TriggerCallback('jrs_huntingpets:server:selectDog', function(success)
        cb({ success = success == true })
    end, data.id)
end)

-- Select bird (from My Pets tab)
RegisterNUICallback('selectBird', function(data, cb)
    JRS.TriggerCallback('jrs_huntingpets:server:selectBird', function(success)
        cb({ success = success == true })
    end, data.id)
end)

-- Buy pet (from NUI shop). The price shown in the NUI is cosmetic only —
-- the server always looks up the real price from Config itself.
RegisterNUICallback('buyPet', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
    if data.category == 'dogs' then
        TriggerServerEvent('jrs_huntingpets:server:buyDog', data.model)
    else
        local preset = tonumber(data.preset) or 0
        TriggerServerEvent('jrs_huntingpets:server:buyBird', data.model, preset)
    end
    SendNUIMessage({ action = 'close' })
end)

-- Get pet data (for my pets menu)
RegisterNUICallback('getPetData', function(data, cb)
    JRS.TriggerCallback('jrs_huntingpets:server:getPetData', function(petData)
        cb(petData)
    end, data.index)
end)

-- Show pet (spawn/despawn)
RegisterNUICallback('showPet', function(data, cb)
    cb('ok')
    if data.pet then
        -- Pet exists, show it
        if data.pet.type == 'dog' then
            TriggerServerEvent('jrs_huntingpets:server:callDog', data.pet.id)
        else
            TriggerServerEvent('jrs_huntingpets:server:callBird', data.pet.id)
        end
    end
end)

-- Spawn pet
RegisterNUICallback('spawnPet', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
    if HasActivePet() then
        Notify(L('notif_title_pets'), L('notif_send_pet_home_first'), 'ERROR')
        return
    end
    if data.pet.type == 'dog' then
        TriggerServerEvent('jrs_huntingpets:server:callDog', data.pet.id)
    else
        TriggerServerEvent('jrs_huntingpets:server:callBird', data.pet.id)
    end
end)

-- Follow (set follow distance)
RegisterNUICallback('follow', function(data, cb)
    cb('ok')
    if data.followDistance then
        Config.DogPetAttributes.FollowDistance = data.followDistance
    end
end)

-- Transfer pet
RegisterNUICallback('transferPet', function(data, cb)
    cb('ok')
    -- Transfer functionality - would need server support
    Notify(L('notif_title_pets'), L('notif_transfer_not_implemented'), 'TIP')
end)

-- Feed pet
RegisterNUICallback('feedPet', function(data, cb)
    cb('ok')
    -- This is handled by the dog/bird feeding prompts
end)

-- Get commands
RegisterNUICallback('getCommands', function(data, cb)
    local commands = {}
    cb(commands)
end)

-- Get animations
RegisterNUICallback('getAnimations', function(data, cb)
    local animations = {}
    cb(animations)
end)

-- Start animation
RegisterNUICallback('startanim', function(data, cb)
    cb('ok')
    TriggerEvent('jrs_huntingpets:client:dogAnimations')
end)

-- Do command
RegisterNUICallback('docommand', function(data, cb)
    cb('ok')
end)

-- Update money display
RegisterNUICallback('getMoney', function(data, cb)
    local me = JRS.Me(true) or {}
    cb({
        cash = me.money or 0,
        gold = me.gold or 0
    })
end)

-- ═══════════════════════════════════════════════════════════
-- BLIPS
-- ═══════════════════════════════════════════════════════════
Citizen.CreateThread(function()
    for _, shop in ipairs(Config.Shops) do
        if shop.showblip then
            local blip = BlipAddForCoords(1664425300, shop.Coords)
            SetBlipSprite(blip, Config.Blip.blipSprite, true)
            SetBlipScale(blip, Config.Blip.blipScale)
            SetBlipName(blip, Config.Blip.blipName)
            table.insert(SpawnedPetshopBlips, blip)
        end
    end
end)

local function UpdateBlipColours()
    local isOpen = IsShopOpen()
    for _, blip in pairs(SpawnedPetshopBlips) do
        BlipAddModifier(blip, isOpen and joaat('BLIP_MODIFIER_MP_COLOR_8') or joaat('BLIP_MODIFIER_MP_COLOR_2'))
    end
end

RegisterNetEvent('jrs:SelectedCharacter', function() UpdateBlipColours() end)
CreateThread(function() while true do UpdateBlipColours() Wait(60000) end end)

-- ═══════════════════════════════════════════════════════════
-- EVENTS
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('jrs_huntingpets:client:openShop', function()
    OpenShop()
end)

-- Bird sold from server
RegisterNetEvent('jrs_huntingpets:client:birdSold', function()
    if ActivePetType == 'bird' then
        -- Send bird home if it's the active one
        if CalledBird ~= nil then SendBirdHome(1) end
        ActivePetType = nil
    end
end)

-- ═══════════════════════════════════════════════════════════
-- CLEANUP ON RESOURCE RESTART
-- ═══════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
end)
