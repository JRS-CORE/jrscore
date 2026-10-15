-- jrs_minigame | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_minigame | client
-- exports.jrs_minigame:taskBar(difficulty, skillGap)
--   difficulty  how long the bar takes to fill, in ms (smaller = faster = harder)
--   skillGap    width of the target zone in percent (small = harder)
-- returns 100 when the player hit the zone, 0 when they missed, ran out of time or cancelled.
--
-- The page runs the bar and reports the result; this file only starts it and keeps track of fatigue.

local running                 -- promise of the bar that is on screen
local fatigue = 1.0           -- 1.0 = fresh; falls with every miss and slowly recovers
local frustrated = false

local function text(key)
    local code = (JrsLang and JrsLang.Current and JrsLang.Current()) or 'en'
    local set = Config.Text[code] or Config.Text.en
    return set[key] or Config.Text.en[key]
end

local function isRtl()
    return JrsLang and JrsLang.Current and JrsLang.Current() == 'ar' or false
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ------------------------------------------------------------------ fatigue

local function miss()
    fatigue = math.max(Config.FatigueFloor, fatigue - Config.FatigueStep)
    if fatigue <= Config.FrustratedBelow and not frustrated then
        frustrated = true
        TriggerEvent('jrs:TipRight', text('frustrated'), 3000)
    end
    CreateThread(function()
        Wait(Config.RecoverEvery)
        fatigue = math.min(1.0, fatigue + Config.FatigueStep)
        if frustrated and fatigue > Config.FrustratedBelow then
            frustrated = false
            TriggerEvent('jrs:TipRight', text('calm'), 3000)
        end
    end)
end

-- ------------------------------------------------------------------ page <-> script

local function close()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('result', function(data, cb)
    cb('ok')
    if not running then return end
    local p = running
    running = nil
    close()
    p:resolve(data and data.hit == true)
end)

exports('taskBar', function(difficulty, skillGap)
    if running then return 0 end                         -- a bar is already open: this call fails at once

    local duration = math.max(500, math.floor((tonumber(difficulty) or 3000) * fatigue))
    local width = clamp(tonumber(skillGap) or 20, Config.MinZone, Config.MaxZone)
    local start = math.random(Config.ZoneStart.min, math.min(Config.ZoneStart.max, 100 - width))

    local mine = promise.new()
    running = mine
    TriggerEvent('jrs:TipBottom', text('tip'), 4000)
    SetNuiFocus(true, true)                              -- E or a mouse click hits the bar
    SendNUIMessage({
        action = 'open', duration = duration, zoneStart = start, zoneWidth = width,
        text = text('bar'), hint = text('hint'), rtl = isRtl(),
    })

    -- safety net: if the page never answers, the bar counts as missed
    SetTimeout(duration + 4000, function()
        if running == mine then
            running = nil
            close()
            mine:resolve(false)
        end
    end)

    local hit = Citizen.Await(mine)
    if hit then
        fatigue = 1.0
        return 100
    end
    miss()
    return 0
end)

-- cancel the bar from another script (counts as a miss)
exports('closeGuiFail', function()
    if running then
        local p = running
        running = nil
        close()
        p:resolve(false)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)
