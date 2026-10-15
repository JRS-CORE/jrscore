-- callbacks (Core.Callback.*)
---@class ExtClientRPC @Callback class
---@field name string callback name
---@field _callback fun(any) | fun(cb: fun(data: any), ...) trigger or register
---@field uniqueId string callback unique id
ExtClientRPC = {}
ExtClientRPC.__index = ExtClientRPC
ExtClientRPC.__call = function()
    return "ExtClientRPC"
end

local TriggeredCalls = {}
local callBackId = 0

ExtClientRPC.Callback = {}

function ExtClientRPC:New(name, callback)
    local self = setmetatable({}, ExtClientRPC)
    self.name = name
    self._callback = callback
    self.uniqueId = ""
    return self
end

function ExtClientRPC:TriggerRpcAsync(...)
    if not self.name and type(self.name) ~= "string" then
        return error("Callback name must be a string!", 1)
    end

    callBackId = callBackId + 1
    if callBackId >= 65565 then
        callBackId = 0
        TriggeredCalls = {}
    end

    self.uniqueId = self.name .. tostring(callBackId)

    TriggerServerEvent("jrs:TriggerServerCallback", self.name, self.uniqueId, false, ...)

    TriggeredCalls[self.uniqueId] = self._callback
end

function ExtClientRPC:TriggerRpcAwait(...)
    if not self.name and type(self.name) ~= "string" then
        return error("Callback name must be a string!", 1)
    end

    callBackId = callBackId + 1
    if callBackId >= 65565 then
        callBackId = 0
        TriggeredCalls = {}
    end

    self.uniqueId = self.name .. tostring(callBackId)

    TriggerServerEvent("jrs:TriggerServerCallback", self.name, self.uniqueId, true, ...)

    local promise = promise.new()
    TriggeredCalls[self.uniqueId] = promise

    local result = Citizen.Await(promise)
    return result
end

function ExtClientRPC.ExecuteRpc(uniqueId, isSync, name, ...)
    if not TriggeredCalls[uniqueId] then
        return error("ERROR: No callback with this id found! callback name: " .. name, 1)
    end
    if not isSync then
        TriggeredCalls[uniqueId](...)
    else
        TriggeredCalls[uniqueId]:resolve(...)
    end

    TriggeredCalls[uniqueId] = nil
end

RegisterNetEvent('jrs:ServerCallback', ExtClientRPC.ExecuteRpc)


--- * Trigger a callback Asynchronously
---@param name string callback name
---@param callback fun(any) callback function
---@param ... any callback parameters tables strings numbers etc
function ExtClientRPC.Callback.TriggerAsync(name, callback, ...)
    local trigger = ExtClientRPC:New(name, callback)
    trigger:TriggerRpcAsync(...)
end

--- * Trigger a callback Synchronously
---@param name string callback name
---@param ... any callback parameters tables strings numbers etc
---@return any callback return
function ExtClientRPC.Callback.TriggerAwait(name, ...)
    local trigger = ExtClientRPC:New(name, nil)
    return trigger:TriggerRpcAwait(...)
end

AddEventHandler('jrs:ExecuteServerCallBack', ExtClientRPC.Callback.TriggerAsync)


--* REGISTER CLIENT CALLBACKS

local RegisteredCalls = {}

function ExtClientRPC:Trigger(uniqueId, isSync, ...)
    if not self._callback then
        return error("Callback " .. self.name .. " does not exist. Make sure it's registered in the server side.", 1)
    end

    self._callback(function(...)
        TriggerServerEvent("jrs:ServerCallback", uniqueId, isSync, self.name, ...)
    end, ...)
end

RegisterNetEvent("jrs:TriggerServerCallback", function(name, uniqueId, isSync, ...)
    if not RegisteredCalls[name] then
        return error("Callback " .. name .. " hasn't been registered.", 1)
    end

    RegisteredCalls[name]:Trigger(uniqueId, isSync, ...)
end)

--- * Register a callback
---@param name string callback name
---@param callback fun( func:fun(any),any) callback function
function ExtClientRPC.Callback.Register(name, callback)
    if not name and type(name) ~= "string" then
        return error("Callback name must be a string!", 1)
    end

    RegisteredCalls[name] = ExtClientRPC:New(name, callback)
end

-- Export
exports("ClientRpcCall", function()
    return ExtClientRPC
end)
