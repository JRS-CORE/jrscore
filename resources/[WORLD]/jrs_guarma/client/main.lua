local sailing = false

-- world state for Guarma (minimap, water, horizon) or the mainland
local function setGuarmaWorld(on)
    if on then
        Citizen.InvokeNative(0xA657EC9DBC6CC900, 1935063277)   -- minimap: Guarma
        Citizen.InvokeNative(0xE8770EE02AEE45C2, 1)            -- Guarma water
        Citizen.InvokeNative(0x74E2261D2A66849A, true)         -- Guarma horizon
    else
        Citizen.InvokeNative(0x74E2261D2A66849A, false)
        Citizen.InvokeNative(0xA657EC9DBC6CC900, -1868977180)  -- minimap: world
        Citizen.InvokeNative(0xE8770EE02AEE45C2, 0)
    end
end

-- after a relog / respawn the world flags are reset by the game: put them back
-- to match where the player actually stands (Guarma lies far south, y < -5000)
local onGuarma = false
CreateThread(function()
    while true do
        Wait(3000)
        if not sailing then
            local here = GetEntityCoords(PlayerPedId()).y < -5000.0
            if here ~= onGuarma then
                onGuarma = here
                setGuarmaWorld(here)
            end
        end
    end
end)

local function sail(portId)
    local port = Config.Ports[portId]
    local arrive = Config.Arrive[port.to]
    sailing = true
    local ped = PlayerPedId()
    DoScreenFadeOut(1500)
    Wait(1500)
    Citizen.InvokeNative(0x1E5B70E53DB661E5, 0, 0, 0, port.loading[1], port.loading[2], port.loading[3]) -- loading screen text
    setGuarmaWorld(not port.guarma)
    onGuarma = not port.guarma
    Wait(2000)
    SetEntityCoords(ped, arrive.x, arrive.y, arrive.z, false, false, false, false)
    SetEntityHeading(ped, arrive.w)
    Wait(12000)
    ShutdownLoadingScreen()
    DoScreenFadeIn(3000)
    sailing = false
end

local function openMenu(portId)
    local port = Config.Ports[portId]
    local elements = {}
    for i, p in ipairs(port.payments) do elements[i] = { label = p.label, value = i, desc = '' } end
    JRS.OpenMenu('jrs_guarma', L('title'), port.label, elements, function(el, menu)
        menu.close()
        local ok, msg = JRS.Await('jrs_guarma:pay', portId, el.value)
        if ok then sail(portId) elseif msg then JRS.Notify(msg) end
    end)
end

CreateThread(function()
    local blips = {}
    for _, port in pairs(Config.Ports) do
        blips[#blips + 1] = JRS.Blip(port.port, Config.BlipSprite, port.label, 0.2)
    end
    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() then for _, b in ipairs(blips) do RemoveBlip(b) end end
    end)

    local prompts = JRS.Prompts()
    local travel = prompts:add(Config.Key, LE('prompt'), 1000)
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        if not sailing and not IsEntityDead(ped) then
            local pos = GetEntityCoords(ped)
            for id, port in pairs(Config.Ports) do
                local d = #(pos - port.port.xyz)
                if d < 2.0 then
                    wait = 0
                    prompts:show(port.label)
                    if prompts:done(travel) then openMenu(id) Wait(1000) end
                elseif d < 30.0 then
                    wait = math.min(wait, 250)
                end
            end
        end
        Wait(wait)
    end
end)
