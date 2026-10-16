-- jrs_attached_objects | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_attached_objects | client helpers

-- streams a model in (by name) before it is used
function LoadModel(name)
    local hash = joaat(name)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
end

-- removes an entity whatever kind it is, and lets go of its model
function RemoveEntityProperly(entity, modelHash)
    DeleteEntity(entity)
    DeletePed(entity)
    DeleteObject(entity)
    SetEntityAsNoLongerNeeded(entity)
    if modelHash then SetModelAsNoLongerNeeded(modelHash) end
end
