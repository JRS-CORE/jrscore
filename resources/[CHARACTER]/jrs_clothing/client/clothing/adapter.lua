if ClothingConfig.framework == 'jrs_core' then
    -- jrs_character's own appearance pipeline can legitimately take up to
    -- ~32s under heavy join load (model streaming + collision wait). Track
    -- its canonical readiness signal here instead of guessing a fixed delay
    -- before snapshotting whatever the ped currently has equipped.
    local characterAppearanceReady = false
    AddEventHandler('jrs_character:isPlayerReady', function()
        characterAppearanceReady = true
    end)
    -- jrs_character fires this while the screen is still black (before the
    -- reveal and the wake-up animation), so the canonical outfit pass runs
    -- hidden instead of stripping/re-dressing the ped in front of the player.
    AddEventHandler('jrs_character:appearanceStageReady', function()
        characterAppearanceReady = true
        -- Tell jrs_character the dress pass is pending so it holds the reveal.
        clotheitemBusyUntil = GetGameTimer() + 4000
    end)

    local function waitForCharacterAppearanceReady(timeoutMs)
        if characterAppearanceReady then return true end
        local deadline = GetGameTimer() + (timeoutMs or 35000)
        while not characterAppearanceReady and GetGameTimer() < deadline do
            Wait(100)
        end
        return characterAppearanceReady
    end

    local function loadCurrentClothes()
        CreateThread(function()
            waitForCharacterAppearanceReady(35000)
            Wait(300)

            Callback.triggerServer('jrs_clothing:GetCurrentClothes', function(datatable, id, exists, hiddenCategories)
                if SetHiddenClothingCategories then SetHiddenClothingCategories(hiddenCategories) end
                SelectedGender = IsPedMale(PlayerPedId()) and 'male' or 'female'
                if type(baseskin) ~= 'table' then baseskin = {} end

                local ped = PlayerPedId()
                if not baseskin.bodies_upper or baseskin.bodies_upper == 0 then
                    baseskin.bodies_upper = GetComponentEquiped(ped, 'bodies_upper')
                end
                if not baseskin.bodies_lower or baseskin.bodies_lower == 0 then
                    baseskin.bodies_lower = GetComponentEquiped(ped, 'bodies_lower')
                end

                if exists ~= true then
                    -- The character still uses compPlayer. Let jrs_character
                    -- finish applying it, capture the real equipped pieces in
                    -- jrs_clothing format, then save and retire compPlayer.
                    Wait(200)
                    local captured = CaptureCurrentJRSClothes and CaptureCurrentJRSClothes(PlayerPedId()) or {}
                    if type(captured) == 'table' and next(captured) then
                        TriggerServerEvent('jrs_clothes:updateclothes', captured, 0)
                        datatable = captured
                    end
                end

                local dressed = false
                if type(datatable) == 'table' then
                    for _, value in pairs(datatable) do
                        if type(value) == 'table' and tonumber(value.model or 0) > 0 then
                            TriggerEvent('jrs_clothes:clotheitem', datatable, id)
                            dressed = true
                            break
                        end
                    end
                end
                -- Nothing to apply: release the reveal hold set above.
                if not dressed then clotheitemBusyUntil = 0 end
            end)
        end)
    end

    RegisterNetEvent('jrs:SelectedCharacter', function()
        characterAppearanceReady = false
        loadCurrentClothes()
    end)
    RegisterNetEvent('jrs_character:revive_player', loadCurrentClothes)
    RegisterNetEvent('jrs_clothes:reloadCurrentClothes', loadCurrentClothes)
    RegisterNetEvent('jrs_character:client:reloadCurrentCharacter', loadCurrentClothes)
    RegisterNetEvent('jrs_character_creator:loadskin', loadCurrentClothes)
    RegisterNetEvent('jrs_character_creator:loadskinjrs', loadCurrentClothes)

    RegisterNetEvent('jrs_clothing:captureCurrent', function()
        CreateThread(function()
            Wait(750)
            local captured = CaptureCurrentJRSClothes and CaptureCurrentJRSClothes(PlayerPedId()) or {}
            if type(captured) == 'table' and next(captured) then
                TriggerServerEvent('jrs_clothes:updateclothes', captured, 0)
            end
        end)
    end)

end
