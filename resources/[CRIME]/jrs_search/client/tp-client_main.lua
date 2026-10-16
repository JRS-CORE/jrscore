-- jrs_search | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_search | client
-- Near a player who can be searched (hogtied, cuffed, dead or hands up) a hold prompt appears;
-- holding it asks the server to open that player's inventory.

local state = { searching = false, target = -1, surrendering = false }

function GetPlayerData() return state end

local function genderKey(ped) return IsPedMale(ped) and 'male' or 'female' end

local function stopAnimation(ped, clearTask)
    if not Config.PlaySearchAnimation.Enabled then return end
    local anim = Config.PlaySearchAnimation[genderKey(ped)]
    if clearTask then ClearPedSecondaryTask(ped) else StopAnimTask(ped, anim.dict, anim.name, 1) end
    RemoveAnimDict(anim.dict)
end

local function finish()
    state.searching, state.target = false, -1
end

RegisterNetEvent('jrs_search:client:setSearchingState', function(on) state.searching = on end)
RegisterNetEvent('jrs_search:client:setSurrenderingState', function(on) state.surrendering = on end)

-- the inventory window was closed by the searcher
RegisterNetEvent('jrs_search:client:closed', function(stillOpen)
    if not (state.searching and state.target ~= -1 and stillOpen == false) then return end
    TriggerServerEvent('jrs_search:server:reset_searched_target', state.target)
    finish()
    stopAnimation(PlayerPedId(), false)
end)

-- can the player in front of us be searched right now?
local function searchable(ped)
    if Citizen.InvokeNative(0xD453BB601D4A606E, ped) then return false end        -- being hogtied by somebody
    local dead = IsEntityDead(ped)
    if not IsPedOnFoot(ped) or IsPedSwimming(ped) or (dead and not Config.SearchDead) then return false end

    local hogtied = Citizen.InvokeNative(0x3AA24CCC0D451379, ped)
    local cuffed = Citizen.InvokeNative(0x74E559B3BC910685, ped)
    return (Config.SearchHogtie and hogtied) or (Config.SearchHandcuffed and cuffed)
        or (Config.SearchDead and dead) or (Config.SearchHandsUp and state.surrendering)
end

-- a search that is running ends when the target walks away
local function watchTarget(me, here)
    local there = GetEntityCoords(GetPlayerPed(state.target))
    if #(here - there) <= Config.CheckNearestPlayersDistance then return end

    TriggerEvent('jrs_inventory:CloseInv')
    TriggerServerEvent('jrs_search:server:reset_searched_target', GetPlayerServerId(state.target))
    finish()
    stopAnimation(me, true)
end

local function offer(me, player)
    local group, prompt = GetPromptData()
    PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', ''))
    if not PromptHasHoldModeCompleted(prompt) then return end

    if Config.PlaySearchAnimation.Enabled then
        JRS.PlayAnimation(me, Config.PlaySearchAnimation[genderKey(me)])
    end
    state.target = player
    TriggerServerEvent('jrs_search:server:search', GetPlayerServerId(player))
    Wait(2000)
end

CreateThread(function()
    RegisterActionPrompt()

    while true do
        local wait = 1500
        local me = PlayerPedId()
        local here = GetEntityCoords(me)

        if state.searching and state.target ~= -1 then
            watchTarget(me, here)
        elseif not state.searching then
            local player = GetNearestPlayers(Config.CheckNearestPlayersDistance)[1]
            if player then
                local ped = GetPlayerPed(player)
                if #(here - GetEntityCoords(ped)) <= Config.CheckNearestPlayersDistance and searchable(ped) then
                    wait = 0
                    offer(me, player)
                end
            end
        end
        Wait(wait)
    end
end)
