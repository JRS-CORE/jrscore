local responseCallbacks = {}
local registeredCallbacks = {}

local isServer = IsDuplicityVersion()
local callbackNamespace = GetCurrentResourceName()
local triggerEventName = callbackNamespace .. ':callback:trigger'
local responseEventName = callbackNamespace .. ':callback:response'
local clearEventName = callbackNamespace .. ':callback:clear'
local NO_RESPONSE_ID = -1
local MAX_REQUEST_ID = 2147483000
local RESPONSE_TTL_MS = 30000

-- Starting from a non-zero, session-specific id prevents delayed responses from
-- a previous resource start from colliding with the first callback after restart.
local currentRequestId = ((GetGameTimer and GetGameTimer() or 0) % 1000000) + 1000

Callback = Callback or {}

local function printconsole(...)
  if IsDuplicityVersion() then
    return print(('^1%s:^7'):format(GetCurrentResourceName()), ...)
  end
  return print(('^1%s:^7'):format(GetCurrentResourceName()), ...)
end

local function nextRequestId()
  local startId = currentRequestId
  repeat
    currentRequestId = currentRequestId >= MAX_REQUEST_ID and 1000 or (currentRequestId + 1)
    if not responseCallbacks[currentRequestId] then
      return currentRequestId
    end
  until currentRequestId == startId
  return nil
end

local function executeCallback(name, ...)
  local entry = registeredCallbacks[name]
  if not entry or type(entry.cb) ~= 'function' then
    printconsole(('No callback registered for: %s'):format(tostring(name)))
    return nil
  end

  local packed = table.pack(pcall(entry.cb, ...))
  if not packed[1] then
    printconsole(('Callback failed [%s]: %s'):format(tostring(name), tostring(packed[2])))
    return nil
  end
  return table.unpack(packed, 2, packed.n)
end

local function executeResponse(requestId, fromResource, ...)
  requestId = tonumber(requestId)
  if not requestId or requestId == NO_RESPONSE_ID then
    return
  end

  local entry = responseCallbacks[requestId]
  if not entry then
    -- A delayed response can arrive after a resource restart/cleanup.  It is
    -- stale and must be ignored rather than producing the old
    -- "No callback response for: 0" spam.
    return
  end

  responseCallbacks[requestId] = nil
  local ok, err = pcall(entry.cb, ...)
  if not ok then
    printconsole(('Response callback failed [%s] from %s: %s'):format(
      tostring(entry.name or requestId), tostring(fromResource or 'unknown'), tostring(err)))
  end
end

local function storeResponse(name, cb)
  if type(cb) ~= 'function' then
    return NO_RESPONSE_ID
  end

  local requestId = nextRequestId()
  if not requestId then
    printconsole('Callback request id pool exhausted.')
    return NO_RESPONSE_ID
  end

  responseCallbacks[requestId] = {
    cb = cb,
    name = name,
    createdAt = GetGameTimer and GetGameTimer() or 0,
  }
  return requestId
end

function Callback.register(name, cb)
  if type(name) ~= 'string' or name == '' or type(cb) ~= 'function' then
    return false
  end

  registeredCallbacks[name] = {
    cb = cb,
    resource = GetInvokingResource() or GetCurrentResourceName()
  }
  return true
end

function Callback.clearPending()
  responseCallbacks = {}
end

if isServer then
  function Callback.triggerClient(name, source, cb, ...)
    if not source or not GetPlayerIdentifier(source) then
      printconsole('Callback Module: player is not connected - source: ' .. tostring(source))
      return false
    end

    local requestId = storeResponse(name, cb)
    TriggerClientEvent(triggerEventName, source, name, requestId, GetInvokingResource() or callbackNamespace, ...)
    return requestId ~= NO_RESPONSE_ID
  end

  function Callback.triggerServer(name, cb, ...)
    if not registeredCallbacks[name] then
      printconsole('No server callback for: ' .. tostring(name))
      return nil
    end

    if type(cb) == 'function' then
      cb(executeCallback(name, ...))
      return true
    end
    return executeCallback(name, ...)
  end

  RegisterNetEvent(responseEventName, function(requestId, fromResource, ...)
    executeResponse(requestId, fromResource, ...)
  end)

  RegisterNetEvent(triggerEventName, function(name, requestId, fromResource, ...)
    local src = source
    if tonumber(requestId) == NO_RESPONSE_ID then
      executeCallback(name, src, ...)
      return
    end
    TriggerClientEvent(responseEventName, src, requestId, fromResource or callbackNamespace,
      executeCallback(name, src, ...))
  end)
else
  RegisterNetEvent(clearEventName, Callback.clearPending)

  function Callback.triggerServer(name, cb, ...)
    local requestId = storeResponse(name, cb)
    TriggerServerEvent(triggerEventName, name, requestId, GetInvokingResource() or callbackNamespace, ...)
    return requestId ~= NO_RESPONSE_ID
  end

  function Callback.triggerClient(name, cb, ...)
    if not registeredCallbacks[name] then
      printconsole('No client callback for: ' .. tostring(name))
      return nil
    end

    if type(cb) == 'function' then
      cb(executeCallback(name, ...))
      return true
    end
    return executeCallback(name, ...)
  end

  RegisterNetEvent(responseEventName, function(requestId, fromResource, ...)
    executeResponse(requestId, fromResource, ...)
  end)

  RegisterNetEvent(triggerEventName, function(name, requestId, fromResource, ...)
    if tonumber(requestId) == NO_RESPONSE_ID then
      executeCallback(name, ...)
      return
    end
    TriggerServerEvent(responseEventName, requestId, fromResource or callbackNamespace,
      executeCallback(name, ...))
  end)
end

-- Remove callbacks that never received a response so a broken remote callback
-- cannot leak memory forever.  This runs on both sides and is intentionally low
-- frequency.
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(15000)
    local now = GetGameTimer and GetGameTimer() or 0
    for requestId, entry in pairs(responseCallbacks) do
      if entry.createdAt and now - entry.createdAt > RESPONSE_TTL_MS then
        responseCallbacks[requestId] = nil
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    Callback.clearPending()
  end

  for name, callback in pairs(registeredCallbacks) do
    if callback.resource == resource then
      registeredCallbacks[name] = nil
    end
  end
end)
