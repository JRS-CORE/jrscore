-- JRS advanced inputs (part of jrs_core, NUI in html/modules/extinput).
--   local text = exports.jrs_core:advancedInput({ type = 'enableinput', inputType = 'input', button = 'Confirm',
--       placeholder = 'Name', style = 'block', attributes = { inputHeader = 'Title', type = 'text' } })
--   TriggerEvent('jrsinputs:getInput', 'Confirm', 'Placeholder', function(text) end)
local callbackOfCurrentOpenInput = nil

local function nui(payload)
    SendNUIMessage({ __jrsModule = 'extinput', payload = payload })
end

local function callOnce(result)
    if callbackOfCurrentOpenInput == nil then return end
    local cb = callbackOfCurrentOpenInput
    callbackOfCurrentOpenInput = nil
    cb(result)
end

local function closeInput()
    callOnce("")
    JRSExtInputOpen = false
    SetNuiFocus(false, false)
    nui({ type = "enableinput", style = "none" })
end

local function submit(result)
    local text = type(result) == 'table' and result.stringtext or nil
    if text ~= nil then callOnce(text) end
    Wait(1)
    closeInput()
end

local function waitForInputs(button, placeHolder, cb, inputType)
    JRSExtInputOpen = true
    SetNuiFocus(true, true)
    nui({ type = "enableinput", style = "block", button = button, placeholder = placeHolder, inputType = inputType or "input" })
    callbackOfCurrentOpenInput = cb
end

local function onAdvancedInput(inputConfig, cb)
    local data = type(inputConfig) == 'table' and inputConfig or json.decode(inputConfig)
    JRSExtInputOpen = true
    SetNuiFocus(true, true)
    nui(data)
    callbackOfCurrentOpenInput = cb
end

RegisterNetEvent('jrsinputs:getInput', function(title, placeHolder, cb) waitForInputs(title, placeHolder, cb) end)
RegisterNetEvent('jrsinputs:getInputsWithInputType', function(title, placeHolder, inputType, cb)
    waitForInputs(title, placeHolder, cb, inputType)
end)
RegisterNetEvent('jrsinputs:advancedInput', onAdvancedInput)

RegisterNUICallback("extinput_submit", function(data, cb) cb('ok'); submit(data) end)
RegisterNUICallback("extinput_close", function(_, cb) cb('ok'); closeInput() end)
RegisterCommand("closeinput", closeInput, false)

exports("advancedInput", function(input)
    local p = promise.new()
    onAdvancedInput(input, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end)
