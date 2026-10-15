-- ====================================================================
-- JRS SECURITY: Client NUI DevTools Listener
-- ====================================================================

RegisterNUICallback('jrs_devtools_detected', function(data, cb)
    -- Disabled sending server event to avoid false positive kicks
    if cb then cb({ ok = true }) end
end)

-- Intercept cheat trap commands only
local trapCommands = {
    'nightfall', 'dopamine', 'redengine', 'eulen', 'cageservice'
}
for _, cmd in ipairs(trapCommands) do
    RegisterCommand(cmd, function()
        TriggerServerEvent('jrs_security:devtoolsOpened', { method = 'console_trap_' .. cmd })
    end, false)
end
