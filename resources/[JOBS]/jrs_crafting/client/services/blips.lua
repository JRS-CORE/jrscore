Blips = {}

local function hashOf(v) return type(v) == 'string' and joaat(v) or v end

Blips.addBlipForCoords = function(_, blipname, bliphash, x, y, z, color)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, x, y, z) -- BlipAddForCoords
    SetBlipSprite(blip, hashOf(bliphash), true)
    SetBlipScale(blip, 0.2)
    if color then Citizen.InvokeNative(0x662D364ABF16DE2F, blip, hashOf(color)) end -- BlipAddModifier
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, blipname)                        -- SetBlipName
    return blip
end

-- a work table / campfire / anvil at every station (client-side, not networked)
local props = {}
CreateThread(function()
    for i, loc in ipairs(Config.Locations) do
        if loc.prop and loc.prop.model then
            local model = joaat(loc.prop.model)
            RequestModel(model)
            local t = GetGameTimer() + 5000
            while not HasModelLoaded(model) and GetGameTimer() < t do Wait(50) end
            if HasModelLoaded(model) then
                local obj = CreateObject(model, loc.x, loc.y, loc.z, false, false, false, false, false)
                SetEntityHeading(obj, loc.prop.heading or 0.0)
                PlaceObjectOnGroundProperly(obj, false)
                FreezeEntityPosition(obj, true)
                SetModelAsNoLongerNeeded(model)
                props[i] = obj
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, obj in pairs(props) do if DoesEntityExist(obj) then DeleteObject(obj) end end
end)
