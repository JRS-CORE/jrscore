-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | client
-- Registration offices: a clerk and a blip per office, open during the office hours. Holding a prompt
-- registers a passport, retrieves a lost one or renews an expired one.

local me = {
    IsBusy = false, Loaded = false, HasNUIActive = false,
    Username = nil, Identifier = nil, CharIdentifier = 0, Job = nil, JobGrade = 0,
}

function GetPlayerData() return me end

local function loadMe()
    local data = JRS.Me()
    if not data then return end
    me.Identifier, me.CharIdentifier, me.Job, me.JobGrade = data.identifier, data.charIdentifier, data.job, data.jobGrade
    me.Username = data.firstname .. ' ' .. data.lastname
    me.Loaded = true
end

RegisterNetEvent('jrs:SelectedCharacter', function()
    Wait(2000)
    loadMe()
end)

if Config.DevMode then
    CreateThread(function() Wait(2000) loadMe() end)
end

RegisterNetEvent('jrs_core:client:jobChanged', function(job, grade)
    me.Job, me.JobGrade = job, grade
end)

-- an office open at the current hour (closing before opening runs past midnight)
local function isOpen(office)
    local hours = office.Hours
    if not hours.Enabled then return true end
    local now = GetClockHours()
    if hours.Opening < hours.Closing then return now >= hours.Opening and now < hours.Closing end
    return now >= hours.Opening or now < hours.Closing
end

local function dropClerk(office)
    RemoveEntityProperly(office.NPC, joaat(office.NPCData.Model))
    office.NPC = nil
end

local function updateBlip(index, office, open)
    if not office.BlipData.Enabled then return end
    local closedLook = office.BlipData.DisplayClosedHours

    if open ~= office.IsAllowed and office.BlipHandle then
        RemoveBlip(office.BlipHandle)
        office.BlipHandle, office.IsAllowed = nil, open
    end
    if not office.BlipHandle and (open or (closedLook and closedLook.Enabled)) then
        AddBlip(index, open and 'OPEN' or 'CLOSED')
        office.IsAllowed = open
    end
end

-- ------------------------------------------------------------------ the three services

local function finish() me.IsBusy = false end

local function register(status)
    if status.registered then
        SendNotification(nil, Locales['ALREADY_REGISTERED'], 'error')
        return finish()
    end
    PassportTextInput({
        title = Locales['INPUT_REGISTER_TITLE'],
        desc = Locales['INPUT_REGISTER_DESCRIPTION']:format(Config.PassportCosts.Registration),
        buttonparam1 = Locales['INPUT_REGISTER_ACCEPT_BUTTON'],
        buttonparam2 = Locales['INPUT_REGISTER_CANCEL_BUTTON'],
    }, function(photo)
        if photo and not photo:match('^%s*$') then
            TriggerServerEvent('jrs_passports:server:register', nil, photo)
        elseif photo ~= 'DECLINE' and photo ~= Locales['INPUT_REGISTER_CANCEL_BUTTON'] then
            SendNotification(nil, Locales['REGISTRATION_REQUIRES_AVATAR_URL'], 'error')
        end
        finish()
    end)
end

-- retrieving and renewing only differ in texts, price and the event they send
local function confirmService(prefix, costKey, event)
    return function(status)
        if not status.registered then
            SendNotification(nil, Locales['NOT_REGISTERED'], 'error')
            return finish()
        end
        PassportButtonInput({
            title = Locales['INPUT_' .. prefix .. '_TITLE'],
            desc = Locales['INPUT_' .. prefix .. '_DESCRIPTION']:format(Config.PassportCosts[costKey]),
            buttonparam1 = Locales['INPUT_' .. prefix .. '_ACCEPT_BUTTON'],
            buttonparam2 = Locales['INPUT_' .. prefix .. '_CANCEL_BUTTON'],
        }, function(answer)
            if answer == 'ACCEPT' then TriggerServerEvent(event) end
            finish()
        end)
    end
end

local services = {
    REGISTER = register,
    RETRIEVE = confirmService('RETRIEVE', 'Retrieve', 'jrs_passports:server:retrieve'),
    RENEW = confirmService('RENEWAL', 'Renewal', 'jrs_passports:server:renew'),
}

-- ------------------------------------------------------------------ the offices

if Config.EnableRegistrationLocations then
    CreateThread(function()
        RegisterActionPrompts()

        while true do
            Wait(0)
            local near = false
            local ped = PlayerPedId()

            if not IsEntityDead(ped) and not me.IsBusy and me.Loaded then
                local here = GetEntityCoords(ped)

                for index, office in pairs(Config.Locations) do
                    local away = #(here - vector3(office.Coords.x, office.Coords.y, office.Coords.z))
                    if office.NPC and away > Config.NPCRenderingSpawnDistance then dropClerk(office) end

                    local open = isOpen(office)
                    updateBlip(index, office, open)
                    if office.NPC and not open then dropClerk(office) end

                    if open then
                        if not office.NPC and office.NPCData.Enabled and away <= Config.NPCRenderingSpawnDistance then SpawnNPC(index) end

                        if away <= office.ActionDistance then
                            near = true
                            local group, list = GetPromptData()
                            PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', Locales['PROMPT_PASSPORT_REGISTRATION_OFFICE']))

                            for _, entry in ipairs(list) do
                                if PromptHasHoldModeCompleted(entry.prompt) then
                                    me.IsBusy = true
                                    JRS.TriggerCallback('jrs_passports:callbacks:isRegistered', function(status)
                                        (services[entry.type] or finish)(status)
                                    end)
                                    Wait(2000)
                                end
                            end
                        end
                    end
                end
            end

            if not near then Wait(1000) end
        end
    end)
end
