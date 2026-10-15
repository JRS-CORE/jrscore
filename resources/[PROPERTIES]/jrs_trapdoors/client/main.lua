local ANIM_DICT = 'mech_cover@env@doors@unlocked@generic@base@push_return@bow@left@no_lean'

-- runtime state per door id: { entity, open, progress, animToken, animating, owner }
local doors = {}
local modelToIds = {}

for id, cfg in pairs(Config.Trapdoors) do
    local open = GlobalState['trapdoor:' .. id] == true
    doors[id] = {
        entity = 0, open = open, progress = open and 1.0 or 0.0, animToken = 0, animating = false,
        owner = GlobalState['trapdoorCode:' .. id] or false, -- owner citizenid when a passcode is set
    }
    local hash = joaat(cfg.model)
    modelToIds[hash] = modelToIds[hash] or {}
    modelToIds[hash][#modelToIds[hash] + 1] = id
end

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------
local function lerp(a, b, t) return a + (b - a) * t end

local function lerpAngle(a, b, t)
    local delta = (b - a + 180.0) % 360.0 - 180.0
    return a + delta * t
end

local function findEntity(cfg)
    local p = cfg.closedPosition
    local ent = GetClosestObjectOfType(p.x, p.y, p.z, 3.0, joaat(cfg.model), false, false, false)
    return DoesEntityExist(ent) and ent or 0
end

-- pose is always derived from config + progress (0 = closed, 1 = open).
-- Never read rotation back from the entity: at -90 pitch GetEntityRotation
-- returns gimbal-locked angles, which made the door twist when closing.
local function applyPose(ent, cfg, p)
    local a, b = cfg.closedPosition, cfg.openPosition
    local ra, rb = cfg.closedRotation, cfg.openRotation
    SetEntityCoordsNoOffset(ent, lerp(a.x, b.x, p), lerp(a.y, b.y, p), lerp(a.z, b.z, p), false, false, false)
    SetEntityRotation(ent, lerpAngle(ra.x, rb.x, p), lerpAngle(ra.y, rb.y, p), lerpAngle(ra.z, rb.z, p), 2, true)
end

local function placeInstant(id)
    local d = doors[id]
    d.progress = d.open and 1.0 or 0.0
    if d.entity ~= 0 then applyPose(d.entity, Config.Trapdoors[id], d.progress) end
end

local function animate(id)
    local d, cfg = doors[id], Config.Trapdoors[id]
    local ent = d.entity
    if ent == 0 or not DoesEntityExist(ent) then return end

    d.animToken = d.animToken + 1
    local token = d.animToken
    d.animating = true

    local from = d.progress
    local to = d.open and 1.0 or 0.0
    local duration = math.max(Config.MoveDuration * math.abs(to - from), 1)
    local startTime = GetGameTimer()

    CreateThread(function()
        while true do
            if d.animToken ~= token or not DoesEntityExist(ent) then return end
            local t = math.min((GetGameTimer() - startTime) / duration, 1.0)
            local e = t * t * (3.0 - 2.0 * t) -- smoothstep
            d.progress = lerp(from, to, e)
            applyPose(ent, cfg, d.progress)
            if t >= 1.0 then break end
            Wait(0)
        end
        d.animating = false
    end)
end

-- resolve which configured door a targeted entity belongs to
local function idFromEntity(entity)
    local ids = modelToIds[GetEntityModel(entity)]
    if not ids then return end
    for i = 1, #ids do
        if doors[ids[i]].entity == entity then return ids[i] end
    end
    -- entity not cached yet (just streamed in) - match by proximity
    local coords = GetEntityCoords(entity)
    for i = 1, #ids do
        if #(coords - Config.Trapdoors[ids[i]].closedPosition) < 3.0 then return ids[i] end
    end
end

---------------------------------------------------------------------
-- state sync (server -> clients via GlobalState)
---------------------------------------------------------------------
for id in pairs(Config.Trapdoors) do
    AddStateBagChangeHandler('trapdoor:' .. id, 'global', function(_, _, value)
        local d = doors[id]
        d.open = value == true
        if d.entity ~= 0 then animate(id) end
    end)
    AddStateBagChangeHandler('trapdoorCode:' .. id, 'global', function(_, _, value)
        doors[id].owner = value or false
    end)
end

-- keep entity handles fresh as props stream in/out and snap them to the synced state
CreateThread(function()
    while true do
        local pCoords = GetEntityCoords(PlayerPedId())
        for id, cfg in pairs(Config.Trapdoors) do
            local d = doors[id]
            if #(pCoords - cfg.closedPosition) <= Config.StreamDistance then
                local ent = findEntity(cfg)
                if ent ~= d.entity then
                    d.entity = ent
                    if ent ~= 0 then placeInstant(id) end
                end
            elseif d.entity ~= 0 then
                d.entity = 0
            end
        end
        Wait(1000)
    end
end)

---------------------------------------------------------------------
-- interaction: prompt -> JRS menu -> JRS inputs (no the JRS interaction prompt, no NUI)
---------------------------------------------------------------------
local myId = nil

local function playPushAnim()
    if JRS.LoadDict(ANIM_DICT) then
        TaskPlayAnim(PlayerPedId(), ANIM_DICT, 'open', 8.0, -8.0, -1, 0, 0, false, false, false)
        RemoveAnimDict(ANIM_DICT)
    end
end

local function askCode(title)
    local code = JRS.Input(title, '0000', false)
    return code and code:gsub('%s', '') or nil
end

local function result(res)
    if res and res.msg then JRS.Notify(res.msg) end
    return res and res.ok
end

local function openDoor(id)
    local code = nil
    if doors[id].owner then
        code = askCode(L('enter_code'))
        if not code then return end
    end
    if result(JRS.Await('jrs_trapdoors:open', id, code)) then playPushAnim() end
end

local function openMenu(id)
    local d = doors[id]
    myId = myId or JRS.Await('jrs_trapdoors:myId')
    local elements = {}
    if d.open then
        elements[#elements + 1] = { label = L('close'), value = 'close', desc = '' }
    else
        elements[#elements + 1] = { label = L('open'), value = 'open', desc = '' }
    end
    if not d.owner then
        elements[#elements + 1] = { label = L('set_code'), value = 'set', desc = '' }
    elseif myId and d.owner == myId then
        elements[#elements + 1] = { label = L('change_code'), value = 'change', desc = '' }
    end

    JRS.OpenMenu('jrs_trapdoors', L(Config.Trapdoors[id].label or id), L('menu_sub'), elements, function(el, menu)
        menu.close()
        if doors[id].animating then return JRS.Notify(L('busy')) end
        if el.value == 'open' then
            openDoor(id)
        elseif el.value == 'close' then
            playPushAnim()
            TriggerServerEvent('jrs_trapdoors:server:close', id)
        elseif el.value == 'set' then
            local code = askCode(L('new_code'))
            if code then result(JRS.Await('jrs_trapdoors:setCode', id, code)) end
        elseif el.value == 'change' then
            local current = askCode(L('current_code'))
            if not current then return end
            local new = askCode(L('new_code'))
            if new then result(JRS.Await('jrs_trapdoors:changeCode', id, current, new)) end
        end
    end)
end

CreateThread(function()
    local prompts = JRS.Prompts()
    local usePrompt = prompts:add(0x760A9C6F, LE('menu_sub'))
    while true do
        local wait = 750
        local pos = GetEntityCoords(PlayerPedId())
        for id, cfg in pairs(Config.Trapdoors) do
            local d = doors[id]
            if d.entity ~= 0 and not d.animating and #(pos - cfg.closedPosition) <= (cfg.interactDistance or 2.0) then
                wait = 0
                prompts:show(LE(cfg.label or id))
                if prompts:done(usePrompt) then openMenu(id) end
                break
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id, d in pairs(doors) do
        d.animToken = d.animToken + 1
        d.open = false
        placeInstant(id)
    end
end)
