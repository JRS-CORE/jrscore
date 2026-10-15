-- jrs_paycheck | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_paycheck | server
-- One loop, once per interval: look at every player who is in the game, work out what they are owed
-- right now (job wage + group stipend) from their live character, and pay it. Because the amount is
-- worked out at payment time, job, grade and group changes need no tracking at all.

local Core = exports.jrs_core:GetCore()

local function debug(...)
    if Config.DevMode then print('^3[jrs_paycheck]^7', ...) end
end

-- Duty is always decided by the server, never by a value the client can set.
local function onDuty(src, job, character)
    if type(job.IsOnDuty) == 'function' then
        return job.IsOnDuty(src, character.job, character.jobGrade) == true
    end
    if job.statebagKey == 'isPoliceDuty' and GetResourceState('jrs_police') == 'started' then
        return exports.jrs_police:isOnDuty(src) == true
    end
    if job.statebagKey == 'isMedicDuty' and GetResourceState('jrs_medic') == 'started' then
        return exports.jrs_medic:isOnDuty(src) == true
    end
    return job.statebagKey ~= nil and Player(src).state[job.statebagKey] == true
end

local function jobWage(src, character)
    local job = Config.Jobs[character.job]
    if not job then return end
    local amount = job.payment and job.payment[character.jobGrade]
    if not amount then return end
    if job.mustbeonduty and not onDuty(src, job, character) then return end
    return amount, job.currency or 0
end

local function groupWage(character)
    local group = Config.Groups[character.group]
    if group then return group.payment, group.currency or 0 end
end

local function pay(character, amount, currency, why, src)
    if not amount or amount <= 0 then return end
    character.addCurrency(currency, amount)
    debug(('paid %s %s (currency %d) to %d'):format(amount, why, currency, src))
end

local function payroll()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if Player(src).state.IsInSession then
            local user = Core.getUser(src)
            local character = user and user.getUsedCharacter
            if character then
                local amount, currency = jobWage(src, character)
                pay(character, amount, currency, 'job wage', src)

                amount, currency = groupWage(character)
                pay(character, amount, currency, 'group stipend', src)
            end
        end
    end
end

CreateThread(function()
    local step = math.max(10, tonumber(Config.PayEverySeconds) or 60) * 1000
    while true do
        Wait(step)
        local ok, err = pcall(payroll)
        if not ok then print('^1[jrs_paycheck]^7 payroll failed: ' .. tostring(err)) end
    end
end)
