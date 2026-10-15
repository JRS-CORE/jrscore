

-----------------------------------------------------------
--[[ Notifications  ]]--
-----------------------------------------------------------

RegisterNetEvent('jrs_core:sendLeftNotification')
AddEventHandler('jrs_core:sendLeftNotification', function(firsttext, secondtext, dict, icon, duration, color)
    CoreNotifications.NotifyLeft(tostring(firsttext), tostring(secondtext), tostring(dict), tostring(icon), tonumber(duration), (color and tostring(color)) or "COLOR_WHITE")
end)

RegisterNetEvent('jrs_core:sendTipNotification')
AddEventHandler('jrs_core:sendTipNotification', function(text, duration, title)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= '' then
        CoreNotifications.SetSource(invoker)
    end
    CoreNotifications.NotifyTip(tostring(text), tonumber(duration), title)
    CoreNotifications.SetSource(nil)
end)

RegisterNetEvent('jrs_core:sendTopNotification')
AddEventHandler('jrs_core:sendTopNotification', function(text, location, duration)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= '' then
        CoreNotifications.SetSource(invoker)
    end
    CoreNotifications.NotifyTop(tostring(text), tostring(location), tonumber(duration))
    CoreNotifications.SetSource(nil)
end)

RegisterNetEvent('jrs_core:sendRightTipNotification')
AddEventHandler('jrs_core:sendRightTipNotification', function(text, duration, title)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= '' then
        CoreNotifications.SetSource(invoker)
    end
    CoreNotifications.NotifyRightTip(tostring(text), tonumber(duration), title)
    CoreNotifications.SetSource(nil)
end)

RegisterNetEvent('jrs_core:sendBottomTipNotification')
AddEventHandler('jrs_core:sendBottomTipNotification', function(text, duration)
    CoreNotifications.NotifyObjective(tostring(text), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendSimpleTopNotification')
AddEventHandler('jrs_core:sendSimpleTopNotification', function(title, subtitle, duration)
    CoreNotifications.NotifySimpleTop(tostring(title), tostring(subtitle), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendAdvancedRightNotification')
AddEventHandler('jrs_core:sendAdvancedRightNotification', function(text, dict, icon, text_color, duration, quality)
    CoreNotifications.NotifyAdvanced(tostring(text), tostring(dict), tostring(icon), tostring(text_color), tonumber(duration), quality)
end)

RegisterNetEvent('jrs_core:sendBasicTopNotification')
AddEventHandler('jrs_core:sendBasicTopNotification', function(text, duration)
    CoreNotifications.NotifyBasicTop(tostring(text), tonumber(duration))
end)       

RegisterNetEvent('jrs_core:sendSimpleCenterNotification')
AddEventHandler('jrs_core:sendSimpleCenterNotification', function(text, duration)
    CoreNotifications.NotifyCenter(tostring(text), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendBottomRightNotification')
AddEventHandler('jrs_core:sendBottomRightNotification', function(text, duration)
    CoreNotifications.NotifyBottomRight(tostring(text), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendFailMissionNotification')
AddEventHandler('jrs_core:sendFailMissionNotification', function(title, subtitle, duration)
    CoreNotifications.NotifyFail(tostring(title), tostring(subtitle), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendDeadPlayerNotification')
AddEventHandler('jrs_core:sendDeadPlayerNotification', function(title, audioRef, audioName, duration)
    CoreNotifications.NotifyDead(tostring(title), tostring(audioRef), tostring(audioName), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendMissionUpdateNotification')
AddEventHandler('jrs_core:sendMissionUpdateNotification', function(utitle, umsg, duration)
    CoreNotifications.NotifyUpdate(tostring(utitle), tostring(umsg), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendWarningNotification')
AddEventHandler('jrs_core:sendWarningNotification', function(title, msg, audioRef, audioName, duration)
    CoreNotifications.NotifyWarning(tostring(title), tostring(msg), tostring(audioRef), tostring(audioName), tonumber(duration))
end)

RegisterNetEvent('jrs_core:sendLeftRankNotification')
AddEventHandler('jrs_core:sendLeftRankNotification', function(title, subtitle, dict, icon, duration, color)
    CoreNotifications.NotifyLeftRank(tostring(title), tostring(subtitle), tostring(dict), tostring(icon) , tonumber(duration), (color and tostring(color)) or "COLOR_WHITE")
end)

-----------------------------------------------------------
--[[ Health  ]]--
-----------------------------------------------------------

RegisterNetEvent('jrs_core:healPlayer')
AddEventHandler('jrs_core:healPlayer', function()
    CoreFunctions.HealPlayer()
end)

