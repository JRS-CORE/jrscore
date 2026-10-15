-- JRS Core Free - simple tailor
-- Pick a piece per category and its colour, pay, done.

local MenuCategories = {
    male = {
        order = { "head", "upper", "lower", "feets", "accs", "weapons" },
        head = { "hats", "masks", "eyewear", "headwear", "face_props", "hat_accessories", "masks_large" },
        upper = {
            "coats", "shirts_full", "lduvmjua_0x2b388a05", "vests", "suspenders", "unionsuits_full",
            "overalls_full", "shirts_full_overpants", "cloaks", "overalls_modular_uppers", "coats_closed",
            "outfits", "coats_heavy", "ponchos",
        },
        lower = { "pants", "overalls_modular_lowers", "dresses", "skirts", "unionsuit_legs" },
        feets = { "boots", "boot_accessories", "spats" },
        accs = {
            "neckerchiefs", "neckties", "gloves", "belts", "accessories", "badges", "satchels", "neckwear",
            "jewelry_necklaces", "jewelry_rings", "vest_accessories", "hair_accessories", "aprons",
            "coat_accessories", "chaps", "pants_accessories", "armor", "jewelry_bracelets", "wrist_bindings",
            "gauntlets", "ankle_bindings", "belt_buckles", "jewelry_rings_right", "jewelry_rings_left",
            "satchel_straps", "jewelry_earrings",
        },
        weapons = {
            "gunbelts", "holsters_right", "holsters_knife", "loadouts", "holsters_left", "holsters_crossdraw",
            "holsters_center", "gunbelt_accs", "holsters_quivers", "ammo_pistols",
        },
    },
    female = {
        order = { "head", "upper", "lower", "feets", "accs", "weapons" },
        head = { "hats", "headwear", "hair_accessories", "masks", "eyewear", "hat_accessories", "face_props" },
        upper = {
            "shirts_full", "lduvmjua_0x2b388a05", "nbtudvja_0x53b67599", "coats", "vests", "suspenders",
            "coats_closed", "overalls_full", "ponchos", "capes", "shawls", "cloaks", "corsets", "chemises",
            "outfits", "cnvfyaba_0xd7ae0d03", "gjrbmoma_0xcb39a6f4", "pnyvpusa_0x44f4c713", "ogoolgaa_0xecd61654",
            "gnuusvra_0x7024af8b", "oacpqvda_0x41292b6f", "ywkywwvb_0xe93b9f1b",
        },
        lower = { "skirts", "pants", "dresses", "knickers", "stockings" },
        feets = { "boots", "boot_accessories", "spats" },
        accs = {
            "jewelry_necklaces", "gloves", "belts", "neckwear", "neckerchiefs", "neckties", "accessories",
            "jewelry_earrings", "jewelry_bracelets", "aprons", "gauntlets", "chaps", "satchels",
            "jewelry_rings_left", "wrist_bindings", "belt_buckles", "badges", "jewelry_rings_right",
            "ankle_bindings", "mbbwboia_0x42e8f927", "pants_accessories", "coat_accessories", "armor",
        },
        weapons = { "gunbelts", "loadouts", "holsters_right", "holsters_left", "holsters_center", "gunbelt_accs" },
    },
}

SelectedGender = "male"
local ShopOpen = false
local ShopBusy = false
local ShopOutfitId = 0
local promptKey = 0x760A9C6F -- G
local PromptGroup = GetHashKey('jrs_clothing:shopPromptGroup')
local shopPrompt = nil
local shopBlips = {}

-- MP items only (NPC clothes are not part of the free edition).
local function ItemList(cat)
    return GetAllowedClothingAssetIndices(SelectedGender, cat, "mp")
end

local function ColourList(cat, model)
    if (tonumber(model) or 0) <= 0 then return {} end
    return GetAllowedClothingVariantIndices(SelectedGender, cat, model)
end

local function CurrentVariant(cat)
    local data = ClothesCache[cat]
    if type(data) ~= "table" then return nil end
    if type(data.texture) == "table" then return tonumber(data.texture.palette) end
    return tonumber(data.texture)
end

local function RowFor(cat)
    local list = ItemList(cat)
    local model = type(ClothesCache[cat]) == "table" and tonumber(ClothesCache[cat].model) or 0
    local itemIndex = GetAllowedClothingAssetUiIndex(SelectedGender, cat, model, "mp")
    local colours = ColourList(cat, model)
    local colourIndex = 0
    if itemIndex > 0 then
        colourIndex = GetAllowedClothingVariantUiIndex(SelectedGender, cat, model, CurrentVariant(cat))
    end
    return {
        id = cat,
        label = ClothingLang.Label(cat),
        item = itemIndex,
        items = #list,
        colour = colourIndex,
        colours = itemIndex > 0 and #colours or 0,
    }
end

local function ShopPrice()
    local total = 0.0
    for cat, data in pairs(ClothesCache or {}) do
        if type(data) == "table" and cat ~= "bodies_upper" and cat ~= "bodies_lower" then
            local model = tonumber(data.model) or 0
            local old = type(OldClothesCache[cat]) == "table" and OldClothesCache[cat] or {}
            if model > 0 and (model ~= (tonumber(old.model) or 0) or CurrentVariant(cat) ~= (type(old.texture) == "table" and tonumber(old.texture.palette) or tonumber(old.texture))) then
                total = total + (tonumber(ClothingConfig.Price[cat]) or 0)
            end
        end
    end
    return math.floor(total * 100 + 0.5) / 100
end

local function SendRow(cat)
    SendClothingNUIMessage({ type = "row", row = RowFor(cat), price = ShopPrice() })
end

local function BuildMenu()
    local defs = MenuCategories[SelectedGender]
    local tabs = {}
    for _, key in ipairs(defs.order) do
        local rows = {}
        for _, cat in ipairs(defs[key] or {}) do
            if ClothingAssets[SelectedGender][cat] and #ItemList(cat) > 0 then
                rows[#rows + 1] = RowFor(cat)
            end
        end
        if #rows > 0 then
            tabs[#tabs + 1] = { id = key, label = ClothingLang.Label(key), rows = rows }
        end
    end
    return tabs
end

local function CanOpen()
    local ped = PlayerPedId()
    if ShopOpen or ShopBusy then return false end
    if IsEntityDead(ped) or IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) or IsPedCuffed(ped) then return false end
    return true
end

function OpenClothingShop()
    if not CanOpen() then return end
    ShopBusy = true
    local ped = PlayerPedId()
    SelectedGender = IsPedMale(ped) and "male" or "female"
    Callback.triggerServer('jrs_clothing:GetCurrentClothes', function(datatable, outfitId)
        ShopOutfitId = outfitId or 0
        ClothesCache = deepcopy(type(datatable) == "table" and datatable or {})
        for k, v in pairs(ClothesCache) do
            if type(v) == "table" and type(v.texture) == "table" and v.texture.model ~= nil then
                v.texture.palette = v.texture.model
                v.texture.model = nil
            end
        end
        for k in pairs(ClothingAssets[SelectedGender]) do
            if type(ClothesCache[k]) ~= "table" then ClothesCache[k] = { model = 0, texture = 0 } end
        end
        OldClothesCache = deepcopy(ClothesCache)
        ClothingSessionDirty = false

        ShopOpen = true
        ShopBusy = false
        CreatorLight = true
        OutfitMenuOpen = true
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, true)
        ClothingViewBaseHeading = GetEntityHeading(ped)
        ClothingMoveCam("Body")
        SendClothingNUIMessage({
            type = "open",
            tabs = BuildMenu(),
            price = 0,
            currency = (ClothingConfig.CurrencySymbol or "$"),
        })
        SetNuiFocus(true, true)
        PlaySound("INFO", "HUD_SHOP_SOUNDSET")
        CreateThread(IdleAnim)
    end)
end

local function CloseClothingShop(applySaved, saved)
    if not ShopOpen then return end
    ShopOpen = false
    CancelClothingEdits()
    SendClothingNUIMessage({ type = "close" })
    SetNuiFocus(false, false)
    PlaySound("INFO_HIDE", "HUD_SHOP_SOUNDSET")
    CreatorLight = false
    OutfitMenuOpen = false
    KillCamera()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    if applySaved and type(saved) == "table" then
        TriggerEvent("jrs_clothes:clotheitem", saved, ShopOutfitId, nil, nil, nil, true)
    elseif ClothingSessionDirty then
        local hadClothes = false
        for _, v in pairs(OldClothesCache or {}) do
            if type(v) == "table" and (tonumber(v.model) or 0) > 0 then hadClothes = true break end
        end
        if hadClothes then
            TriggerEvent("jrs_clothes:clotheitem", OldClothesCache, ShopOutfitId, nil, nil, nil, true)
        else
            ClothesCache = deepcopy(OldClothesCache)
            CreateThread(function() RemoveAllClothesExceptEssentials(ped) end)
        end
    end
end

RegisterNUICallback("clothing:item", function(body, cb)
    cb({ ok = true })
    if not ShopOpen or type(body) ~= "table" then return end
    local cat, index = tostring(body.category or ""), math.floor(tonumber(body.index) or 0)
    if type(ClothesCache[cat]) ~= "table" then return end
    local real = 0
    if index > 0 then
        real = ItemList(cat)[index]
        if not real then return end
    end
    QueueClothingEdit("model:" .. cat, function()
        Change(real, cat, "model")
        SendRow(cat)
    end)
    PlaySound("Amount_Increase", "HUD_Donate_Sounds")
end)

RegisterNUICallback("clothing:colour", function(body, cb)
    cb({ ok = true })
    if not ShopOpen or type(body) ~= "table" then return end
    local cat, index = tostring(body.category or ""), math.floor(tonumber(body.index) or 0)
    if type(ClothesCache[cat]) ~= "table" then return end
    QueueClothingEdit("var:" .. cat, function()
        local model = tonumber(ClothesCache[cat].model) or 0
        local variant = ColourList(cat, model)[index]
        if model <= 0 or not variant then return end
        Change(model, cat, "variants", variant)
        SendRow(cat)
    end)
    PlaySound("Amount_Increase", "HUD_Donate_Sounds")
end)

RegisterNUICallback("clothing:focus", function(body, cb)
    cb({ ok = true })
    if ShopOpen and type(body) == "table" then FocusClothingCameraCategory(body.category, body.group) end
end)

RegisterNUICallback("clothing:rotate", function(body, cb)
    cb({ ok = true })
    if ShopOpen and type(body) == "table" then
        HandleClothingViewControl({ action = body.dir == "left" and "rotateLeft" or "rotateRight" })
    end
end)

RegisterNUICallback("clothing:close", function(_, cb)
    cb({ ok = true })
    CloseClothingShop(false)
end)

RegisterNUICallback("clothing:buy", function(_, cb)
    if not ShopOpen or ShopBusy then cb({ ok = false }) return end
    ShopBusy = true
    WaitClothingEditsIdle(3000)
    local ped = PlayerPedId()
    local male = IsPedMale(ped) == true or IsPedMale(ped) == 1
    Callback.triggerServer('jrs_clothing:BuyClothes', function(ok, reason, saved)
        ShopBusy = false
        if ok then
            PlaySound("PURCHASE", "Ledger_Sounds")
            cb({ ok = true })
            CloseClothingShop(true, saved or ClothesCache)
            TriggerEvent('jrs_core:sendRightTipNotification', _U('clothing_outfit_saved'), 3500)
        else
            PlaySound("UNAFFORDABLE", "Ledger_Sounds")
            cb({ ok = false, reason = reason })
            local key = 'clothing_save_failed_' .. tostring(reason or '')
            local text = _U(key)
            if text == key then text = _U('clothing_save_failed_generic') end
            TriggerEvent('jrs_core:sendRightTipNotification', text, 4000)
        end
    end, ClothesCache, male)
end)

-- Prompt + blips -------------------------------------------------------------
local function ShopCoords(shop)
    local c = type(shop) == "table" and shop.shopCoords or shop
    return vector3(c.x, c.y, c.z)
end

CreateThread(function()
    if ClothingConfig.NativePrompt == false then return end
    shopPrompt = PromptRegisterBegin()
    PromptSetControlAction(shopPrompt, promptKey)
    PromptSetText(shopPrompt, CreateVarString(10, 'LITERAL_STRING', ClothingLang.Prompt.interact or "Open"))
    PromptSetEnabled(shopPrompt, true)
    PromptSetVisible(shopPrompt, true)
    PromptSetStandardMode(shopPrompt, true)
    PromptSetGroup(shopPrompt, PromptGroup)
    PromptRegisterEnd(shopPrompt)

    for name, shop in pairs(ClothingConfig.Shops or {}) do
        local c = ShopCoords(shop)
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, c.x, c.y, c.z)
        if blip and blip ~= 0 then
            SetBlipSprite(blip, 1195729388)
            SetBlipScale(blip, 0.2)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, tostring(name))
            shopBlips[#shopBlips + 1] = blip
        end
    end

    while true do
        local sleep = 750
        if not ShopOpen then
            local coords = GetEntityCoords(PlayerPedId())
            for name, shop in pairs(ClothingConfig.Shops or {}) do
                local dist = #(coords - ShopCoords(shop))
                if dist < 12.0 then sleep = 0 end
                if dist < 2.0 then
                    -- VarString must be created in the frame it is drawn.
                    PromptSetActiveGroupThisFrame(PromptGroup, CreateVarString(10, 'LITERAL_STRING', tostring(name)))
                    if IsControlJustPressed(0, promptKey) then
                        OpenClothingShop()
                        Wait(350)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

if ClothingConfig.MenuCommand then
    RegisterCommand(ClothingConfig.MenuCommand, function() OpenClothingShop() end, false)
end

RegisterNetEvent("jrs_clothing:open", OpenClothingShop)
RegisterNetEvent("jrs_clothing:OpenClothingMenu", OpenClothingShop)
RegisterNetEvent("jrs_clothes:OpenClothingMenu", OpenClothingShop)
exports('OpenClothing', function() OpenClothingShop() return true end)

-- Reload the saved clothes (used by jrs_character) -----------------------------
local function LoadSavedClothes()
    Callback.triggerServer('jrs_clothing:GetCurrentClothes', function(datatable, id)
        SelectedGender = IsPedMale(PlayerPedId()) and "male" or "female"
        if type(baseskin) ~= 'table' then baseskin = {} end
        local ped = PlayerPedId()
        if not baseskin.bodies_upper or baseskin.bodies_upper == 0 then
            baseskin.bodies_upper = GetComponentEquiped(ped, 'bodies_upper')
        end
        if not baseskin.bodies_lower or baseskin.bodies_lower == 0 then
            baseskin.bodies_lower = GetComponentEquiped(ped, 'bodies_lower')
        end
        if type(datatable) == "table" then
            for _, v in pairs(datatable) do
                if type(v) == "table" and (tonumber(v.model) or 0) > 0 then
                    TriggerEvent("jrs_clothes:clotheitem", datatable, id)
                    return
                end
            end
        end
    end)
end

RegisterNetEvent('jrs_clothing:loadclothes', LoadSavedClothes)
if ClothingConfig.LoadClothesCommand then
    RegisterCommand(ClothingConfig.LoadClothesCommand, LoadSavedClothes, false)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    for _, blip in ipairs(shopBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    if ShopOpen then
        KillCamera(true)
        ClearPedTasksImmediately(PlayerPedId())
        FreezeEntityPosition(PlayerPedId(), false)
    end
end)

-- jrs_character still calls this; body fitting is not part of the free edition.
exports('SmartBodyFitPed', function() return false end)
