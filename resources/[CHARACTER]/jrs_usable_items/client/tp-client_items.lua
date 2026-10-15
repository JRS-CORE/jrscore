local IsUsingItem = false

local DisplayedPrompts = false

---------------------------------------------------------------
--[[ General Events ]]--
---------------------------------------------------------------

RegisterNetEvent('jrs_usable_items:client:use')
AddEventHandler('jrs_usable_items:client:use', function(itemName) 

	if Config.UsableItems[itemName] == nil then
		return
	end

	if IsUsingItem then
		-- notify
		return
	end

	local ItemData = Config.UsableItems[itemName]

	if ItemData.PutAwayPromptAction.Enabled then
		RegisterPutAwayPrompt(ItemData.PutAwayPromptAction.Label)
	end

	if ItemData.UsePromptAction.Enabled then
		RegisterUsePrompt(ItemData.UsePromptAction.Label)
	end

	if ItemData.ChangePromptAction.Enabled then
		RegisterChangePrompt(ItemData.ChangePromptAction.Label)
	end

	if ItemData.Type == 'POCKET_WATCH' then
		OnPocketWatch(itemName)

	elseif ItemData.Type == 'HAIR_POMADE' then

		OnHairPomade(itemName)

	elseif ItemData.Type == 'CIGARETTE' then

		OnCigarette(itemName)

	elseif ItemData.Type == 'CIGAR' then

		OnCigar(itemName)

	elseif ItemData.Type == 'PIPE_OF_PEACE' then
		OnPipePeace(itemName)

	elseif ItemData.Type == 'PIPE' then
		OnPipe(itemName)
	end

end)

---------------------------------------------------------------
--[[ Item Usable Functions ]]--
---------------------------------------------------------------

function OnPipe(itemName)
    local ped = PlayerPedId()
	local ItemData = Config.UsableItems[itemName]

	local data = { gender = IsPedMale(PlayerPedId()) and 0 or 1 } -- 0 male / 1 female

	if data == nil then
		-- not loaded?
		return
	end

	if ItemData.RemoveItemOnUse then
		TriggerServerEvent("jrs_usable_items:remove", itemName)
	end
	
	
	local animation = {
		[0] = { -- male
			[1] = 'amb_rest@world_human_smoking@male_b@base',
			[2] = 'amb_rest@world_human_smoking@male_b@idle_a',
			[3] = 'amb_rest@world_human_smoking@male_b@idle_b',
		},

		[1] = { -- female
			[1] = 'amb_rest@world_human_smoking@female_b@base',
			[2] = 'amb_rest@world_human_smoking@female_b@idle_a',
			[3] = 'amb_rest@world_human_smoking@female_b@idle_b',
		}
	}

	LoadModel(ItemData.Object)

	local coords    = GetEntityCoords(ped, true)
    local pipe      = CreateObject(GetHashKey(ItemData.Object), coords.x, coords.y, coords.z + 0.2, true, true, true)
    local righthand = GetEntityBoneIndexByName(ped, "SKEL_R_Finger13")
    
    AttachEntityToEntity(pipe, ped, righthand, 0.005, -0.045, 0.0, -170.0, 10.0, -15.0, true, true, false, true, 1, true)
    Anim(ped,"amb_wander@code_human_smoking_wander@male_b@trans","nopipe_trans_pipe",-1,30)
    
	Wait(9000)
    Anim(ped, animation[data.gender][1],"base",-1,31)

    while not IsEntityPlayingAnim(ped, animation[data.gender][1],"base", 3) do
        Wait(100)
    end

    if not DisplayedPromptS then
        PromptSetEnabled(GetPromptPutAway(), true) PromptSetVisible(GetPromptPutAway(), true)
        PromptSetEnabled(GetPromptUse(), true) PromptSetVisible(GetPromptUse(), true)
        DisplayedPrompts = true
	end

    while IsEntityPlayingAnim(ped, animation[data.gender][1],"base", 3) do

        Wait(5)
		if IsControlJustReleased(0, 0x3B24C470) then
			PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
			PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)

            DisplayedPrompts = false

			if data.gender == 0 then -- TRANS DOES NOT EXIST FOR FEMALES (ITS AN PIPE EXIT ANIM)
				Anim(ped, "amb_wander@code_human_smoking_wander@male_b@trans", "pipe_trans_nopipe", -1, 30)
				Wait(6066)
			end

			DetachEntity(pipe, true, true)
			RemoveEntityProperly(pipe, GetHashKey(pipe))
            ClearPedSecondaryTask(ped)
            ClearPedTasks(ped)
            Wait(10)
		end

        if IsControlJustReleased(0, 0x07B8BEAF) then
            Wait(500)
            if IsControlPressed(0, 0x07B8BEAF) then
                Anim(ped, animation[data.gender][3],"idle_d", -1, 30, 0)
                Wait(15599)
                Anim(ped, animation[data.gender][1],"base", -1, 31, 0)
                Wait(100)

				-- METABOLISM STRESS TRIGGER HERE?
				-- to-do0)
            else
                Anim(ped, animation[data.gender][2],"idle_a", -1, 30, 0)
                Wait(22600)
                Anim(ped, animation[data.gender][1],"base", -1, 31, 0)
                Wait(100)

				-- METABOLISM STRESS TRIGGER HERE?
				-- to-do
            end
        end
    end

	PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
	PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)

    DisplayedPrompts = false

    DetachEntity(pipe, true, true)
	RemoveEntityProperly(pipe, GetHashKey(pipe))
    ClearPedSecondaryTask(ped)

	if data.gender == 0 then -- TRANS DOES NOT EXIST FOR FEMALES (ITS AN PIPE EXIT ANIM)
		RemoveAnimDict("amb_wander@code_human_smoking_wander@male_b@trans")
	end
	
    RemoveAnimDict(animation[data.gender][1])
    RemoveAnimDict(animation[data.gender][2])
    RemoveAnimDict(animation[data.gender][3])
    Wait(100)
    ClearPedTasks(ped)

end

function OnPipePeace(itemName)
    local ped = PlayerPedId()
	local ItemData = Config.UsableItems[itemName]

	local data = { gender = IsPedMale(PlayerPedId()) and 0 or 1 } -- 0 male / 1 female

	if data == nil then
		-- not loaded?
		return
	end

	if ItemData.RemoveItemOnUse then
		TriggerServerEvent("jrs_usable_items:remove", itemName)
	end

	local animation = {
		[0] = { -- male
			[1] = 'amb_rest@world_human_smoking@male_b@base',
			[2] = 'amb_rest@world_human_smoking@male_b@idle_a',
			[3] = 'amb_rest@world_human_smoking@male_b@idle_b',
		},

		[1] = { -- female
			[1] = 'amb_rest@world_human_smoking@female_b@base',
			[2] = 'amb_rest@world_human_smoking@female_b@idle_a',
			[3] = 'amb_rest@world_human_smoking@female_b@idle_b',
		}
	}

	LoadModel(ItemData.Object)

	local coords    = GetEntityCoords(ped, true)
    local pipe      = CreateObject(GetHashKey(ItemData.Object), coords.x, coords.y, coords.z + 0.2, true, true, true)
    local righthand = GetEntityBoneIndexByName(ped, "SKEL_R_Finger13")
                                    
    AttachEntityToEntity(pipe, ped, righthand, -0.06, -0.025, 0.15, -170.0, 20.0, -22.0, true, true, false, false, 1, true)
    
    Anim(ped, animation[data.gender][1], "base",-1,31)

    while not IsEntityPlayingAnim(ped, animation[data.gender][1], "base", 3) do
        Wait(100)
    end

    if not DisplayedPrompts then
        PromptSetEnabled(GetPromptPutAway(), true) PromptSetVisible(GetPromptPutAway(), true)
        PromptSetEnabled(GetPromptUse(), true) PromptSetVisible(GetPromptUse(), true)

        DisplayedPrompts = true
	end

    while IsEntityPlayingAnim(ped, animation[data.gender][1],"base", 3) do

        Wait(5)
		if IsControlJustReleased(0, 0x3B24C470) then

            PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
            PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)

            DisplayedPrompts = false

			if data.gender == 0 then -- TRANS DOES NOT EXIST FOR FEMALES (ITS AN PIPE OF PEACE EXIT ANIM)
				Anim(ped, "amb_wander@code_human_smoking_wander@male_b@trans", "pipe_trans_nopipe", -1, 30)
				Wait(6066)
			end

			DetachEntity(pipe, true, true)
			RemoveEntityProperly(pipe, GetHashKey(ItemData.Object) )
            ClearPedSecondaryTask(ped)
            ClearPedTasks(ped)
            Wait(10)
		end
        
        if IsControlJustReleased(0, 0x07B8BEAF) then
            Wait(500)
            if IsControlPressed(0, 0x07B8BEAF) then
                Anim(ped, animation[data.gender][3],"idle_d", -1, 30, 0)
                Wait(15599)
                Anim(ped, animation[data.gender][1],"base", -1, 31, 0)
                Wait(100)

				-- METABOLISM STRESS TRIGGER HERE?
				-- to-do
            else
                Anim(ped, animation[data.gender][2],"idle_a", -1, 30, 0)
                Wait(22600)
                Anim(ped, animation[data.gender][1],"base", -1, 31, 0)
                Wait(100)

				-- METABOLISM STRESS TRIGGER HERE?
				-- to-do
            end
        end
    end

    PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
    PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)

    DisplayedPrompts = false

    DetachEntity(pipe, true, true)
	RemoveEntityProperly(pipe, GetHashKey(ItemData.Object) )

    ClearPedSecondaryTask(ped)

	if data.gender == 0 then -- TRANS DOES NOT EXIST FOR FEMALES (ITS AN PIPE OF PEACE EXIT ANIM)
		RemoveAnimDict("amb_wander@code_human_smoking_wander@male_b@trans")
	end

    RemoveAnimDict(animation[data.gender][1])
    RemoveAnimDict(animation[data.gender][2])
    RemoveAnimDict(animation[data.gender][3])
    Wait(100)
    ClearPedTasks(ped)
end
    

function OnCigarette(itemName)
	local ped      = PlayerPedId()
	local ItemData = Config.UsableItems[itemName]

	local data = { gender = IsPedMale(PlayerPedId()) and 0 or 1 } -- 0 male / 1 female

	if data == nil then
		-- not loaded?
		return
	end

	if ItemData.RemoveItemOnUse then
		TriggerServerEvent("jrs_usable_items:remove", itemName)
	end
	
	LoadModel(ItemData.Object)

	local coords    = GetEntityCoords(ped, true)

	local cigarette = CreateObject(GetHashKey(ItemData.Object), coords.x, coords.y, coords.z + 0.2, true, true, true)
	local righthand = GetEntityBoneIndexByName(ped, "SKEL_R_Finger13")
	local mouth     = GetEntityBoneIndexByName(ped, "skel_head")
	
	local stance    = "c"

	if data.gender == 0 then
		AttachEntityToEntity(cigarette, ped, mouth, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
		Anim(ped,"amb_rest@world_human_smoking@male_c@stand_enter","enter_back_rf",9400,0)
		Wait(1000)
		AttachEntityToEntity(cigarette, ped, righthand, 0.03, -0.01, 0.0, 0.0, 90.0, 0.0, true, true, false, true, 1, true)
		Wait(1000)
		AttachEntityToEntity(cigarette, ped, mouth, -0.017, 0.1, -0.01, 0.0, 90.0, -90.0, true, true, false, true, 1, true)
		Wait(3000)
		AttachEntityToEntity(cigarette, ped, righthand, 0.017, -0.01, -0.01, 0.0, 120.0, 10.0, true, true, false, true, 1, true)
		Wait(1000)
		Anim(ped,"amb_rest@world_human_smoking@male_c@base","base",-1,30)
		RemoveAnimDict("amb_rest@world_human_smoking@male_c@stand_enter")
		Wait(1000)

	else --female
		AttachEntityToEntity(cigarette, ped, mouth, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
		Anim(ped,"amb_rest@world_human_smoking@female_c@base","base",-1,30)
		Wait(1000)
		AttachEntityToEntity(cigarette, ped, righthand, 0.01, 0.0, 0.01, 0.0, -160.0, -130.0, true, true, false, true, 1, true)
		Wait(2500)
	end

	if not DisplayedPrompts then
		PromptSetEnabled(GetPromptPutAway(), true) PromptSetVisible(GetPromptPutAway(), true)
		PromptSetEnabled(GetPromptUse(), true) PromptSetVisible(GetPromptUse(), true)

		PromptSetEnabled(ChangeStance, true)
		PromptSetVisible(ChangeStance, true)
		DisplayedPrompts = true
	end

	if data.gender == 0 then
		while  IsEntityPlayingAnim(ped, "amb_rest@world_human_smoking@male_c@base","base", 3)
			or IsEntityPlayingAnim(ped, "amb_rest@world_human_smoking@nervous_stressed@male_b@base","base", 3)
			or IsEntityPlayingAnim(ped, "amb_rest@world_human_smoking@male_d@base","base", 3)
			or IsEntityPlayingAnim(ped, "amb_wander@code_human_smoking_wander@male_a@base","base", 3) do

			Wait(5)
			if IsControlJustReleased(0, 0x3B24C470) then
				PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
				PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)
		
				PromptSetEnabled(ChangeStance, false)
				PromptSetVisible(ChangeStance, false)
				DisplayedPrompts = false

				ClearPedSecondaryTask(ped)
				Anim(ped, "amb_rest@world_human_smoking@male_a@stand_exit", "exit_back", -1, 1)
				Wait(2800)
				DetachEntity(cigarette, true, true)
				SetEntityVelocity(cigarette, 0.0,0.0,-1.0)
				Wait(1500)
				ClearPedSecondaryTask(ped)
				ClearPedTasks(ped)
				Wait(10)
			end
			
			if stance=="c" then
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@male_c@idle_a","idle_b", -1, 30, 0)
						Wait(21166)
						Anim(ped, "amb_rest@world_human_smoking@male_c@base","base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do

					else
						Anim(ped, "amb_rest@world_human_smoking@male_c@idle_a","idle_a", -1, 30, 0)
						Wait(8500)
						Anim(ped, "amb_rest@world_human_smoking@male_c@base","base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					end
				end
			elseif stance=="b" then
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@nervous_stressed@male_b@idle_c","idle_g", -1, 30, 0)
						Wait(13433)
						Anim(ped, "amb_rest@world_human_smoking@nervous_stressed@male_b@base", "base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					else
						Anim(ped, "amb_rest@world_human_smoking@nervous_stressed@male_b@idle_a", "idle_a", -1, 30, 0)
						Wait(3199)
						Anim(ped, "amb_rest@world_human_smoking@nervous_stressed@male_b@base", "base", -1, 30, 0)
						Wait(100)
					
						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					end
				end
			elseif stance=="d" then
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@male_d@idle_a","idle_b", -1, 30, 0)
						Wait(7366)
						Anim(ped, "amb_rest@world_human_smoking@male_d@base", "base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					else
						Anim(ped, "amb_rest@world_human_smoking@male_d@idle_c", "idle_g", -1, 30, 0)
						Wait(7866)
						Anim(ped, "amb_rest@world_human_smoking@male_d@base", "base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					end
				end
			else --stance=="a"
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@male_a@idle_a", "idle_b", -1, 30, 0)
						Wait(12533)
						Anim(ped, "amb_wander@code_human_smoking_wander@male_a@base", "base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					else
						Anim(ped, "amb_rest@world_human_smoking@male_a@idle_a","idle_a", -1, 30, 0)
						Wait(8200)
						Anim(ped, "amb_wander@code_human_smoking_wander@male_a@base", "base", -1, 30, 0)
						Wait(100)

						-- METABOLISM STRESS TRIGGER HERE?
						-- to-do
					end
				end
			end
		end
	else --if female
		while  IsEntityPlayingAnim(ped,"amb_rest@world_human_smoking@female_c@base", "base", 3) 
			or IsEntityPlayingAnim(ped,"amb_rest@world_human_smoking@female_b@base", "base", 3)
			or IsEntityPlayingAnim(ped,"amb_rest@world_human_smoking@female_a@base", "base", 3)do

			Wait(5)
			if IsControlJustReleased(0, 0x3B24C470) then
				PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
				PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)

				PromptSetEnabled(ChangeStance, false)
				PromptSetVisible(ChangeStance, false)
				DisplayedPrompts = false

				ClearPedSecondaryTask(ped)
				Anim(ped, "amb_rest@world_human_smoking@female_b@trans", "b_trans_fire_stand_a", -1, 1)
				Wait(3800)
				DetachEntity(cigarette, true, true)
				Wait(800)
				ClearPedSecondaryTask(ped)
				ClearPedTasks(ped)
				Wait(10)
			end

			if stance=="c" then
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@female_c@idle_a","idle_a", -1, 30, 0)
						Wait(9566)
						Anim(ped, "amb_rest@world_human_smoking@female_c@base","base", -1, 30, 0)
						Wait(100)
					else
						Anim(ped, "amb_rest@world_human_smoking@female_c@idle_b","idle_f", -1, 30, 0)
						Wait(8133)
						Anim(ped, "amb_rest@world_human_smoking@female_c@base","base", -1, 30, 0)
						Wait(100)
					end
				end
			elseif stance=="b" then
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@female_b@idle_b","idle_f", -1, 30, 0)
						Wait(8033)
						Anim(ped, "amb_rest@world_human_smoking@female_b@base", "base", -1, 30, 0)
						Wait(100)
					else
						Anim(ped, "amb_rest@world_human_smoking@female_b@idle_a", "idle_b", -1, 30, 0)
						Wait(4266)
						Anim(ped, "amb_rest@world_human_smoking@female_b@base", "base", -1, 30, 0)
						Wait(100)
					end
				end
			else --stance=="a"
				if IsControlJustReleased(0, 0x07B8BEAF) then
					Wait(500)
					if IsControlPressed(0, 0x07B8BEAF) then
						Anim(ped, "amb_rest@world_human_smoking@female_a@idle_b", "idle_d", -1, 30, 0)
						Wait(14566)
						Anim(ped, "amb_rest@world_human_smoking@female_a@base", "base", -1, 30, 0)
						Wait(100)
					else
						Anim(ped, "amb_rest@world_human_smoking@female_a@idle_a","idle_b", -1, 30, 0)
						Wait(6100)
						Anim(ped, "amb_rest@world_human_smoking@female_a@base", "base", -1, 30, 0)
						Wait(100)
					end
				end
			end
		end
	end

	PromptSetEnabled(GetPromptPutAway(), false) PromptSetVisible(GetPromptPutAway(), false)
	PromptSetEnabled(GetPromptUse(), false) PromptSetVisible(GetPromptUse(), false)

	PromptSetEnabled(ChangeStance, false)
	PromptSetVisible(ChangeStance, false)
	DisplayedPrompts = false

	DetachEntity(cigarette, true, true)
	ClearPedSecondaryTask(ped)
	RemoveAnimDict("amb_wander@code_human_smoking_wander@male_a@base")
	RemoveAnimDict("amb_rest@world_human_smoking@male_a@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@nervous_stressed@male_b@base")
	RemoveAnimDict("amb_rest@world_human_smoking@nervous_stressed@male_b@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@nervous_stressed@male_b@idle_g")
	RemoveAnimDict("amb_rest@world_human_smoking@male_c@base")
	RemoveAnimDict("amb_rest@world_human_smoking@male_c@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@male_d@base")
	RemoveAnimDict("amb_rest@world_human_smoking@male_d@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@male_d@idle_c")
	RemoveAnimDict("amb_rest@world_human_smoking@male_a@trans")
	RemoveAnimDict("amb_rest@world_human_smoking@male_c@trans")
	RemoveAnimDict("amb_rest@world_human_smoking@male_d@trans")
	RemoveAnimDict("amb_rest@world_human_smoking@female_a@base")
	RemoveAnimDict("amb_rest@world_human_smoking@female_a@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@female_a@idle_b")
	RemoveAnimDict("amb_rest@world_human_smoking@female_b@base")
	RemoveAnimDict("amb_rest@world_human_smoking@female_b@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@female_b@idle_b")
	RemoveAnimDict("amb_rest@world_human_smoking@female_c@base")
	RemoveAnimDict("amb_rest@world_human_smoking@female_c@idle_a")
	RemoveAnimDict("amb_rest@world_human_smoking@female_c@idle_b")
	RemoveAnimDict("amb_rest@world_human_smoking@female_b@trans")
	Wait(100)
	ClearPedTasks(ped)
end

function OnCigar(itemName)
	local ped      = PlayerPedId()
	local ItemData = Config.UsableItems[itemName]

	if ItemData.RemoveItemOnUse then
		TriggerServerEvent("jrs_usable_items:remove", itemName)
	end

    PlaySoundFrontend("Core_Full", "Consumption_Sounds", true, 0)

    local dict = 'amb_rest@world_human_smoke_cigar@male_a@idle_b'
    local anim = 'idle_d'

	LoadModel(ItemData.Object)

	local coords    = GetEntityCoords(ped, true)
    local prop      = CreateObject(GetHashKey(ItemData.Object), coords.x, coords.y, coords.z + 0.2, true, true, true)
    local boneIndex = GetEntityBoneIndexByName(ped, 'SKEL_R_Finger12')
    local smoking   = false

	local waiting   = 0

	RequestAnimDict(dict)

	while (not HasAnimDictLoaded(dict)) do
		
		RequestAnimDict(dict)

		Citizen.Wait(300)

		waiting = waiting + 300

		if waiting > 5000 then
			print('RedM broke up this animation')
			break
		end

	end	

	Wait(100)
	AttachEntityToEntity(prop, ped,boneIndex, 0.01, -0.00500, 0.01550, 0.024, 300.0, -40.0, true, true, false, true, 1, true)
	TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 31, 0, true, 0, false, 0, false)
	Wait(1000)

	-- TRIGGER HERE METABOLISM VALUES!
	-- to-do

	if not DisplayedPrompts then
		PromptSetEnabled(GetPromptPutAway(), true)
		PromptSetVisible(GetPromptPutAway(), true)
		DisplayedPrompts = true
	end
	
	smoking = true

	while smoking do

		if IsEntityPlayingAnim(ped, dict, anim, 3) then

			DisableControlAction(0, 0x07CE1E61, true)
			DisableControlAction(0, 0xF84FA74F, true)
			DisableControlAction(0, 0xCEE12B50, true)
			DisableControlAction(0, 0xB2F377E8, true)
			DisableControlAction(0, 0x8FFC75D6, true)
			DisableControlAction(0, 0xD9D0E1C0, true)

			if IsControlPressed(0, 0x3B24C470) then

				PromptSetEnabled(GetPromptPutAway(), false)
				PromptSetVisible(GetPromptPutAway(), false)
				DisplayedPrompts = false
				smoking = false
				ClearPedSecondaryTask(ped)
				RemoveEntityProperly(prop, GetHashKey(ItemData.Object))
				RemoveAnimDict(dict)
				break
			end

		else
			TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 31, 0, true, 0, false, 0, false)
		end

		Wait(0)
	end

end

function OnHairPomade(itemName)
	local ItemData  = Config.UsableItems[itemName]
    local playerPed = PlayerPedId()

    if Citizen.InvokeNative(0xFB4891BD7578CDC1, playerPed, tonumber(0x9925C067)) then   -- _IS_METAPED_USING_COMPONENT
        TaskItemInteraction(playerPed, 0, GetHashKey("APPLY_POMADE_WITH_HAT"), 1, 0, -1082130432)
    else
        TaskItemInteraction(playerPed, 0, GetHashKey("APPLY_POMADE_WITH_NO_HAT"), 1, 0, -1082130432)
    end

    Wait(1500)
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, playerPed, GetCurrentPedComponent(playerPed, "hair"), GetHashKey("POMADE"), 0, true, 1) -- _UPDATE_SHOP_ITEM_WEARABLE_STATE
    Citizen.InvokeNative(0xCC8CA3E88256E58F, playerPed, false, true, true, true, false) -- _UPDATE_PED_VARIATION

	if ItemData.RemoveItemOnUse then
		TriggerServerEvent("jrs_usable_items:remove", itemName)
	end

end

function OnPocketWatch(itemName)
	local ped  = PlayerPedId()
	local data = { gender = IsPedMale(PlayerPedId()) and 0 or 1 } -- 0 male / 1 female

	if data == nil then
		-- not loaded?
		return
	end

	local ItemData = Config.UsableItems[itemName]

	RequestAnimDict('mech_inventory@item@pocketwatch@unarmed@base')

 local waiting = 0

	while (not HasAnimDictLoaded('mech_inventory@item@pocketwatch@unarmed@base')) do
		
		RequestAnimDict('mech_inventory@item@pocketwatch@unarmed@base')

		Citizen.Wait(300)

		waiting = waiting + 300

		if waiting > 5000 then
			print('RedM broke up this animation')
			break
		end

	end	

	LoadModel(ItemData.Object)

	local coords    = GetEntityCoords(ped, true)
	local prop      = CreateObject(GetHashKey(ItemData.Object), coords.x, coords.y, coords.z + 0.2, true, true, true)
	local boneIndex = GetEntityBoneIndexByName(ped, "SKEL_R_Hand")

    if data.gender == 0 then
	    AttachEntityToEntity(prop, ped,boneIndex, 0.085,0.025,-0.035,  15.0,190.0,-140.0, true, true, false, true, 1, true)
    else
        AttachEntityToEntity(prop, ped,boneIndex, 0.075,0.025,-0.045,  35.0,200.0,-140.0, true, true, false, true, 1, true)
    end

	local UnholsterTime = GetAnimDuration('mech_inventory@item@pocketwatch@unarmed@base', "unholster")

	Anim(ped,"mech_inventory@item@pocketwatch@unarmed@base","unholster",UnholsterTime*1000,0)

    Wait(UnholsterTime*1000)

    Anim(ped,"mech_inventory@item@pocketwatch@unarmed@base","inspect_base",-1,31)

    Wait(100)

    if not DisplayedPrompts then
		PromptSetEnabled(GetPromptPutAway(), true)
		PromptSetVisible(GetPromptPutAway(), true)
		DisplayedPrompts = true
	end

	--Force 1st person view when watch is out
	Citizen.CreateThread(function()
		while true do

			Wait(1)

			local hasWatchActive = false
			local forced         = false
			
			local playerPed     = PlayerPedId()

			if IsEntityPlayingAnim(playerPed, "mech_inventory@item@pocketwatch@unarmed@base", "inspect_base", 3) then
				hasWatchActive = true

				local inFirstPerson = Citizen.InvokeNative(0x90DA5BA5C2635416) -- Is already aiming first person?

				if inFirstPerson and not forced then
					forced = false
				else
					Citizen.InvokeNative(0x90DA5BA5C2635416) -- force first
					forced = true
				end

			end

			if IsControlJustReleased(0, 0x3B24C470) or not hasWatchActive then

				Citizen.InvokeNative(0x1CFB749AD4317BDE) -- force 3rd

				StopAnimTask(playerPed, 'mech_inventory@item@pocketwatch@unarmed@base', "inspect_base", 1.0)
				Anim(playerPed,"mech_inventory@item@pocketwatch@unarmed@base","holster",1000,0)

				Citizen.Wait(2000)

				PromptSetEnabled(GetPromptPutAway(), false)
				PromptSetVisible(GetPromptPutAway(), false)
				DisplayedPrompts = false
			
				StopAnimTask(playerPed, 'mech_inventory@item@pocketwatch@unarmed@base', "inspect_base", 1.0)
			
				RemoveEntityProperly(prop, GetHashKey(ItemData.Object))
				RemoveAnimDict('mech_inventory@item@pocketwatch@unarmed@base')

				break
			end

		end
	end)

end
