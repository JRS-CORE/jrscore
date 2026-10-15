
-- ============================================================================
-- JRS unified UI manager
-- Owns NUI focus/busy state for core modules and exposes a stable cross-resource
-- API for character/clothing/barber/inventory integrations.
-- ============================================================================
JRSUI = JRSUI or {}

local owners = {}
local focusOwner = nil

local function normalizedOwner(owner)
    owner = tostring(owner or '')
    if owner == '' then
        owner = (type(GetInvokingResource) == 'function' and GetInvokingResource()) or GetCurrentResourceName()
    end
    return owner
end

local function setLocalState(key, value)
    if LocalPlayer and LocalPlayer.state and type(LocalPlayer.state.set) == 'function' then
        LocalPlayer.state:set(key, value, false)
    end
end

local function refreshState()
    local any = next(owners) ~= nil
    setLocalState('uiOpen', any)
    setLocalState('jrsUiOwner', focusOwner or false)
    TriggerEvent('jrs_core:ui:stateChanged', any, focusOwner, owners)
end

function JRSUI.Acquire(owner, options)
    owner = normalizedOwner(owner)
    options = type(options) == 'table' and options or {}

    local wantsFocus = options.focus == true
    if wantsFocus and focusOwner and focusOwner ~= owner and options.force ~= true then
        return false, 'ui_busy:' .. tostring(focusOwner)
    end

    owners[owner] = {
        focus = wantsFocus,
        cursor = options.cursor == true,
        manageFocus = options.manageFocus ~= false,
        openedAt = GetGameTimer(),
        kind = tostring(options.kind or owner),
    }

    if wantsFocus then
        focusOwner = owner
        if options.manageFocus ~= false then
            SetNuiFocus(true, options.cursor == true)
        end
    end

    TriggerEvent('jrs_hud:busy', owner, true)
    if type(JRSNotifySetMenuOpen) == 'function' then
        JRSNotifySetMenuOpen(true, owner)
    end
    refreshState()
    return true
end

function JRSUI.Release(owner, options)
    owner = normalizedOwner(owner)
    options = type(options) == 'table' and options or {}
    local entry = owners[owner]
    owners[owner] = nil

    if focusOwner == owner then
        focusOwner = nil
        if (not entry or entry.manageFocus ~= false) and options.manageFocus ~= false then
            SetNuiFocus(false, false)
        end
    end

    TriggerEvent('jrs_hud:busy', owner, false)
    if type(JRSNotifySetMenuOpen) == 'function' then
        JRSNotifySetMenuOpen(false, owner)
    end
    refreshState()
    return true
end

function JRSUI.IsBusy(exceptOwner)
    exceptOwner = exceptOwner and tostring(exceptOwner) or nil
    if focusOwner and focusOwner ~= exceptOwner then
        return true, focusOwner
    end
    return false, focusOwner
end

function JRSUI.GetOwner()
    return focusOwner
end

function JRSUI.GetState()
    local copy = {}
    for k, v in pairs(owners) do
        copy[k] = {
            focus = v.focus == true,
            cursor = v.cursor == true,
            kind = v.kind,
            openedAt = v.openedAt,
        }
    end
    return {
        busy = next(owners) ~= nil,
        focusOwner = focusOwner,
        owners = copy,
    }
end

function JRSUI.ReleaseAll()
    owners = {}
    focusOwner = nil
    SetNuiFocus(false, false)
    setLocalState('uiOpen', false)
    setLocalState('jrsUiOwner', false)
    TriggerEvent('jrs_hud:busy', GetCurrentResourceName(), false)
    return true
end

exports('AcquireUI', function(owner, options)
    return JRSUI.Acquire(owner, options)
end)
exports('ReleaseUI', function(owner, options)
    return JRSUI.Release(owner, options)
end)
exports('IsUIBusy', function(owner)
    return JRSUI.IsBusy(owner)
end)
exports('GetOpenUI', function()
    return JRSUI.GetState()
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        JRSUI.ReleaseAll()
        return
    end
    if owners[resource] then
        JRSUI.Release(resource)
    end
end)
