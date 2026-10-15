-- jrs_core/lib main scripts draw in the html/modules/extlib frame.
function JRSExtLibNUI(message)
    SendNUIMessage({ __jrsModule = 'extlib', payload = message })
end

function JRSExtLibFocus(hasFocus, hasCursor)
    SetNuiFocus(hasFocus, hasCursor)
    SendNUIMessage({ __jrsModule = 'extlib', focus = hasFocus == true })
end
