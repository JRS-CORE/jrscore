-- jrs_mdt | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- JRS characters in the player shape the MDT code works with.
MDTCore = {}

local function build(src)
    src = tonumber(src)
    if not src then return nil end
    local c = JRS.Char(src)
    if not c then return nil end
    local grade = tonumber(c.jobGrade) or 0
    local p = {
        PlayerData = {
            source = src,
            citizenid = tostring(c.charIdentifier),
            charinfo = { firstname = c.firstname or '', lastname = c.lastname or '' },
            job = {
                name = c.job or 'unemployed', label = c.jobLabel or c.job or 'unemployed',
                grade = { level = grade, name = tostring(grade) },
                onduty = true,
            },
            money = { cash = tonumber(c.money) or 0 },
            metadata = {},
        },
    }
    p.Functions = {
        SetJob = function(job, g) return exports.jrs_core:SetJob(src, job, g) end,
        SetMetaData = function() end, -- jail / records live in the MDT tables and jrs_police
        RemoveMoney = function(kind, amount)
            if kind ~= 'cash' then return false end
            return JRS.TakeMoney(src, amount)
        end,
    }
    return p
end

MDTCore.GetPlayer = build

function MDTCore.GetPlayers()
    local out = {}
    for _, s in ipairs(GetPlayers()) do out[#out + 1] = tonumber(s) end
    return out
end

function MDTCore.GetPlayerByCitizenId(citizenid)
    citizenid = tostring(citizenid)
    for _, s in ipairs(GetPlayers()) do
        local c = JRS.Char(s)
        if c and tostring(c.charIdentifier) == citizenid then return build(s) end
    end
end

-- The officer runs jrs_police's own /jail on the target (keeps police permissions + jail logic)
function MDTJail(officerSrc, targetSrc, minutes)
    TriggerClientEvent('jrs_mdt:client:runJail', officerSrc, targetSrc, minutes)
end
