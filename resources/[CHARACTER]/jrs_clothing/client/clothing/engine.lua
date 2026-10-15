OldClothesCache = {}
ClothesCache = {}


ComponentsMale = {}
ComponentsFemale = {}
local camConfig = nil
local IsWeaponClothingCategory, QueueWeaponClothingRepair
Citizen.CreateThread(function()
    for i, v in pairs(ComponentsBody) do
        if v.category_hashname == "BODIES_LOWER" or v.category_hashname == "BODIES_UPPER" or v.category_hashname ==
            "heads" or v.category_hashname == "hair" or v.category_hashname == "teeth" or v.category_hashname == "eyes" then
            if v.ped_type == "female" and v.is_multiplayer and v.hashname ~= "" then
                if ComponentsFemale[v.category_hashname] == nil then
                    ComponentsFemale[v.category_hashname] = {}
                end
                table.insert(ComponentsFemale[v.category_hashname], v.hash)
            elseif v.ped_type == "male" and v.is_multiplayer and v.hashname ~= "" then
                if ComponentsMale[v.category_hashname] == nil then
                    ComponentsMale[v.category_hashname] = {}
                end
                table.insert(ComponentsMale[v.category_hashname], v.hash)
            end
        end
    end
end)

function Change(id, category, change_type, value)
    id = tonumber(id)
    if not id or not category or not ClothesCache[category] then return false end
    local ped = PlayerPedId()
    local gender
    if IsPedMale(ped) then gender = "male" else gender = "female" end
    local categoryAssets = ClothingAssets[gender] and ClothingAssets[gender][category]
    if id > 0 and not IsClothingAssetAllowed(gender, category, id) then
        return false
    end
    if id < 1 then
        -- One removal per category hash and ONE commit. The old code also passed
        -- the raw Lua string and a nil/`true` "hex hash" to the native (garbage
        -- arguments), and for cloaks committed + waited three times in a row -
        -- a visible stutter/flicker of the whole ped while scrolling to "none".
        local toRemove = { category }
        if category == "cloaks" or category == "ponchos" or category == "capes" then
            toRemove = { "cloaks", "ponchos", "capes" }
        end
        for _, cat in ipairs(toRemove) do
            local catHash
            if cat == "beard" then
                catHash = 0xF8016BCA
            elseif cat == "hair" then
                catHash = 0x864B03AE
            else
                local hex = tostring(cat):match("^0x%x+$")
                catHash = hex and tonumber(hex) or joaat(cat)
            end
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, catHash, 0)
            if ClothesCache[cat] and cat ~= category then
                ClothesCache[cat].model = 0
                ClothesCache[cat].texture = 0
            end
        end
        NativeUpdatePedVariation(ped)
        ClothesCache[category].model = id
    else
        local asset = categoryAssets and categoryAssets[id]
        if change_type == "model" and not asset then return false end
        if change_type == "model" then
            ClothesCache[category].model = id
            if asset.drawable and asset.variants and asset.variants[1] then
                ClothesCache[category].texture = {}
                local firstVariantIndex = GetFirstAllowedClothingVariantIndex(gender, category, id) or 1
                local firstVariant = asset.variants[firstVariantIndex]
                if not firstVariant then return false end
                local tint = firstVariant.tint or { 0, 0, 0 }
                local drawable = asset.drawable
                local albedo = firstVariant.albedo
                local normal = firstVariant.normal
                local material = firstVariant.material
                local palette = firstVariant.palette
                local tint0 = tint[1] or 0
                local tint1 = tint[2] or 0
                local tint2 = tint[3] or 0
                ClothesCache[category].texture.palette = firstVariantIndex
                ClothesCache[category].texture.tint0 = tint0
                ClothesCache[category].texture.tint1 = tint1
                ClothesCache[category].texture.tint2 = tint2
                UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            elseif asset[1] and asset[1].hash then
                local firstTextureIndex = GetFirstAllowedClothingVariantIndex(gender, category, id)
                if not firstTextureIndex or not asset[firstTextureIndex] then
                    ClothesCache[category].model = 0
                    return false
                end
                ClothesCache[category].texture = firstTextureIndex
                NativeSetPedComponentEnabled(ped, asset[firstTextureIndex].hash, false, true, true)
            else
                ClothesCache[category].model = 0
                return false
            end
        else
            -- Were implicit globals: two overlapping calls shared (and swapped)
            -- each other's albedo/normal/tints.
            local drawable, albedo, normal, material, palette, tint0, tint1, tint2
            local currentModel = tonumber(ClothesCache[category].model) or 0
            if change_type == "variants" and not IsClothingVariantAllowed(gender, category, currentModel, value) then
                return false
            end
            local modelAsset = ClothingAssets[gender] and ClothingAssets[gender][category] and ClothingAssets[gender][category][currentModel]
            if not modelAsset then
                return false
            end
            if modelAsset.drawable then
                drawable = modelAsset.drawable
                if type(ClothesCache[category].texture) ~= "table" then
                    local oldPalette = tonumber(ClothesCache[category].texture) or 1
                    ClothesCache[category].texture = {
                        palette = oldPalette,
                        tint0 = 0,
                        tint1 = 0,
                        tint2 = 0,
                    }
                end
                local currentPalette = tonumber(ClothesCache[category].texture.palette) or 1
                local variantObj = modelAsset.variants and (modelAsset.variants[currentPalette] or modelAsset.variants[1])
                if not variantObj then return false end

                if change_type ~= "variants" then
                    albedo = variantObj.albedo
                    normal = variantObj.normal
                    material = variantObj.material
                    palette = variantObj.palette
                    tint0 = tonumber(ClothesCache[category].texture.tint0) or 0
                    tint1 = tonumber(ClothesCache[category].texture.tint1) or 0
                    tint2 = tonumber(ClothesCache[category].texture.tint2) or 0
                end
                if change_type == "variants" then
                    local selectedVariant = modelAsset.variants and modelAsset.variants[value]
                    if not selectedVariant then return false end
                    local selectedTint = selectedVariant.tint or {}
                    albedo = selectedVariant.albedo
                    normal = selectedVariant.normal
                    material = selectedVariant.material
                    palette = selectedVariant.palette
                    tint0 = tonumber(selectedVariant.tint0 or selectedTint[1]) or 0
                    tint1 = tonumber(selectedVariant.tint1 or selectedTint[2]) or 0
                    tint2 = tonumber(selectedVariant.tint2 or selectedTint[3]) or 0

                    ClothesCache[category].texture.palette = value
                    ClothesCache[category].texture.tint0 = tint0
                    ClothesCache[category].texture.tint1 = tint1
                    ClothesCache[category].texture.tint2 = tint2
                elseif change_type == 1 then
                    ClothesCache[category].texture.tint0 = value
                    tint0 = value
                    tint1 = ClothesCache[category].texture.tint1 or 0
                    tint2 = ClothesCache[category].texture.tint2 or 0
                elseif change_type == 2 then
                    ClothesCache[category].texture.tint1 = value
                    tint0 = ClothesCache[category].texture.tint0 or 0
                    tint1 = value
                    tint2 = ClothesCache[category].texture.tint2 or 0
                elseif change_type == 3 then
                    ClothesCache[category].texture.tint2 = value
                    tint0 = ClothesCache[category].texture.tint0 or 0
                    tint1 = ClothesCache[category].texture.tint1 or 0
                    tint2 = value
                end
                UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            else
                local catHash = (type(category) ~= "number") and joaat(category) or category
                if change_type == "variants" then
                    ClothesCache[category].texture = value
                    local varData = modelAsset[value] or modelAsset[1]
                    if varData and varData.hash then
                        NativeSetPedComponentEnabled(ped, varData.hash, false, true, true)
                    end
                elseif change_type == 1 then
                    if type(ClothesCache[category].texture) ~= "table" then
                        local oldVal = ClothesCache[category].texture
                        ClothesCache[category].texture = { palette = oldVal, tint0 = 0, tint1 = 0, tint2 = 0 }
                    end
                    local componentIndex = GetComponentIndexByCategory(ped, catHash)
                    -- The color picker is only exposed for an already-active MetaPed tag.
                    -- Never spin/wait here: a missing component simply keeps its current color.
                    if componentIndex == -1 then return false end
                    local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                    local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                    ClothesCache[category].texture.tint0 = value
                    tint0 = value
                    tint1 = ClothesCache[category].texture.tint1 or tint1
                    tint2 = ClothesCache[category].texture.tint2 or tint2
                    UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                elseif change_type == 2 then
                    if type(ClothesCache[category].texture) ~= "table" then
                        local oldVal = ClothesCache[category].texture
                        ClothesCache[category].texture = { palette = oldVal, tint0 = 0, tint1 = 0, tint2 = 0 }
                    end
                    local componentIndex = GetComponentIndexByCategory(ped, catHash)
                    -- The color picker is only exposed for an already-active MetaPed tag.
                    -- Never spin/wait here: a missing component simply keeps its current color.
                    if componentIndex == -1 then return false end
                    local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                    local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                    ClothesCache[category].texture.tint1 = value
                    tint0 = ClothesCache[category].texture.tint0 or tint0
                    tint1 = value
                    tint2 = ClothesCache[category].texture.tint2 or tint2
                    UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                elseif change_type == 3 then
                    if type(ClothesCache[category].texture) ~= "table" then
                        local oldVal = ClothesCache[category].texture
                        ClothesCache[category].texture = { palette = oldVal, tint0 = 0, tint1 = 0, tint2 = 0 }
                    end
                    local componentIndex = GetComponentIndexByCategory(ped, catHash)
                    -- The color picker is only exposed for an already-active MetaPed tag.
                    -- Never spin/wait here: a missing component simply keeps its current color.
                    if componentIndex == -1 then return false end
                    local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                    local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                    ClothesCache[category].texture.tint2 = value
                    tint0 = ClothesCache[category].texture.tint0 or tint0
                    tint1 = ClothesCache[category].texture.tint1 or tint1
                    tint2 = value
                    UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                end
            end
        end
    end

    if IsWeaponClothingCategory(category) then
        QueueWeaponClothingRepair(ped)
    end
    return true
end

------- EDITOR APPLY QUEUE ------
-- Why the ped "glitched" while editing (3.8.2):
-- every NUI callback (itemValue / varValue / tintValue / body sliders /
-- smart body / My-outfits sliders) runs in its own coroutine, and every apply
-- path yields - UpdateCustomClothes and NativeUpdatePedVariation each wait up
-- to 2s for MetaPed streaming. Clicking the arrows quickly therefore ran 5-10
-- component writes + commits on the same ped at once, each followed by a
-- smart-body mesh swap, finishing in random order. The ped flickered, parts
-- went invisible/stretched, the body mesh no longer matched the garment, and
-- the menu could show a different item than the one actually worn. A close /
-- save (jrs_clothes:clotheitem) could also land in the middle of that and
-- then get overwritten by a stale edit finishing afterwards.
--
-- Now every editor change goes through ONE worker, one job at a time, and
-- pending jobs are coalesced by key (latest value wins), so fast scrolling
-- applies only the item the player actually stopped on.
local EditorQueueOrder = {}
local EditorQueueJobs = {}
local EditorWorkerRunning = false
ClothingEditorApplying = false
ClothingEditorEpoch = 0

local function dropQueuedEdits(prefix)
    for key in pairs(EditorQueueJobs) do
        if key:sub(1, #prefix) == prefix then EditorQueueJobs[key] = nil end
    end
end

function QueueClothingEdit(key, fn)
    if type(fn) ~= "function" then return end
    key = tostring(key or "misc")
    -- A new model for a category makes its pending variant/tint edits stale.
    local modelCategory = key:match("^model:(.+)$")
    if modelCategory then
        dropQueuedEdits("var:" .. modelCategory)
        dropQueuedEdits("tint:" .. modelCategory .. ":")
    end
    if not EditorQueueJobs[key] then
        EditorQueueOrder[#EditorQueueOrder + 1] = key
    end
    EditorQueueJobs[key] = { fn = fn, epoch = ClothingEditorEpoch }
    if EditorWorkerRunning then return end
    EditorWorkerRunning = true
    Citizen.CreateThread(function()
        while #EditorQueueOrder > 0 do
            local nextKey = table.remove(EditorQueueOrder, 1)
            local job = EditorQueueJobs[nextKey]
            EditorQueueJobs[nextKey] = nil
            -- Never edit on top of a whole-outfit apply that is still running
            -- (e.g. "modify outfit" opens the editor while it re-dresses).
            local busyDeadline = GetGameTimer() + 3000
            while GetGameTimer() < (tonumber(clotheitemBusyUntil) or 0) and GetGameTimer() < busyDeadline do
                Wait(0)
            end
            if job and job.epoch == ClothingEditorEpoch then
                ClothingEditorApplying = true
                local ok, err = pcall(job.fn)
                ClothingEditorApplying = false
                if not ok then
                    print(("^3[jrs_clothing] editor change '%s' failed: %s^7"):format(nextKey, tostring(err)))
                end
            end
        end
        EditorWorkerRunning = false
    end)
end

-- Drop everything still waiting (not the job currently running).
function CancelClothingEdits()
    ClothingEditorEpoch = ClothingEditorEpoch + 1
    EditorQueueOrder = {}
    EditorQueueJobs = {}
end

function WaitClothingEditsIdle(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 3000)
    while (ClothingEditorApplying or #EditorQueueOrder > 0) and GetGameTimer() < deadline do
        Wait(0)
    end
end

------- ESSENTIAL ------


-- MetaPed shop-item refresh / commit helpers.
-- 0x59BD177A1A48600A is _REFRESH_META_PED_SHOP_ITEMS and its second argument is
-- the refresh mode (R* uses 1), not a component-category hash. Passing a category
-- hash here caused weapon-clothing meshes (gun belts / holsters / loadouts) to be
-- refreshed with invalid state and could visually deform the surrounding clothes.
local function RefreshMetaPedShopItems(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, 1)
end

function NativeSetPedComponentEnabled(ped, componentHash, immediately, isMp)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not componentHash then return false end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, immediately == true, isMp ~= false, true)
    RefreshMetaPedShopItems(ped)
    NativeUpdatePedVariation(ped)
    return true
end

-- Same shop-item apply without committing immediately. Used when rebuilding a whole
-- outfit so Red Dead resolves all dependent weapon-clothing tags in one variation pass.
local function NativeSetPedComponentEnabledDeferred(ped, componentHash, isMp)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not componentHash then return false end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, false, isMp ~= false, true)
    return true
end

function NativeGetPedComponentCategory(isFemale, componentHash)
    return Citizen.InvokeNative(0x5FF9A878C3D115B8, componentHash, isFemale, true)
end

function NativeFixMeshIssues(ped, _categoryHash)
    -- The old implementation passed _categoryHash as p1. Cfx/RDR native metadata
    -- identifies p1 as the refresh mode and documents that it is always 1.
    RefreshMetaPedShopItems(ped)
end

-- RedM resets the ped to scale 1.0 whenever MetaPed components are
-- re-committed. A short character then grew to full size with the root still
-- at its old height, so the legs went through the floor ("sank into the
-- ground") until jrs_character's 1.2s watchdog put the height back - and every
-- click in the tailor did it again. Re-assert the saved height right after
-- each commit on the player's own ped. jrs_character owns the height; this
-- only asks it to re-apply what it already has cached.
function ReassertPlayerScale(ped)
    if not ped or ped ~= PlayerPedId() then return end
    if GetResourceState('jrs_character') ~= 'started' then return end
    pcall(function() exports['jrs_character']:ApplyCachedPlayerScale() end)
end

-- 3.10.6: true once the player's look was committed since the tailor list
-- opened. Closing the shop re-dresses from the DB only when it is set (or an
-- eye-button preview is on) - browsing and closing no longer re-dresses.
ClothingSessionDirty = true

function NativeUpdatePedVariation(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if ped == PlayerPedId() then ClothingSessionDirty = true end
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
    RefreshMetaPedShopItems(ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    ReassertPlayerScale(ped)
    local deadline = GetGameTimer() + 2000
    while not NativeHasPedComponentLoaded(ped) and GetGameTimer() < deadline do
        Wait(1)
    end
    ReassertPlayerScale(ped)
    if ped == PlayerPedId() then TriggerEvent('jrs_animmenu:client:reassertWalk') end
    return NativeHasPedComponentLoaded(ped) == true
end

function NativeHasPedComponentLoaded(ped)
    return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
end

function SetMetaPedTag(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
end

function UpdatePedVariation(ped)
    if ped == PlayerPedId() then ClothingSessionDirty = true end
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)                           -- UNKNOWN "Fixes outfit"- always paired with _UPDATE_PED_VARIATION
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) -- _UPDATE_PED_VARIATION
    ReassertPlayerScale(ped)
end

function UpdateCustomClothes(playerPed, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    local deadline = GetGameTimer() + 2000
    while not NativeHasPedComponentLoaded(playerPed) and GetGameTimer() < deadline do
        Wait(0)
    end
    -- Do not bail on timeout: every caller discards the return value, so an
    -- early return here silently skipped SetMetaPedTag/NativeUpdatePedVariation
    -- and the garment the player just picked (or a colour change) never
    -- applied - it looked like the item disappeared. Same fix as jrs_barber
    -- v3.6.1's UpdateCustomhairstyle; NativeUpdatePedVariation below already
    -- tolerates a still-streaming ped.
    local playerPed = playerPed
    local _drawable = drawable
    local _albedo = albedo
    local _normal = normal
    local _material = material
    local _palette = palette
    local _tint0 = tonumber(tint0)
    local _tint1 = tonumber(tint1)
    local _tint2 = tonumber(tint2)

    SetMetaPedTag(playerPed, _drawable, _albedo, _normal, _material, _palette, _tint0, _tint1, _tint2)

    -- Full commit, not the two-native short form.
    --
    -- This is the path every NPC / custom drawable asset takes (MP shop items go
    -- through NativeSetPedComponentEnabled instead, which already commits in
    -- full). The short UpdatePedVariation only fires 0xAAB86462966168CE and
    -- 0xCC8CA3E88256E58F: the tag is staged but the pending components are never
    -- applied, the shop items are never refreshed, and nothing waits for the
    -- component data to finish streaming. That is why NPC clothing sat wrong -
    -- pieces clipping through, sitting off the body, or the previous garment
    -- still showing underneath - while the same garment from the MP list was
    -- fine, and why switching the body was the only thing that appeared to
    -- help. NativeUpdatePedVariation does all four steps and then waits.
    NativeUpdatePedVariation(playerPed)
end

function UpdateShopItemWearableState(ped, shopItemHash, wearableStateHash, isMultiplayer)
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, shopItemHash, wearableStateHash, 0, isMultiplayer, 1)
end

function ReapplyExpressions(ped)
    local ok, expressions = pcall(function()
        return exports['jrs_character']:GetCachedExpressions()
    end)
    if ok and expressions then
        for hash, value in pairs(expressions) do
            Citizen.InvokeNative(0x5653AB26C82938CF, ped, hash, value)
        end
        UpdatePedVariation(ped)
    end
end

function FixIssues(target)
    if IsPedMale(target) then
        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, target, 0, 0)
        NativeUpdatePedVariation(target)

        NativeSetPedComponentEnabled(target, tonumber(ComponentsMale["BODIES_UPPER"][1]), false, true, true)
        NativeSetPedComponentEnabled(target, tonumber(ComponentsMale["BODIES_LOWER"][1]), false, true, true)
        -- NativeSetPedComponentEnabled(target, `CLOTHING_ITEM_M_HEAD_001_V_001`, false, true, true)
        -- NativeSetPedComponentEnabled(target, `CLOTHING_ITEM_M_EYES_001_TINT_001`, false, true, true)
        -- texture_types["male"].albedo = GetHashKey("mp_head_mr1_sc08_c0_000_ab")
        Citizen.InvokeNative(0xD710A5007C2AC539, target, 0x1D4C528A, 0)
    else
        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, target, 7, true)
        NativeUpdatePedVariation(target)
        NativeSetPedComponentEnabled(target, tonumber(ComponentsFemale["BODIES_UPPER"][1]), false, true, true)
        NativeSetPedComponentEnabled(target, tonumber(ComponentsFemale["BODIES_LOWER"][1]), false, true, true)
        -- NativeSetPedComponentEnabled(target, `CLOTHING_ITEM_F_HEAD_001_V_001`, false, true, true)
        -- NativeSetPedComponentEnabled(target, `CLOTHING_ITEM_F_EYES_001_TINT_001`, false, true, true)
        -- NativeSetPedComponentEnabled( target, 0x1EECD215, false, true, true)
        -- texture_types["female"].albedo = GetHashKey("mp_head_fr1_sc08_c0_000_ab")
    end
    Citizen.InvokeNative(0xD710A5007C2AC539, target, 0x3F1F01E5, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, target, 0xDA0E2C55, 0)
    NativeUpdatePedVariation(target)
end

function IsPedReadyToRender(ped)
    local target = ped or PlayerPedId()
    local deadline = GetGameTimer() + 2500
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, target) and GetGameTimer() < deadline do
        Wait(0)
    end
    return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, target) == true
end

function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, f)
    local i = 0             -- iterator variable
    local iter = function() -- iterator function
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function GetNumComponentsInPed(ped)
    return Citizen.InvokeNative(0x90403E8107B60E81, ped, Citizen.ResultAsInteger())
end

function GetCategoryOfComponentAtIndex(ped, componentIndex)
    return Citizen.InvokeNative(0x9b90842304c938a7, ped, componentIndex, 0, Citizen.ResultAsInteger())
end

function GetComponentIndexByCategory(ped, category)
    local numComponents = GetNumComponentsInPed(ped)
    for i = 0, numComponents - 1, 1 do
        local componentCategory = GetCategoryOfComponentAtIndex(ped, i)
        if componentCategory == category then
            return i
        end
    end
    return -1
end

function GetMetaPedAssetGuids(ped, index)
    return Citizen.InvokeNative(0xA9C28516A6DC9D56, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(),
        Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

function GetMetaPedAssetTint(ped, index)
    return Citizen.InvokeNative(0xE7998FEC53A33BBE, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(),
        Citizen.PointerValueInt(), Citizen.PointerValueInt())
end


CreatorLight = false

---- CAMERA (ported from jrs_character appearance/camera.lua) ----
-- Uses the same dual-camera interpolation and body-focus destinations as the
-- character creator. Keep ClothingCamera as an alias to the active camera so
-- legacy clothing code can continue to use it safely.
c_offset = -0.15
c_zoom = 2.8
CamFov = 30.0
BaseCamFov = 30.0
ClothingCamera = nil
FixedCamera = false
CurrentShopName = nil

ClothingActiveCam = 0
ClothingCam1 = nil
ClothingCam2 = nil
ClothingCurrentCamDestination = ""
ClothingCamCoords = {}
ClothingViewBaseHeading = nil
ClothingViewFov = nil
ClothingViewPedHandle = nil

local function GetClothingCameraPed()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end
    return ped
end

local function ClothingGetActiveCamera()
    if ClothingCamera and DoesCamExist(ClothingCamera) then return ClothingCamera end
    if ClothingActiveCam == 1 and ClothingCam1 and DoesCamExist(ClothingCam1) then return ClothingCam1 end
    if ClothingActiveCam == 2 and ClothingCam2 and DoesCamExist(ClothingCam2) then return ClothingCam2 end
    return nil
end

local DEFAULT_CLOTHING_LATERAL_RATIO = 0.065
local clothingViewPanRatio = 0.0
local clothingCurrentRawCamCoords = nil
local clothingCurrentRawCamTarget = nil

local function ApplyClothingCameraLateralOffset(rawCoords, rawTarget)
    if not rawCoords or not rawTarget then return rawCoords, rawTarget end
    local fwd = rawTarget - rawCoords
    local fwdLen = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
    if fwdLen < 0.001 then return rawCoords, rawTarget end
    local dist = #(rawCoords - rawTarget)
    local totalRatio = DEFAULT_CLOTHING_LATERAL_RATIO + clothingViewPanRatio
    local lateralDist = dist * totalRatio
    local ux = fwd.x / fwdLen
    local uy = fwd.y / fwdLen
    local shiftX = -uy * lateralDist
    local shiftY = ux * lateralDist
    local newCoords = vector3(rawCoords.x + shiftX, rawCoords.y + shiftY, rawCoords.z)
    local newTarget = vector3(rawTarget.x + shiftX, rawTarget.y + shiftY, rawTarget.z)
    return newCoords, newTarget
end

local function ResolveObstructionFreeCameraCoords(target, desiredCoords, ped, baseFov)
    if not target or not desiredCoords or not ped or ped == 0 or not DoesEntityExist(ped) then
        return desiredCoords, baseFov
    end

    -- Raycast flags: 1 = World/Map geometry, 16 = Objects/Props
    local ray = StartShapeTestRay(target.x, target.y, target.z, desiredCoords.x, desiredCoords.y, desiredCoords.z, 17, ped, 7)
    local _, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)

    if hit ~= 0 and entityHit ~= ped then
        local dir = desiredCoords - target
        local totalDist = #(dir)
        local hitDist = #(hitCoords - target)

        if totalDist > 0.1 and hitDist < totalDist then
            local normDir = dir / totalDist
            -- Position camera 0.25 meters in front of the obstacle towards target
            local safeDist = math.max(0.65, hitDist - 0.25)
            local newCoords = target + (normDir * safeDist)

            -- Widen FOV proportionally so player is still completely in view
            local ratio = safeDist / totalDist
            local adjustedFov = math.min(65.0, (baseFov or 30.0) / math.max(0.65, ratio))
            return newCoords, adjustedFov
        end
    end

    return desiredCoords, baseFov
end

local function UpdateClothingActiveCameraPosition()
    local cam = ClothingGetActiveCamera()
    if not cam or not clothingCurrentRawCamCoords or not clothingCurrentRawCamTarget then return end
    local coords, target = ApplyClothingCameraLateralOffset(clothingCurrentRawCamCoords, clothingCurrentRawCamTarget)
    local ped = GetClothingCameraPed()
    coords, CamFov = ResolveObstructionFreeCameraCoords(target, coords, ped, CamFov)
    SetCamCoord(cam, coords)
    PointCamAtCoord(cam, target)
    SetCamFov(cam, CamFov)
end

-- Height the destinations were built at, per ped. Destinations are world
-- coords, so if the ped drops/rises after the build (teleport settle, fall
-- rescue) they must be rebuilt or the camera frames empty air.
local clothingCamBuiltZ = {}

local function ClothingBuildCameraDestinations(ped)
    if ClothingCamCoords[ped] then
        local builtZ = clothingCamBuiltZ[ped]
        if not builtZ or math.abs(GetEntityCoords(ped).z - builtZ) <= 0.2 then return end
        ClothingCamCoords[ped] = nil
    end
    clothingCamBuiltZ[ped] = GetEntityCoords(ped).z
    ClothingCamCoords[ped] = {
        default = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.3, 0.25),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.15),
            fov = 38.0,
        },
        edit = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.3, 0.25),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.15),
            fov = 38.0,
        },
        Body = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.3, 0.25),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.15),
            fov = 38.0,
        },
        head = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.35, 0.68),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.68),
            fov = 32.0,
        },
        facial = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.95, 0.62),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.62),
            fov = 28.0,
        },
        upperbody = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.75, 0.2),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.2),
            fov = 30.0,
        },
        lowerbody = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.75, -0.4),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.4),
            fov = 30.0,
        },
        waist = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, -0.05),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.05),
            fov = 28.0,
        },
        feet = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.5, -0.75),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.75),
            fov = 28.0,
        },
        hands = {
            coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, 0.0),
            target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0),
            fov = 30.0,
        },
    }
end

function ClothingMoveCam(destination, data, tpcam)
    local ped = GetClothingCameraPed()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    destination = tostring(destination or "Body")

    ClothingBuildCameraDestinations(ped)
    if destination == ClothingCurrentCamDestination and ClothingGetActiveCamera() then
        return true
    end
    ClothingCurrentCamDestination = destination

    local destinationData = ClothingCamCoords[ped][destination]
    local coords, target, fov
    if destinationData then
        coords, target, fov = destinationData.coords, destinationData.target, destinationData.fov
    elseif type(data) == "table" and data.coords and data.target then
        coords, target, fov = data.coords, data.target, tonumber(data.fov) or 30.0
    else
        local fallback = ClothingCamCoords[ped].default
        coords, target, fov = fallback.coords, fallback.target, fallback.fov
    end

    clothingCurrentRawCamCoords = coords
    clothingCurrentRawCamTarget = target
    coords, target = ApplyClothingCameraLateralOffset(coords, target)
    coords, fov = ResolveObstructionFreeCameraCoords(target, coords, ped, fov)

    CamFov = tonumber(fov) or 30.0
    BaseCamFov = CamFov
    ClothingViewFov = CamFov

    if ClothingActiveCam == 0 then
        ClothingCam1 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(ClothingCam1, coords)
        PointCamAtCoord(ClothingCam1, target)
        SetCamFov(ClothingCam1, CamFov)
        SetCamActive(ClothingCam1, true)
        if not tpcam then
            RenderScriptCams(true, true, 1000, true, true)
        else
            RenderScriptCams(true, false, 0, true, true)
        end
        SetCamFocusDistance(ClothingCam1, #(GetCamCoord(ClothingCam1) - target))
        ClothingActiveCam = 1
        ClothingCamera = ClothingCam1
    else
        local from, to
        if ClothingActiveCam == 1 then
            if not ClothingCam2 or not DoesCamExist(ClothingCam2) then
                ClothingCam2 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
            end
            from, to = ClothingCam1, ClothingCam2
            ClothingActiveCam = 2
        else
            if not ClothingCam1 or not DoesCamExist(ClothingCam1) then
                ClothingCam1 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
            end
            from, to = ClothingCam2, ClothingCam1
            ClothingActiveCam = 1
        end

        SetCamCoord(to, coords)
        PointCamAtCoord(to, target)
        SetCamFov(to, CamFov)
        if not tpcam then
            SetCamActiveWithInterp(to, from, 1000, true, true)
        else
            SetCamActive(to, true)
        end
        SetCamFocusDistance(to, #(GetCamCoord(to) - target))
        ClothingCamera = to
    end

    TriggerEvent('jrs_hud:busy', 'jrs_clothing', true)
    DisplayRadar(false)
    return true
end

-- Legacy entry point used by the clothing menu builder. The character-style
-- camera owns positioning, so zoom/offset are intentionally ignored.
function camera(zoom, offset)
    return ClothingMoveCam("Body")
end

function KillCamera(immediate)
    local ease = immediate ~= true
    local duration = immediate == true and 0 or 500
    RenderScriptCams(false, ease, duration, true, true)
    if ClothingCam1 and DoesCamExist(ClothingCam1) then DestroyCam(ClothingCam1, true) end
    if ClothingCam2 and DoesCamExist(ClothingCam2) then DestroyCam(ClothingCam2, true) end
    if ClothingCamera and DoesCamExist(ClothingCamera)
        and ClothingCamera ~= ClothingCam1 and ClothingCamera ~= ClothingCam2 then
        DestroyCam(ClothingCamera, true)
    end
    TriggerEvent('jrs_hud:busy', 'jrs_clothing', false)
    pcall(DisplayHud, true)
    DisplayRadar(true)
    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
    end
    ClothingActiveCam = 0
    ClothingCam1 = nil
    ClothingCam2 = nil
    ClothingCamera = nil
    ClothingCurrentCamDestination = ""
    ClothingCamCoords = {}
    ClothingViewBaseHeading = nil
    ClothingViewFov = nil
    ClothingViewPedHandle = nil
    clothingCurrentRawCamCoords = nil
    clothingCurrentRawCamTarget = nil
    clothingViewPanRatio = 0.0
    CamFov = 30.0
    BaseCamFov = 30.0
    FixedCamera = false
    CurrentShopName = nil
    baseHeading = nil
    angleOffset = nil
end

-- Fixed shop cameras are deliberately replaced by the same camera used by
-- jrs_character so every tailor behaves identically to the character creator.
function CreateFixedCamera(shopName)
    CurrentShopName = shopName
    FixedCamera = false
    return ClothingMoveCam("Body")
end

local clothingCameraGroups = {
    head = "head", upper = "upperbody", lower = "lowerbody", feets = "feet",
    footwear = "feet", accs = "Body", accessories = "Body", weapons = "waist",
    skin = "Body", body = "Body"
}

local clothingFaceCategories = {
    masks = true, eyewear = true, face_props = true
}
local clothingHeadCategories = {
    hats = true, headwear = true, hat_accessories = true, masks_large = true,
    hair_accessories = true, jewelry_earrings = true
}
local clothingUpperCategories = {
    coats = true, shirts_full = true, lduvmjua_0x2b388a05 = true, nbtudvja_0x53b67599 = true,
    vests = true, suspenders = true, unionsuits_full = true, overalls_full = true,
    shirts_full_overpants = true, cloaks = true, overalls_modular_uppers = true,
    coats_closed = true, coats_heavy = true, ponchos = true, capes = true, shawls = true,
    corsets = true, chemises = true, armor = true, cnvfyaba_0xd7ae0d03 = true,
    gjrbmoma_0xcb39a6f4 = true, pnyvpusa_0x44f4c713 = true, ogoolgaa_0xecd61654 = true,
    gnuusvra_0x7024af8b = true, oacpqvda_0x41292b6f = true, ywkywwvb_0xe93b9f1b = true
}
local clothingLowerCategories = {
    pants = true, overalls_modular_lowers = true, dresses = true, skirts = true,
    unionsuit_legs = true, knickers = true, stockings = true, chaps = true,
    pants_accessories = true, aprons = true
}
local clothingFeetCategories = {
    boots = true, boot_accessories = true, spats = true, ankle_bindings = true
}
local clothingWaistCategories = {
    belts = true, belt_buckles = true, gunbelts = true, loadouts = true,
    holsters_right = true, holsters_left = true, holsters_center = true,
    holsters_crossdraw = true, holsters_knife = true, gunbelt_accs = true,
    holsters_quivers = true, ammo_pistols = true, coat_accessories = true, vest_accessories = true
}
local clothingHandCategories = {
    gloves = true, jewelry_rings = true, jewelry_rings_right = true, jewelry_rings_left = true,
    jewelry_bracelets = true, wrist_bindings = true, gauntlets = true
}

function GetClothingCameraDestination(category, group)
    category = tostring(category or "")
    group = tostring(group or "")
    if clothingFaceCategories[category] then return "facial" end
    if clothingHeadCategories[category] then return "head" end
    if clothingFeetCategories[category] then return "feet" end
    if clothingWaistCategories[category] then return "waist" end
    if clothingHandCategories[category] then return "hands" end
    if clothingLowerCategories[category] then return "lowerbody" end
    if clothingUpperCategories[category] then return "upperbody" end
    if category == "outfits" or category == "satchels" or category == "satchel_straps" or category == "accessories" then
        return "Body"
    end
    return clothingCameraGroups[group] or clothingCameraGroups[category] or "Body"
end

function FocusClothingCameraCategory(category, group)
    ClothingCurrentCamDestination = ""
    return ClothingMoveCam(GetClothingCameraDestination(category, group))
end

function HandleClothingViewControl(data)
    data = type(data) == "table" and data or {}
    local action = tostring(data.action or "")
    local focusTarget = tostring(data.target or "")
    local ped = GetClothingCameraPed()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return { ok = false, reason = "invalid_ped" }
    end

    if ClothingViewPedHandle ~= ped then
        ClothingViewPedHandle = ped
        ClothingViewBaseHeading = GetEntityHeading(ped)
        ClothingViewFov = nil
    elseif ClothingViewBaseHeading == nil then
        ClothingViewBaseHeading = GetEntityHeading(ped)
    end

    local function applyFocus(destination)
        if not destination or destination == "" then return false end
        ClothingCurrentCamDestination = ""
        ClothingMoveCam(destination)
        local cam = ClothingGetActiveCamera()
        if cam then
            ClothingViewFov = tonumber(GetCamFov(cam)) or ClothingViewFov
            CamFov = ClothingViewFov or CamFov
        end
        return true
    end

    local focusMap = {
        fullbody = "Body", body = "Body", head = "head", face = "facial",
        torso = "upperbody", upperbody = "upperbody", hands = "hands", waist = "waist",
        legs = "lowerbody", lowerbody = "lowerbody", boots = "feet", feet = "feet"
    }
    local downSequence = {
        head = "facial", facial = "upperbody", upperbody = "hands", hands = "waist",
        waist = "lowerbody", lowerbody = "feet", feet = "Body", Body = "lowerbody", [""] = "lowerbody"
    }
    local upSequence = {
        feet = "lowerbody", lowerbody = "waist", waist = "hands", hands = "upperbody",
        upperbody = "facial", facial = "head", head = "head", Body = "upperbody", [""] = "head"
    }

    if action == "rotateLeft" or action == "rotateRight" then
        local step = 7.5
        local heading = GetEntityHeading(ped)
        heading = heading + (action == "rotateLeft" and step or -step)
        SetEntityHeading(ped, heading % 360.0)
        baseHeading = false
    elseif action == "zoomIn" or action == "zoomOut" then
        local cam = ClothingGetActiveCamera()
        if cam then
            local current = tonumber(GetCamFov(cam)) or tonumber(ClothingViewFov) or tonumber(BaseCamFov) or 30.0
            local nextFov = current + (action == "zoomIn" and -1.5 or 1.5)
            nextFov = math.max(12.0, math.min(75.0, nextFov))
            ClothingViewFov = nextFov
            CamFov = nextFov
            SetCamFov(cam, nextFov)
            if ClothingCam1 and DoesCamExist(ClothingCam1) and cam ~= ClothingCam1 then SetCamFov(ClothingCam1, nextFov) end
            if ClothingCam2 and DoesCamExist(ClothingCam2) and cam ~= ClothingCam2 then SetCamFov(ClothingCam2, nextFov) end
        end
    elseif action == "moveDown" then
        applyFocus(downSequence[ClothingCurrentCamDestination or ""] or "lowerbody")
    elseif action == "moveUp" then
        applyFocus(upSequence[ClothingCurrentCamDestination or ""] or "head")
    elseif action == "focus" then
        local mapped = focusMap[string.lower(focusTarget)]
        if not mapped or not applyFocus(mapped) then
            return { ok = false, reason = "invalid_focus_target" }
        end
    elseif action == "panRight" then
        -- 0.007 per press was ~3cm on the body cam: buttons looked dead.
        clothingViewPanRatio = math.min(0.35, clothingViewPanRatio + 0.035)
        UpdateClothingActiveCameraPosition()
    elseif action == "panLeft" then
        clothingViewPanRatio = math.max(-0.35, clothingViewPanRatio - 0.035)
        UpdateClothingActiveCameraPosition()
    elseif action == "centerView" then
        clothingViewPanRatio = 0.0
        UpdateClothingActiveCameraPosition()
    elseif action == "reset" then
        clothingViewPanRatio = 0.0
        if ClothingViewBaseHeading ~= nil then SetEntityHeading(ped, ClothingViewBaseHeading) end
        baseHeading = false
        applyFocus("Body")
        local cam = ClothingGetActiveCamera()
        if cam then
            local resetFov = tonumber(BaseCamFov) or 30.0
            ClothingViewFov = resetFov
            CamFov = resetFov
            SetCamFov(cam, resetFov)
        end
    else
        return { ok = false, reason = "invalid_action" }
    end

    return {
        ok = true,
        heading = GetEntityHeading(ped),
        fov = ClothingViewFov,
        current = ClothingCurrentCamDestination
    }
end

function PlaySound(action, soundset)
    PlaySoundFrontend(action, soundset, true, 0)
end

local lastanim = 0
function ChangeClothesAnim()
    RequestAnimDict("script_common@tailor_shop@camp")
    local animDeadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded("script_common@tailor_shop@camp") and GetGameTimer() < animDeadline do
        Citizen.Wait(0)
    end
    if not HasAnimDictLoaded("script_common@tailor_shop@camp") then return false end
    local anim = { "shoulder_roll_double", "adjust", "checkout_boot_left", "checkout_boot_right", "checkout_gloves_both",
        "checkout_pants_v1", "checkout_v3", "checkout_side", "shoulder_roll", "checkout_v2", "new_look",
        "checkout_right_glove", "new_look_v1", "checkout_v1", "different_fit" }
    local selectedanim = math.random(1, #anim)
    lastanim = selectedanim
    repeat selectedanim = math.random(1, #anim) until selectedanim ~= lastanim
    local timer = GetAnimDuration("script_common@tailor_shop@camp", anim[selectedanim])
    if CreatorLight == false then
        return
    end
    TaskPlayAnim(PlayerPedId(), "script_common@tailor_shop@camp", anim[selectedanim], 1.0, 1.0, -1, 0, 0, 0, 0, 0)
    Wait(timer * 1000 * 2)
    return true
end

local lastidle = 0
function IdleAnim()
    local ped = PlayerPedId()
    if OutfitMenuOpen == false then return end
    RequestAnimDict("script_common@tailor_shop@camp")
    local animDeadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded("script_common@tailor_shop@camp") and GetGameTimer() < animDeadline do
        Citizen.Wait(0)
    end
    if not HasAnimDictLoaded("script_common@tailor_shop@camp") then return false end
    local idle = { "idle_v1", "idle_v2", "idle" }
    local selectedidle = math.random(1, #idle)
    lastidle = selectedidle
    repeat selectedidle = math.random(1, #idle) until selectedidle ~= lastidle
    local timer = GetAnimDuration("script_common@tailor_shop@camp", idle[selectedidle])
    if CreatorLight == false then
        return
    end
    TaskPlayAnim(ped, "script_common@tailor_shop@camp", idle[selectedidle], 1.0, 1.0, -1, 0, 0, 0, 0, 0)
    Wait(timer * 1000 * 2)
    return true
end
function ApplyShopItemToPed(ped, shopItemHash, immediately, isMultiplayer)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, shopItemHash, immediately, isMultiplayer, false)
end

function IsMetaPedUsingComponentCategory(ped, componentCategory)
    return Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, componentCategory)
end

function GetHashFromString(value)
    if type(value) == "string" then
        local number = tonumber(value)
        if number then return number end
        return joaat(value)
    end
    return value
end

function GetComponentEquiped(ped, category)
    local categoryHash = GetHashFromString(category)
    -- if not IsMetaPedUsingComponentCategory(ped, categoryHash) then
    --     print ("not using", category)
    --   return false
    -- end
    local equiped = GetCategoriesEquiped(ped)
    if equiped[categoryHash] then
        local index = equiped[categoryHash].index
        return GetShopItemComponentAtIndex(ped, index, true)
    else
        return false
    end
end

function GetCategoriesEquiped(ped)
    local equiped = {}
    local numComponent = GetNumComponentsInPed(ped) or 0
    for index = 0, numComponent - 1 do
        --Get current component
        local category = GetCategoryOfComponentAtIndex(ped, index)
        equiped[category] = {
            index = index,
        }
        if category == `neckwear` then
            equiped[`neckerchiefs`] = equiped[category]
            equiped[`neckerchiefs`].category = "neckerchiefs"
        elseif category == `neckerchiefs` then
            equiped[`neckwear`] = equiped[category]
            equiped[`neckwear`].category = "neckwear"
        end
    end
    --clear cached value
    local component = equiped
    return component
end

-- Convert the components currently worn by a ped into jrs_clothing's native
-- { category = { model, texture } } representation. This is used once for
-- legacy characters and also provides a stable integration point.
function CaptureCurrentJRSClothes(ped)
    ped = ped or PlayerPedId()
    local gender = IsPedMale(ped) and 'male' or 'female'
    local assets = ClothingAssets and ClothingAssets[gender]
    if type(assets) ~= 'table' then return {} end

    local captured = {}
    for category, models in pairs(assets) do
        if type(models) == 'table' and category ~= 'bodies_upper' and category ~= 'bodies_lower'
            and category ~= 'hair' and not string.find(category, 'beard', 1, true) then
            local componentIndex = GetComponentIndexByCategory(ped, joaat(category))
            if componentIndex and componentIndex >= 0 then
                local equippedHash = GetShopItemComponentAtIndex(ped, componentIndex, true)
                local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)

                for modelIndex, modelData in pairs(models) do
                    if type(modelIndex) == 'number' and type(modelData) == 'table' then
                        if modelData.drawable and tonumber(modelData.drawable) == tonumber(drawable) then
                            local texture = nil
                            for variantIndex, variant in pairs(modelData.variants or {}) do
                                if type(variantIndex) == 'number' and type(variant) == 'table'
                                    and tonumber(variant.albedo) == tonumber(albedo)
                                    and tonumber(variant.normal) == tonumber(normal)
                                    and tonumber(variant.material) == tonumber(material) then
                                    local _, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                                    texture = { palette = variantIndex, tint0 = tint0 or 0, tint1 = tint1 or 0, tint2 = tint2 or 0 }
                                    break
                                end
                            end
                            if texture then captured[category] = { model = modelIndex, texture = texture } end
                        else
                            for textureIndex, variant in pairs(modelData) do
                                if type(textureIndex) == 'number' and type(variant) == 'table'
                                    and tonumber(variant.hash) == tonumber(equippedHash) then
                                    captured[category] = { model = modelIndex, texture = textureIndex }
                                    break
                                end
                            end
                        end
                    end
                    if captured[category] then break end
                end
            end
        end
    end
    return captured
end

exports('CaptureCurrentClothes', CaptureCurrentJRSClothes)

function GetBuggedCategories(ped)
    local returntable = {}
    local buggedcategories = {
        `hair`,
        `hair_bonnet`,
        `beard`,
        `teeth`,
        `eyes`,
        `beards_chin`,
        `beards_chops`,
        `beards_mustache`,
        `beards_complete`,
    }
    local numComponent = GetNumComponentsInPed(ped) or 0
    for index = 0, numComponent - 1 do
        --Get current component
        local category = GetCategoryOfComponentAtIndex(ped, index)
        if contains(buggedcategories, category) then
            local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, index)
            if drawable and tonumber(drawable) ~= 0 then
                local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, index)
                if category == `hair` or category == `hair_bonnet` or category == `beard`
                    or category == `beards_chin` or category == `beards_chops`
                    or category == `beards_mustache` or category == `beards_complete` then
                    if not palette or tonumber(palette) == 0 or tonumber(palette) == 1 then
                        palette = `metaped_tint_hair`
                    end
                end
                returntable[category] = {
                    index = index,
                    drawable = drawable,
                    albedo = albedo,
                    normal = normal,
                    material = material,
                    palette = palette,
                    tint0 = tint0 or 0,
                    tint1 = tint1 or 0,
                    tint2 = tint2 or 0
                }
            end
        end
    end
    return returntable
end

function scale(value, oldMin, oldMax, newMin, newMax)
    return (((value - oldMin) * (newMax - newMin)) / (oldMax - oldMin)) + newMin
end

--- Reapply base MP body (baseskin) to the ped
--- This function properly applies the stored bodies_upper and bodies_lower with their original albedo
---@param ped number Optional ped entity (defaults to PlayerPedId())
-- Put the player's own MP body back on for `category` (used when no trusted
-- skin tone is known, instead of painting an NPC body with a wrong texture).
function RestorePlayerBaseBody(ped, category)
    if type(WearableCache) ~= "table" then WearableCache = {} end
    WearableCache[category] = { model = 1 }
    if baseskin and baseskin[category] and baseskin[category] ~= 0 then
        NativeSetPedComponentEnabled(ped, baseskin[category], false, true)
    end
    NativeUpdatePedVariation(ped)
end

-- Public repair hook for resources that used to apply NPC body meshes.  Both
-- body slots are restored from this character's saved base skin before any
-- clothing overlay is applied.
function RestorePlayerBodyMeshes(ped)
    ped = ped or PlayerPedId()
    RestorePlayerBaseBody(ped, "bodies_upper")
    RestorePlayerBaseBody(ped, "bodies_lower")
    ReapplyBaseSkin(ped)
    return true
end
exports('RestorePlayerBodyMeshes', RestorePlayerBodyMeshes)

-- Player: the trusted skin albedo (smart_body.lua), falling back to the stored
-- one. Other peds: nil, so their own body albedo is kept.
function TrustedSkinAlbedo(ped, bodyCat)
    if ped ~= PlayerPedId() then return nil end
    return baseskin and baseskin[bodyCat .. "_albedo"] ~= 0 and baseskin[bodyCat .. "_albedo"] or nil
end

function ReapplyBaseSkin(ped)
    ped = ped or PlayerPedId()

    if not baseskin or type(baseskin) ~= "table" then
        baseskin = {}
    end

    local isMale = IsPedMale(ped)
    local defaultUpper = isMale and (ComponentsMale and ComponentsMale["BODIES_UPPER"] and tonumber(ComponentsMale["BODIES_UPPER"][1])) or (ComponentsFemale and ComponentsFemale["BODIES_UPPER"] and tonumber(ComponentsFemale["BODIES_UPPER"][1])) or 0x206061DB
    local defaultLower = isMale and (ComponentsMale and ComponentsMale["BODIES_LOWER"] and tonumber(ComponentsMale["BODIES_LOWER"][1])) or (ComponentsFemale and ComponentsFemale["BODIES_LOWER"] and tonumber(ComponentsFemale["BODIES_LOWER"][1])) or 0x84BB6309

    if not baseskin["bodies_upper"] or baseskin["bodies_upper"] == 0 or baseskin["bodies_upper"] == false then
        local currentUpper = GetComponentEquiped(ped, "bodies_upper")
        baseskin["bodies_upper"] = (currentUpper and currentUpper ~= 0) and currentUpper or defaultUpper
    end

    if not baseskin["bodies_lower"] or baseskin["bodies_lower"] == 0 or baseskin["bodies_lower"] == false then
        local currentLower = GetComponentEquiped(ped, "bodies_lower")
        baseskin["bodies_lower"] = (currentLower and currentLower ~= 0) and currentLower or defaultLower
    end

    local equipped = GetCategoriesEquiped(ped)
    local palette, tint0, tint1, tint2

    -- Get head palette for consistency
    if equipped[`heads`] then
        local index = equipped[`heads`].index
        palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, index)
    end

    -- Ensure bodies_upper is equipped
    if not equipped[`bodies_upper`] and baseskin["bodies_upper"] then
        NativeSetPedComponentEnabled(ped, baseskin["bodies_upper"], false, true)
        equipped = GetCategoriesEquiped(ped)
    end

    -- Reapply bodies_upper textures
    -- 3.10.1: skin tone read off the player's own MP body (see
    -- SmartBodySkinAlbedo), never a stale value from another body/character.
    local skinAlbedo = TrustedSkinAlbedo(ped, "bodies_upper")
    equipped = GetCategoriesEquiped(ped)
    if baseskin["bodies_upper"] and equipped[`bodies_upper`] then
        local index = equipped[`bodies_upper`].index
        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, index)
        albedo = skinAlbedo or albedo

        UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    end

    -- Ensure bodies_lower is equipped
    if not equipped[`bodies_lower`] and baseskin["bodies_lower"] then
        NativeSetPedComponentEnabled(ped, baseskin["bodies_lower"], false, true)
        equipped = GetCategoriesEquiped(ped)
    end

    -- Reapply bodies_lower textures
    -- 3.10.1: skin tone read off the player's own MP body (see
    -- SmartBodySkinAlbedo), never a stale value from another body/character.
    local skinAlbedo = TrustedSkinAlbedo(ped, "bodies_lower")
    equipped = GetCategoriesEquiped(ped)
    if baseskin["bodies_lower"] and equipped[`bodies_lower`] then
        local index = equipped[`bodies_lower`].index
        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, index)
        albedo = skinAlbedo or albedo

        UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    end
    NativeUpdatePedVariation(ped)
end

function RemoveAllClothesExceptEssentials(ped)
    ped = ped or PlayerPedId()
    IsPedReadyToRender(ped)
    local equipped = GetCategoriesEquiped(ped)
    local essentialHashes = {}

    for _, essential in ipairs(ClothingConfig.EssentialsCategories or {}) do
        essentialHashes[GetHashFromString(essential)] = true
    end

    -- Remove the categories that are actually equipped.  The previous code
    -- walked a static category list and never committed the MetaPed change,
    -- so F2 displayed a success notification while the clothes stayed on.
    for category in pairs(equipped) do
        if category and category ~= 0 and not essentialHashes[category] then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, category, 0)
        end
    end

    NativeUpdatePedVariation(ped)
    Wait(0)

    -- Keep the canonical MP body and its original skin colour visible after
    -- shirts, pants and the other wearable categories have been removed.
    ReapplyBaseSkin(ped)
    NativeUpdatePedVariation(ped)
    return true
end

-- Vérifie si une table contient une valeur spécifique
function contains(table, value)
    for _, v in pairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

function areTablesEqual(t1, t2)
    -- Vérifie si les deux références pointent vers la même table
    if t1 == t2 then return true end

    -- Vérifie si les deux objets sont des tables
    if type(t1) ~= "table" or type(t2) ~= "table" then return false end

    -- Vérifie que toutes les clés et valeurs de t1 sont dans t2
    for key, value in pairs(t1) do
        if type(value) == "table" then
            -- Appel récursif pour les sous-tables
            if not areTablesEqual(value, t2[key]) then
                return false
            end
        else
            -- Comparaison des valeurs simples
            if value ~= t2[key] then
                return false
            end
        end
    end

    -- Vérifie que t2 n'a pas de clés supplémentaires
    for key in pairs(t2) do
        if t1[key] == nil then
            return false
        end
    end

    return true
end

-- Weapon clothing has explicit parent/child relationships. Applying these categories
-- through an unordered pairs() loop can leave a holster bound to the previous gun belt
-- or force Red Dead to resolve the torso mesh while only half of the weapon outfit exists.
local WeaponClothingCategories = {
    gunbelts = true,
    gunbelt_accs = true,
    holsters_right = true,
    holsters_left = true,
    holsters_crossdraw = true,
    holsters_center = true,
    holsters_knife = true,
    ammo_pistols = true,
    loadouts = true,
    holsters_quivers = true,
}

local WeaponBeltDependentCategories = {
    gunbelt_accs = true,
    holsters_right = true,
    holsters_left = true,
    holsters_crossdraw = true,
    holsters_center = true,
    holsters_knife = true,
    ammo_pistols = true,
}

local WeaponClothingApplyOrder = {
    'gunbelts',
    'gunbelt_accs',
    'holsters_right',
    'holsters_left',
    'holsters_crossdraw',
    'holsters_center',
    'holsters_knife',
    'ammo_pistols',
    'loadouts',
    'holsters_quivers',
}

-- Full MetaPed layering order. Weapon clothing is deliberately last so shirts, coats,
-- pants and normal accessories are already present before holsters/loadouts are resolved.
local ClothingApplyOrder = {
    -- Head
    'hats', 'headwear', 'eyewear', 'face_props', 'masks', 'masks_large',
    'hat_accessories', 'hair_accessories',

    -- Base upper/lower garments
    'chemises', 'corsets', 'unionsuits_full', 'unionsuit_legs',
    'shirts_full', 'lduvmjua_0x2b388a05', 'nbtudvja_0x53b67599',
    'pants', 'skirts', 'dresses', 'knickers', 'stockings',
    'overalls_modular_uppers', 'overalls_modular_lowers', 'overalls_full',
    'shirts_full_overpants',

    -- Normal layered clothing
    'vests', 'suspenders', 'coats', 'coats_closed', 'coats_heavy',
    'cloaks', 'capes', 'shawls', 'ponchos', 'outfits',

    -- Feet / leg overlays
    'boots', 'boot_accessories', 'spats', 'chaps',

    -- Neck / hands / general accessories
    'neckerchiefs', 'neckwear', 'neckties', 'gloves', 'gauntlets',
    'wrist_bindings', 'ankle_bindings',
    'belts', 'belt_buckles', 'pants_accessories', 'coat_accessories',
    'vest_accessories', 'aprons', 'satchels', 'satchel_straps',
    'accessories', 'badges', 'armor',
    'jewelry_necklaces', 'jewelry_bracelets', 'jewelry_rings',
    'jewelry_rings_left', 'jewelry_rings_right', 'jewelry_earrings',
}

IsWeaponClothingCategory = function(category)
    return WeaponClothingCategories[tostring(category or '')] == true
end

local function RemoveMetaPedCategoryDeferred(ped, category)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local hash = type(category) == 'number' and category or joaat(tostring(category))
    if hash and hash ~= 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, hash, 0)
    end
end

local function ResolveCachedClothingVariant(gender, category, data)
    if type(data) ~= 'table' then return nil end
    local model = tonumber(data.model) or 0
    if model <= 0 then return nil end
    if not ClothingAssets[gender] or not ClothingAssets[gender][category] then return nil end
    local asset = ClothingAssets[gender][category][model]
    if type(asset) ~= 'table' then return nil end
    if not IsClothingAssetAllowed(gender, category, model) then return nil end

    local texture = data.texture
    local variantIndex
    if type(texture) == 'table' then
        variantIndex = tonumber(texture.palette or texture.model)
    else
        variantIndex = tonumber(texture)
    end
    if not variantIndex or variantIndex <= 0 or not IsClothingVariantAllowed(gender, category, model, variantIndex) then
        variantIndex = GetFirstAllowedClothingVariantIndex(gender, category, model) or 1
    end

    if asset.drawable then
        local variant = asset.variants and (asset.variants[variantIndex] or asset.variants[1])
        if not variant then return nil end
        local tint = variant.tint or {}
        return {
            custom = true,
            drawable = asset.drawable,
            albedo = variant.albedo,
            normal = variant.normal,
            material = variant.material,
            palette = variant.palette,
            tint0 = type(texture) == 'table' and tonumber(texture.tint0) or tonumber(variant.tint0 or tint[1]) or 0,
            tint1 = type(texture) == 'table' and tonumber(texture.tint1) or tonumber(variant.tint1 or tint[2]) or 0,
            tint2 = type(texture) == 'table' and tonumber(texture.tint2) or tonumber(variant.tint2 or tint[3]) or 0,
        }
    end

    local variant = asset[variantIndex] or asset[1]
    if not variant or not variant.hash then return nil end
    return { custom = false, hash = tonumber(variant.hash) or variant.hash }
end

local function ApplyCachedClothingDeferred(ped, gender, category, data)
    local resolved = ResolveCachedClothingVariant(gender, category, data)
    if not resolved then return false end

    if resolved.custom then
        SetMetaPedTag(ped, resolved.drawable, resolved.albedo, resolved.normal, resolved.material,
            resolved.palette, resolved.tint0, resolved.tint1, resolved.tint2)
    else
        NativeSetPedComponentEnabledDeferred(ped, resolved.hash, true)
    end
    return true
end

local function CommitClothingBatch(ped)
    RefreshMetaPedShopItems(ped)
    return NativeUpdatePedVariation(ped)
end

local weaponRepairGeneration = 0
local function RebuildWeaponClothing(ped)
    ped = ped or PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    local gender = IsPedMale(ped) and 'male' or 'female'

    -- Clear only weapon-clothing tags; never touch actual weapon entities/inventory.
    for _, category in ipairs(WeaponClothingApplyOrder) do
        RemoveMetaPedCategoryDeferred(ped, category)
    end

    local gunbeltData = ClothesCache and ClothesCache.gunbelts
    local hasGunbelt = type(gunbeltData) == 'table'
        and (tonumber(gunbeltData.model) or 0) > 0
        and Equipped.gunbelts ~= false
        and IsClothingAssetAllowed(gender, 'gunbelts', gunbeltData.model)

    for _, category in ipairs(WeaponClothingApplyOrder) do
        local data = ClothesCache and ClothesCache[category]
        local canApply = type(data) == 'table' and (tonumber(data.model) or 0) > 0 and Equipped[category] ~= false
        if canApply and WeaponBeltDependentCategories[category] and not hasGunbelt then
            canApply = false
        end
        if canApply then
            ApplyCachedClothingDeferred(ped, gender, category, data)
        end
    end

    CommitClothingBatch(ped)
    return true
end

QueueWeaponClothingRepair = function(ped)
    weaponRepairGeneration = weaponRepairGeneration + 1
    local generation = weaponRepairGeneration
    Citizen.CreateThread(function()
        Wait(35)
        if generation ~= weaponRepairGeneration then return end
        if ped and DoesEntityExist(ped) then
            RebuildWeaponClothing(ped)
        end
    end)
end

-- Integration point for inventory/admin/uniform scripts that alter weapon-clothing tags.
function RepairWeaponClothing(ped)
    return RebuildWeaponClothing(ped or PlayerPedId())
end
exports('RepairWeaponClothing', RepairWeaponClothing)
RegisterNetEvent('jrs_clothes:RepairWeaponClothing', function(ped)
    RepairWeaponClothing(ped or PlayerPedId())
end)

function ReequipAllClothes(ped)
    ped = ped or PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    local gender = IsPedMale(ped) and 'male' or 'female'
    IsPedReadyToRender(ped)

    -- Bodies are owned by the wearable/base-skin system and should never be re-added
    -- as normal shop clothing. They are already applied before this function runs.
    ClothesCache['bodies_upper'], ClothesCache['bodies_lower'] = nil, nil

    local applied = {}
    local gunbeltData = ClothesCache and ClothesCache.gunbelts
    local hasGunbelt = type(gunbeltData) == 'table'
        and (tonumber(gunbeltData.model) or 0) > 0
        and Equipped.gunbelts ~= false
        and IsClothingAssetAllowed(gender, 'gunbelts', gunbeltData.model)

    -- Deterministic base -> outerwear -> accessories -> weapon clothing order.
    for _, category in ipairs(ClothingApplyOrder) do
        local data = ClothesCache[category]
        if type(data) == 'table' and (tonumber(data.model) or 0) > 0 and Equipped[category] ~= false then
            local canApply = true
            if WeaponBeltDependentCategories[category] and not hasGunbelt then
                canApply = false
            end
            if canApply and ApplyCachedClothingDeferred(ped, gender, category, data) then
                applied[category] = true
                Equipped[category] = true
            end
        end
    end

    -- Preserve custom/dev categories that are not in the known list, but make their order
    -- stable and keep them before the final MetaPed commit.
    local extras = {}
    local essentials = {}
    for _, category in ipairs(ClothingConfig.EssentialsCategories or {}) do
        essentials[tostring(category)] = true
    end
    for category, data in pairs(ClothesCache) do
        if not applied[category]
            and not essentials[tostring(category)]
            and not IsWeaponClothingCategory(category)
            and type(data) == 'table'
            and (tonumber(data.model) or 0) > 0 then
            extras[#extras + 1] = tostring(category)
        end
    end
    table.sort(extras)
    for _, category in ipairs(extras) do
        if ApplyCachedClothingDeferred(ped, gender, category, ClothesCache[category]) then
            Equipped[category] = true
        end
    end

    -- Weapon clothing is always the final layer, including when custom/dev categories exist.
    for _, category in ipairs(WeaponClothingApplyOrder) do
        local data = ClothesCache[category]
        local canApply = type(data) == 'table' and (tonumber(data.model) or 0) > 0 and Equipped[category] ~= false
        if canApply and WeaponBeltDependentCategories[category] and not hasGunbelt then
            canApply = false
        end
        if canApply and ApplyCachedClothingDeferred(ped, gender, category, data) then
            applied[category] = true
            Equipped[category] = true
        end
    end

    -- One refresh/update after the complete outfit prevents half-resolved gunbelt/holster
    -- states and keeps the surrounding shirt/vest/coat mesh intact.
    CommitClothingBatch(ped)
    return true
end

Equipped = Equipped or {}

-- Guards jrs_clothes:clotheitem against itself. The handler below spawns a new
-- thread on every call and that thread yields several times (an async
-- server round-trip for wearable data, a couple of fixed Waits) between its
-- own RemoveAllClothesExceptEssentials reset and its ReequipAllClothes
-- reapply, all while mutating the shared ClothesCache/Equipped globals. Two
-- overlapping calls (a quick second equip, a reload firing mid-purchase, a
-- preview racing a real equip) used to both run through that reset/reapply
-- sequence concurrently - whichever thread's server round-trip resolved last
-- could reset the ped's clothing again right after the other thread had
-- already finished reapplying it, leaving the ped visibly undressed with no
-- later reapply ever coming ("clothes sometimes disappear"). Each call now
-- takes a generation ticket and checks it after every yield point; a call
-- that has been superseded by a newer one abandons itself instead of
-- finishing a stale reset/reapply.
clotheitemGeneration = 0

-- A deadline (not a plain done/not-done flag) so a second resource that also
-- writes to this ped's clothing components (police duty uniforms, bathing,
-- mount/dismount outfits, etc.) has something to poll via IsClothingBusy()
-- before running its own reset - self-expires instead of ever getting stuck
-- reporting "busy" if some exit path failed to clear it. Generous on purpose:
-- covers the worst case (the ~1200ms wearable round-trip plus the preview's
-- extra Waits) with margin, since under-reporting busy is what causes the
-- actual collision, not over-reporting it for an extra few hundred ms.
clotheitemBusyUntil = 0
exports('IsClothingBusy', function()
    return GetGameTimer() < clotheitemBusyUntil
end)

-- Same component hash, tolerant of signed/unsigned values.
function SameComponentHash(a, b)
    a, b = tonumber(a), tonumber(b)
    if not a or not b or a == 0 or b == 0 then return false end
    return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

-- Applies a full saved outfit to the player (or to `target`).
-- restoreOnly = re-apply what is already stored (no DB write, no outfitchanged).
RegisterNetEvent('jrs_clothes:clotheitem')
AddEventHandler('jrs_clothes:clotheitem', function(ClothesComponents, outfitid, target, charid, previewOnly, restoreOnly)
    clotheitemGeneration = clotheitemGeneration + 1
    local myGeneration = clotheitemGeneration
    clotheitemBusyUntil = GetGameTimer() + 2500
    Citizen.CreateThread(function()
        -- Never strip the ped when no valid clothing data arrived.
        local hasValidClothes = false
        if type(ClothesComponents) == 'table' then
            for _, v in pairs(ClothesComponents) do
                if type(v) == 'table' and (tonumber(v.model) or 0) > 0 then
                    hasValidClothes = true
                    break
                end
            end
        end
        if not hasValidClothes and not target then
            if myGeneration == clotheitemGeneration then clotheitemBusyUntil = 0 end
            return
        end
        if not target and LocalPlayer and LocalPlayer.state and LocalPlayer.state.jrs_appearance_paused then
            if myGeneration == clotheitemGeneration then clotheitemBusyUntil = 0 end
            return
        end

        local _Target = target or PlayerPedId()
        if not target then
            CancelClothingEdits()
            WaitClothingEditsIdle(3000)
            if myGeneration ~= clotheitemGeneration then return end
            if restoreOnly ~= true then TriggerEvent("jrs_clothes:outfitchanged") end
        end

        local buggedCategories = GetBuggedCategories(_Target)
        local gender = IsPedMale(_Target) and "male" or "female"
        local tracksPlayerClothes = not target
        ClothesCache = type(ClothesComponents) == "table" and ClothesComponents or {}
        if tracksPlayerClothes then Equipped = {} end

        for k, v in pairs(ClothesCache) do
            if type(v) == "table" and type(v.texture) == "table" and v.texture.model ~= nil then
                v.texture.palette = v.texture.model
                v.texture.model = nil
            end
            if tracksPlayerClothes and type(v) == "table" and (tonumber(v.model) or 0) > 0 then
                Equipped[k] = IsClothingAssetAllowed(gender, k, v.model) == true
            end
        end
        for k in pairs(ClothingAssets[gender]) do
            if ClothesCache[k] == nil then
                ClothesCache[k] = { model = 0, texture = 0 }
            end
        end
        if not target then
            if restoreOnly ~= true then
                TriggerServerEvent("jrs_clothes:updateclothes", ClothesCache, outfitid)
            end
            OldClothesCache = deepcopy(ClothesCache)
        end

        RemoveAllClothesExceptEssentials(_Target)
        if myGeneration ~= clotheitemGeneration then return end
        ReapplyBaseSkin(_Target)
        ReequipAllClothes(_Target)
        Wait(80)
        if myGeneration ~= clotheitemGeneration then return end

        for _, v in pairs(buggedCategories) do
            local drawable = tonumber(v.drawable)
            if drawable and drawable ~= 0 then
                UpdateCustomClothes(_Target, drawable, tonumber(v.albedo) or 0, tonumber(v.normal) or 0,
                    tonumber(v.material) or 0, tonumber(v.palette) or 0,
                    tonumber(v.tint0) or 0, tonumber(v.tint1) or 0, tonumber(v.tint2) or 0)
            end
        end
        ReapplyExpressions(_Target)
        if tracksPlayerClothes then
            CreateThread(function()
                Wait(200)
                TriggerEvent('jrs_barber:loadbarberoverlay')
            end)
        end
        if myGeneration == clotheitemGeneration then
            clotheitemBusyUntil = GetGameTimer() + 100
            if restoreOnly == true and not target then ClothingSessionDirty = false end
        end
    end)
end)


WearableCache = {}

---Returns a table of currently equipped clothing categories
---@return table categories Table containing equipped clothing categories and their data
function GetEquippedCategories()
    local equippedCategories = {}

    local ped = PlayerPedId()
    local gender = IsPedMale(ped) and "male" or "female"
    for category, data in pairs(ClothesCache) do
        local modelNum = tonumber(type(data) == "table" and data.model or nil) or 0
        if modelNum > 0 and IsClothingAssetAllowed(gender, category, modelNum) then
            equippedCategories[category] = {
                model = data.model,
                texture = data.texture
            }
        end
    end

    return equippedCategories
end

exports('GetEquippedCategories', GetEquippedCategories)

-- jrs_character fires Loadupperbody/Loadlowerbody (the MP body for the
-- chosen skin tone) and then LoadBasSkin while that MP body is on the ped.
-- 3.10.1: before, Load*body set the hash first, so LoadBasSkin's
-- "only if not set" never refreshed the albedo - a character switch kept the
-- previous character's skin tone on every NPC body. Now a new body hash drops
-- the old albedo, and LoadBasSkin re-reads it whenever the MP body is on.
local function setBaseBody(bodyCat, comp)
    if type(baseskin) ~= "table" then baseskin = {} end
    if not SameComponentHash(baseskin[bodyCat], comp) then
        baseskin[bodyCat .. "_albedo"] = nil
        baseskin[bodyCat .. "_albedo_src"] = nil
    end
    baseskin[bodyCat] = comp
end

RegisterNetEvent("jrs_clothes:LoadBasSkin", function()
    if type(baseskin) ~= "table" then
        baseskin = {}
    end
    local ped = PlayerPedId()
    local equipped = GetCategoriesEquiped(ped)
    for _, bodyCat in ipairs({ "bodies_upper", "bodies_lower" }) do
        local cur = GetComponentEquiped(ped, bodyCat)
        if not baseskin[bodyCat] or baseskin[bodyCat] == 0 then
            setBaseBody(bodyCat, cur)
        end
        local slot = bodyCat == "bodies_upper" and equipped[`bodies_upper`] or equipped[`bodies_lower`]
        if slot and SameComponentHash(cur, baseskin[bodyCat]) then
            local _, albedo = GetMetaPedAssetGuids(ped, slot.index)
            if albedo and albedo ~= 0 then
                baseskin[bodyCat .. "_albedo"] = albedo
                baseskin[bodyCat .. "_albedo_src"] = cur
            end
        end
    end
end)

RegisterNetEvent("jrs_clothes:Loadlowerbody", function(comp)
    setBaseBody("bodies_lower", comp)
end)

RegisterNetEvent("jrs_clothes:Loadupperbody", function(comp)
    setBaseBody("bodies_upper", comp)
end)

---Equips multiple clothing items at once with support for model, texture (palette), and tint values
---@param clothesData table Table containing clothing categories with model, texture, and optional tint values
---Example: { ["hats"] = {model = 1, texture = 0, tint0 = 0, tint1 = 0, tint2 = 0}, ["shirts_full"] = {model = 5, texture = 2} }
---@param ped number Optional ped entity to apply clothes to (defaults to PlayerPedId())
function EquipMultipleClothes(clothesData, ped)
    if type(clothesData) ~= 'table' then return false end
    ped = ped or PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    local gender = IsPedMale(ped) and 'male' or 'female'
    local changedCategories = {}

    -- Normalize and cache first. Do not partially apply items while iterating a Lua pairs()
    -- table: that produces nondeterministic MetaPed layering and is especially visible with
    -- gun belts/holsters/loadouts.
    for category, data in pairs(clothesData) do
        if type(data) == 'table' then
            local model = tonumber(data.model) or 0
            if model <= 0 then
                ClothesCache[category] = { model = 0, texture = 0 }
                Equipped[category] = false
                changedCategories[#changedCategories + 1] = category
                goto continue_multi
            end

            local assets = ClothingAssets and ClothingAssets[gender] and ClothingAssets[gender][category]
            local asset = assets and assets[model]
            if not asset or not IsClothingAssetAllowed(gender, category, model) then
                goto continue_multi
            end

            local texture = data.texture
            local textureIndex
            if type(texture) == 'table' then
                textureIndex = tonumber(texture.palette or texture.model)
            else
                textureIndex = tonumber(texture)
            end
            textureIndex = textureIndex or GetFirstAllowedClothingVariantIndex(gender, category, model)
            if not textureIndex or not IsClothingVariantAllowed(gender, category, model, textureIndex) then
                goto continue_multi
            end

            local cacheTexture
            if asset.drawable then
                local variant = asset.variants and asset.variants[textureIndex]
                if not variant then goto continue_multi end
                local variantTint = variant.tint or {}
                cacheTexture = {
                    palette = textureIndex,
                    tint0 = tonumber(data.tint0) or (type(texture) == 'table' and tonumber(texture.tint0)) or tonumber(variant.tint0 or variantTint[1]) or 0,
                    tint1 = tonumber(data.tint1) or (type(texture) == 'table' and tonumber(texture.tint1)) or tonumber(variant.tint1 or variantTint[2]) or 0,
                    tint2 = tonumber(data.tint2) or (type(texture) == 'table' and tonumber(texture.tint2)) or tonumber(variant.tint2 or variantTint[3]) or 0,
                }
            else
                cacheTexture = textureIndex
            end

            ClothesCache[category] = { model = model, texture = cacheTexture }
            Equipped[category] = true
            changedCategories[#changedCategories + 1] = category
        end
        ::continue_multi::
    end

    -- Remove only the changed tags, then rebuild the whole cached outfit once using the
    -- deterministic layer order. Actual weapon entities are untouched.
    for _, category in ipairs(changedCategories) do
        RemoveMetaPedCategoryDeferred(ped, category)
    end
    ReequipAllClothes(ped)
    return true
end

-- Export the function
exports('EquipMultipleClothes', EquipMultipleClothes)
exports('RemoveAllClothesExceptEssentials', RemoveAllClothesExceptEssentials)
exports('UpdateCustomClothes', UpdateCustomClothes)
exports('NativeUpdatePedVariation', NativeUpdatePedVariation)
exports('NativeHasPedComponentLoaded', NativeHasPedComponentLoaded)
exports('SetMetaPedTag', SetMetaPedTag)

-- Register event for equipping multiple clothes
RegisterNetEvent("jrs_clothes:EquipMultipleClothes", function(clothesData, ped)
    EquipMultipleClothes(clothesData, ped)
end)