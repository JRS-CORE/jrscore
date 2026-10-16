local RESOURCE = GetCurrentResourceName()
local HEADERS  = { ['User-Agent'] = 'jrs_updater', ['Accept'] = 'application/vnd.github+json' }
local running  = false
local lastReport = nil

local function log(color, msg)
    print(('%s[%s]^7 %s'):format(color, RESOURCE, msg))
end

local WIDTH = 72
local function rule(char)
    print('^5' .. string.rep(char or '=', WIDTH) .. '^7')
end

local LOGO = [=[
        _   _____     _____    _____    ____    _____    ______
       | | |  __ \   / ____|  / ____|  / __ \  |  __ \  |  ____|
       | | | |__) | | (___   | |      | |  | | | |__) | | |__
   _   | | |  _  /   \___ \  | |      | |  | | |  _  /  |  __|
  | |__| | | | \ \   ____) | | |____  | |__| | | | \ \  | |____
   \____/  |_|  \_\ |_____/   \_____|  \____/  |_|  \_\ |______|
]=]

local function countJrsResources()
    local started, total = 0, 0
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and name:sub(1, 4) == 'jrs_' then
            total = total + 1
            if GetResourceState(name) == 'started' then started = started + 1 end
        end
    end
    return started, total
end

local function printBanner()
    local pack = GetResourceMetadata(RESOURCE, 'jrscore_pack', 0) or '?'
    local started, total = countJrsResources()
    print('')
    rule('=')
    for line in LOGO:gmatch('[^\n]+') do print('^5' .. line .. '^7') end
    print('')
    print('^7  FREE RedM ROLEPLAY FRAMEWORK')
    rule('-')
    print(('^7  Version     : ^2%s^7'):format(pack))
    print(('^7  Resources   : ^2%d^7 / %d jrs_* started'):format(started, total))
    print(('^7  GitHub      : ^5github.com/%s^7'):format(Config.Repo))
    print(('^7  Updates     : first check in %ds, then every %sh  (^3%s^7 to check now)'):format(
        Config.StartDelaySec, Config.IntervalHours > 0 and tostring(Config.IntervalHours) or '-', Config.Command))
    rule('=')
    print('')
end

-- HTTP GET that can be awaited from a thread.
local function httpGet(url)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body)
        p:resolve({ status = status, body = body })
    end, 'GET', '', HEADERS)
    return Citizen.Await(p)
end

local function encodePath(path)
    return (path:gsub('[^%w%-%._~/]', function(c)
        return ('%%%02X'):format(c:byte())
    end))
end

-- "2.5.6-habitats" -> { 2, 5, 6 }
local function parseVersion(v)
    local parts = {}
    for n in tostring(v or ''):gmatch('%d+') do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

-- 1 = a newer than b, -1 = older, 0 = same numbers
local function compareVersions(a, b)
    local pa, pb = parseVersion(a), parseVersion(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

local function remoteManifestVersion(body)
    body = body:gsub('%-%-%[%[.-%]%]', '')
    for line in body:gmatch('[^\r\n]+') do
        if not line:match('^%s*%-%-') then
            local v = line:match('^%s*version%s+[\'"]([^\'"]+)[\'"]')
            if v then return v end
        end
    end
end

local function isTracked(name)
    for _, prefix in ipairs(Config.Prefixes) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    for _, n in ipairs(Config.Include) do
        if n == name then return true end
    end
    return false
end

local function localVersion(name)
    if GetResourceState(name) == 'missing' then return nil end
    return GetResourceMetadata(name, 'version', 0) or '?'
end

-- Returns { {name=, path=} ... } for every tracked fxmanifest.lua in the repo.
local function listRemoteResources()
    local url = ('https://api.github.com/repos/%s/git/trees/%s?recursive=1'):format(Config.Repo, Config.Branch)
    local res = httpGet(url)
    if res.status ~= 200 then
        return nil, ('GitHub API returned %s (rate limit or wrong repo?)'):format(tostring(res.status))
    end
    local data = json.decode(res.body or '{}')
    if not data or not data.tree then return nil, 'unexpected GitHub response' end

    local out, seen = {}, {}
    for _, item in ipairs(data.tree) do
        local dir = item.path:match('^resources/(.+)/fxmanifest%.lua$')
        if dir and not dir:find('node_modules', 1, true) then
            local name = dir:match('([^/]+)$')
            if isTracked(name) and not seen[name] then
                seen[name] = true
                out[#out + 1] = { name = name, path = item.path }
            end
        end
    end
    return out
end

local function latestRelease()
    local res = httpGet(('https://api.github.com/repos/%s/releases/latest'):format(Config.Repo))
    if res.status ~= 200 then return nil end
    local data = json.decode(res.body or '{}')
    return data and data.tag_name, data and data.html_url
end

local function fetchVersions(items)
    local results, index, active = {}, 0, 0
    local total = #items
    local done = promise.new()

    local function worker()
        while true do
            index = index + 1
            local item = items[index]
            if not item then break end
            local url = ('https://raw.githubusercontent.com/%s/%s/%s'):format(Config.Repo, Config.Branch, encodePath(item.path))
            local res = httpGet(url)
            if res.status == 200 then
                results[item.name] = remoteManifestVersion(res.body or '')
            end
        end
        active = active - 1
        if active == 0 then done:resolve(true) end
    end

    if total == 0 then return results end
    local workers = math.min(Config.Concurrency, total)
    for _ = 1, workers do
        active = active + 1
        CreateThread(worker)
    end
    Citizen.Await(done)
    return results
end

local function sendWebhook(lines)
    local url = GetConvar(Config.WebhookConvar, '')
    if url == '' then return end
    local content = table.concat(lines, '\n')
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'JRS Updater',
        content  = content:sub(1, 1900),
    }), { ['Content-Type'] = 'application/json' })
end

local function runCheck(manual)
    if running then
        log('^3', 'a check is already running')
        return
    end
    running = true

    local ok, err = pcall(function()
        print('')
        rule('-')
        log('^5', ('UPDATE CHECK  %s (%s)'):format(Config.Repo, Config.Branch))

        local remote, why = listRemoteResources()
        if not remote then
            log('^1', 'update check failed: ' .. why)
            return
        end

        local versions = fetchVersions(remote)
        local outdated, newer, missing, current = {}, {}, {}, 0

        for _, item in ipairs(remote) do
            local name   = item.name
            local theirs = versions[name]
            local mine   = localVersion(name)
            if theirs then
                if not mine then
                    missing[#missing + 1] = ('%s %s'):format(name, theirs)
                else
                    local cmp = compareVersions(theirs, mine)
                    if cmp > 0 or (cmp == 0 and theirs ~= mine) then
                        outdated[#outdated + 1] = ('%s  %s -> %s'):format(name, mine, theirs)
                    elseif cmp < 0 then
                        newer[#newer + 1] = ('%s  local %s, GitHub %s'):format(name, mine, theirs)
                    else
                        current = current + 1
                    end
                end
            end
        end

        local tag, releaseUrl = latestRelease()
        local packVersion = GetResourceMetadata(RESOURCE, 'jrscore_pack', 0) or '0'
        local packOutdated = tag and compareVersions(tag, packVersion) > 0

        table.sort(outdated); table.sort(newer); table.sort(missing)

        local report = {}
        if packOutdated then
            report[#report + 1] = ('New JRS Core release: %s (installed pack %s) %s'):format(tag, packVersion, releaseUrl or '')
        end
        if #outdated > 0 then
            report[#report + 1] = ('%d resource(s) have an update on GitHub:'):format(#outdated)
            for _, l in ipairs(outdated) do report[#report + 1] = '  - ' .. l end
        end

        if packOutdated then
            log('^3', ('new JRS Core release %s (installed pack %s) %s'):format(tag, packVersion, releaseUrl or ''))
        end
        if #outdated > 0 then
            log('^3', ('%d resource(s) have an update on GitHub:'):format(#outdated))
            for _, l in ipairs(outdated) do print('^3   - ' .. l .. '^7') end
        end
        if #newer > 0 and manual then
            log('^5', ('%d resource(s) are newer locally than on GitHub:'):format(#newer))
            for _, l in ipairs(newer) do print('^5   - ' .. l .. '^7') end
        end
        if Config.ShowNewResources and #missing > 0 and manual then
            log('^5', ('%d resource(s) on GitHub are not installed here:'):format(#missing))
            for _, l in ipairs(missing) do print('^5   - ' .. l .. '^7') end
        end

        if #outdated == 0 and not packOutdated then
            log('^2', ('up to date (%d resources checked)'):format(current))
        else
            log('^3', 'update by copying the new files from GitHub into your resources folder (keep your config files), then restart.')
        end

        rule('-')
        print('')

        lastReport = {
            checkedAt = os.time(), packOutdated = packOutdated and tag or false,
            outdated = outdated, newer = newer, missing = missing, upToDate = current,
        }

        -- notify Discord only when something is outdated
        if #report > 0 then sendWebhook(report) end
    end)

    running = false
    if not ok then log('^1', 'error: ' .. tostring(err)) end
end

RegisterCommand(Config.Command, function(source)
    if source ~= 0 then return end
    CreateThread(function() runCheck(true) end)
end, true)

exports('GetUpdateStatus', function() return lastReport end)

CreateThread(function()
    Wait(500)
    printBanner()
end)

CreateThread(function()
    if not Config.CheckOnStart then return end
    Wait(Config.StartDelaySec * 1000)
    runCheck(false)
    if Config.IntervalHours > 0 then
        while true do
            Wait(Config.IntervalHours * 3600 * 1000)
            runCheck(false)
        end
    end
end)
