-- jrs_metabolism | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
function startNeeds()
    needs = true
    TriggerEvent("BasicNeeds.startUI")    
    return needs
end

function isStartedNeeds()
    return needs
end

Citizen.CreateThread(
    function()
        while true do
            Citizen.Wait(5000)
            
            if MetabolismReady() and not IsEntityDead(PlayerPedId()) then
                local ped = PlayerPedId()

                local vthirst = 0

                local vhunger = 0

                local factor = 0.02

                --[[if IsPedOnFoot(ped) and not Citizen.InvokeNative(0x857ACB0AB4BD0D55, ped) then
                    factor = math.min(math.max(getSpeed(), factor), 10)
                end]]

                if Citizen.InvokeNative(0x857ACB0AB4BD0D55, ped) then
                    factor = 0
                end

                if not IsPedOnFoot(ped) then
                    factor = 0
                end

                vthirst = vthirst + 0.2 * factor
                vhunger = vhunger + 0.2 * factor

                if IsPedInMeleeCombat(ped) then
                    vthirst = vthirst + 3
                    vhunger = vhunger + 2
                end

                if IsPedInjured(ped) then
                    vthirst = vthirst + 2
                    vhunger = vhunger + 1
                end

                if vthirst ~= 0 then
                    TriggerServerEvent("metabolism.vary", 'thirst', vthirst)
                end
                
                if vhunger ~= 0 then
                    TriggerServerEvent("metabolism.vary", 'hunger', vhunger)
                end

            end
        end
    end
)

RegisterNetEvent("metabolism.varyHealth")
AddEventHandler("metabolism.varyHealth", function (variation)    
    VaryPlayerHealth(variation)
end)

function VaryPlayerHealth(variation, variationTime)
    VaryPedHealth(PlayerPedId(), variation, variationTime)
end

function VaryPlayerStamina(variation, variationTime)
    VaryPedStamina(PlayerPedId(), variation, variationTime)
end

function VaryPlayerCore(core, variation, variationTime, goldenEffect)
    VaryPedCore(PlayerPedId(), core, variation, variationTime, goldenEffect)
end

function VaryPedHealth(ped, variation, variationTime)
    if variationTime == nil or variationTime <= 1 then
        SetEntityHealth(ped, GetEntityHealth(ped) + variation)
    else
        Citizen.CreateThread(
            function()
                local variationPerTick = variation / variationTime
                while true do
                    local oldValue = GetEntityHealth(ped)
                    SetEntityHealth(ped, oldValue + variationPerTick)

                    variationTime = variationTime - 1

                    if variationTime <= 0 then
                        break
                    end

                    Citizen.Wait(1000)
                end
            end
        )
    end
end

function VaryPedStamina(ped, variation, variationTime)
    if variationTime == nil or variationTime <= 1 then
        -- Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, variation) -- _CHARGE_PED_STAMINA
        Citizen.InvokeNative(0x675680D089BFA21F, ped, variation) -- _RESTORE_PED_STAMINA
    else
        Citizen.CreateThread(
            function()
                local variationPerTick = variation / variationTime
                while variationTime > 0 do
                    local oldValue = GetPedStamina(ped)
                    -- Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, oldValue + variationPerTick) -- _CHARGE_PED_STAMINA
                    Citizen.InvokeNative(0x675680D089BFA21F, ped, variationPerTick) -- _RESTORE_PED_STAMINA

                    variationTime = variationTime - 1

                    if variationTime <= 0 then
                        break
                    end

                    Citizen.Wait(1000)
                end
            end
        )
    end
end

function VaryPedCore(ped, core, variation, variationTime, goldenEffect)
    if variationTime == nil or variationTime <= 1 then
        local oldCoreValue = GetAttributeCoreValue(ped, core)
        Citizen.InvokeNative(0xC6258F41D86676E0, ped, core, oldCoreValue + variation)
    else
        Citizen.CreateThread(
            function()
                local valuePerTick = variation / variationTime
                while true do
                    local oldCoreValue = GetAttributeCoreValue(ped, core)
                    Citizen.InvokeNative(0xC6258F41D86676E0, ped, core, oldCoreValue + valuePerTick)

                    variationTime = variationTime - 1

                    if variationTime <= 0 then
                        break
                    end

                    Citizen.Wait(1000)
                end
            end
        )
    end
end

-- return vx,vy,vz
function getSpeed()
	local vx, vy, vz = table.unpack(GetEntityVelocity(PlayerPedId()))
	return math.sqrt(vx * vx + vy * vy + vz * vz)
end


