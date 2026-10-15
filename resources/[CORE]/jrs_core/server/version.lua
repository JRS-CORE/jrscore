-- JRS - startup banner + version reporting.
--
-- Two jobs:
--   1. Print the JRS banner AFTER every resource has finished starting, so it is
--      the last thing in the boot log instead of being buried mid-boot.
--   2. Report the version of every JRS resource (read from each fxmanifest's
--      `version`) and, when a remote manifest is configured, say whether each
--      one is up to date.
--
-- Version source of truth: each resource's own fxmanifest `version` field, plus
-- `versions.json` in this resource, which lists the expected/latest versions.

local BOOT_SETTLE_MS = 2500   -- print once no new resource has started for this long
local lastResourceStart = 0
local reported = false

local function isJrsResource(name)
    name = tostring(name or ''):lower()
    return name:find('jrs', 1, true) ~= nil
end

local function resourceVersion(name)
    local ok, ver = pcall(GetResourceMetadata, name, 'version', 0)
    if ok and ver and tostring(ver) ~= '' then return tostring(ver) end
    return '--'
end

-- Collect { name = version } for every started JRS resource.
local function collectVersions()
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and isJrsResource(name) and GetResourceState(name) == 'started' then
            list[#list + 1] = { name = name, version = resourceVersion(name) }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

JRSVersions = JRSVersions or {}

-- Expected versions, loaded from versions.json in this resource. Any resource
-- listed there whose live version differs is reported as out of date.
local function loadExpected()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'versions.json')
    if not raw or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    return type(decoded.resources) == 'table' and decoded.resources or decoded
end

local function printBanner()
-- JRS startup banner (kept intentionally; fully green).
print("^2")
print("^2╔══════════════════════════════════════════════════════════════════════╗")
print("^2║                                                                      ║")
print("^2║     ██╗ ██████╗  ███████╗        ██████╗ ██████╗ ██████╗ ███████╗    ║")
print("^2║     ██║ ██╔══██╗ ██╔════╝       ██╔════╝██╔═══██╗██╔══██╗██╔════╝    ║")
print("^2║     ██║ ██████╔╝ ███████╗       ██║     ██║   ██║██████╔╝█████╗      ║")
print("^2║██   ██║ ██╔══██╗ ╚════██║       ██║     ██║   ██║██╔══██╗██╔══╝      ║")
print("^2║╚█████╔╝ ██║  ██║ ███████║       ╚██████╗╚██████╔╝██║  ██║███████╗    ║")
print("^2║ ╚════╝  ╚═╝  ╚═╝ ╚══════╝        ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝    ║")
print("^2║                                                                      ║")
print("^2╠═══════════════════════════[ SYSTEM READY ]═══════════════════════════╣")
print("^2║                         J-R-S FRAMEWORK                              ║")
print("^2╚══════════════════════════════════════════════════════════════════════╝")
print("^2")
end

-- Compare two version strings numerically, segment by segment. A plain string
-- compare cannot tell "1.10.0" from "1.9.0", and cannot tell whether a mismatch
-- means behind or ahead. Any trailing suffix (-beta, -jrs-radio-slot) is ignored
-- for ordering; only the numeric segments decide.
-- Returns -1 when a < b, 0 when equal, 1 when a > b.
local function compareVersions(a, b)
    local av, bv = {}, {}
    for n in tostring(a or ''):gmatch('%d+') do av[#av + 1] = tonumber(n) end
    for n in tostring(b or ''):gmatch('%d+') do bv[#bv + 1] = tonumber(n) end

    for i = 1, math.max(#av, #bv) do
        local x, y = av[i] or 0, bv[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local function printVersionReport()
    local list = collectVersions()
    local expected = loadExpected()
    JRSVersions.list = list
    JRSVersions.expected = expected

    local outdated, ahead, unknown = 0, 0, 0

    -- One line per resource, in the familiar "IS UP TO DATE!" style.
    for _, entry in ipairs(list) do
        local want = expected[entry.name]
        if want == nil then
            unknown = unknown + 1
            print(('VERSION: ^3%s^7 ^2v%s^7 ^3IS NOT REGISTERED^7 (add it to versions.json)')
                :format(entry.name, entry.version))
        elseif tostring(want) == entry.version then
            print(('VERSION: ^3%s^7 ^2v%s^7 ^2IS UP TO DATE!^7'):format(entry.name, entry.version))
        elseif compareVersions(entry.version, want) > 0 then
            -- Installed is NEWER than the registry. That is an updated resource
            -- whose versions.json entry was not bumped, not an out-of-date one -
            -- calling it OUTDATED sent people looking for an update that does
            -- not exist.
            ahead = ahead + 1
            print(('VERSION: ^3%s^7 ^2v%s^7 ^3IS NEWER THAN THE REGISTRY^7 (versions.json still says ^3v%s^7 - bump it)')
                :format(entry.name, entry.version, tostring(want)))
        else
            outdated = outdated + 1
            print(('VERSION: ^3%s^7 ^2v%s^7 ^1IS OUTDATED!^7 (latest ^2v%s^7)')
                :format(entry.name, entry.version, tostring(want)))
        end
    end

    print(('^2[JRS] %s resources checked | %s outdated | %s ahead of registry | %s unregistered^7')
        :format(#list, outdated, ahead, unknown))
end

-- Any resource starting pushes the report back, so it always lands last.
AddEventHandler('onResourceStart', function()
    lastResourceStart = GetGameTimer()
end)

CreateThread(function()
    lastResourceStart = GetGameTimer()
    while true do
        Wait(500)
        if not reported and (GetGameTimer() - lastResourceStart) >= BOOT_SETTLE_MS then
            reported = true
            printBanner()
            printVersionReport()
        end
    end
end)

exports('GetResourceVersions', function()
    return JRSVersions.list or collectVersions()
end)

exports('GetResourceVersion', function(resourceName)
    return resourceVersion(tostring(resourceName or ''))
end)
