--------------------------------------------------------------------------------------------
-- JRS SAMPLES - client: samples journal (JRS menus) + leaderboard prompt + revive notice
--------------------------------------------------------------------------------------------
local journal -- last data sent by the server

AddEventHandler('jrs_samples:ReviveData', function()
    JRS.Notify(L('revived'), 4000)
end)

local function pretty(name)
    return (tostring(name):gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

local openJournal

local function sampleList(collectedOnly)
    local d = journal
    local list = {}
    for _, animal in pairs(d.allSamples or {}) do
        local have = d.collectedSamples[animal.name] ~= nil
        if have == collectedOnly then
            local tags = {}
            if animal.legendary then tags[#tags + 1] = L('ui_legendary') end
            if d.featuredAnimal == animal.name then tags[#tags + 1] = L('ui_featured', d.featuredMultiplier) end
            tags[#tags + 1] = L('ui_reward', animal.reward)
            list[#list + 1] = { label = pretty(animal.name), value = animal.name, desc = animal.category .. '  |  ' .. table.concat(tags, '  |  ') }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    if #list == 0 then list[1] = { label = L('ui_no_samples'), value = 'none', desc = '' } end
    JRS.OpenMenu('jrs_samples_list', L('ui_title'), L(collectedOnly and 'ui_tab_samples' or 'ui_tab_missing'), list, function() end,
        function() openJournal() end)
end

local function leaderboard()
    local list = {}
    for _, row in ipairs(journal.topCollectors or {}) do
        list[#list + 1] = { label = ('#%d  %s'):format(row.rank, row.name or '?'), value = row.rank, desc = L('ui_samples_count', row.sample_count or 0) }
    end
    if #list == 0 then list[1] = { label = L('ui_no_samples'), value = 'none', desc = '' } end
    JRS.OpenMenu('jrs_samples_top', L('ui_title'), L('ui_tab_leaderboard'), list, function() end, function() openJournal() end)
end

local function stats()
    local g = journal.globalStats or {}
    local list = {
        { label = L('ui_total_all'), value = 1, desc = tostring(g.totalCollected or 0) },
        { label = L('ui_rarest'), value = 2, desc = g.rarestAnimal and pretty(g.rarestAnimal) or L('ui_none') },
        { label = L('ui_weekly_top'), value = 3, desc = g.weeklyTopName and ('%s (%d)'):format(g.weeklyTopName, g.weeklyTopCount or 0) or L('ui_none') },
        { label = L('ui_featured_now'), value = 4, desc = (journal.featuredAnimal or '') ~= '' and pretty(journal.featuredAnimal) or L('ui_none') },
    }
    JRS.OpenMenu('jrs_samples_stats', L('ui_title'), L('ui_tab_stats'), list, function() end, function() openJournal() end)
end

openJournal = function()
    local total, have = 0, 0
    for _, animal in pairs(journal.allSamples or {}) do
        total = total + 1
        if journal.collectedSamples[animal.name] then have = have + 1 end
    end
    JRS.OpenMenu('jrs_samples', L('ui_title'), journal.playerName or '', {
        { label = L('ui_tab_samples'), value = 'mine', desc = L('ui_progress', have, total) },
        { label = L('ui_tab_missing'), value = 'missing', desc = '' },
        { label = L('ui_tab_leaderboard'), value = 'top', desc = '' },
        { label = L('ui_tab_stats'), value = 'stats', desc = '' },
    }, function(el)
        if el.value == 'mine' then sampleList(true)
        elseif el.value == 'missing' then sampleList(false)
        elseif el.value == 'top' then leaderboard()
        else stats() end
    end)
end

RegisterNetEvent('jrs_samples:client:openSamplesMenu', function(data)
    if type(data) ~= 'table' then return end
    data.collectedSamples = data.collectedSamples or {}
    journal = data
    openJournal()
end)

TriggerEvent('chat:addSuggestion', '/samplesmenu', L('cmd_samplesmenu'))

-- leaderboard spot: prompt + blip
CreateThread(function()
    local loc = Config.LeaderboardLocation
    local blip
    if Config.ShowBlip then
        blip = JRS.Blip(loc.coords, Config.BlipSprite, LE('blip_label'), Config.BlipScale)
        if Config.BlipColor and Config.BlipColor ~= '' then
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(Config.BlipColor))
        end
    end
    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() and blip then RemoveBlip(blip) end
    end)

    local prompts = JRS.Prompts()
    local open = prompts:add(0x760A9C6F, LE('target_leaderboard'))
    while true do
        local dist = #(GetEntityCoords(PlayerPedId()) - loc.coords)
        if dist < (loc.radius or 1.5) + 1.0 then
            prompts:show(LE('blip_label'))
            if prompts:done(open) then
                TriggerServerEvent('jrs_samples:server:requestMenu')
                Wait(1000)
            end
            Wait(0)
        else
            Wait(dist < 30.0 and 250 or 1500)
        end
    end
end)
