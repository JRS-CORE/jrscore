

local PlayerData = { 
    IsBusy        = false,
    Loaded        = false,
    LocationIndex = nil,
}

---------------------------------------------------------------
--[[ Local Functions ]]--
---------------------------------------------------------------

local function IsStoreOpen(storeConfig)

    if not storeConfig.Hours.Allowed then
        return true
    end

    local hour = GetClockHours()
    
    if storeConfig.Hours.Opening < storeConfig.Hours.Closing then
        -- Normal hours: Opening and closing on the same day (e.g., 08 to 20)
        if hour < storeConfig.Hours.Opening or hour >= storeConfig.Hours.Closing then
            return false
        end
    else
        -- Overnight hours: Closing time is on the next day (e.g., 21 to 05)
        if hour < storeConfig.Hours.Opening and hour >= storeConfig.Hours.Closing then
            return false
        end
    end

    return true

end

---------------------------------------------------------------
--[[ Public Functions ]]--
---------------------------------------------------------------

function GetPlayerData()
    return PlayerData
end

---------------------------------------------------------------
--[[ Threads ]]--
---------------------------------------------------------------

Citizen.CreateThread(function()

    CreatePromptRegistration()

    while true do

        local sleep        = 1000

        local player       = PlayerPedId()
        local isPlayerDead = IsEntityDead(player)

        if isPlayerDead and PlayerData.IsBusy then
            TriggerEvent("jrs_canoe:client:close")
            if PlayerData.LocationIndex then TriggerServerEvent("jrs_canoe:server:setBusyState", PlayerData.LocationIndex, false) end
        end

        if not PlayerData.IsBusy and not isPlayerDead then

            local coords = GetEntityCoords(player)
            local hour   = GetClockHours()

            for storeId, storeConfig in pairs(Config.Stores) do

                local coordsDist  = vector3(coords.x, coords.y, coords.z)
                local coordsStore = vector3(storeConfig.Coords.x, storeConfig.Coords.y, storeConfig.Coords.z)
                local distance    = #(coordsDist - coordsStore)

                -- Before everything, we are removing spawned entities if the rendering distance
                -- is bigger than the configurable max distance.
                if storeConfig.NPC and distance > Config.NPCRenderingSpawnDistance then
                    
                    JRS.RemoveEntity(storeConfig.NPC, joaat(storeConfig.NPCData.Model) )
                    storeConfig.NPC = nil
                end

                local isAllowed = IsStoreOpen(storeConfig)

                if storeConfig.BlipData.Allowed then
    
                    local ClosedHoursData = storeConfig.BlipData.DisplayClosedHours

                    if isAllowed ~= storeConfig.IsAllowed and storeConfig.BlipHandle then

                        RemoveBlip(storeConfig.BlipHandle)
                        
                        Config.Stores[storeId].BlipHandle = nil
                        Config.Stores[storeId].IsAllowed = isAllowed

                    end

                    if (isAllowed and storeConfig.BlipHandle == nil) or (not isAllowed and ClosedHoursData and ClosedHoursData.Enabled and storeConfig.BlipHandle == nil ) then
                        local blipModifier = isAllowed and 'OPEN' or 'CLOSED'
                        AddBlip(storeId, blipModifier)

                        Config.Stores[storeId].IsAllowed = isAllowed
                    end

                end

                if storeConfig.NPC and not isAllowed then

                    JRS.RemoveEntity(storeConfig.NPC, joaat(storeConfig.NPCData.Model) )
                    storeConfig.NPC = nil
                end
                
                if isAllowed then
    
                    if not storeConfig.NPC and storeConfig.NPCData.Allowed and distance <= Config.NPCRenderingSpawnDistance then
                        SpawnNPC(storeId)
                    end

                    if (distance <= storeConfig.DistanceOpenStore) and (not storeConfig.useInteractPrompt or not storeConfig.NPC) then
                        sleep = 0

                        local promptGroup, promptList = GetPromptData()

                        local label = CreateVarString(10, 'LITERAL_STRING', storeConfig.PromptName)
                        PromptSetActiveGroupThisFrame(promptGroup, label)

                        if PromptHasHoldModeCompleted(promptList) then
                            OpenCanoeRentingShop(storeId, storeConfig.City)
                            Wait(1000)
                        end

                    end

                end

            end

        end

        Wait(sleep)

    end

end)