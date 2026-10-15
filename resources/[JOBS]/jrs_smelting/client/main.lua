local peds, blips = {}, {}
local busy = false

local function smelt(index)
    if busy then return JRS.Notify(L('busy')) end
    local recipes = JRS.Await('jrs_smelting:recipes') or {}
    local elements = {}
    for _, r in ipairs(recipes) do
        elements[#elements + 1] = { label = r.label, value = r.index, desc = L('needs', r.needs) }
    end

    JRS.OpenMenu('jrs_smelting', L('title'), L('subtitle'), elements, function(el, menu)
        menu.close()
        local amount = JRS.Input(L('title'), L('how_many', Config.MaxBatch), true)
        if not amount then return end
        amount = math.floor(amount)
        if amount < 1 or amount > Config.MaxBatch then return JRS.Notify(L('bad_amount')) end

        local res = JRS.Await('jrs_smelting:start', index, el.value, amount)
        if not res or not res.ok then return JRS.Notify(res and res.msg or L('bad_amount')) end

        busy = true
        local ped = PlayerPedId()
        TaskStartScenarioInPlace(ped, `WORLD_HUMAN_CROUCH_INSPECT`, -1, true, false, false, false)
        JRS.Progress(L('smelting', amount, res.label), res.duration)
        ClearPedTasks(ped)
        busy = false
        TriggerServerEvent('jrs_smelting:server:finish', true)
    end)
end

CreateThread(function()
    for _, s in ipairs(Config.Smelters) do
        if s.blip then blips[#blips + 1] = JRS.Blip(s.coords, Config.BlipSprite, s.label, 0.2) end
    end

    local prompts = JRS.Prompts()
    local usePrompt = prompts:add(0x760A9C6F, LE('prompt'))

    while true do
        local wait = 1000
        local pos = GetEntityCoords(PlayerPedId())
        for i, s in ipairs(Config.Smelters) do
            local dist = #(pos - s.coords.xyz)
            if dist < Config.SpawnDistance then
                if not peds[i] and JRS.LoadModel(s.model) then
                    local ped = CreatePed(joaat(s.model), s.coords.x, s.coords.y, s.coords.z - 1.0, s.coords.w, false, false, false, false)
                    SetModelAsNoLongerNeeded(joaat(s.model))
                    SetRandomOutfitVariation(ped, true)
                    SetEntityInvincible(ped, true)
                    SetEntityCanBeDamaged(ped, false)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    if s.scenario then TaskStartScenarioInPlace(ped, joaat(s.scenario), -1, true, false, false, false) end
                    peds[i] = ped
                end
                if dist < Config.UseDistance and not busy then
                    wait = 0
                    prompts:show(s.label)
                    if prompts:done(usePrompt) then smelt(i) end
                end
            elseif peds[i] then
                DeletePed(peds[i])
                peds[i] = nil
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(peds) do if DoesEntityExist(ped) then DeletePed(ped) end end
    for _, b in ipairs(blips) do RemoveBlip(b) end
end)
