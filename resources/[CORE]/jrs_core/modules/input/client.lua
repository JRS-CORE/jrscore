
local activeRequest = nil
local UI_OWNER = 'jrs_core:input'

local function moduleMessage(payload)
    SendNUIMessage({ __jrsModule = 'input', payload = payload })
end

local function hideAll()
    moduleMessage({ type = 'open_inputs', status = false })
    moduleMessage({ type = 'open_answer', status = false })
    if JRSUI then JRSUI.Release(UI_OWNER) else SetNuiFocus(false, false) end
end

local function validateInput(value, options)
    options = type(options) == 'table' and options or {}
    local text = tostring(value or '')

    local maxLength = tonumber(options.maxLength)
    if maxLength and #text > maxLength then
        return false, ('Maximum length is %d characters.'):format(maxLength)
    end
    local minLength = tonumber(options.minLength)
    if minLength and #text < minLength then
        return false, ('Minimum length is %d characters.'):format(minLength)
    end

    if options.type == 'number' or options.number == true then
        local number = tonumber(text)
        if number == nil then return false, 'A valid number is required.' end
        local min = tonumber(options.min)
        local max = tonumber(options.max)
        if min and number < min then return false, ('Minimum value is %s.'):format(min) end
        if max and number > max then return false, ('Maximum value is %s.'):format(max) end
        if options.integer == true then number = math.floor(number) end
        return true, number
    end

    if type(options.validate) == 'function' then
        local ok, accepted, reason = pcall(options.validate, text)
        if not ok then return false, 'Input validation failed.' end
        if accepted ~= true then return false, tostring(reason or 'Invalid value.') end
    end

    return true, text
end

local function showValidationError(message)
    if CoreNotifications and CoreNotifications.NotifyRightTip then
        local text = message or 'input_invalid_value'
        if type(_U) == 'function' then
            text = _U(text)
        end
        CoreNotifications.NotifyRightTip(tostring(text or 'Invalid value.'), 2500)
    end
end

local function resolveActive(value, bypassValidation)
    local request = activeRequest
    if not request then
        hideAll()
        return
    end

    local resolved = value
    if request.kind == 'input' and bypassValidation ~= true then
        local ok, normalized = validateInput(value, request.options)
        if not ok then
            showValidationError(normalized)
            return
        end
        resolved = normalized
    end

    activeRequest = nil
    hideAll()
    if type(request.cb) == 'function' then
        local ok, err = pcall(request.cb, resolved)
        if not ok then
            print(('^1[jrs_core/input] callback failed: %s^0'):format(tostring(err)))
        end
    end
    if request.promise then request.promise:resolve(resolved) end
end

local function cancelActive()
    local request = activeRequest
    if not request then
        hideAll()
        return
    end
    resolveActive(request.kind == 'answer' and false or 'close', true)
end

local function beginRequest(kind, title, a, b, cb, options)
    if activeRequest then cancelActive() end

    options = type(options) == 'table' and options or {}
    local acquired, reason = true, nil
    if JRSUI then
        acquired, reason = JRSUI.Acquire(UI_OWNER, { focus = true, cursor = true, kind = 'input', force = options.force == true })
    else
        SetNuiFocus(true, true)
    end
    if acquired ~= true then return false, reason or 'ui_busy' end

    activeRequest = { kind = kind, cb = cb, options = options }

    if kind == 'answer' then
        moduleMessage({
            type = 'open_answer',
            status = true,
            title = tostring(title or ''),
            first = tostring(a or ''),
            second = tostring(b or ''),
        })
    else
        local subtext = tostring(a or '')
        if options.hint and tostring(options.hint) ~= '' then
            subtext = subtext ~= '' and (subtext .. '\n' .. tostring(options.hint)) or tostring(options.hint)
        end
        moduleMessage({
            type = 'open_inputs',
            status = true,
            title = tostring(title or ''),
            subtext = subtext,
        })
    end
    return true
end

JRSInputAPI = {
    Open = function(title, subtext, cb, options)
        return beginRequest('input', title, subtext, nil, cb, options)
    end,
    Number = function(title, subtext, cb, options)
        options = type(options) == 'table' and options or {}
        options.type = 'number'
        return beginRequest('input', title, subtext, nil, cb, options)
    end,
    Confirm = function(title, first, second, cb)
        return beginRequest('answer', title, first, second, cb)
    end,
    IsOpen = function()
        return activeRequest ~= nil
    end,
    Close = function()
        cancelActive()
        return true
    end,
    Await = function(title, subtext, options)
        local p = promise.new()
        local ok, reason = beginRequest('input', title, subtext, nil, nil, options)
        if ok ~= true then return nil, reason end
        activeRequest.promise = p
        return Citizen.Await(p)
    end,
    ConfirmAwait = function(title, first, second)
        local p = promise.new()
        local ok, reason = beginRequest('answer', title, first, second, nil)
        if ok ~= true then return false, reason end
        activeRequest.promise = p
        return Citizen.Await(p)
    end,
}

RegisterNetEvent('jrs_inputs:getInput', function(title, subtext, cb)
    JRSInputAPI.Open(title, subtext, cb)
end)
RegisterNetEvent('jrs_inputs:getAnswer', function(title, first, second, cb)
    JRSInputAPI.Confirm(title, first, second, cb)
end)

RegisterNUICallback('jrs:close', function(_, cb)
    cancelActive()
    if cb then cb('ok') end
end)
RegisterNUICallback('jrs:send', function(data, cb)
    if activeRequest and activeRequest.kind == 'input' then
        resolveActive(data and data.text or '')
    end
    if cb then cb('ok') end
end)
RegisterNUICallback('jrs:yes', function(_, cb)
    if activeRequest and activeRequest.kind == 'answer' then resolveActive(true, true) end
    if cb then cb('ok') end
end)
RegisterNUICallback('jrs:no', function(_, cb)
    if activeRequest and activeRequest.kind == 'answer' then resolveActive(false, true) end
    if cb then cb('ok') end
end)

AddEventHandler('onClientResourceStop', function(stopped)
    if stopped ~= GetCurrentResourceName() then return end
    activeRequest = nil
    hideAll()
end)
