local PlayerData = { 
    IsSearching = false,
    IsSearchingId = -1,
    IsSurrendering = false,
}

-----------------------------------------------------------
--[[ Functions ]]--
-----------------------------------------------------------

function GetPlayerData()
    return PlayerData
end

-----------------------------------------------------------
--[[ Base Events & Threads ]]--
-----------------------------------------------------------

RegisterNetEvent("jrs_search:client:setSearchingState")
AddEventHandler("jrs_search:client:setSearchingState", function(state)
    PlayerData.IsSearching = state
end)

RegisterNetEvent('jrs_search:client:closed')
AddEventHandler('jrs_search:client:closed', function(cb)
    local player = PlayerPedId()

    if PlayerData.IsSearching and PlayerData.IsSearchingId ~= -1 and cb == false then 
        TriggerServerEvent("jrs_search:server:reset_searched_target", PlayerData.IsSearchingId)
        PlayerData.IsSearching = false
        PlayerData.IsSearchingId = -1


        local sex = IsPedMale(player) and 'male' or 'female'

        if Config.PlaySearchAnimation.Enabled then
            StopAnimTask(player, Config.PlaySearchAnimation[sex].dict, Config.PlaySearchAnimation[sex].name, 1)
            RemoveAnimDict(Config.PlaySearchAnimation[sex].dict)
        end

    end

end)

RegisterNetEvent("jrs_search:client:setSurrenderingState")
AddEventHandler("jrs_search:client:setSurrenderingState", function(state)
    PlayerData.IsSurrendering = state
end)


-----------------------------------------------------------
--[[ Threads ]]--
-----------------------------------------------------------


Citizen.CreateThread(function()

    RegisterActionPrompt()

    while true do 

        local sleep          = 1500

        local player         = PlayerPedId()
        local closestPlayers = GetNearestPlayers(Config.CheckNearestPlayersDistance)
        local coords         = GetEntityCoords(player)

        local length         = JRS.TableLength(closestPlayers)

        if PlayerData.IsSearching and PlayerData.IsSearchingId ~= -1 then 
            
            local targetPlayerPed = GetPlayerPed(PlayerData.IsSearchingId)
            local tcoords         = GetEntityCoords(targetPlayerPed)

            if #(coords - tcoords) > Config.CheckNearestPlayersDistance then

                TriggerEvent('jrs_inventory:CloseInv')
                TriggerServerEvent("jrs_search:server:reset_searched_target", GetPlayerServerId(PlayerData.IsSearchingId))
                PlayerData.IsSearching = false
                PlayerData.IsSearchingId = -1

                local sex = IsPedMale(player) and 'male' or 'female'

                if Config.PlaySearchAnimation.Enabled then
                    ClearPedSecondaryTask(player)
                    RemoveAnimDict(Config.PlaySearchAnimation[sex].dict)
                end

            end

            goto END
        end

        if length <= 0 or PlayerData.IsSearching then 
            goto END
        end

        if length > 0 then 

            local foundPlayer     = closestPlayers[1]
            local targetPlayerPed = GetPlayerPed(foundPlayer)
            local tcoords         = GetEntityCoords(targetPlayerPed)

            if #(coords - tcoords) <= Config.CheckNearestPlayersDistance then

                local isBeingHogtied  = Citizen.InvokeNative(0xD453BB601D4A606E, targetPlayerPed)
                local hogtied    = Citizen.InvokeNative(0x3AA24CCC0D451379, targetPlayerPed)
                local handcuffed = Citizen.InvokeNative(0x74E559B3BC910685, targetPlayerPed)
                local isDead     = IsEntityDead(targetPlayerPed)
    
                local allowed    = true 
    
                if not IsPedOnFoot(targetPlayerPed) or IsPedSwimming(targetPlayerPed) or (not Config.SearchDead and isDead) then 
                    allowed = false
                end
                
                if allowed and not isBeingHogtied then 

                    local canSearch = false

                    if (Config.SearchHogtie and hogtied) or (Config.SearchHandcuffed and handcuffed) or (Config.SearchDead and isDead) or (Config.SearchHandsUp and PlayerData.IsSurrendering) then 
                        canSearch = true
                    end
    
                    if canSearch then 
                        sleep = 0
                        local promptGroup, promptList = GetPromptData()
    
                        local label = CreateVarString(10, 'LITERAL_STRING', '')
                        PromptSetActiveGroupThisFrame(promptGroup, label)
    
                        if PromptHasHoldModeCompleted(promptList) then

                            local sex = IsPedMale(player) and 'male' or 'female'
                            
                            if Config.PlaySearchAnimation.Enabled then
                                JRS.PlayAnimation(player, Config.PlaySearchAnimation[sex])
                            end

                            PlayerData.IsSearchingId = foundPlayer
                            TriggerServerEvent("jrs_search:server:search", GetPlayerServerId(foundPlayer))
                            Wait(2000)
                        end
    
                    end

                end

            end

        end


        ::END::
        Wait(sleep)

    end

end)


