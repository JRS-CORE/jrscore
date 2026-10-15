-- jrs_core keeps the job list (GetJobs / AddJob / RemoveJob / SwitchJob, cooldown, max jobs).
-- This resource is the player-facing side: /myjobs and remembering every job a player gets.

local REASON = { cooldown = 'cooldown', max_jobs = 'max_jobs', active_job = 'active_job', job_not_owned = 'not_found', not_found = 'not_found' }

local function reasonText(reason)
    return L(REASON[reason or ''] or 'failed')
end

JRS.Callback('jrs_multijob:list', function(src)
    local char = JRS.Char(src)
    if not char then return nil end
    local jobs = exports.jrs_core:GetJobs(src) or {}
    local list = {}
    for name, info in pairs(jobs) do
        if not Config.IgnoreJobs[name] or name == char.job then
            list[#list + 1] = { name = name, label = info.label or name, grade = tonumber(info.grade) or 0, active = name == char.job }
        end
    end
    table.sort(list, function(a, b)
        if a.active ~= b.active then return a.active end
        return a.label < b.label
    end)
    return { active = char.jobLabel or char.job, jobs = list }
end)

JRS.Callback('jrs_multijob:switch', function(src, job)
    if type(job) ~= 'string' then return { ok = false, msg = L('failed') } end
    local ok, reason = exports.jrs_core:SwitchJob(src, job)
    if not ok then return { ok = false, msg = reasonText(reason) } end
    local info = (exports.jrs_core:GetJobs(src) or {})[job] or {}
    return { ok = true, msg = L('switched', info.label or job) }
end)

JRS.Callback('jrs_multijob:quit', function(src, job)
    if type(job) ~= 'string' then return { ok = false, msg = L('failed') } end
    local info = (exports.jrs_core:GetJobs(src) or {})[job] or {}
    local ok, reason = exports.jrs_core:RemoveJob(src, job)
    if not ok then return { ok = false, msg = reasonText(reason) } end
    return { ok = true, msg = L('quitted', info.label or job) }
end)

-- remember every job the player is given
if Config.CaptureJobChanges then
    AddEventHandler('jrs_core:server:jobChanged', function(src, job, grade)
        if not job or Config.IgnoreJobs[job] then return end
        local char = JRS.Char(src)
        local label = char and char.jobLabel or job
        exports.jrs_core:AddJob(src, job, grade, label)
    end)
end

RegisterCommand(Config.AdminRemoveCommand, function(src, args)
    if src > 0 and not JRS.IsAdmin(src) then return end
    local target, job = tonumber(args[1]), args[2]
    local function reply(text) if src > 0 then JRS.Notify(src, text) else print(text) end end
    if not target or not job or not GetPlayerName(target) then return reply(L('failed')) end
    local ok, reason = exports.jrs_core:RemoveJob(target, job)
    reply(ok and L('removed', job, target) or reasonText(reason))
end, false)
