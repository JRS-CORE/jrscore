-- jrs_lockpick | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_lockpick | client
--   local opened = exports.jrs_lockpick:startLockpick(picks)   -- picks = how many lockpicks you may break (default 5)
-- Blocks until the player opens the lock (true), runs out of picks, or presses ESC (false).

local waiting                      -- promise of the game that is running

local TEXT = {
    en = { help = 'Move the mouse to aim the pick, hold A / D (or the arrows) to turn the lock', picks = 'Picks left:', esc = 'ESC to stop' },
    ar = { help = 'حرك الماوس لتوجيه المفك، واضغط A / D (أو الأسهم) لتدوير القفل', picks = 'المفكات الباقية:', esc = 'ESC للإيقاف' },
}

local function language()
    return (JrsLang and JrsLang.Current and JrsLang.Current()) or 'en'
end

local function settle(result)
    SetNuiFocus(false, false)
    if waiting then
        local p = waiting
        waiting = nil
        p:resolve(result)
    end
end

RegisterNUICallback('done', function(data, cb)
    settle(data and data.opened == true)
    cb('ok')
end)

exports('startLockpick', function(picks)
    if waiting then return false end        -- one lock at a time

    picks = math.floor(tonumber(picks) or 5)
    picks = math.max(1, math.min(picks, 10))

    local code = language()
    waiting = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'start', picks = picks, text = TEXT[code] or TEXT.en, rtl = code == 'ar' })

    return Citizen.Await(waiting)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then settle(false) end
end)
