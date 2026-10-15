function NativeApplyDamageToPed(ped, damage)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    local current = GetEntityHealth(ped)
    local minimum = canDamageKillPlayer and 0 or Config.MinimumHealth
    local amount = math.min(damage, math.max(0, current - minimum))
    if amount > 0 then Citizen.InvokeNative(0x697157CED63F18D4, ped, amount, false, true, true) end
end
function getLastMount(ped) return Citizen.InvokeNative(0x4C8B59171957BCF7, ped) end
Citizen.CreateThread(function()
    --[[ UitutorialSetRpgIconVisibility ]]
    -- HIDE THE GAME HUD CORES
    Citizen.InvokeNative(0xC116E6DF68DCE667, 0 --[[ ICON_STAMINA ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 1 --[[ ICON_STAMINA_CORE ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 2 --[[ ICON_DEADEYE ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 3 --[[ ICON_DEADEYE_CORE ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 4 --[[ ICON_HEALTH ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 5 --[[ ICON_HEALTH_CORE ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 6 --[[ ICON_HEALTH ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 7 --[[ ICON_HEALTH_CORE ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 8 --[[ ICON_HEALTH ]], 2)
    Citizen.InvokeNative(0xC116E6DF68DCE667, 9 --[[ ICON_HEALTH_CORE ]], 2)
end)