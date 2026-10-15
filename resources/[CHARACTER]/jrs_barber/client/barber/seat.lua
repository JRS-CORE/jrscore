-- JRS barber chair: the player sits in the shop's barber chair (Rockstar
-- PROP_PLAYER_BARBER_SEAT scenario). Used when the barber opens, and by the
-- standalone "Sit" prompt next to every chair.
local SEAT = `PROP_PLAYER_BARBER_SEAT`
local CHAIR_MODELS = { `p_barberchair01x`, `p_barberchair02x`, `p_barberchair03x` }

local seat = { active = false, ped = nil, scenario = nil, coords = nil, created = nil, lastRetask = 0 }
local spawnedChairs = {}

function BarberIsSeatActive()
    local ped = PlayerPedId()
    return seat.active and seat.ped == ped and DoesEntityExist(ped) and not IsEntityDead(ped)
end

local function usingScenario(ped)
    local ok, r = pcall(function() return Citizen.InvokeNative(0x57AB4A3080F85143, ped, Citizen.ResultAsInteger()) end) -- IS_PED_USING_ANY_SCENARIO
    if ok then return tonumber(r) == 1 end
    return nil
end

-- an authored barber seat point near coords (MLO shops already have one)
local function findSeatPoint(coords, radius)
    local best, bestCoords, bestDist
    pcall(function()
        local buf = DataView.ArrayBuffer(256 * 4)
        local found = tonumber(Citizen.InvokeNative(0x345EC3B7EBDE1CB5, coords, radius, buf:Buffer(), 32)) or 0 -- GET_SCENARIO_POINTS_IN_AREA
        for i = 1, found do
            local point = buf:GetInt32(8 * i)
            if point and point ~= 0 and GetScenarioPointType(point) == SEAT then
                local p = GetScenarioPointCoords(point, true)
                local d = p and #(coords - p)
                if d and (not bestDist or d < bestDist) then best, bestCoords, bestDist = point, p, d end
            end
        end
    end)
    return best, bestCoords
end

local function findChair(coords, radius)
    local best, bestDist
    for _, model in ipairs(CHAIR_MODELS) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, model, false, false, false)
        if obj and obj ~= 0 and DoesEntityExist(obj) then
            local d = #(coords - GetEntityCoords(obj))
            if not bestDist or d < bestDist then best, bestDist = obj, d end
        end
    end
    return best
end

-- attach the barber seat scenario to a chair prop that has none
local function seatOnChair(chair)
    if not chair then return nil end
    local ok, point = pcall(function()
        return Citizen.InvokeNative(0x794AB1379A74064D, chair, SEAT, 0.0, 0.12, 0.75423, 180.0, 1, 1, true) -- CREATE_SCENARIO_POINT_HASH_ATTACHED_TO_ENTITY
    end)
    if not ok or not point or point == 0 then return nil end
    return point, GetScenarioPointCoords(point, true)
end

local function resolveSeat(coords)
    local point, pCoords = findSeatPoint(coords, 7.5)
    if point then return point, pCoords, false end
    point, pCoords = seatOnChair(findChair(coords, 7.5))
    return point, pCoords, point ~= nil
end

-- Sit in the chair nearest to `coords`. Blocks until seated (or timeout).
function BarberSit(coords)
    if BarberConfig.ChairAnimation == false then return false end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) then return false end
    coords = coords or GetEntityCoords(ped)

    local point, pCoords, created = resolveSeat(coords)
    if not point then return false end

    ClearPedTasks(ped)
    Wait(50)
    TaskUseScenarioPoint(ped, point, 0, -1, true)
    seat.ped, seat.scenario, seat.coords, seat.created, seat.lastRetask = ped, point, pCoords, created and point or nil, GetGameTimer()

    local started = GetGameTimer()
    local deadline = started + (tonumber(BarberConfig.ChairTimeout) or 8000)
    local stableSince
    while GetGameTimer() < deadline do
        if IsEntityDead(ped) then break end
        local now = GetGameTimer()
        local seated = usingScenario(ped) == true
            or ((now - started) > 700 and #(GetEntityCoords(ped) - pCoords) <= 1.15 and GetEntitySpeed(ped) <= 0.2)
        if seated then
            stableSince = stableSince or now
            if now - stableSince >= 350 then
                Wait(tonumber(BarberConfig.ChairSettleDelay) or 700)
                seat.active = true
                return true
            end
        else
            stableSince = nil
        end
        Wait(50)
    end
    BarberStandUp(true)
    return false
end

function BarberStandUp(immediate)
    local ped = seat.ped or PlayerPedId()
    local created = seat.created
    seat.active, seat.ped, seat.scenario, seat.coords, seat.created = false, nil, nil, nil, nil
    if DoesEntityExist(ped) and not IsEntityDead(ped) then
        if immediate then ClearPedTasksImmediately(ped) else ClearPedTasks(ped) end
        -- the stand-up exit can hang on some MLO chairs: snap out after a while
        CreateThread(function()
            Wait(3500)
            if not seat.active and DoesEntityExist(ped) and usingScenario(ped) == true and not BarberSessionIsBusy() then
                ClearPedTasksImmediately(ped)
            end
        end)
    end
    if created then pcall(function() Citizen.InvokeNative(0x81948DFE4F5A0283, created) end) end -- DELETE_SCENARIO_POINT
end

-- keep the scenario while seated (another resource may clear the ped tasks)
CreateThread(function()
    while true do
        if seat.active then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or (seat.coords and #(GetEntityCoords(ped) - seat.coords) > 3.0) then
                seat.active = false
            elseif usingScenario(ped) == false and GetGameTimer() - seat.lastRetask > 1500 then
                seat.lastRetask = GetGameTimer()
                TaskUseScenarioPoint(ped, seat.scenario, 0, -1, true)
            end
            Wait(250)
        else
            Wait(1000)
        end
    end
end)

-- chairs for shops that have no barber chair in the map (Rhodes, Annesburg)
CreateThread(function()
    for name, shop in pairs(BarberConfig.Shops or {}) do
        local p = shop.chair
        if p and p.model then
            local model = joaat(p.model)
            RequestModel(model)
            local t = GetGameTimer() + 5000
            while not HasModelLoaded(model) and GetGameTimer() < t do Wait(50) end
            if HasModelLoaded(model) then
                local c = p.coords or shop.coords
                local obj = CreateObject(model, c.x, c.y, c.z, false, false, false, false, false)
                SetEntityHeading(obj, p.heading or 0.0)
                PlaceObjectOnGroundProperly(obj, false)
                FreezeEntityPosition(obj, true)
                SetModelAsNoLongerNeeded(model)
                spawnedChairs[name] = obj
            end
        end
    end
end)

-- standalone: sit in any barber chair without opening the barber
CreateThread(function()
    if BarberConfig.SitPrompt == false then return end
    local group = GetRandomIntInRange(0, 0xffffff)
    local function make(key, text)
        local p = UiPromptRegisterBegin()
        UiPromptSetControlAction(p, key)
        UiPromptSetText(p, VarString(10, 'LITERAL_STRING', text))
        UiPromptSetEnabled(p, true)
        UiPromptSetVisible(p, true)
        UiPromptSetStandardMode(p, true)
        UiPromptSetGroup(p, group, 0)
        UiPromptRegisterEnd(p)
        return p
    end
    local sitKey = BarberConfig.SitKey or 0xCEFD9220 -- E
    local pSit = make(sitKey, BarberConfig.SitText or 'Sit')
    local pStand = make(sitKey, BarberConfig.StandText or 'Stand up')
    local pBarber = make(BarberConfig.PromptKey or 0x760A9C6F, 'Barber')

    AddEventHandler('onResourceStop', function(res)
        if res ~= GetCurrentResourceName() then return end
        UiPromptDelete(pSit) UiPromptDelete(pStand) UiPromptDelete(pBarber)
        for _, obj in pairs(spawnedChairs) do if DoesEntityExist(obj) then DeleteObject(obj) end end
        if seat.active then BarberStandUp(true) end
    end)

    while true do
        local wait = 750
        if not BarberSessionIsBusy() then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            if seat.active then
                wait = 0
                UiPromptSetVisible(pSit, false) UiPromptSetVisible(pStand, true) UiPromptSetVisible(pBarber, true)
                UiPromptSetActiveGroupThisFrame(group, VarString(10, 'LITERAL_STRING', 'Barber Chair'), 0, 0, 0, 0)
                if UiPromptHasStandardModeCompleted(pStand) then BarberStandUp(false) Wait(500)
                elseif UiPromptHasStandardModeCompleted(pBarber) then
                    CreateThread(function() OpenBarberShop(seat.coords) end)
                    Wait(800)
                end
            else
                for _, shop in pairs(BarberConfig.Shops or {}) do
                    local d = #(pos - shop.coords)
                    if d < 15.0 then wait = math.min(wait, 250) end
                    if d < (BarberConfig.SitDistance or 4.0) and findChair(pos, 1.6) then
                        wait = 0
                        UiPromptSetVisible(pSit, true) UiPromptSetVisible(pStand, false) UiPromptSetVisible(pBarber, false)
                        UiPromptSetActiveGroupThisFrame(group, VarString(10, 'LITERAL_STRING', 'Barber Chair'), 0, 0, 0, 0)
                        if UiPromptHasStandardModeCompleted(pSit) then
                            CreateThread(function() BarberSit(pos) end)
                            Wait(800)
                        end
                        break
                    end
                end
            end
        end
        Wait(wait)
    end
end)
