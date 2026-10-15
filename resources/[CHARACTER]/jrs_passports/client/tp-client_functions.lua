local Prompts     = GetRandomIntInRange(0, 0xffffff)
local PromptsList = {}

--[[-------------------------------------------------------
 Base Events
]]---------------------------------------------------------

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    Citizen.InvokeNative(0x00EDE88D4D13CF59, Prompts) -- UiPromptDelete

    for i, v in pairs(Config.Locations) do

        if v.BlipHandle then
            RemoveBlip(v.BlipHandle)
        end

        if v.NPC then
            DeleteEntity(v.NPC)
            DeletePed(v.NPC)
            SetEntityAsNoLongerNeeded(v.NPC)
        end

    end

end)

--[[-------------------------------------------------------
 Prompts
]]---------------------------------------------------------

RegisterActionPrompts = function()

    for index, action in pairs (Config.PromptKeys) do
        local str      = action.label
        local keyPress = action.key
    
        local dPrompt = PromptRegisterBegin()
        PromptSetControlAction(dPrompt, keyPress)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(dPrompt, str)
        PromptSetEnabled(dPrompt, 1)
        PromptSetVisible(dPrompt, 1)
        PromptSetStandardMode(dPrompt, 1)
        PromptSetHoldMode(dPrompt, 1000)
        PromptSetGroup(dPrompt, Prompts)
        Citizen.InvokeNative(0xC5F428EE08FA7F2C, dPrompt, true)
        PromptRegisterEnd(dPrompt)
    
        table.insert(PromptsList, { prompt = dPrompt, type = index })

    end
end

function GetPromptData()
    return Prompts, PromptsList
end

--[[-------------------------------------------------------
 Blips Management
]]---------------------------------------------------------

function AddBlip(LocationIndex, StatusType)

    if Config.Locations[LocationIndex].BlipData then

        local BlipData = Config.Locations[LocationIndex].BlipData

        local sprite, blipModifier = BlipData.Sprite, 'BLIP_MODIFIER_MP_COLOR_32'

        if BlipData.OpenBlipModifier then
            blipModifier = BlipData.OpenBlipModifier
        end

        if StatusType == 'CLOSED' then
            sprite = BlipData.DisplayClosedHours.Sprite
            blipModifier = BlipData.DisplayClosedHours.BlipModifier
        end
        
        Config.Locations[LocationIndex].BlipHandle = N_0x554d9d53f696d002(1664425300, Config.Locations[LocationIndex].Coords.x, Config.Locations[LocationIndex].Coords.y, Config.Locations[LocationIndex].Coords.z)

        SetBlipSprite(Config.Locations[LocationIndex].BlipHandle, sprite, 1)
        SetBlipScale(Config.Locations[LocationIndex].BlipHandle, 0.2)

        Citizen.InvokeNative(0x662D364ABF16DE2F, Config.Locations[LocationIndex].BlipHandle, GetHashKey(blipModifier))

        Config.Locations[LocationIndex].BlipHandleModifier = blipModifier

        Citizen.InvokeNative(0x9CB1A1623062F402, Config.Locations[LocationIndex].BlipHandle, BlipData.Title)

    end
end

--[[-------------------------------------------------------
 NPC
]]---------------------------------------------------------

LoadModel = function(inputModel)
    local model = GetHashKey(inputModel)
 
    RequestModel(model)
 
    while not HasModelLoaded(model) do RequestModel(model)
        Citizen.Wait(10)
    end
end

RemoveEntityProperly = function(entity, objectHash)
	DeleteEntity(entity)
	DeletePed(entity)
	SetEntityAsNoLongerNeeded( entity )

	if objectHash then
		SetModelAsNoLongerNeeded(objectHash)
	end
end

function SpawnNPC(LocationIndex)
    local v = Config.Locations[LocationIndex]

    LoadModel(v.NPCData.Model)

    local coords = v.NPCData.Coords
    local npc = CreatePed(v.NPCData.Model, coords.x, coords.y, coords.z, coords.h, false, true, true, true)

    Citizen.InvokeNative(0x283978A15512B2FE, npc, true) -- SetRandomOutfitVariation
    SetEntityNoCollisionEntity(PlayerPedId(), npc, false)
    SetEntityCanBeDamaged(npc, false)
    SetEntityInvincible(npc, true)
    Wait(1000)
    FreezeEntityPosition(npc, true) -- NPC can't escape
    SetBlockingOfNonTemporaryEvents(npc, true) -- NPC can't be scared

    Config.Locations[LocationIndex].NPC = npc
end