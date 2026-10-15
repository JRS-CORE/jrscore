-- JRS Clothing - law-enforcement clothing access filter.
-- This layer never reorders ClothingAssets, so existing saved outfit indices remain stable.

JrsClothingAssetIndices = JrsClothingAssetIndices or {}
JrsClothingVariantIndices = JrsClothingVariantIndices or {}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function listContains(list, value)
    value = lower(value)
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        if lower(entry) == value then return true end
    end
    return false
end

local function containsAny(value, keywords)
    value = lower(value)
    if value == "" then return false end
    for _, keyword in ipairs(type(keywords) == "table" and keywords or {}) do
        keyword = lower(keyword)
        if keyword ~= "" and string.find(value, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function lawSettings()
    return type(ClothingConfig) == "table" and type(ClothingConfig.LawClothing) == "table"
        and ClothingConfig.LawClothing or {}
end

function IsLawClothingAvailable()
    return lawSettings().Enabled == true
end

local function isBlockedLawCategory(category)
    if IsLawClothingAvailable() then return false end
    return listContains(lawSettings().BlockedCategories, category)
end

local function isLawPed(pedName)
    if IsLawClothingAvailable() then return false end
    pedName = lower(pedName)
    if pedName == "" then return false end

    -- A prisoner can be sourced from a law-camp ped without being law clothing.
    if containsAny(pedName, lawSettings().PedExceptions) then
        return false
    end

    return containsAny(pedName, lawSettings().PedKeywords)
end

local function isLawHashName(hashName)
    if IsLawClothingAvailable() then return false end
    return containsAny(hashName, lawSettings().HashNameKeywords)
end

local function getAllowedDrawableVariants(category, asset)
    local allowed = {}
    if type(asset) ~= "table" or type(asset.variants) ~= "table" then return allowed end
    for variantIndex, variant in ipairs(asset.variants) do
        if not isBlockedLawCategory(category) and not isLawPed(type(variant) == "table" and variant.ped or nil) then
            table.insert(allowed, variantIndex)
        end
    end
    return allowed
end

local function getAllowedShopVariants(category, asset)
    local allowed = {}
    if type(asset) ~= "table" or isBlockedLawCategory(category) then return allowed end
    for variantIndex, item in ipairs(asset) do
        if type(item) == "table" and item.hash and not isLawHashName(item.hashname) then
            table.insert(allowed, variantIndex)
        end
    end
    return allowed
end

function RefreshJrsClothingAccessIndex()
    JrsClothingAssetIndices = {}
    JrsClothingVariantIndices = {}

    for gender, categories in pairs(type(ClothingAssets) == "table" and ClothingAssets or {}) do
        JrsClothingAssetIndices[gender] = {}
        JrsClothingVariantIndices[gender] = {}

        for category, assets in pairs(type(categories) == "table" and categories or {}) do
            local all, mp, npc = {}, {}, {}
            JrsClothingVariantIndices[gender][category] = {}

            for assetIndex, asset in ipairs(type(assets) == "table" and assets or {}) do
                local allowed = true
                if not IsLawClothingAvailable() then
                    if isBlockedLawCategory(category) then
                        JrsClothingVariantIndices[gender][category][assetIndex] = {}
                        allowed = false
                    elseif type(asset) == "table" and asset.drawable then
                        local variants = getAllowedDrawableVariants(category, asset)
                        JrsClothingVariantIndices[gender][category][assetIndex] = variants
                        allowed = #variants > 0
                    else
                        local variants = getAllowedShopVariants(category, asset)
                        JrsClothingVariantIndices[gender][category][assetIndex] = variants
                        allowed = #variants > 0
                    end
                elseif type(asset) == "table" then
                    local variants = {}
                    if asset.drawable and type(asset.variants) == "table" then
                        for variantIndex in ipairs(asset.variants) do table.insert(variants, variantIndex) end
                    else
                        for variantIndex, item in ipairs(asset) do
                            if type(item) == "table" and item.hash then table.insert(variants, variantIndex) end
                        end
                    end
                    JrsClothingVariantIndices[gender][category][assetIndex] = variants
                end

                if allowed then
                    table.insert(all, assetIndex)
                    if type(asset) == "table" and asset.drawable then
                        table.insert(npc, assetIndex)
                    else
                        table.insert(mp, assetIndex)
                    end
                end
            end

            JrsClothingAssetIndices[gender][category] = { all = all, mp = mp, npc = npc }
        end
    end
end

function GetAllowedClothingAssetIndices(gender, category, mode)
    local categoryMap = JrsClothingAssetIndices[gender] and JrsClothingAssetIndices[gender][category]
    if not categoryMap then return {} end
    mode = mode == "mp" and "mp" or (mode == "npc" and "npc" or "all")
    return categoryMap[mode] or {}
end

function ResolveAllowedClothingAssetIndex(gender, category, uiIndex, mode)
    uiIndex = tonumber(uiIndex)
    if not uiIndex or uiIndex <= 0 then return uiIndex end
    return GetAllowedClothingAssetIndices(gender, category, mode)[uiIndex]
end

function GetAllowedClothingAssetUiIndex(gender, category, assetIndex, mode)
    assetIndex = tonumber(assetIndex)
    if not assetIndex or assetIndex <= 0 then return 0 end
    for uiIndex, realIndex in ipairs(GetAllowedClothingAssetIndices(gender, category, mode)) do
        if realIndex == assetIndex then return uiIndex end
    end
    return 0
end

function IsClothingAssetAllowed(gender, category, assetIndex)
    assetIndex = tonumber(assetIndex)
    if not assetIndex or assetIndex <= 0 then return true end
    return GetAllowedClothingAssetUiIndex(gender, category, assetIndex, "all") > 0
end

function GetAllowedClothingVariantIndices(gender, category, assetIndex)
    local byGender = JrsClothingVariantIndices[gender]
    local byCategory = byGender and byGender[category]
    local variants = byCategory and byCategory[tonumber(assetIndex)]
    if type(variants) == "table" then return variants end

    local asset = ClothingAssets and ClothingAssets[gender] and ClothingAssets[gender][category]
        and ClothingAssets[gender][category][tonumber(assetIndex)]
    local fallback = {}
    if type(asset) == "table" then
        if asset.drawable and asset.variants then
            for i in ipairs(asset.variants) do table.insert(fallback, i) end
        else
            for i, item in ipairs(asset) do
                if type(item) == "table" and item.hash then table.insert(fallback, i) end
            end
        end
    end
    return fallback
end

function IsClothingVariantAllowed(gender, category, assetIndex, variantIndex)
    variantIndex = tonumber(variantIndex)
    if not variantIndex or variantIndex <= 0 then return true end
    for _, realIndex in ipairs(GetAllowedClothingVariantIndices(gender, category, assetIndex)) do
        if realIndex == variantIndex then return true end
    end
    return false
end

function ResolveAllowedClothingVariantIndex(gender, category, assetIndex, uiIndex)
    uiIndex = tonumber(uiIndex)
    if not uiIndex or uiIndex <= 0 then return uiIndex end
    return GetAllowedClothingVariantIndices(gender, category, assetIndex)[uiIndex]
end

function GetAllowedClothingVariantUiIndex(gender, category, assetIndex, variantIndex)
    variantIndex = tonumber(variantIndex)
    if not variantIndex or variantIndex <= 0 then return 1 end
    for uiIndex, realIndex in ipairs(GetAllowedClothingVariantIndices(gender, category, assetIndex)) do
        if realIndex == variantIndex then return uiIndex end
    end
    return 1
end

function GetFirstAllowedClothingVariantIndex(gender, category, assetIndex)
    return GetAllowedClothingVariantIndices(gender, category, assetIndex)[1]
end

RefreshJrsClothingAccessIndex()
