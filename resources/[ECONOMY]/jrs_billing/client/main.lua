-- JRS billing (client): themed form, the server checks everything again.
local open = false

RegisterNetEvent("jrs_billing:client:open", function(maxAmount)
    if open then return end
    open = true
    local lang = "en"
    pcall(function() lang = exports.jrs_core:GetLanguage() or "en" end)
    SendNUIMessage({ type = "open", language = lang, max = maxAmount })
    SetNuiFocus(true, true)
end)

local function close()
    open = false
    SendNUIMessage({ type = "close" })
    SetNuiFocus(false, false)
end

RegisterNUICallback("send", function(data, cb)
    cb({ ok = true })
    close()
    TriggerServerEvent("jrs_billing:server:send", {
        playerId = tonumber(data.playerId), amount = tonumber(data.amount), reason = tostring(data.reason or ""),
    })
end)

RegisterNUICallback("close", function(_, cb)
    cb({ ok = true })
    close()
end)

AddEventHandler("onResourceStop", function(name)
    if name == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)
