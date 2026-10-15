local ready = false

local function refreshFromState()
    ready = LocalPlayer and LocalPlayer.state and LocalPlayer.state.CharacterReady == true or false
    return ready
end

RegisterNetEvent("jrs_core:client:characterLoaded", function(charId)
    ready = true
    TriggerEvent("jrs_core:characterLoaded", charId)
end)

RegisterNetEvent("jrs_core:client:characterReady", function(charId)
    ready = true
    TriggerEvent("jrs_core:characterReady", charId)
end)

RegisterNetEvent("jrs_core:client:characterUnloaded", function(reason)
    ready = false
    TriggerEvent("jrs_core:characterUnloaded", reason)
end)

AddStateBagChangeHandler("CharacterReady", nil, function(bagName, _, value)
    if bagName == ("player:%s"):format(GetPlayerServerId(PlayerId())) then
        ready = value == true
    end
end)

exports("IsCharacterReady", function()
    return refreshFromState()
end)

exports("WaitForCharacterReady", function(timeoutMs)
    local deadline = GetGameTimer() + math.max(0, tonumber(timeoutMs) or 10000)
    while not refreshFromState() and GetGameTimer() < deadline do
        Wait(50)
    end
    return ready
end)

CreateThread(refreshFromState)


RegisterNetEvent('jrs_core:client:jobChanged', function(job, grade)
    TriggerEvent('jrs_core:jobChanged', job, grade)
end)

RegisterNetEvent('jrs_core:client:dutyChanged', function(state, job)
    TriggerEvent('jrs_core:dutyChanged', state == true, job)
end)

RegisterNetEvent('jrs_core:client:skillLevelChanged', function(skill, newLevel, oldLevel)
    TriggerEvent('jrs_core:skillLevelChanged', skill, newLevel, oldLevel)
end)

exports('GetCharacterStateLocal', function()
    local state = LocalPlayer and LocalPlayer.state or {}
    return {
        ready = state.CharacterReady == true,
        charIdentifier = state.CharacterId,
        identifier = state.CharacterIdentifier,
        firstname = state.FirstName,
        lastname = state.LastName,
        job = state.Job,
        jobGrade = state.JobGrade,
        jobLabel = state.JobLabel,
        onDuty = state.OnDuty == true,
        gender = state.Gender,
    }
end)
