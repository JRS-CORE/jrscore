CreateThread(function()
    while true do
        local c = Config.NetworkGuard or {}
        if c.Enabled == true then
            TriggerServerEvent('jrs_core:networkGuard:heartbeat')
            Wait(math.max(1000, tonumber(c.HeartbeatIntervalMs) or 5000))
        else
            Wait(5000)
        end
    end
end)
