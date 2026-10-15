-- callbacks (Core.Callback.*)
---@class ExtServerRPC
---@field name string callback name
---@field _callback fun(source: number, cb: fun(data: any), ...) callback function
---@field uniqueId string callback unique id
ExtServerRPC = {}
ExtServerRPC.Callback = {}
ExtServerRPC.__index = ExtServerRPC
ExtServerRPC.__call = function()
    return 'ExtServerRPC'
end

function ExtServerRPC:New(name, callback)
    self = setmetatable({}, ExtServerRPC)
    self.name = name
    self._callback = callback
    self.uniqueId = ""
    return self
end

function ExtServerRPC:Trigger(_source, uniqueId, isSync, ...)
    if not self._callback then
        return error("Callback " .. self.name .. " does not exist. Make sure it's registered in the server side.", 1)
    end

    self._callback(_source, function(...)
        TriggerClientEvent("jrs:ServerCallback", _source, uniqueId, isSync, self.name, ...)
    end, ...)
end

local RegisteredCalls = {}

RegisterNetEvent("jrs:TriggerServerCallback", function(name, uniqueId, isSync, ...)
    local _source = source

    if not RegisteredCalls[name] then
        return error("Callback " .. name .. " hasn't been registered.", 1)
    end

    RegisteredCalls[name]:Trigger(_source, uniqueId, isSync, ...)
end)

--- Register a new Rpc callback
---@param name string callback name
---@param callback fun(source: number, cb: fun(...), ...) callback function
function ExtServerRPC.Callback.Register(name, callback)
    if name == nil or type(name) ~= "string" then
        return error("Parameter \"name\" must be a string!", 1)
    end
    RegisteredCalls[name] = ExtServerRPC:New(name, callback)
end

--- * Trigger a callback Asynchronously
---@param source number player source
---@param name string callback name
---@param callback fun(...) callback function
---@param ... any callback parameters tables strings numbers etc
function ExtServerRPC.Callback.TriggerAsync(name, source, callback, ...)
    local trigger = ExtServerRPC:New(name, callback)
    trigger:TriggerRpcAsync(source, ...)
end

--- * Trigger a callback Synchronously
---@param source number player source
---@param name string callback name
---@param ... any callback parameters tables strings numbers etc
---@return any callback return
function ExtServerRPC.Callback.TriggerAwait(name, source, ...)
    local trigger = ExtServerRPC:New(name, nil)
    return trigger:TriggerRpcAwait(source, ...)
end

-- * TRIGGER CLIENT CALLBACKS HANDLER
local callBackId = 0
local TriggeredCalls = {}

function ExtServerRPC:TriggerRpcAsync(source, ...)
    if not self.name and type(self.name) ~= "string" then
        return error("Callback name must be a string!", 1)
    end

    if not source and type(source) ~= "number" then
        return error("Callback source must exist and be a number!", 1)
    end

    callBackId = callBackId + 1
    if callBackId >= 65565 then
        callBackId = 0
        TriggeredCalls = {}
    end

    self.uniqueId = self.name .. tostring(callBackId)

    TriggerClientEvent("jrs:TriggerServerCallback", source, self.name, self.uniqueId, false, ...)

    TriggeredCalls[self.uniqueId] = self._callback
end

function ExtServerRPC:TriggerRpcAwait(source, ...)
    if not self.name and type(self.name) ~= "string" then
        return error("Callback name must be a string!", 1)
    end
    callBackId = callBackId + 1
    if callBackId >= 65565 then
        callBackId = 0
        TriggeredCalls = {}
    end

    self.uniqueId = self.name .. tostring(callBackId)
    TriggerClientEvent("jrs:TriggerServerCallback", source, self.name, self.uniqueId, true, ...)

    local promise = promise.new()
    TriggeredCalls[self.uniqueId] = promise

    local result = Citizen.Await(promise)
    return result
end

function ExtServerRPC.ExecuteRpc(uniqueId, isSync, name, ...)
    local _source = source
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

RegisterNetEvent('jrs:ServerCallback', ExtServerRPC.ExecuteRpc)


-- Export
exports("ServerRpcCall", function()
    return ExtServerRPC
end)

-- (jrs:addNewCallBack belongs to jrs_core itself)
