-- ============================================================================
-- JRS CORE — STARTER ORIGIN & BACKGROUND SELECTION CLIENT HANDLER
-- ============================================================================
-- Renders interactive origin selection menu on first character entry.
-- ============================================================================

local isMenuOpen = false

local function OpenOriginMenu(origins)
    if isMenuOpen then return end
    isMenuOpen = true

    local elements = {}

    for originKey, origin in pairs(origins or {}) do
        table.insert(elements, {
            label = origin.label or originKey,
            value = originKey,
            desc = (origin.description or "") .. "\n" .. _U('starter_origin_starting_cash', origin.money or 0)
        })
    end

    TriggerEvent('jrs_core:menu:open', 'default', GetCurrentResourceName(), 'starter_origin_menu', {
        title = _U('starter_origin_title'),
        align = "top-left",
        elements = elements
    }, function(data, menu)
        local selectedOrigin = data.current.value
        menu.close()
        isMenuOpen = false

        TriggerServerEvent('jrs_core:server:selectStarterOrigin', selectedOrigin)
    end, function(data, menu)
        -- Do not allow closing without picking an origin on first entry
        menu.close()
        isMenuOpen = false
        SetTimeout(1000, function()
            OpenOriginMenu(origins)
        end)
    end)
end

RegisterNetEvent('jrs_core:client:openStarterOriginMenu', function(origins)
    OpenOriginMenu(origins)
end)

RegisterNetEvent('jrs_core:client:starterOriginCompleted', function(originConfig)
    isMenuOpen = false
    TriggerEvent('jrs_core:notify', _U('starter_origin_completed', tostring(originConfig.label), tonumber(originConfig.money or 0)), 6000)
end)

RegisterNetEvent('jrs_core:client:starterOriginAlreadySet', function()
    isMenuOpen = false
end)
