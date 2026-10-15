-- Legacy static HUMAN / VEHICLE density controller.
-- Config.Performance owns human/wagon density while enabled. Animals are always
-- separate and are controlled only by client/animals.lua + config/animals.lua.
Citizen.CreateThread(function()
    while true do
        local adaptiveEnabled = Config.Performance and Config.Performance.Enabled == true

        if not adaptiveEnabled and Config.Traffic and Config.Traffic.enabled then
            local ped = tonumber(Config.Traffic.pedFrequency) or 0.05
            local traffic = tonumber(Config.Traffic.trafficFrequency) or 0.0

            -- Human-specific multipliers only. Do not apply generic PED density
            -- here because that can also suppress wildlife used by hunting.
            Citizen.InvokeNative(0xBA0980B5C0A11924, ped)
            Citizen.InvokeNative(0x28CB6391ACEDD9DB, ped)

            Citizen.InvokeNative(0xFEDFA97638D61D4A, traffic)
            Citizen.InvokeNative(0x1F91D44490E1EA0C, traffic)
            Citizen.InvokeNative(0x606374EBFC27B133, traffic)
            Citizen.Wait(0)
        else
            Citizen.Wait(1000)
        end
    end
end)
