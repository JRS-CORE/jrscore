-- ============================================================================
-- jrs_core / server/permissions.lua
-- Admin-group / per-command permission checks.
--
-- Moved out of config/config.lua (2026-09-18 config cleanup) so that file
-- stays values-only for buyers. The data these functions read
-- (Config.AdminGroups, Config.CommandPermissions) still lives in
-- config/config.lua; only the logic lives here. Exported by server/api.lua as
-- 'CanUseCommand' / 'IsAdmin' for other resources - do not rename these
-- Config.* function names without also updating server/api.lua,
-- server/commands.lua, server/hud_export.lua and server/performance.lua.
-- ============================================================================

function Config.IsAdminGroup(group)
    if group == nil then return false end
    return Config.AdminGroups[string.lower(tostring(group))] == true
end

function Config.CanUseCommand(group, commandKey)
    if group == nil then return false end
    local allowedGroups = Config.CommandPermissions[commandKey]
    if allowedGroups == nil then return Config.IsAdminGroup(group) end

    local normalizedGroup = string.lower(tostring(group))
    for _, allowedGroup in ipairs(allowedGroups) do
        if normalizedGroup == string.lower(tostring(allowedGroup)) then
            return true
        end
    end
    return false
end
