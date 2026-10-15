-- JRS Core Free - simple barber
-- Hair / beard style + hair colour. Pay, done.

BarberBaseOverlay = BarberDeepcopy(BarberOverlayLayers)
BarberSelectedGender = "male"
BarberNuiActive = false

local Categories = {
    male = { "hair", "beard", "beards_complete", "beards_chin", "beards_chops", "beards_mustache" },
    female = { "hair", "hair_bonnet" },
}

local ShopOpen = false
local ShopBusy = false
local SatForSession = false     -- the barber session put the player in the chair
local OldHair = {}
local Headwear = {}
local Dirty = false
local promptKey = BarberConfig.PromptKey or 0x760A9C6F
local promptGroup = GetHashKey('jrs_barber:shopPromptGroup')
local promptHandle = nil
local blips = {}

-- MP styles only; NPC hair/beards are not part of the free edition.
local MpIndices = {}
local function BuildIndices()
    MpIndices = {}
    for _, gender in ipairs({ "male", "female" }) do
        MpIndices[gender] = {}
        for category, list in pairs(BarberAssets[gender] or {}) do
            local mp = {}
            for index, asset in ipairs(list) do
                local variants = type(asset.variants) == "table" and asset.variants or (asset.drawable == nil and asset) or {}
                for _, v in ipairs(variants) do
                    local p = v.ped and string.lower(tostring(v.ped)) or nil
                    if (p and (p:find("^mp_") or p:find("^cs_mp_"))) or v.is_multiplayer == true then
                        mp[#mp + 1] = index
                        break
                    end
                end
            end
            MpIndices[gender][category] = mp
        end
    end
end
BuildIndices()

local function Items(cat)
    return (MpIndices[BarberSelectedGender] or {})[cat] or {}
end

local function UiIndex(cat, real)
    real = tonumber(real) or 0
    if real <= 0 then return 0 end
    for ui, idx in ipairs(Items(cat)) do
        if idx == real then return ui end
    end
    return 0
end

local function CurrentTint(cat)
    local data = BarberHairCache[cat]
    if type(data) == "table" and type(data.texture) == "table" then return tonumber(data.texture.tint0) end
    return nil
end

local function ColourIndex(cat)
    local tint = CurrentTint(cat)
    if not tint then return 0 end
    for i, c in ipairs(BarberConfig.HairColours) do
        if c.tint == tint then return i end
    end
    return 0
end

local function RowFor(cat)
    local model = type(BarberHairCache[cat]) == "table" and tonumber(BarberHairCache[cat].model) or 0
    local item = UiIndex(cat, model)
    return {
        id = cat,
        label = BarberLang.Label(cat),
        item = item,
        items = #Items(cat),
        colour = item > 0 and ColourIndex(cat) or 0,
        colours = item > 0 and #BarberConfig.HairColours or 0,
        swatches = true,
    }
end

local function Price()
    local total = 0.0
    for cat, data in pairs(BarberHairCache or {}) do
        if type(data) == "table" then
            local model = tonumber(data.model) or 0
            local old = type(OldHair[cat]) == "table" and OldHair[cat] or {}
            local oldTint = type(old.texture) == "table" and tonumber(old.texture.tint0) or nil
            if model > 0 and (model ~= (tonumber(old.model) or 0) or CurrentTint(cat) ~= oldTint) then
                total = total + (tonumber(BarberConfig.Price[cat]) or 0)
            end
        end
    end
    return math.floor(total * 100 + 0.5) / 100
end

local function SendRow(cat)
    SendBarberNUIMessage({ type = "row", row = RowFor(cat), price = Price() })
end

local function CanOpen()
    local ped = PlayerPedId()
    if ShopOpen or ShopBusy then return false end
    if IsEntityDead(ped) or IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) or IsPedCuffed(ped) then return false end
    return true
end

function BarberSessionIsBusy() return ShopOpen or ShopBusy end

local function UiLanguage()
    if JrsLang and type(JrsLang.Current) == 'function' then
        local ok, code = pcall(JrsLang.Current)
        if ok and code then return tostring(code) end
    end
    return 'en'
end

function OpenBarberShop(shopCoords)
    if not CanOpen() then return end
    ShopBusy = true
    local ped = PlayerPedId()
    -- sit in the barber chair first (falls back to standing when no chair is found)
    SatForSession = false
    if BarberConfig.ChairAnimation ~= false and not BarberIsSeatActive() then
        SatForSession = BarberSit(shopCoords or GetEntityCoords(ped)) == true
    end
    BarberSelectedGender = IsPedMale(ped) and "male" or "female"
    Callback.triggerServer('jrs_barber:GetCurrentHairs', function(hair)
        local cache = type(hair) == "table" and BarberDeepcopy(hair) or {}
        if next(cache) == nil then
            local ok, captured = pcall(CaptureCurrentJRSBarber, ped)
            if ok and type(captured) == "table" then cache = captured end
        end
        for category in pairs(BarberAssets[BarberSelectedGender] or {}) do
            if type(cache[category]) ~= "table" then cache[category] = { model = 0, texture = 0 } end
        end
        BarberHairCache = cache
        OldHair = BarberDeepcopy(cache)
        Dirty = false

        Headwear = CaptureBarberHeadwear(ped) or {}
        RemoveAllBarber(ped, true)
        ReequipAllhairstyle(ped, BarberHairCache)

        local rows = {}
        for _, cat in ipairs(Categories[BarberSelectedGender]) do
            if #Items(cat) > 0 then rows[#rows + 1] = RowFor(cat) end
        end
        local swatches = {}
        for i, c in ipairs(BarberConfig.HairColours) do swatches[i] = { hex = c.hex } end

        ShopOpen = true
        ShopBusy = false
        BarberNuiActive = true
        BarberCreatorLight = true
        if not BarberIsSeatActive() then
            ClearPedTasks(ped)
            FreezeEntityPosition(ped, true)
        end
        BarberMoveCam("head")
        SendBarberNUIMessage({
            type = "open",
            tabs = { { id = "barber", label = "", rows = rows } },
            swatches = swatches,
            price = 0,
            currency = "$",
            language = UiLanguage(),
            prices = BarberConfig.Price,
        })
        SetNuiFocus(true, true)
        BarberPlaySound("INFO", "HUD_SHOP_SOUNDSET")
    end)
end

local function CloseBarberShop(keep)
    if not ShopOpen then return end
    ShopOpen = false
    BarberNuiActive = false
    BarberCreatorLight = false
    SendBarberNUIMessage({ type = "close" })
    SetNuiFocus(false, false)
    BarberPlaySound("INFO_HIDE", "HUD_SHOP_SOUNDSET")
    BarberKillCamera()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if SatForSession then
        SatForSession = false
        BarberStandUp(false)
    elseif not BarberIsSeatActive() then
        ClearPedTasks(ped)
    end
    CreateThread(function()
        if not keep and Dirty then
            BarberHairCache = BarberDeepcopy(OldHair)
            RemoveAllBarber(ped)
            ReequipAllhairstyle(ped, BarberHairCache)
        end
        RestoreBarberHeadwear(ped, Headwear or {})
        Headwear = {}
    end)
end

RegisterNUICallback("barber:item", function(body, cb)
    cb({ ok = true })
    if not ShopOpen or type(body) ~= "table" then return end
    local cat, index = tostring(body.category or ""), math.floor(tonumber(body.index) or 0)
    if type(BarberHairCache[cat]) ~= "table" then return end
    local real = 0
    if index > 0 then
        real = Items(cat)[index]
        if not real then return end
    end
    CreateThread(function()
        -- Keep the current hair colour when the style changes.
        local tint = CurrentTint(cat)
        BarberChange(real, cat, "model")
        if real > 0 and tint then BarberChange(real, cat, 1, tint) end
        Dirty = true
        SendRow(cat)
    end)
    BarberPlaySound("Amount_Increase", "HUD_Donate_Sounds")
end)

RegisterNUICallback("barber:colour", function(body, cb)
    cb({ ok = true })
    if not ShopOpen or type(body) ~= "table" then return end
    local cat, index = tostring(body.category or ""), math.floor(tonumber(body.index) or 0)
    local colour = BarberConfig.HairColours[index]
    local model = type(BarberHairCache[cat]) == "table" and tonumber(BarberHairCache[cat].model) or 0
    if not colour or model <= 0 then return end
    CreateThread(function()
        BarberChange(model, cat, 1, colour.tint)
        Dirty = true
        SendRow(cat)
    end)
    BarberPlaySound("Amount_Increase", "HUD_Donate_Sounds")
end)

RegisterNUICallback("barber:focus", function(_, cb) cb({ ok = true }) end)

RegisterNUICallback("barber:rotate", function(body, cb)
    cb({ ok = true })
    if ShopOpen and type(body) == "table" then
        HandleBarberViewControl({ action = body.dir == "left" and "rotateLeft" or "rotateRight" })
    end
end)

local ViewActions = { rotateLeft = true, rotateRight = true, zoomIn = true, zoomOut = true, reset = true }
RegisterNUICallback("barber:view", function(body, cb)
    cb({ ok = true })
    local action = type(body) == "table" and tostring(body.action or "") or ""
    if ShopOpen and ViewActions[action] then HandleBarberViewControl({ action = action }) end
end)

RegisterNUICallback("barber:close", function(_, cb)
    cb({ ok = true })
    CloseBarberShop(false)
end)

RegisterNUICallback("barber:buy", function(_, cb)
    if not ShopOpen or ShopBusy then cb({ ok = false }) return end
    ShopBusy = true
    Callback.triggerServer('jrs_barber:BuyHair', function(ok, reason)
        ShopBusy = false
        if ok then
            BarberPlaySound("PURCHASE", "Ledger_Sounds")
            cb({ ok = true })
            CloseBarberShop(true)
            TriggerEvent('jrs_core:sendRightTipNotification', _U('barber_saved'), 3500)
        else
            BarberPlaySound("UNAFFORDABLE", "Ledger_Sounds")
            cb({ ok = false, reason = reason })
            local key = 'barber_' .. tostring(reason or 'failed')
            local text = _U(key)
            if text == key then text = _U('barber_failed') end
            TriggerEvent('jrs_core:sendRightTipNotification', text, 4000)
        end
    end, BarberHairCache)
end)

-- Prompt + blips ---------------------------------------------------------------
CreateThread(function()
    promptHandle = PromptRegisterBegin()
    PromptSetControlAction(promptHandle, promptKey)
    -- prompts stay English: the game font has no Arabic glyphs
    PromptSetText(promptHandle, CreateVarString(10, 'LITERAL_STRING', BarberConfig.PromptText or Locales.en.barber_open_barber))
    PromptSetEnabled(promptHandle, true)
    PromptSetVisible(promptHandle, true)
    PromptSetStandardMode(promptHandle, true)
    PromptSetGroup(promptHandle, promptGroup)
    PromptRegisterEnd(promptHandle)

    for name, shop in pairs(BarberConfig.Shops or {}) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, shop.coords)
        if blip and blip ~= 0 then
            SetBlipSprite(blip, -2090472724)
            SetBlipScale(blip, 0.2)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, tostring(name))
            blips[#blips + 1] = blip
        end
    end

    while true do
        local sleep = 750
        if not ShopOpen and not ShopBusy and not BarberIsSeatActive() then
            local coords = GetEntityCoords(PlayerPedId())
            for name, shop in pairs(BarberConfig.Shops or {}) do
                local dist = #(coords - shop.coords)
                if dist < 12.0 then sleep = 0 end
                if dist < (BarberConfig.PromptDistance or 2.2) then
                    PromptSetActiveGroupThisFrame(promptGroup, CreateVarString(10, 'LITERAL_STRING', tostring(name)))
                    if IsControlJustPressed(0, promptKey) then
                        local at = shop.coords
                        CreateThread(function() OpenBarberShop(at) end)
                        Wait(800)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

if BarberConfig.MenuCommand then
    RegisterCommand(BarberConfig.MenuCommand, function() OpenBarberShop() end, false)
end
RegisterNetEvent('jrs_barber:open', OpenBarberShop)
RegisterNetEvent('jrs_barber:OpenBarberMenu', OpenBarberShop)
exports('OpenBarber', function() OpenBarberShop() return true end)
exports('IsBarberBusy', function() return ShopOpen or ShopBusy end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    if ShopOpen then
        BarberKillCamera()
        FreezeEntityPosition(PlayerPedId(), false)
        RestoreBarberHeadwear(PlayerPedId(), Headwear or {})
    end
    if SatForSession then BarberStandUp(true) end
end)
