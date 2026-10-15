
--[[-------------------------------------------------------
 Threads
]]---------------------------------------------------------

Citizen.CreateThread(function() 
    RegisterCanoeDropActionPrompt() 

    if Config.UseInteractPrompt then 
        JRS.AddModelTarget(Config.Models, Config.ModelsTargetOptions)
    end

end)

AddEventHandler('jrs_canoe:client:tasks', function()

    local retval, canoeEntity = IsCarryingCanoe()

    Citizen.CreateThread(function()

        while IsEntityAttached(canoeEntity) do

            Wait(0) 
            
            local ped = PlayerPedId()

            Citizen.InvokeNative(0x433083750C5E064A, ped, Config.SetPedMaxMoveBlendRatio)

            DisableControlAction(0, 0xD9D0E1C0, true) -- Jump
			DisableControlAction(0, 0x8FFC75D6, true) -- Sprint
			DisableControlAction(0, 0xD23C3EBE, true) -- Crouch
			DisableControlAction(0, 0xCEFD9220, true) -- Mount horse
			
			-- Combat
			DisableControlAction(0, 0x07CE1E61, true) -- Attack
			DisableControlAction(0, 0xF84FA74F, true) -- Aim
			DisableControlAction(0, 0x1F80208B, true) -- Melee
			DisableControlAction(0, 0xE30CD707, true) -- Reload
			
			-- Weapons / inventory
			DisableControlAction(0, 0xB2F377E8, true) -- Weapon wheel
			DisableControlAction(0, 0x4CC0E2FE, true) -- Inventory
			DisableControlAction(0, 0xC1989F95, true) -- Inventory

			-- Vehicles / wagons
			DisableControlAction(0, 0xCB2E7FA2, true) -- Enter vehicle/wagon

            if Config.RemoveStaminaWhileCarrying.Enabled then
                -- removing stamine while carrying
                Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, - Config.RemoveStaminaWhileCarrying.RemoveValue)

                -- if not enough stamina, drop the canoe.
                if Citizen.InvokeNative(0x22F2A386D43048A9, ped) == false then
                    DropCarriedCanoe()
    
                    ShowNotification(Locales['CANNOT_CARRY_NOT_ENOUGH_STAMINA'], {r = 255, g = 0, b = 0, a = 255})
                end

            end

            -- Prompt displaying while carrying canoe.

            local PromptGroup, PromptList = GetCanoeActionPromptData()
            local label = CreateVarString(10, 'LITERAL_STRING', LocalesEN['DROP_CANOE_ACTION'])
            PromptSetActiveGroupThisFrame(PromptGroup, label)

            if Citizen.InvokeNative(0xC92AC953F0A982AE, PromptList) or IsEntityDead(ped) or IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then
                DropCarriedCanoe()
            end
    
        end

    end)
    

end)