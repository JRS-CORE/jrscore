if BarberConfig.framework == 'jrs_core' then
    local characterAppearanceReady = false
    AddEventHandler('jrs_character:isPlayerReady', function()
        characterAppearanceReady = true
    end)

    local function waitForCharacterAppearanceReady(timeoutMs)
        if characterAppearanceReady then return true end
        local deadline = GetGameTimer() + (timeoutMs or 35000)
        while not characterAppearanceReady and GetGameTimer() < deadline do
            Wait(100)
        end
        return characterAppearanceReady
    end

    local function loadBarberOverlay()
        CreateThread(function()
            waitForCharacterAppearanceReady(35000)
            Wait(400)
            TriggerEvent('jrs_barber:loadbarberoverlay')
        end)
    end

    RegisterNetEvent('jrs:SelectedCharacter', function()
        characterAppearanceReady = false
        loadBarberOverlay()
    end)
    RegisterNetEvent('jrs_character:revive_player', loadBarberOverlay)
    RegisterNetEvent('jrs_character_creator:loadbarberoverlay', loadBarberOverlay)
    RegisterNetEvent('jrs_barber:reloadCurrentBarber', loadBarberOverlay)
    RegisterNetEvent('jrs_character:client:reloadCurrentCharacter', loadBarberOverlay)
    RegisterNetEvent('jrs_clothes:outfitchanged', function()
        Wait(500)
        TriggerEvent('jrs_barber:loadbarberoverlay')
    end)
end
