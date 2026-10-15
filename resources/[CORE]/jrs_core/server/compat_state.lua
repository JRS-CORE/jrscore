-- Character state + events for the extra scripts (server).
-- extra scripts wait for LocalPlayer.state.IsInSession and read
-- LocalPlayer.state.Character.{Job,Grade,Money,...}; JRS Core does not set
-- those, so they are mirrored here from the live JRS character.

local Snapshot = {}

local function BuildState(source)
    local char = JRSExtBridge.JrsCharacter(source)
    if not char then return nil end
    return {
        CharId = tonumber(char.charIdentifier),
        Job = char.job or "unemployed",
        JobLabel = char.joblabel or char.job or "unemployed",
        Grade = tonumber(char.jobgrade) or 0,
        Group = JRSExtBridge.JrsGroup(source),
        Money = tonumber(char.money) or 0,
        Gold = tonumber(char.gold) or 0,
        Rol = tonumber(char.rol) or 0,
        XP = tonumber(char.xp) or 0,
        FirstName = char.firstname or "",
        LastName = char.lastname or "",
        Gender = char.gender,
        NickName = char.nickname or "",
    }
end

local function Sync(source, selected)
    source = tonumber(source)
    if not source or not GetPlayerName(source) then return end
    local state = BuildState(source)
    local player = Player(source)
    if not state then
        if Snapshot[source] then
            Snapshot[source] = nil
            player.state:set('IsInSession', false, true)
            player.state:set('Character', nil, true)
        end
        return
    end

    local old = Snapshot[source]
    if old and not selected then
        local changed = false
        for k, v in pairs(state) do
            if old[k] ~= v then changed = true break end
        end
        if not changed then return end
    end
    Snapshot[source] = state
    player.state:set('Character', state, true)
    if not player.state.IsInSession then player.state:set('IsInSession', true, true) end

    if selected or not old then
        local user = JRSExtBridge.BuildUser(source)
        TriggerEvent('jrs:SelectedCharacter', source, user and user.getUsedCharacter)
        return
    end
    if old.Job ~= state.Job then
        TriggerEvent('jrs:playerJobChange', source, state.Job, old.Job)
        TriggerClientEvent('jrs:playerJobChange', source, state.Job, old.Job)
    end
    if old.Grade ~= state.Grade then
        TriggerEvent('jrs:playerJobGradeChange', source, state.Grade, old.Grade)
    end
    if old.Group ~= state.Group then
        TriggerEvent('jrs:playerGroupChange', source, state.Group, old.Group)
    end
end

AddEventHandler('jrs_core:server:characterReady', function(source)
    CreateThread(function()
        Wait(250)
        Sync(source, true)
    end)
end)

AddEventHandler('jrs_core:server:characterUnloaded', function(source)
    source = tonumber(source)
    if not source then return end
    Snapshot[source] = nil
    if GetPlayerName(source) then
        Player(source).state:set('IsInSession', false, true)
        Player(source).state:set('Character', nil, true)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    Snapshot[src] = nil
    TriggerEvent('jrs:Server:playerLeave', src)
end)

-- Job / money / group changes have no single JRS event; poll the cheap snapshot.
CreateThread(function()
    while true do
        Wait(2000)
        for _, id in ipairs(GetPlayers()) do
            Sync(tonumber(id), false)
        end
    end
end)

-- Resource restart: pick up everyone already playing.
AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1500)
        for _, id in ipairs(GetPlayers()) do Sync(tonumber(id), true) end
    end)
end)

-- Death state reported by the client respawn system.
-- A client can only claim "dead" if its ped really is dead on the server.
RegisterNetEvent('jrs:ImDead', function(isDead)
    local src = source
    if isDead ~= true then
        Player(src).state:set('isDead', false, true)
        return
    end
    CreateThread(function()
        Wait(750)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and GetEntityHealth(ped) <= 0 then
            Player(src).state:set('isDead', true, true)
        end
    end)
end)
