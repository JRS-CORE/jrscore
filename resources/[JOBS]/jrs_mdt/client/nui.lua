NUI = {}

local windowState = {
    width = 1100,
    height = 700,
}

local externalStateCallback = nil

function NUI.SetStateCallback(cb)
    externalStateCallback = cb
end

function NUI.SendMessage(action, data)
    SendNuiMessage(json.encode({ action = action, data = data or {} }))
end

function NUI.SetVisibility(visible)
    NUI.SendMessage('setVisible', { visible = visible })
end

function NUI.SetFocus(hasFocus, hasCursor)
    SetNuiFocus(hasFocus, hasCursor ~= false and hasFocus)
end

function NUI.Open(data)
    NUI.SetFocus(true, true)
    
    local openData = data or {}
    openData.window = {
        width = windowState.width,
        height = windowState.height,
    }
    
    NUI.SendMessage('open', openData)
    
    if externalStateCallback then
        externalStateCallback(true)
    end
end

function NUI.Close()
    NUI.SetFocus(false, false)
    NUI.SendMessage('close')
    
    if externalStateCallback then
        externalStateCallback(false)
    end
end

function NUI.GetWindowState()
    return {
        width = windowState.width,
        height = windowState.height,
    }
end

function NUI.SetWindowState(state)
    if state.width then windowState.width = state.width end
    if state.height then windowState.height = state.height end
end

RegisterNuiCallback('windowResize', function(data, cb)
    if data.width and data.height then
        windowState.width = data.width
        windowState.height = data.height
    end
    cb({ success = true })
end)
