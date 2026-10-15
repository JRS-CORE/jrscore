local openJobs

local function jobMenu(job)
    local elements = {}
    if not job.active then
        elements[#elements + 1] = { label = L('switch'), value = 'switch', desc = '' }
        elements[#elements + 1] = { label = L('quit'), value = 'quit', desc = '' }
    end
    elements[#elements + 1] = { label = L('back'), value = 'back', desc = '' }

    JRS.OpenMenu('jrs_multijob_job', job.label, L('grade', job.grade), elements, function(el, menu)
        menu.close()
        if el.value == 'switch' or el.value == 'quit' then
            local res = JRS.Await('jrs_multijob:' .. el.value, job.name)
            if res and res.msg then JRS.Notify(res.msg) end
        end
        openJobs()
    end, function() openJobs() end)
end

openJobs = function()
    local data = JRS.Await('jrs_multijob:list')
    if not data then return end
    if #data.jobs == 0 then return JRS.Notify(L('no_jobs')) end
    local elements = {}
    for _, job in ipairs(data.jobs) do
        elements[#elements + 1] = {
            label = job.label, value = job.name, job = job,
            desc = job.active and (L('active') .. '  |  ' .. L('grade', job.grade)) or L('grade', job.grade),
        }
    end
    JRS.OpenMenu('jrs_multijob', L('title'), L('subtitle', data.active or '-'), elements, function(el, menu)
        menu.close()
        if el.job then jobMenu(el.job) end
    end)
end

RegisterCommand(Config.Command, function() CreateThread(openJobs) end, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.Command, L('cmd_help'))
