-- jrs_walkanim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_walkanim | server
-- Stores the chosen walk style on the character row and hands it back after character selection.

local Core = exports.jrs_core:GetCore()

local NONE = 'noanim'
local allowed = { [NONE] = true }
for _, style in ipairs(Config.Styles) do allowed[style.name] = true end

local function characterId(src)
    local user = Core.getUser(src)
    local character = user and user.getUsedCharacter
    return character and character.charIdentifier
end

AddEventHandler('jrs:SelectedCharacter', function(src, character)
    local id = character and character.charIdentifier
    if not id then return end
    exports.oxmysql:execute('SELECT walk FROM jrs_characters WHERE charidentifier = ?', { id }, function(rows)
        local style = rows and rows[1] and rows[1].walk
        if style then
            TriggerClientEvent('jrs_walkanim:Server:setwalk', src, style)
        end
    end)
end)

RegisterNetEvent('jrs_walkanim:setwalk', function(style)
    local src = source
    if type(style) ~= 'string' or not allowed[style] then return end   -- only styles from the config
    local id = characterId(src)
    if not id then return end
    exports.oxmysql:execute('UPDATE jrs_characters SET walk = ? WHERE charidentifier = ?', { style, id })
end)
