local PromptPutAway = nil
local PromptUse     = nil
local PromptChange  = nil

---------------------------------------------------------------
--[[ Prompts ]]--
---------------------------------------------------------------

function RegisterPutAwayPrompt(text, hold)
	PromptPutAway = nil

	local str        = text
	local holdbutton = hold or false

	local prompt = PromptRegisterBegin()
	PromptSetControlAction(prompt, 0x3B24C470)
	str = CreateVarString(10, 'LITERAL_STRING', str)
	PromptSetText(prompt, str)
	PromptSetEnabled(prompt, false)
	PromptSetVisible(prompt, false)
	PromptSetHoldMode(prompt, holdbutton)
	PromptRegisterEnd(prompt)

	PromptPutAway = prompt
end

function GetPromptPutAway()
	return PromptPutAway
end

function RegisterUsePrompt(text, hold)
	PromptUse = nil
	
	local str        = text
	local holdbutton = hold or false

	local prompt = PromptRegisterBegin()
	PromptSetControlAction(prompt, 0x07B8BEAF)
	str = CreateVarString(10, 'LITERAL_STRING', str)
	PromptSetText(prompt, str)
	PromptSetEnabled(prompt, false)
	PromptSetVisible(prompt, false)
	PromptSetHoldMode(prompt, holdbutton)
	PromptRegisterEnd(prompt)

	PromptUse = prompt
end

function GetPromptUse()
	return PromptUse
end

function RegisterChangePrompt(text, hold)
	PromptChange = nil

	local str        = text
	local holdbutton = hold or false

	local prompt = PromptRegisterBegin()
	PromptSetControlAction(prompt, 0xD51B784F)
	str = CreateVarString(10, 'LITERAL_STRING', str)
	PromptSetText(prompt, str)
	PromptSetEnabled(prompt, false)
	PromptSetVisible(prompt, false)
	PromptSetHoldMode(prompt, holdbutton)
	PromptRegisterEnd(prompt)

	PromptChange = prompt
end

function GetPromptChange()
	return PromptChange
end

---------------------------------------------------------------
--[[ Animations ]]--
---------------------------------------------------------------

function Anim(actor, dict, body, duration, flags, introtiming, exittiming)
	Citizen.CreateThread(function()
		RequestAnimDict(dict)
		local dur = duration or -1
		local flag = flags or 1
		local intro = tonumber(introtiming) or 1.0
		local exit = tonumber(exittiming) or 1.0
		timeout = 5
		while (not HasAnimDictLoaded(dict) and timeout>0) do
			timeout = timeout-1
			if timeout == 0 then 
				print("Animation Failed to Load")
			end
			Citizen.Wait(300)
		end
		TaskPlayAnim(actor, dict, body, intro, exit, dur, flag --[[1 for repeat--]], 1, false, false, false, 0, true)
	end)
end
	
function StopAnim(dict, body)
	Citizen.CreateThread(function()
		StopAnimTask(PlayerPedId(), dict, body, 1.0)
	end)
end

---------------------------------------------------------------
--[[ Models ]]--
---------------------------------------------------------------

function LoadModel(inputModel)
    local model = GetHashKey(inputModel)
 
    RequestModel(model)
 
    while not HasModelLoaded(model) do RequestModel(model)
        Citizen.Wait(10)
    end
 end

 function RemoveEntityProperly(entity, objectHash)
    DeleteEntity(entity)
    DeletePed(entity)
    SetEntityAsNoLongerNeeded( entity )

    if objectHash then
        SetModelAsNoLongerNeeded(objectHash)
    end
end

---------------------------------------------------------------
--[[ Other ]]--
---------------------------------------------------------------

function GetCurrentPedComponent(ped, category)

    local componentsCount = GetNumComponentsInPed(ped)
    if not componentsCount then
        return 0
    end
    local metaPedType = GetMetaPedType(ped)
    local dataStruct = DataView.ArrayBuffer(6 * 8)
    local fullPedComponents = {}
    for i = 0, componentsCount, 1 do
        local componentHash = GetShopPedComponentAtIndex(ped, i, true, dataStruct:Buffer(), dataStruct:Buffer())
        if componentHash then
            local componentCategoryHash = GetShopPedComponentCategory(componentHash, metaPedType, true)
            if category ~= nil then
                if GetHashKey(category) == componentCategoryHash then
                    return componentHash
                end
            else
                fullPedComponents[componentCategoryHash] = componentHash
            end
        end
    end
    if category then
        return 0
    end
    return fullPedComponents
end

function GetNumComponentsInPed(ped)
    return Citizen.InvokeNative(0x90403E8107B60E81, ped)
end

function GetMetaPedType(ped)
    return Citizen.InvokeNative(0xEC9A1261BF0CE510, ped)
end

function GetShopPedComponentAtIndex(ped, index, bool, struct1, struct2)
    return Citizen.InvokeNative(0x77BA37622E22023B, ped, index, bool, struct1, struct2)
end

function GetShopPedComponentCategory(componentHash, metaPedType, bool)
    return Citizen.InvokeNative(0x5FF9A878C3D115B8, componentHash, metaPedType, bool)
end