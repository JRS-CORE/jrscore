-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | client: showing a passport on screen

local function titleCase(text)
    return (text:lower():gsub('(%a)(%w*)', function(first, rest) return first:upper() .. rest end))
end

local function toggle(show)
    SetNuiFocus(false, false)
    if not show then GetPlayerData().HasNUIActive = false end
    SendNUIMessage({ type = 'enable', enable = show })
end

function CloseNUI() SendNUIMessage({ action = 'close' }) end

-- somebody close by showed their passport (or we did)
RegisterNetEvent('jrs_passports:client:onPassportItemUse', function(card)
    local state = GetPlayerData()
    if state.HasNUIActive then return end
    state.HasNUIActive = true

    local first, last = titleCase(card.firstname), titleCase(card.lastname)
    SendNUIMessage({
        action = 'updateInformation',
        info = {
            firstname = first, lastname = last, dob = card.dob,
            sex = Locales['SEX_' .. tostring(card.sex)],
            identity_id = card.identityId,
            avatar_url = card.avatar_url,
            expiration = Locales['PASSPORT_DISPLAY_EXPIRATION_TITLE']:format(card.expiration_date),
        },
        locales = {
            fullname = Locales['PASSPORT_DISPLAY_FULL_NAME_TITLE'],
            dob = Locales['PASSPORT_DISPLAY_DOB_TITLE'],
            sex = Locales['PASSPORT_DISPLAY_SEX_TITLE'],
            signature = Locales['PASSPORT_DISPLAY_SIGNATURE_TITLE'],
        },
    })

    toggle(true)
    Wait(1000 * Config.AutomaticallyClosePassportDelayDuration)
    CloseNUI()
end)

RegisterNUICallback('close', function() toggle(false) end)
