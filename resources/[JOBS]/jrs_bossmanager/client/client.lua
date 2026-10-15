-- JRS boss menu (client)
local function notify(text) if text and text ~= '' then JRS.Notify(text, 5000) end end
RegisterNetEvent('jrs_bossmanager:notify', function(text, ms) JRS.Notify(text, ms or 5000) end)

local OpenBossMenu

local function gradeOptions()
    local opts = {}
    for g = 0, Config.MaxGrade do opts[#opts + 1] = tostring(g) end
    return opts
end

local function openHire()
    local ids = {}
    local me, pos = PlayerId(), GetEntityCoords(PlayerPedId())
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= me and #(GetEntityCoords(GetPlayerPed(pid)) - pos) <= Config.HireRange then
            ids[#ids + 1] = GetPlayerServerId(pid)
        end
    end
    local list = #ids > 0 and (JRS.Await('jrs_bossmanager:nearby', ids) or {}) or {}

    local elements = {}
    -- a slider row per player: the slider position (el.value) is the grade, the player id rides in `target`
    for _, p in ipairs(list) do
        elements[#elements + 1] = { label = L('confirm_hire', p.name), target = p.id, value = 0, desc = L('grade_desc'),
            type = 'slider', options = gradeOptions() }
    end
    if #elements == 0 then elements[1] = { label = L('nobody_near'), value = 'none', disabled = true, desc = '' } end

    JRS.OpenMenu('jrs_boss_hire', L('title'), L('hire'), elements, function(el, menu)
        if el.value == 'none' or not el.target then return end
        menu.close()
        local _, msg = JRS.Await('jrs_bossmanager:hire', el.target, tonumber(el.value) or 0)
        notify(msg)
        OpenBossMenu()
    end, function() OpenBossMenu() end)
end

local function openEmployee(emp)
    local elements = {}
    if emp.grade < Config.MaxGrade then elements[#elements + 1] = { label = L('promote', emp.grade + 1), value = 'up', desc = '' } end
    if emp.grade > 0 then elements[#elements + 1] = { label = L('demote', emp.grade - 1), value = 'down', desc = '' } end
    elements[#elements + 1] = { label = L('fire'), value = 'fire', desc = '' }

    JRS.OpenMenu('jrs_boss_emp', emp.name, ('%s %s  |  %s'):format(L('grade'), emp.grade, emp.online and L('online') or L('offline')),
        elements, function(el, menu)
            menu.close()
            local _, msg
            if el.value == 'up' then
                _, msg = JRS.Await('jrs_bossmanager:setGrade', emp.charId, emp.grade + 1)
            elseif el.value == 'down' then
                _, msg = JRS.Await('jrs_bossmanager:setGrade', emp.charId, emp.grade - 1)
            else
                if JRS.Confirm({ header = emp.name, content = L('fire') .. '?' }) ~= 'confirm' then return OpenBossMenu() end
                _, msg = JRS.Await('jrs_bossmanager:fire', emp.charId)
            end
            notify(msg)
            OpenBossMenu()
        end, function() OpenBossMenu() end)
end

local function openEmployees(job, list)
    local elements = {}
    for i, e in ipairs(list) do
        elements[#elements + 1] = { label = e.name, value = i, rightLabel = ('%s %s'):format(L('grade'), e.grade),
            desc = e.online and L('online') or L('offline') }
    end
    if #elements == 0 then elements[1] = { label = '-', value = 'none', disabled = true, desc = '' } end
    JRS.OpenMenu('jrs_boss_list', L('title'), L('employees', #list) .. ' - ' .. job, elements, function(el, menu)
        local emp = list[el.value]
        if not emp then return end
        menu.close()
        openEmployee(emp)
    end, function() OpenBossMenu() end)
end

OpenBossMenu = function()
    local job, list = JRS.Await('jrs_bossmanager:open')
    if not job then return notify(L('not_boss')) end
    list = list or {}
    JRS.OpenMenu('jrs_boss', L('title'), job, {
        { label = L('hire'), value = 'hire', desc = L('hire_desc') },
        { label = L('employees', #list), value = 'list', desc = L('employees_d') },
        { label = L('close'), value = 'close', desc = '' },
    }, function(el, menu)
        menu.close()
        if el.value == 'hire' then openHire()
        elseif el.value == 'list' then openEmployees(job, list) end
    end)
end

if Config.Command then RegisterCommand(Config.Command, function() OpenBossMenu() end, false) end

CreateThread(function()
    while true do
        Wait(0)
        if IsControlJustReleased(0, Config.Key) and not IsPauseMenuActive() then
            OpenBossMenu()
            Wait(500)
        end
    end
end)

exports('OpenBossMenu', function() OpenBossMenu() end)
