local PlayerData = { 
    IsBusy             = false,

    Username            = nil,
    Identifier          = nil,
    CharIdentifier      = 0,
    Job                 = nil,
    JobGrade            = 0,

    HasNUIActive        = false,
    Loaded              = false,
}

-----------------------------------------------------------
--[[ Local Functions ]]--
-----------------------------------------------------------

local function HasRequiredJobGrade(requiredJobs, currentJob, currentJobGrade)

    -- in case there are no required jobs, we return as true.
    if not requiredJobs or requiredJobs and JRS.TableLength(requiredJobs) <= 0 then
        return true
    end

    for job, data in pairs (requiredJobs) do

        if job == currentJob then

            for _, grade in pairs (data) do

                if tonumber(grade) == currentJobGrade then
                    return true
                end

            end

        end

    end

    return false

end

local function IsRegistrationLocationOpen(locConfig)

    if not locConfig.Hours.Enabled then
        return true
    end

    local hour = GetClockHours()
    
    if locConfig.Hours.Opening < locConfig.Hours.Closing then
        -- Normal hours: Opening and closing on the same day (e.g., 08 to 20)
        if hour < locConfig.Hours.Opening or hour >= locConfig.Hours.Closing then
            return false
        end
    else
        -- Overnight hours: Closing time is on the next day (e.g., 21 to 05)
        if hour < locConfig.Hours.Opening and hour >= locConfig.Hours.Closing then
            return false
        end
    end

    return true

end

-----------------------------------------------------------
--[[ Functions ]]--
-----------------------------------------------------------

function GetPlayerData()
    return PlayerData
end

-----------------------------------------------------------
--[[ Base Events ]]--
-----------------------------------------------------------

-- Gets the player job when devmode set to false and character is selected.
RegisterNetEvent("jrs:SelectedCharacter")
AddEventHandler("jrs:SelectedCharacter", function()

    Wait(2000)
    
    local data = JRS.Me()

    if data == nil then
        return
    end

    PlayerData.Identifier     = data.identifier
    PlayerData.CharIdentifier = data.charIdentifier
    PlayerData.Job            = data.job
    PlayerData.JobGrade       = data.jobGrade

    PlayerData.Username       = data.firstname .. ' ' .. data.lastname

    PlayerData.Loaded         = true
    
end)

-- Gets the player job when devmode set to true.
if Config.DevMode then

    Citizen.CreateThread(function ()

        Wait(2000)

        local data = JRS.Me()

        if data == nil then
            return
        end

        PlayerData.Identifier     = data.identifier
        PlayerData.CharIdentifier = data.charIdentifier
        PlayerData.Job            = data.job
        PlayerData.JobGrade       = data.jobGrade

        PlayerData.Username       = data.firstname .. ' ' .. data.lastname

        PlayerData.Loaded         = true
    end)
    
end

-- Updates the player job and job grade in case if changes.
RegisterNetEvent("jrs_core:client:jobChanged")
AddEventHandler("jrs_core:client:jobChanged", function(job, grade)
    PlayerData.Job      = job
    PlayerData.JobGrade = grade
end)

-----------------------------------------------------------
--[[ Threads ]]--
-----------------------------------------------------------

if Config.EnableRegistrationLocations then

    Citizen.CreateThread(function()
        RegisterActionPrompts()
    
        while true do
    
            Citizen.Wait(0)
            
            local sleep  = true
            local player = PlayerPedId()
            local coords = GetEntityCoords(PlayerPedId())
    
            local isDead = IsEntityDead(player)
    
            if not isDead and not PlayerData.IsBusy and PlayerData.Loaded then
    
                for index, locConfig in pairs(Config.Locations) do
    
                    local playerDist  = vector3(coords.x, coords.y, coords.z)
                    local locDist     = vector3(locConfig.Coords.x, locConfig.Coords.y, locConfig.Coords.z)
                    local distance    = #(playerDist - locDist)

                    -- Before everything, we are removing spawned entities if the rendering distance
                    -- is bigger than the configurable max distance.
                    if locConfig.NPC and distance > Config.NPCRenderingSpawnDistance then
                        RemoveEntityProperly(locConfig.NPC, GetHashKey(locConfig.NPCData.Model) )
                        locConfig.NPC = nil
                    end
    
                    local isAllowed = IsRegistrationLocationOpen(locConfig)
    
                    if locConfig.BlipData.Enabled then
        
                        local ClosedHoursData = locConfig.BlipData.DisplayClosedHours
    
                        if isAllowed ~= locConfig.IsAllowed and locConfig.BlipHandle then
    
                            RemoveBlip(locConfig.BlipHandle)
                            
                            Config.Locations[index].BlipHandle = nil
                            Config.Locations[index].IsAllowed = isAllowed
    
                        end
    
                        if (isAllowed and locConfig.BlipHandle == nil) or (not isAllowed and ClosedHoursData and ClosedHoursData.Enabled and locConfig.BlipHandle == nil ) then
                            local blipModifier = isAllowed and 'OPEN' or 'CLOSED'
                            AddBlip(index, blipModifier)
    
                            Config.Locations[index].IsAllowed = isAllowed
                        end
    
                    end
    
                    if locConfig.NPC and not isAllowed then
                        RemoveEntityProperly(locConfig.NPC, GetHashKey(locConfig.NPCData.Model) )
                        locConfig.NPC = nil
                    end

                    if isAllowed then
    
                        if not locConfig.NPC and locConfig.NPCData.Enabled and distance <= Config.NPCRenderingSpawnDistance then
                            SpawnNPC(index)
                        end
    
                        if (distance <= locConfig.ActionDistance) then

                            sleep = false
        
                            local Prompt, PromptList = GetPromptData()
        
                            local label = CreateVarString(10, 'LITERAL_STRING', Locales['PROMPT_PASSPORT_REGISTRATION_OFFICE'])
                            PromptSetActiveGroupThisFrame(Prompt, label)
    
                            for index, prompt in pairs (PromptList) do

                                if PromptHasHoldModeCompleted(prompt.prompt) then
    
                                    PlayerData.IsBusy = true

                                    JRS.TriggerCallback("jrs_passports:callbacks:isRegistered", function(result)
    
                                        if prompt.type == 'REGISTER' then
                                        
                                            if not result.registered then
            
                                                local inputData = {
                                                    title        = Locales['INPUT_REGISTER_TITLE'],
                                                    desc         = string.format(Locales['INPUT_REGISTER_DESCRIPTION'], Config.PassportCosts.Registration),
                                                    buttonparam1 = Locales['INPUT_REGISTER_ACCEPT_BUTTON'],
                                                    buttonparam2 = Locales['INPUT_REGISTER_CANCEL_BUTTON'],
                                                }
                                                                            
                                                PassportTextInput(inputData, function(cb)
                                                
                                                
                                                    if cb and not cb:match('^%s*$') then

                                                        TriggerServerEvent("jrs_passports:server:register", nil, cb)
                                                    else

                                                        if cb ~= 'DECLINE' and cb ~= Locales['INPUT_REGISTER_CANCEL_BUTTON'] then
                                                            SendNotification(nil, Locales['REGISTRATION_REQUIRES_AVATAR_URL'], "error")
                                                        end

                                                    end

                                                    PlayerData.IsBusy = false

                                                end) 

                                            else
                                                SendNotification(nil, Locales['ALREADY_REGISTERED'], "error")
                                                PlayerData.IsBusy = false
                                            end
        
                                        elseif prompt.type == 'RETRIEVE' then

                                            if result.registered then

                                                local inputData = {
                                                    title        = Locales['INPUT_RETRIEVE_TITLE'],
                                                    desc         = string.format(Locales['INPUT_RETRIEVE_DESCRIPTION'], Config.PassportCosts.Retrieve),
                                                    buttonparam1 = Locales['INPUT_RETRIEVE_ACCEPT_BUTTON'],
                                                    buttonparam2 = Locales['INPUT_RETRIEVE_CANCEL_BUTTON'],
                                                }
                                                                            
                                                PassportButtonInput(inputData, function(cb)
                                                
                                                    if cb == "ACCEPT" then
                                                        TriggerServerEvent("jrs_passports:server:retrieve")
                                                    end

                                                    PlayerData.IsBusy = false

                                                end) 

                                            else
                                                SendNotification(nil, Locales['NOT_REGISTERED'], "error")
                                                PlayerData.IsBusy = false
                                            end
    
                                        elseif prompt.type == 'RENEW' then

                                            if result.registered then

                                                local inputData = {
                                                    title        = Locales['INPUT_RENEWAL_TITLE'],
                                                    desc         = string.format(Locales['INPUT_RENEWAL_DESCRIPTION'], Config.PassportCosts.Renewal),
                                                    buttonparam1 = Locales['INPUT_RENEWAL_ACCEPT_BUTTON'],
                                                    buttonparam2 = Locales['INPUT_RENEWAL_CANCEL_BUTTON'],
                                                }
                                                                            
                                                PassportButtonInput(inputData, function(cb)
                                                
                                                    if cb == "ACCEPT" then
                                                        TriggerServerEvent('jrs_passports:server:renew')
                                                    end

                                                    PlayerData.IsBusy = false

                                                end) 

                                            else 
                                                SendNotification(nil, Locales['NOT_REGISTERED'], "error")
                                                PlayerData.IsBusy = false
                                            end

                                        end

                                    end)

                                    Wait(2000)
                                end

                            end
        
                        end
    
                    end
    
                end
    
            end
    
            if sleep then
                Citizen.Wait(1000)
            end
        end
    end)

end
