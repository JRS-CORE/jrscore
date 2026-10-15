local PromptGroup = GetRandomIntInRange(0, 0xffffff)
local Prompts = {}
local placing = false

local KEY_CANCEL       = 0xF84FA74F -- right mouse
local KEY_PLACE        = 0x07CE1E61 -- left mouse
local KEY_ROTATE_LEFT  = 0xA65EBAB4 -- left arrow
local KEY_ROTATE_RIGHT = 0xDEB34313 -- right arrow

local function RegisterPrompt(key, text, holdMode)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, key)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    if holdMode then PromptSetHoldMode(prompt, true) else PromptSetStandardMode(prompt, true) end
    PromptSetGroup(prompt, PromptGroup)
    PromptRegisterEnd(prompt)
    return prompt
end

CreateThread(function()
    Prompts.cancel      = RegisterPrompt(KEY_CANCEL, L('prompt_cancel'), true)
    Prompts.place       = RegisterPrompt(KEY_PLACE, L('prompt_place'), true)
    Prompts.rotateLeft  = RegisterPrompt(KEY_ROTATE_LEFT, L('prompt_rotate_left'), false)
    Prompts.rotateRight = RegisterPrompt(KEY_ROTATE_RIGHT, L('prompt_rotate_right'), false)
end)

local function PropPlacer()
    if placing or IsBusy() then return end
    local model = Config.GoldRocker
    if not LoadModel(model) then return end
    placing = true

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    -- attach offsets are in the ped's local space, so "in front" is simply +Y
    local offsetX, offsetY = 0.0, Config.ForwardDistance
    local pos = GetEntityCoords(ped)

    -- visible ghost + invisible anchor used to read the final world position
    local ghost  = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    local anchor = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityAlpha(ghost, 180, false)
    SetEntityAlpha(anchor, 0, false)
    SetEntityCollision(ghost, false, false)
    SetEntityCollision(anchor, false, false)
    AttachEntityToEntity(anchor, ped, 0, offsetX, offsetY, 0.5, 0.0, 0.0, 0.0, true, false, false, false, 0, false)

    local groupName = CreateVarString(10, 'LITERAL_STRING', L('prompt_group'))
    local heading = 0.0

    while true do
        Wait(0)
        PromptSetActiveGroupThisFrame(PromptGroup, groupName)

        if IsControlPressed(0, KEY_ROTATE_LEFT) then heading = heading - 1.0 end
        if IsControlPressed(0, KEY_ROTATE_RIGHT) then heading = heading + 1.0 end
        AttachEntityToEntity(ghost, ped, 0, offsetX, offsetY, -0.8, 0.0, 0.0, heading, true, false, false, false, 0, false)

        if PromptHasHoldModeCompleted(Prompts.place) then
            local finalPos = GetEntityCoords(anchor)
            local finalHeading = GetEntityHeading(ghost)
            DeleteEntity(anchor)
            DeleteEntity(ghost)
            placing = false
            TriggerEvent('jrs_goldclaim:rocker:client:placeNewProp', finalPos, finalHeading)
            break
        end

        if PromptHasHoldModeCompleted(Prompts.cancel) or IsEntityDead(ped) then
            DeleteEntity(anchor)
            DeleteEntity(ghost)
            placing = false
            break
        end
    end

    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('jrs_goldclaim:rocker:client:createprop', PropPlacer)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, prompt in pairs(Prompts) do PromptDelete(prompt) end
end)
