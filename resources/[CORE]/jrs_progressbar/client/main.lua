-- jrs_progressbar | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_progressbar | client
-- Timed progress bars for other JRS resources.
--
-- Public API (kept stable for every resource that already uses it):
--   local bar = exports.jrs_progressbar:initiate()
--   bar.start(message, ms, onDone, theme, color, width, takeFocus)
--   exports.jrs_progressbar:CancelNext(cb)   -- cancel the oldest running bar
--   exports.jrs_progressbar:CancelAll(cb)    -- cancel every running bar
--
-- Timing is owned by this script: a bar finishes when its own timer runs out, the page only draws it.

local active = {}        -- running bars, oldest first
local lastId = 0
local focusHeld = false

-- ------------------------------------------------------------------ helpers

local function wantsFocus()
    for i = 1, #active do
        if active[i].takeFocus then return true end
    end
    return false
end

local function syncFocus()
    local want = wantsFocus()
    if want ~= focusHeld then
        focusHeld = want
        SetNuiFocus(want, false)
    end
end

local function lookup(id)
    for i = 1, #active do
        if active[i].id == id then return i end
    end
end

-- Draw the newest running bar (or hide the page when nothing is running).
local function render()
    local top = active[#active]
    if not top then
        SendNUIMessage({ action = 'hide' })
        return
    end
    local now = GetGameTimer()
    SendNUIMessage({
        action   = 'show',
        id       = top.id,
        text     = top.text,
        total    = top.duration,
        left     = math.max(0, top.endsAt - now),
        theme    = top.theme,
        color    = top.color,
        width    = top.width,
    })
end

local function snapshot(bar)
    return { message = bar.text, callback = bar.onDone, focus = bar.takeFocus }
end

local function remove(index)
    local bar = table.remove(active, index)
    syncFocus()
    render()
    return bar
end

local function finish(id)
    local index = lookup(id)
    if not index then return end -- cancelled in the meantime
    local bar = remove(index)
    if type(bar.onDone) == 'function' or type(bar.onDone) == 'table' then
        local ok, err = pcall(bar.onDone)
        if not ok then
            print(('[jrs_progressbar] callback error: %s'):format(tostring(err)))
        end
    end
end

-- ------------------------------------------------------------------ start

local function start(message, duration, onDone, theme, color, width, takeFocus)
    duration = math.max(0, math.floor(tonumber(duration) or 0))

    lastId = lastId + 1
    local bar = {
        id        = lastId,
        text      = tostring(message or ''),
        duration  = duration,
        endsAt    = GetGameTimer() + duration,
        onDone    = onDone,
        theme     = theme or Config.DefaultTheme,
        color     = color or Config.DefaultColor,
        width     = width or Config.DefaultWidth,
        takeFocus = takeFocus ~= false,
    }
    active[#active + 1] = bar
    syncFocus()
    render()

    CreateThread(function()
        Wait(duration)
        finish(bar.id)
    end)

    return bar.id
end

-- ------------------------------------------------------------------ cancelling

local function cancelOldest()
    if #active == 0 then return {} end
    return snapshot(remove(1))
end

exports('initiate', function()
    return {
        start  = start,
        cancel = function(id)
            local index = lookup(id)
            if index then return snapshot(remove(index)) end
            return {}
        end,
    }
end)

exports('CancelNext', function(cb)
    local gone = cancelOldest()
    if cb then cb(gone) end
end)

exports('CancelAll', function(cb)
    local gone = {}
    while #active > 0 do
        gone[#gone + 1] = cancelOldest()
    end
    if cb then cb(gone) end
end)

-- Drop-in for scripts written against the stock `progressBars` resource (no input lock).
AddEventHandler('__cfx_export_progressBars_startUI', function(setCb)
    setCb(function(duration, text)
        start(text, duration, nil, nil, nil, nil, false)
    end)
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and focusHeld then
        SetNuiFocus(false, false)
    end
end)
