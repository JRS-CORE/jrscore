local function allowed(jobs)
    if not jobs or #jobs == 0 then return true end
    local me = JRS.Me()
    if not me then return false end
    for _, job in ipairs(jobs) do
        if job == me.job then return true end
    end
    return false
end

local function teleport(to)
    local ped = PlayerPedId()
    DoScreenFadeOut(800)
    while not IsScreenFadedOut() do Wait(50) end
    SetEntityCoords(ped, to.x, to.y, to.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, to.w)
    Wait(1500)
    DoScreenFadeIn(800)
end

CreateThread(function()
    local prompts = JRS.Prompts()
    local enter = prompts:add(Config.PromptKey, LE('enter'), 1000)
    local leave = prompts:add(Config.PromptKey, LE('leave'), 1000)

    while true do
        local wait = 1000
        local ped = PlayerPedId()
        if not IsEntityDead(ped) then
            local pos = GetEntityCoords(ped)
            for _, loc in ipairs(Config.Locations) do
                local atEnter = #(pos - loc.enter.xyz) <= loc.distance
                local atExit = #(pos - loc.exit.xyz) <= loc.distance
                if atEnter or atExit then
                    wait = 0
                    prompts:visible(enter, atEnter)
                    prompts:visible(leave, atExit)
                    prompts:show(loc.label)
                    if atEnter and prompts:done(enter) then
                        if allowed(loc.jobs) then teleport(loc.exit) else JRS.Notify(L('no_access')) end
                        Wait(1500)
                    elseif atExit and prompts:done(leave) then
                        teleport(loc.enter)
                        Wait(1500)
                    end
                    break
                elseif #(pos - loc.enter.xyz) < 30.0 then
                    wait = math.min(wait, 250)
                end
            end
        end
        Wait(wait)
    end
end)
