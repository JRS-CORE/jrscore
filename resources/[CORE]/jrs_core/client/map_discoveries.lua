-- jrs_core integrated map discoveries feature.

local discoveriesApplied = false

local function getMapDiscoveriesConfig()
    if type(Config) ~= "table" or type(Config.MapDiscoveries) ~= "table" then
        return nil
    end

    return Config.MapDiscoveries
end

local function debugPrint(message)
    local settings = getMapDiscoveriesConfig()
    if settings and settings.debug then
        print(("[jrs_core:map_discoveries] %s"):format(message))
    end
end

local function toggleAllMapDiscoveries(enable)
    if type(JRSMapDiscoveryData) ~= "table" then
        print("[jrs_core:map_discoveries] Discovery data is missing; feature was not applied.")
        return false
    end

    for _, discovery in ipairs(JRSMapDiscoveryData) do
        if enable then
            MapDiscoverRegion(discovery.hash)
        else
            MapDiscoverySetEnabled(discovery.hash, false)
        end
    end

    discoveriesApplied = enable == true
    debugPrint(("%d map discoveries %s."):format(
        #JRSMapDiscoveryData,
        enable and "enabled" or "disabled"
    ))

    return true
end

Citizen.CreateThread(function()
    local settings = getMapDiscoveriesConfig()
    if not settings or settings.enabled ~= true then
        debugPrint("Feature is disabled in config/config.lua.")
        return
    end

    toggleAllMapDiscoveries(true)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    local settings = getMapDiscoveriesConfig()
    if discoveriesApplied and settings and settings.disableOnResourceStop ~= false then
        toggleAllMapDiscoveries(false)
    end
end)
