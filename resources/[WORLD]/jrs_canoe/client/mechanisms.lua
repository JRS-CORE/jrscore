-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | client: carrying a canoe

CreateThread(function()
    RegisterCanoeDropActionPrompt()
    if Config.UseInteractPrompt then JRS.AddModelTarget(Config.Models, Config.ModelsTargetOptions) end
end)

-- controls that make no sense with a canoe on the shoulder
local BLOCKED <const> = {
    0xD9D0E1C0, 0x8FFC75D6, 0xD23C3EBE, 0xCEFD9220,                    -- jump, sprint, crouch, mount
    0x07CE1E61, 0xF84FA74F, 0x1F80208B, 0xE30CD707,                    -- attack, aim, melee, reload
    0xB2F377E8, 0x4CC0E2FE, 0xC1989F95, 0xCB2E7FA2,                    -- weapon wheel, inventory, enter vehicle
}

AddEventHandler('jrs_canoe:client:tasks', function()
    local _, canoe = IsCarryingCanoe()

    CreateThread(function()
        while IsEntityAttached(canoe) do
            Wait(0)
            local ped = PlayerPedId()
            Citizen.InvokeNative(0x433083750C5E064A, ped, Config.SetPedMaxMoveBlendRatio)
            for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end

            local tiring = Config.RemoveStaminaWhileCarrying
            if tiring.Enabled then
                Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, -tiring.RemoveValue)
                if Citizen.InvokeNative(0x22F2A386D43048A9, ped) == false then
                    DropCarriedCanoe()
                    ShowNotification(Locales['CANNOT_CARRY_NOT_ENOUGH_STAMINA'], { r = 255, g = 0, b = 0, a = 255 })
                end
            end

            local group, prompt = GetCanoeActionPromptData()
            PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', LocalesEN['DROP_CANOE_ACTION']))
            if Citizen.InvokeNative(0xC92AC953F0A982AE, prompt) or IsEntityDead(ped) or IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then
                DropCarriedCanoe()
            end
        end
    end)
end)
