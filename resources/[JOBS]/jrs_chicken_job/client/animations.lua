JRSChickenAnim = JRSChickenAnim or {}

local A = JRSChickenAnim
A.carrying = nil
A.carryKind = nil
A.suspendCarryAnim = false
A.nativeCarry = false
A.slaughterKnife = nil

local function cfg()
    return Config.Animations or {}
end

local function requestAnimDict(dict, timeoutMs)
    if not dict or dict == '' then return false end
    if DoesAnimDictExist and not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local expires = GetGameTimer() + (timeoutMs or 5000)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < expires do
        Wait(0)
    end
    return HasAnimDictLoaded(dict)
end

local function requestModel(model, timeoutMs)
    if not model or model == '' then return false, nil end
    local modelHash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelValid(modelHash) then return false, modelHash end
    RequestModel(modelHash)
    local expires = GetGameTimer() + (timeoutMs or 5000)
    while not HasModelLoaded(modelHash) and GetGameTimer() < expires do
        Wait(0)
    end
    return HasModelLoaded(modelHash), modelHash
end

function A.ClearSlaughterKnife()
    local knife = A.slaughterKnife
    A.slaughterKnife = nil
    if knife and knife ~= 0 and DoesEntityExist(knife) then
        DetachEntity(knife, true, true)
        SetEntityAsMissionEntity(knife, true, true)
        DeleteObject(knife)
        if DoesEntityExist(knife) then DeleteEntity(knife) end
    end
end

local function createSlaughterKnife(ped, data)
    A.ClearSlaughterKnife()
    local loaded, modelHash = requestModel(data.knifeModel or 'w_melee_knife06', data.loadTimeoutMs or 5000)
    if not loaded then return nil end

    local pos = GetEntityCoords(ped)
    local knife = CreateObject(modelHash, pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    if not knife or knife == 0 or not DoesEntityExist(knife) then return nil end

    SetEntityAsMissionEntity(knife, true, true)
    SetEntityCollision(knife, false, false)
    local bone = GetEntityBoneIndexByName(ped, data.knifeBone or 'SKEL_R_Finger13')
    if bone == -1 then bone = GetPedBoneIndex(ped, 7966) end
    local o = data.knifeOffset or {}
    AttachEntityToEntity(
        knife, ped, bone,
        o.x or -0.01, o.y or -0.02, o.z or 0.02,
        o.rx or 190.0, o.ry or 0.0, o.rz or 0.0,
        false, false, false, false, 2, true, false, false
    )
    A.slaughterKnife = knife
    return knife
end

local function playAnim(ped, data, durationOverride)
    if not data or not data.dict or not data.clip then return false end
    if not requestAnimDict(data.dict, data.loadTimeoutMs or 5000) then return false end
    local duration = durationOverride or data.duration or -1
    TaskPlayAnim(
        ped,
        data.dict,
        data.clip,
        data.blendIn or 1.0,
        data.blendOut or 1.0,
        duration,
        data.flag or 0,
        data.playbackRate or 1.0,
        false, false, false,
        '', false
    )
    return true
end

local function faceEntity(ped, ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    TaskTurnPedToFaceEntity(ped, ent, 650)
    Wait(450)
end

local function faceCoord(ped, coords)
    if not coords then return end
    TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 650)
    Wait(450)
end

local function getOffset(kind)
    local offsets = (Config.CarryOffsets or {})
    return offsets[kind] or offsets.liveChicken or {
        bone = 'skel_r_hand', x = 0.0, y = 0.30, z = -0.30,
        rx = 0.0, ry = 0.0, rz = -90.0
    }
end

function A.PlayAction(name, targetEntity, targetCoords)
    if not (cfg().enabled ~= false) then return true end
    local data = cfg()[name]
    if not data then return false end

    local ped = PlayerPedId()
    if targetEntity and DoesEntityExist(targetEntity) then
        faceEntity(ped, targetEntity)
    elseif targetCoords then
        faceCoord(ped, targetCoords)
    end

    ClearPedTasks(ped)
    local ok = playAnim(ped, data)
    if not ok then return false end
    Wait(data.waitMs or data.duration or 800)
    return true
end

function A.PlayScenario(name, coords)
    local data = cfg()[name]
    if not data or not data.scenario then return false end
    local ped = PlayerPedId()
    if coords then faceCoord(ped, coords) end

    A.suspendCarryAnim = true
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, data.freeze ~= false)

    local scenario = data.scenario
    if data.maleScenario or data.femaleScenario then
        local male = true
        if IsPedMale then male = IsPedMale(ped) end
        scenario = male and (data.maleScenario or data.scenario) or (data.femaleScenario or data.scenario)
    end

    TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1, true, false, false, false)
    Wait(data.duration or 3500)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    A.suspendCarryAnim = false
    if A.carrying and DoesEntityExist(A.carrying) then A.EnsureCarryLoop() end
    return true
end

-- Play the real handheld-chicken drop and release it at the exact point where
-- the player's hands reach the ground. Mission code supplies the final ground
-- coordinates so the entity never disappears or snaps away during the action.
function A.PlaceChickenForSlaughter(entity, coords, heading)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not coords then return false end
    local ped = PlayerPedId()
    local data = cfg().killPlace or cfg().putDown

    faceCoord(ped, coords)
    A.suspendCarryAnim = true
    ClearPedTasks(ped)

    local played = data and playAnim(ped, data)
    if played and data.entityClip then
        -- This dictionary includes a matching chicken track. Playing both
        -- sides keeps the bird moving with the player's hands during release.
        playAnim(entity, {
            dict = data.dict,
            clip = data.entityClip,
            duration = data.duration,
            flag = data.entityFlag or 0,
            blendIn = data.blendIn,
            blendOut = data.blendOut,
        })
    end
    local detachAt = played and (data.detachAtMs or 850) or 250
    Wait(detachAt)

    A.ReleaseCarry(entity, true)
    ClearPedTasksImmediately(entity)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, false)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
    if heading then SetEntityHeading(entity, heading) end
    pcall(function() PlaceEntityOnGroundProperly(entity) end)
    FreezeEntityPosition(entity, true)

    if played then
        local remainder = (data.duration or 1900) - detachAt
        if remainder > 0 then Wait(remainder) end
    end

    ClearPedTasks(ped)
    A.suspendCarryAnim = false
    return true
end

-- Draw a visible knife and perform RDR2's grounded knife strike. onStrike is
-- called at the contact frame so the chicken dies during the motion, not before
-- or after it. The butcher-rabbit scenario remains a safe animation fallback.
function A.PlayKnifeSlaughter(targetEntity, coords, onStrike)
    if not targetEntity or targetEntity == 0 or not DoesEntityExist(targetEntity) then return false end
    local data = cfg().kill or {}
    local ped = PlayerPedId()
    local struck = false
    local function strike()
        if struck then return end
        struck = true
        if onStrike then onStrike() end
    end

    faceEntity(ped, targetEntity)
    A.suspendCarryAnim = true
    ClearPedTasksImmediately(ped)
    createSlaughterKnife(ped, data)

    -- v3.4.0: RDR2 chicken field-dress sequence (enter -> success -> exit).
    -- Each clip is started, confirmed, and followed until it ends (phase),
    -- so no fixed durations are guessed. The ped is frozen only once the
    -- first clip is running (freezing first can stop the task starting).
    local played = false
    local isMale = true
    if IsPedMale then isMale = IsPedMale(ped) end
    local seqDict = isMale and data.maleDict or (data.femaleDict or data.maleDict)
    if seqDict and data.clips and requestAnimDict(seqDict, 5000) then
        for i, clip in ipairs(data.clips) do
            local last = (i == #data.clips)
            TaskPlayAnim(ped, seqDict, clip, data.blendIn or 4.0, data.blendOut or -4.0, -1,
                last and 0 or 2, 0.0, false, false, false, '', false)
            local started = false
            local startBy = GetGameTimer() + 700
            while GetGameTimer() < startBy do
                if IsEntityPlayingAnim(ped, seqDict, clip, 3) then started = true break end
                Wait(0)
            end
            if not started then
                if Config.Debug then print(('[jrs_chicken_job] kill clip did not start: %s/%s'):format(seqDict, clip)) end
                if i == 1 then break end
            else
                played = true
                if i == 1 and data.freeze ~= false then FreezeEntityPosition(ped, true) end
                local isStrike = (clip == data.strikeClip)
                local endBy = GetGameTimer() + (data.clipTimeoutMs or 4000)
                while GetGameTimer() < endBy do
                    local okT, phase = pcall(GetEntityAnimCurrentTime, ped, seqDict, clip)
                    phase = okT and phase or 0.0
                    if isStrike and phase >= (data.strikePhase or 0.3) then strike() end
                    if phase >= 0.97 or not IsEntityPlayingAnim(ped, seqDict, clip, 3) then break end
                    Wait(0)
                end
                if isStrike then strike() end
            end
        end
        RemoveAnimDict(seqDict)
    end

    FreezeEntityPosition(ped, data.freeze ~= false)
    if played then
        -- field-dress sequence finished above
    elseif playAnim(ped, data) then
        played = true
        local duration = data.duration or 3000
        local strikeAt = math.max(0, math.min(data.strikeAtMs or 1350, duration))
        Wait(strikeAt)
        strike()
        local remainder = duration - strikeAt
        if remainder > 0 then Wait(remainder) end
    else
        -- Fallback 1: Ground work/hammer anim with knife
        local fb = {
            dict = 'amb_work@world_human_hammer@ground@male_a@idle_a',
            clip = 'idle_a',
            blendIn = 2.0, blendOut = 2.0, flag = 1,
        }
        if playAnim(ped, fb) then
            Wait(1500)
            strike()
            Wait(1500)
            played = true
        else
            -- Fallback 2: Crouch inspect scenario
            TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'), -1, true, false, false, false)
            Wait(1500)
            strike()
            Wait(1500)
            played = true
        end
    end

    strike()
    A.ClearSlaughterKnife()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    pcall(function() PlaceEntityOnGroundProperly(ped) end)
    A.suspendCarryAnim = false
    return played
end

-- Play the butcher chop at the table with a knife in the right hand.
-- v3.2.1: each candidate is checked with IsEntityPlayingAnim. Before, a dict
-- that loaded but never started counted as "played", so the fallbacks never
-- ran and the player stood frozen. The loop is re-applied if something
-- cancels it, and the clip plays upper-body only (flag 17) so the legs keep
-- standing instead of the low-camp-table lunge.
local function startAnimChecked(ped, anim, flag)
    if not requestAnimDict(anim.dict, 5000) then return false end
    TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, -2.0, -1, flag, 0.0, false, false, false, '', false)
    local untilTime = GetGameTimer() + 700
    while GetGameTimer() < untilTime do
        if IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then return true end
        Wait(0)
    end
    return IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3)
end

-- v3.3.0: visible cutting of the bird on the table. The dead chicken jolts on
-- every knife chop, then turns into a plucked carcass, then into halves and
-- drumsticks. All props are tracked in A.cutProps and removed at the end or
-- when the mission is cleaned up mid-cut.
A.cutProps = {}

function A.ClearCutProps()
    for _, obj in ipairs(A.cutProps) do
        if obj and obj ~= 0 and DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteObject(obj)
            if DoesEntityExist(obj) then DeleteEntity(obj) end
        end
    end
    A.cutProps = {}
end

local function tableLocalToWorld(base, heading, lx, ly, lz)
    local h = math.rad(heading or 0.0)
    local rx, ry = math.cos(h), math.sin(h)     -- right vector
    local fx, fy = -math.sin(h), math.cos(h)    -- forward vector
    return vector3(base.x + rx * (lx or 0.0) + fx * (ly or 0.0),
                   base.y + ry * (lx or 0.0) + fy * (ly or 0.0),
                   base.z + (lz or 0.0))
end

local function spawnCutProp(model, pos, heading)
    local loaded, modelHash = requestModel(model, 3000)
    if not loaded then return nil end
    local obj = CreateObject(modelHash, pos.x, pos.y, pos.z, true, true, false)
    SetModelAsNoLongerNeeded(modelHash)
    if not obj or obj == 0 or not DoesEntityExist(obj) then return nil end
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCollision(obj, false, false)
    SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    A.cutProps[#A.cutProps + 1] = obj
    return obj
end

local function hideTableChicken(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    NetworkRequestControlOfEntity(ent)
    SetEntityVisible(ent, false)
end

-- Builds the per-cut visual state; step(progress) is called every tick.
local function newCutVisual(data, chickenEnt, heading)
    local vis = data.visual or {}
    if vis.enabled == false then return nil end
    if not chickenEnt or chickenEnt == 0 or not DoesEntityExist(chickenEnt) then return nil end

    local base = GetEntityCoords(chickenEnt)
    heading = heading or GetEntityHeading(chickenEnt)
    local propBase = vector3(base.x, base.y, base.z + (vis.propZOffset or -0.08))
    local state = { stage = 'whole', current = chickenEnt, currentPos = base, liftedUntil = 0 }
    local chopEvery = vis.chopEveryMs or 750
    local nextChop = GetGameTimer() + (vis.firstChopMs or 450)

    local function setCurrent(ent, pos)
        state.current, state.currentPos = ent, pos
    end

    function state.step(progress)
        local now = GetGameTimer()

        if state.stage == 'whole' and progress >= (vis.pluckedAt or 0.45) then
            local plucked = vis.plucked or { model = 'p_chicken01x' }
            local obj = spawnCutProp(plucked.model, propBase, heading + (plucked.headingOffset or 0.0))
            if obj then
                hideTableChicken(chickenEnt)
                setCurrent(obj, propBase)
            end
            state.stage = 'plucked'
        elseif state.stage == 'plucked' and progress >= (vis.piecesAt or 0.80) then
            local spawned = false
            for _, p in ipairs(vis.pieces or {}) do
                local pos = tableLocalToWorld(propBase, heading, p.x, p.y, p.z)
                if spawnCutProp(p.model, pos, heading + (p.headingOffset or 0.0)) then spawned = true end
            end
            if spawned then
                if state.current ~= chickenEnt and DoesEntityExist(state.current) then
                    SetEntityVisible(state.current, false)
                end
                hideTableChicken(chickenEnt)
                setCurrent(nil, nil)
            end
            state.stage = 'pieces'
        end

        -- Knife contact: a small jolt of whatever is on the board.
        local ent = state.current
        if ent and DoesEntityExist(ent) then
            if now >= nextChop then
                nextChop = now + chopEvery
                local p = state.currentPos
                SetEntityCoordsNoOffset(ent, p.x, p.y, p.z + (vis.joltHeight or 0.018), false, false, false)
                state.liftedUntil = now + 90
            elseif state.liftedUntil > 0 and now >= state.liftedUntil then
                state.liftedUntil = 0
                local p = state.currentPos
                SetEntityCoordsNoOffset(ent, p.x, p.y, p.z, false, false, false)
            end
        end
    end

    return state
end

function A.PlayTableCut(tableCoords, durationOverride, chickenEnt, chickenHeading)
    local ped = PlayerPedId()
    local data = cfg().tableCut or {}
    local isMale = true
    if IsPedMale then isMale = IsPedMale(ped) end

    local primaryDict = isMale and (data.maleDict or 'amb_camp@prop_camp_butcher@working@rabbit@male_a@rabbit_chop@base')
        or (data.femaleDict or 'amb_camp@prop_camp_butcher@working@rabbit@female_a@rabbit_chop@base')
    local flag = data.flag or 17

    local candidates = {}
    if data.useRdo ~= false and data.rdoDict and data.rdoClip then
        candidates[#candidates + 1] = { dict = data.rdoDict, clip = data.rdoClip, flag = data.rdoFlag or 1 }
    end
    candidates[#candidates + 1] = { dict = primaryDict, clip = data.clip or 'base' }
    candidates[#candidates + 1] = { dict = isMale and 'amb_camp@prop_camp_butcher@working@deer@male_a@meat_chop@base'
            or 'amb_camp@prop_camp_butcher@working@deer@female_a@meat_chop@base', clip = 'base' }
    candidates[#candidates + 1] = { dict = 'amb_work@world_human_clean_table@male_b@base', clip = 'base' }

    A.suspendCarryAnim = true
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    Wait(0)

    if tableCoords then
        local pedCoords = GetEntityCoords(ped)
        SetEntityHeading(ped, GetHeadingFromVector_2d(tableCoords.x - pedCoords.x, tableCoords.y - pedCoords.y))
    end

    createSlaughterKnife(ped, data)

    local active = nil
    for _, anim in ipairs(candidates) do
        anim.flag = anim.flag or flag
        if startAnimChecked(ped, anim, anim.flag) then
            active = anim
            break
        end
        if Config.Debug then print(('[jrs_chicken_job] table cut anim did not start: %s/%s'):format(anim.dict, anim.clip)) end
    end
    if not active then
        TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'), -1, true, false, false, false)
    end

    -- Freeze only after the task is running; freezing first can stop it starting.
    FreezeEntityPosition(ped, true)

    local totalDuration = durationOverride or data.duration or 7000
    local startedAt = GetGameTimer()
    local endsAt = startedAt + totalDuration
    local visual = newCutVisual(data, chickenEnt, chickenHeading)
    local nextAnimCheck = 0
    while GetGameTimer() < endsAt do
        local now = GetGameTimer()
        if now >= nextAnimCheck then
            nextAnimCheck = now + 250
            if active and not IsEntityPlayingAnim(ped, active.dict, active.clip, 3) then
                TaskPlayAnim(ped, active.dict, active.clip, 2.0, -2.0, -1, active.flag, 0.0, false, false, false, '', false)
            end
        end
        if visual then visual.step((now - startedAt) / totalDuration) end
        Wait(30)
    end

    A.ClearCutProps()
    A.ClearSlaughterKnife()
    if active then StopAnimTask(ped, active.dict, active.clip, 2.0) end
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    if active then RemoveAnimDict(active.dict) end
    A.suspendCarryAnim = false
    return active ~= nil
end

local function getPedCarriedEntity(ped)
    local ok, carried = pcall(function()
        return Citizen.InvokeNative(0xD806CD2A4F2C2996, ped, Citizen.ResultAsInteger())
    end)
    if ok then return carried or 0 end
    return 0
end

local function requestControl(entity, timeoutMs)
    NetworkRequestControlOfEntity(entity)
    local untilTime = GetGameTimer() + (timeoutMs or 900)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < untilTime do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
end

local function tryNativeCarry(entity, kind)
    local carryCfg = Config.CarrySystem or {}
    if carryCfg.native ~= true then return false end
    if kind ~= 'deadChicken' then return false end
    if carryCfg.nativeForDeadChicken == false then return false end

    local ped = PlayerPedId()
    requestControl(entity, 1000)
    FreezeEntityPosition(entity, false)
    SetEntityCollision(entity, true, true)

    -- Ask RDR2 which carry configuration best fits this exact entity/model.
    local optimal = 0
    pcall(function()
        optimal = Citizen.InvokeNative(0x34F008A7E48C496B, entity, 0, Citizen.ResultAsInteger()) or 0
    end)
    if not optimal or optimal == 0 then
        optimal = GetHashKey(carryCfg.fallbackCarryConfig or 'GENERIC_DEAD_CARRIABLE_SMALL_ANIMAL')
    end

    -- Register the entity as carriable, then let the game execute its native
    -- pickup task/IK. This is the same family of natives used by hunting-wagon
    -- scripts and RDR2's own small-animal carrying system.
    pcall(function()
        Citizen.InvokeNative(0xF0B4F759F35CC7F5,
            entity, optimal, ped,
            carryCfg.taskSlot or 0,
            carryCfg.taskFlags or 0)
    end)
    pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, entity, 21, true) end)

    ClearPedTasks(ped)
    local pickupTaskOk = pcall(function() TaskPickupCarriableEntity(ped, entity) end)
    if not pickupTaskOk then
        pcall(function() Citizen.InvokeNative(0x502EC17B1BED4BFA, ped, entity) end)
    end

    local expires = GetGameTimer() + (carryCfg.timeoutMs or 2600)
    while GetGameTimer() < expires do
        Wait(0)
        local carried = getPedCarriedEntity(ped)
        if carried == entity or IsEntityAttachedToEntity(entity, ped) then
            A.carrying = entity
            A.carryKind = kind
            A.nativeCarry = true
            return true
        end
    end

    -- Native pickup did not engage on this build/entity; clear the temporary
    -- task state and allow the old manual attachment fallback below.
    ClearPedTasks(ped)
    pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, entity, 21, false) end)
    return false
end

function A.AttachCarry(entity, kind)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ped = PlayerPedId()
    local o = getOffset(kind)
    local bone = o.boneIndex
    if bone == nil then
        bone = GetEntityBoneIndexByName(ped, o.bone or 'skel_r_hand')
        if bone == -1 then bone = GetPedBoneIndex(ped, 7966) end
    end

    -- The fourth attachment flag after collision must be true when the
    -- carried entity is a ped (live/dead chicken), otherwise RDR2 can apply
    -- incorrect ped rotation around the chosen attachment point.
    local entityIsPed = IsEntityAPed and IsEntityAPed(entity) or false

    requestControl(entity, 750)
    FreezeEntityPosition(entity, false)
    SetEntityCollision(entity, false, false)
    AttachEntityToEntity(
        entity, ped, bone,
        o.x or 0.0, o.y or 0.30, o.z or -0.30,
        o.rx or 0.0, o.ry or 0.0, o.rz or -90.0,
        false, false, true, entityIsPed, 2, true, false, false
    )

    A.carrying = entity
    A.carryKind = kind
    A.nativeCarry = false
    A.EnsureCarryLoop()
    return true
end

function A.PickupAndCarry(entity, kind)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ped = PlayerPedId()
    faceEntity(ped, entity)

    if tryNativeCarry(entity, kind) then
        return true
    end

    local carryCfg = Config.CarrySystem or {}
    if carryCfg.fallbackManualAttach == false then return false end

    A.suspendCarryAnim = true
    local isChicken = (kind == 'liveChicken' or kind == 'deadChicken' or kind == 'pluckedChicken')
    local pickup = (isChicken and cfg().chickenPickup) or cfg().pickup
    if pickup and playAnim(ped, pickup) then
        Wait(pickup.attachAtMs or 650)
    else
        Wait(250)
    end

    local ok = A.AttachCarry(entity, kind)
    if pickup then
        local remainder = (pickup.duration or 900) - (pickup.attachAtMs or 650)
        if remainder > 0 then Wait(remainder) end
    end
    A.suspendCarryAnim = false
    A.EnsureCarryLoop()
    return ok
end

function A.ReleaseCarry(entity, keepTasks)
    entity = entity or A.carrying
    local ped = PlayerPedId()
    local wasNative = A.nativeCarry and A.carrying == entity

    if wasNative then
        -- Clearing the task makes RDR2 release the native carriable; the entity
        -- is then detached explicitly so mission code can attach it to the cage
        -- or position it on the ground/table immediately afterwards.
        ClearPedTasksImmediately(ped)
        Wait(0)
        pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, entity, 21, false) end)
    end

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        requestControl(entity, 500)
        DetachEntity(entity, true, true)
        SetEntityCollision(entity, true, true)
        FreezeEntityPosition(entity, false)
    end
    if A.carrying == entity then
        A.carrying = nil
        A.carryKind = nil
        A.nativeCarry = false
    end
    if not keepTasks and not wasNative then ClearPedTasks(ped) end
end

function A.PutDown(entity, coords, heading)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ped = PlayerPedId()
    if coords then faceCoord(ped, coords) end

    if A.nativeCarry and A.carrying == entity and coords then
        -- Use the game's native place-carried-entity task so the hands release
        -- naturally instead of snapping the chicken out of the carry pose.
        local placed = pcall(function()
            TaskPlaceCarriedEntityAtCoord(ped, entity, coords.x, coords.y, coords.z, 1.0, 5)
        end)
        if not placed then
            pcall(function() Citizen.InvokeNative(0xC7F0B43DCDC57E3D, ped, entity, coords.x, coords.y, coords.z, 1.0, 5) end)
        end
        Wait(850)
        A.nativeCarry = false
        A.carrying = nil
        A.carryKind = nil
        pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, entity, 21, false) end)
        DetachEntity(entity, true, true)
        SetEntityCollision(entity, true, true)
        FreezeEntityPosition(entity, false)
    else
        local putDown = cfg().putDown
        ClearPedTasks(ped)
        if putDown and playAnim(ped, putDown) then
            Wait(putDown.detachAtMs or 500)
        end

        A.ReleaseCarry(entity, true)
        if putDown then
            local remainder = (putDown.duration or 900) - (putDown.detachAtMs or 500)
            if remainder > 0 then Wait(remainder) end
        end
    end

    if coords then
        SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
    end
    if heading then SetEntityHeading(entity, heading) end
    ClearPedTasks(ped)
    return true
end

function A.StowChicken(entity, wagon)
    if not entity or not DoesEntityExist(entity) then return false end
    local ped = PlayerPedId()
    if wagon and DoesEntityExist(wagon) then faceEntity(ped, wagon) end

    if A.nativeCarry and A.carrying == entity and wagon and DoesEntityExist(wagon) then
        -- Native hand release near the wagon. main.lua immediately attaches the
        -- same chicken into its configured cage slot afterwards.
        local target = GetOffsetFromEntityInWorldCoords(wagon, 0.0, -2.0, 0.25)
        local placed = pcall(function()
            TaskPlaceCarriedEntityAtCoord(ped, entity, target.x, target.y, target.z, 1.0, 5)
        end)
        if not placed then
            pcall(function() Citizen.InvokeNative(0xC7F0B43DCDC57E3D, ped, entity, target.x, target.y, target.z, 1.0, 5) end)
        end
        Wait(800)
        A.nativeCarry = false
        A.carrying = nil
        A.carryKind = nil
        pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, entity, 21, false) end)
        ClearPedTasks(ped)
        return true
    end

    local stow = cfg().chickenStow
    ClearPedTasks(ped)
    local played = stow and playAnim(ped, stow)
    if played then Wait(stow.detachAtMs or 800) else Wait(350) end
    A.ReleaseCarry(entity, true)
    if played then
        local remainder = (stow.duration or 1300) - (stow.detachAtMs or 800)
        if remainder > 0 then Wait(remainder) end
    end
    ClearPedTasks(ped)
    return true
end

function A.UnstowChicken(entity, wagon, kind)
    if not entity or not DoesEntityExist(entity) then return false end
    local ped = PlayerPedId()
    if wagon and DoesEntityExist(wagon) then faceEntity(ped, wagon) end

    -- Once the chicken is detached from the cage, use the same native pickup
    -- path as field catching so the hand/body pose stays consistent.
    return A.PickupAndCarry(entity, kind or 'liveChicken')
end

function A.EnsureCarryLoop()
    if not A.carrying or not DoesEntityExist(A.carrying) then return end
    if A.nativeCarry then return end -- native carriable task owns the full-body/hand pose

    local o = getOffset(A.carryKind)
    if o and o.playCarryAnim == false then return end

    -- Chickens use their own two-hand front carry pose. Other carriables (for
    -- example the basin) keep the generic carry animation.
    local isChicken = (A.carryKind == 'liveChicken' or A.carryKind == 'deadChicken')
    local carry = isChicken and (cfg().chickenCarry or cfg().carry) or cfg().carry
    if not carry then return end

    local ped = PlayerPedId()
    if not IsEntityPlayingAnim(ped, carry.dict, carry.clip, 3) then
        local ok = playAnim(ped, carry, -1)
        if (not ok) and isChicken then
            local fallback = cfg().carry
            if fallback then playAnim(ped, fallback, -1) end
        end
    end
end

CreateThread(function()
    while true do
        local waitMs = 500
        if A.carrying and DoesEntityExist(A.carrying) then
            waitMs = 0
            local ped = PlayerPedId()
            if not A.suspendCarryAnim then A.EnsureCarryLoop() end
            -- prevent combat/vehicle interactions from breaking the carried prop/entity
            DisableControlAction(0, 0x07CE1E61, true) -- attack
            DisableControlAction(0, 0xF84FA74F, true) -- melee attack alternate
            DisableControlAction(0, 0xCEFD9220, true) -- enter vehicle
            local lostCarry = false
            if A.nativeCarry then
                local carried = getPedCarriedEntity(ped)
                lostCarry = (carried ~= A.carrying and not IsEntityAttachedToEntity(A.carrying, ped))
            else
                lostCarry = not IsEntityAttachedToEntity(A.carrying, ped)
            end
            if IsPedDeadOrDying(ped, true) or (not A.suspendCarryAnim and lostCarry) then
                A.ReleaseCarry(A.carrying)
            end
        end
        Wait(waitMs)
    end
end)
