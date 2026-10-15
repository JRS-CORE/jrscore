--------------------------------------------------------------------------------------------
-- JRS SAMPLES — Client: sedation detection + "Take Sample" prompts
--------------------------------------------------------------------------------------------

local SEDATED_FLAG   = 580
local PROMPT_CONTROL = 0x956C2A0E
local PROMPT_RANGE   = 2.0

local tracked = {}   -- [ped] = { prompt = id, sedatedAt = ms }
local handled = {}   -- [ped] = true once sampled or expired, so we never re-prompt the same ped

local function removePrompt(ped)
    local entry = tracked[ped]
    if entry and entry.prompt then
        PromptDelete(entry.prompt)
    end
    tracked[ped] = nil
end

-- Make sure the ped has a network id the server can resolve (bounded, never blocks forever)
local function ensureNetworked(ped)
    for _ = 1, 10 do
        if NetworkGetEntityIsNetworked(ped) and NetworkDoesNetworkIdExist(NetworkGetNetworkIdFromEntity(ped)) then
            return true
        end
        NetworkRegisterEntityAsNetworked(ped)
        Wait(100)
    end
    return false
end

local function startTracking(ped)
    if not ensureNetworked(ped) or not DoesEntityExist(ped) then
        handled[ped] = true -- the server can't verify a non-networked ped, don't retry every scan
        return
    end

    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, PROMPT_CONTROL)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', LE('prompt_take_sample')))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, false)
    PromptSetHoldMode(prompt, Config.SampleHoldTime)
    PromptSetGroup(prompt, UiPromptGetGroupIdForTargetEntity(ped))
    PromptRegisterEnd(prompt)

    tracked[ped] = { prompt = prompt, sedatedAt = GetGameTimer() }
    if Config.DebugClient then print('[jrs_samples] Prompt created for ped', ped) end
end

local function wakeAnimal(ped)
    removePrompt(ped)
    handled[ped] = true
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end

    SetPedConfigFlag(ped, SEDATED_FLAG, false)
    ClearPedTasksImmediately(ped)
    local c = GetEntityCoords(ped)
    TaskFleeCoord(ped, c.x + 100.0, c.y + 100.0, c.z, 2, 0, -1.0, 5000, 0)
    if Config.DebugClient then print('[jrs_samples] Sedation expired for ped', ped) end
end

--------------------------------------------------------------------------------------------
-- Scan thread: find newly sedated animals, drop dead / despawned / expired ones
--------------------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local now = GetGameTimer()

        for _, ped in ipairs(GetGamePool('CPed')) do
            if not tracked[ped] and not handled[ped]
                and not IsPedAPlayer(ped) and not IsEntityDead(ped)
                and GetPedConfigFlag(ped, SEDATED_FLAG, true) then
                startTracking(ped)
            end
        end

        for ped, entry in pairs(tracked) do
            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                removePrompt(ped)
            elseif now - entry.sedatedAt > Config.AnimalCleanupTime then
                wakeAnimal(ped)
            end
        end

        for ped in pairs(handled) do
            if not DoesEntityExist(ped) or IsEntityDead(ped) or not GetPedConfigFlag(ped, SEDATED_FLAG, true) then
                handled[ped] = nil
            end
        end

        Wait(1000)
    end
end)

--------------------------------------------------------------------------------------------
-- Prompt thread: show prompts in range and submit completed samples
--------------------------------------------------------------------------------------------
CreateThread(function()
    while true do
        if next(tracked) == nil then
            Wait(500)
        else
            local playerCoords = GetEntityCoords(PlayerPedId())

            for ped, entry in pairs(tracked) do
                if DoesEntityExist(ped) then
                    local inRange = #(GetEntityCoords(ped) - playerCoords) < PROMPT_RANGE
                    PromptSetVisible(entry.prompt, inRange)

                    if inRange and PromptHasHoldModeCompleted(entry.prompt) then
                        -- Remove first so the next frame can't submit twice
                        removePrompt(ped)
                        handled[ped] = true
                        SetPedQuality(ped, -1)
                        TriggerServerEvent('jrs_samples:server:sampleAnimal', NetworkGetNetworkIdFromEntity(ped))
                        if Config.DebugClient then print('[jrs_samples] Sample submitted for ped', ped) end
                    end
                end
            end

            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for ped in pairs(tracked) do removePrompt(ped) end
end)
