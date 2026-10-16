-- jrs_mdt | client: the page (window, focus and messages)
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

NUI = {}

local window = { width = 1100, height = 700 }
local onChange                          -- called with true/false when the page opens or closes

function NUI.SetStateCallback(fn) onChange = fn end

-- one message to the page: { action, data }
function NUI.Message(action, data)
    SendNuiMessage(json.encode({ action = action, data = data or {} }))
end

NUI.SendMessage = NUI.Message

function NUI.SetVisibility(visible) NUI.Message('setVisible', { visible = visible }) end

function NUI.SetFocus(focus, cursor)
    SetNuiFocus(focus, cursor ~= false and focus)
end

function NUI.Open(data)
    NUI.SetFocus(true, true)

    data = data or {}
    data.window = { width = window.width, height = window.height }
    NUI.Message('open', data)

    if onChange then onChange(true) end
end

function NUI.Close()
    NUI.SetFocus(false, false)
    NUI.Message('close')

    if onChange then onChange(false) end
end

function NUI.GetWindowState() return { width = window.width, height = window.height } end

function NUI.SetWindowState(size)
    window.width = size.width or window.width
    window.height = size.height or window.height
end

-- the page remembers how big the player made the window
RegisterNuiCallback('windowResize', function(data, cb)
    if data.width and data.height then NUI.SetWindowState(data) end
    cb({ success = true })
end)
