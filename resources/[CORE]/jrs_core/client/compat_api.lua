-- Extended Core API (GetCore) for the extra scripts (client).
-- Notifications are shown with jrs_core so every script looks like JRS.

local function jrs(name, ...)
    local args = { ... }
    local ok = pcall(function() exports.jrs_core[name](exports.jrs_core, table.unpack(args)) end)
    return ok
end

local N = {}
N.NotifyTip = function(text, duration) jrs('NotifyTip', tostring(text), tonumber(duration) or 3000) end
N.NotifyRightTip = function(text, duration) jrs('NotifyRightTip', tostring(text), tonumber(duration) or 3000) end
N.NotifyObjective = function(text, duration) jrs('NotifyObjective', tostring(text), tonumber(duration) or 3000) end
N.NotifyLeft = function(title, subtitle, dict, icon, duration, color)
    jrs('NotifyLeft', tostring(title), tostring(subtitle), tostring(dict), tostring(icon), tonumber(duration) or 3000, tostring(color or "COLOR_WHITE"))
end
N.NotifyTop = function(text, location, duration) jrs('NotifyTop', tostring(text), tostring(location), tonumber(duration) or 3000) end
N.NotifySimpleTop = function(text, subtitle, duration) jrs('NotifySimpleTop', tostring(text), tostring(subtitle), tonumber(duration) or 3000) end
N.NotifyAdvanced = function(text, dict, icon, color, duration, quality, showquality)
    jrs('NotifyAdvanced', tostring(text), tostring(dict), tostring(icon), tostring(color), tonumber(duration) or 3000, quality, showquality)
end
N.NotifyAvanced = N.NotifyAdvanced
N.NotifyBasicTop = function(text, duration) jrs('NotifyBasicTop', tostring(text), tonumber(duration) or 3000) end
N.NotifyCenter = function(text, duration, color) jrs('NotifyCenter', tostring(text), tonumber(duration) or 3000, color) end
N.NotifyBottomRight = function(text, duration) jrs('NotifyBottomRight', tostring(text), tonumber(duration) or 3000) end
N.NotifyFail = function(text, subtitle, duration) jrs('NotifyFail', tostring(text), tostring(subtitle), tonumber(duration) or 3000) end
N.NotifyDead = function(title, audioRef, audioName, duration) jrs('NotifyDead', tostring(title), audioRef, audioName, tonumber(duration) or 3000) end
N.NotifyUpdate = function(title, subtitle, duration) jrs('NotifyUpdate', tostring(title), tostring(subtitle), tonumber(duration) or 3000) end
N.NotifyWarning = function(title, msg, audioRef, audioName, duration) jrs('NotifyWarning', tostring(title), tostring(msg), audioRef, audioName, tonumber(duration) or 3000) end
N.NotifyLeftRank = function(title, subtitle, dict, icon, duration, color) jrs('NotifyLeftRank', tostring(title), tostring(subtitle), tostring(dict), tostring(icon), tonumber(duration) or 3000, color) end
N.NotifyThreeSimpleTop = function(title, subtitle, sub2, duration) N.NotifySimpleTop(title, tostring(subtitle) .. "  " .. tostring(sub2 or ""), duration) end
N.NotifyOneSimpleTop = function(title, duration) N.NotifyBasicTop(title, duration) end
N.NotifyLeftInteractive = function(title, description, _, dict, texture, _, _, duration, color) N.NotifyLeft(title, description, dict, texture, duration, color) end

local ExtCoreFunctions = {}
for k, v in pairs(N) do ExtCoreFunctions[k] = v end

ExtCoreFunctions.RpcCall = function(name, callback, ...) ExtClientRPC.Callback.TriggerAsync(name, callback, ...) end
ExtCoreFunctions.instancePlayers = function(set) TriggerServerEvent("jrs_core:instanceplayers", set) end
ExtCoreFunctions.AddWebhook = function() end
ExtCoreFunctions.Graphics = {
    ScreenResolution = function()
        local width, height = GetCurrentScreenResolution()
        return { width = width, height = height }
    end,
}
ExtCoreFunctions.Callback = {
    Register = function(name, callback) ExtClientRPC.Callback.Register(name, callback) end,
    TriggerAsync = function(name, callback, ...) ExtClientRPC.Callback.TriggerAsync(name, callback, ...) end,
    TriggerAwait = function(name, ...) return ExtClientRPC.Callback.TriggerAwait(name, ...) end,
}

exports('GetCore', function() return ExtCoreFunctions end)
exports('jrsAPI', function() return ExtCoreFunctions end)

-- Legacy notification exports
exports('DisplayTip', function(text, duration) N.NotifyTip(text, duration) end)
exports('DisplayTipRight', function(text, duration) N.NotifyRightTip(text, duration) end)
exports('DisplayObjective', function(text, duration) N.NotifyObjective(text, duration) end)
exports('DisplayTopCenterNotification', function(text, location, duration) N.NotifyTop(text, location, duration) end)
exports('ShowTopNotification', function(text, subtitle, duration) N.NotifySimpleTop(text, subtitle, duration) end)
exports('ShowSimpleCenterText', function(text, duration) N.NotifyCenter(text, duration) end)
exports('showBottomRight', function(text, duration) N.NotifyBottomRight(text, duration) end)
exports('failmissioNotifY', function(...) N.NotifyFail(...) end)
exports('deadplayerNotifY', function(...) N.NotifyDead(...) end)
exports('updatemissioNotify', function(...) N.NotifyUpdate(...) end)
exports('updateMission', function(...) N.NotifyUpdate(...) end)
exports('warningNotify', function(...) N.NotifyWarning(...) end)
exports('LeftRank', function(...) N.NotifyLeftRank(...) end)
exports('ThreeSimpleTop', function(...) N.NotifyThreeSimpleTop(...) end)
exports('OneSimpleTop', function(...) N.NotifyOneSimpleTop(...) end)
exports('LeftInteractive', function(...) N.NotifyLeftInteractive(...) end)

-- Legacy notification events (server -> client and client -> client)
RegisterNetEvent('jrs:Tip', N.NotifyTip)
RegisterNetEvent('jrs:TipRight', N.NotifyRightTip)
RegisterNetEvent('jrs:TipBottom', N.NotifyObjective)
RegisterNetEvent('jrs:NotifyLeft', N.NotifyLeft)
RegisterNetEvent('jrs:NotifyTop', N.NotifyTop)
RegisterNetEvent('jrs:ShowTopNotification', N.NotifySimpleTop)
RegisterNetEvent('jrs:ShowAdvancedRightNotification', N.NotifyAdvanced)
RegisterNetEvent('jrs:ShowSimpleCenterText', N.NotifyCenter)
RegisterNetEvent('jrs:ShowBottomRight', N.NotifyBottomRight)
RegisterNetEvent('jrs:failmissioNotifY', N.NotifyFail)
RegisterNetEvent('jrs:deadplayerNotifY', N.NotifyDead)
RegisterNetEvent('jrs:updatemissioNotify', N.NotifyUpdate)
RegisterNetEvent('jrs:warningNotify', N.NotifyWarning)
RegisterNetEvent('jrs:LeftRank', N.NotifyLeftRank)
RegisterNetEvent('jrs:ThreeSimpleTop', N.NotifyThreeSimpleTop)
RegisterNetEvent('jrs:OneSimpleTop', N.NotifyOneSimpleTop)
RegisterNetEvent('jrs:LeftInteractive', N.NotifyLeftInteractive)

RegisterNetEvent('jrs:teleportWayPoint', function()
    pcall(function() exports.jrs_core:getCoreApi().TeleportToWaypoint() end)
end)

-- Old money-HUD events with these; JRS owns the HUD.
RegisterNetEvent('jrs:showUi', function() end)
RegisterNetEvent('jrs:updateUi', function() end)

-- Admin helpers: delete own mount / nearby wagons.
local function takeControl(entity)
    local tries = 0
    if not NetworkHasControlOfEntity(entity) then
        NetworkRequestControlOfEntity(entity)
        repeat Wait(100); tries = tries + 1 until NetworkHasControlOfEntity(entity) or tries > 100 or not DoesEntityExist(entity)
    end
end

RegisterNetEvent('jrs:delHorse', function()
    local ped = PlayerPedId()
    if not IsPedOnMount(ped) then return end
    local mount = GetMount(ped)
    takeControl(mount)
    DeleteEntity(mount)
end)

RegisterNetEvent('jrs:deleteVehicle', function(radius)
    radius = tonumber(radius) or 5.0
    local coords = GetEntityCoords(PlayerPedId())
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        takeControl(veh); DeleteEntity(veh)
        return
    end
    local itemset = CreateItemset(true)
    local size = Citizen.InvokeNative(0x59B57C4B06531E1E, coords, radius, itemset, 2, Citizen.ResultAsInteger())
    for i = 0, (size or 0) - 1 do
        local entity = GetIndexedItemInItemset(i, itemset)
        if DoesEntityExist(entity) then takeControl(entity); DeleteEntity(entity) end
    end
    if IsItemsetValid(itemset) then DestroyItemset(itemset) end
end)
