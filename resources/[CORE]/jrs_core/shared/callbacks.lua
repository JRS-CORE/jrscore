local callbackHandlers = {}
local callbackResolutions = {}
local callbackTicketSequence = 0
local callbackResources = {}

function addCallbackHandler(callbackName, fn)
	callbackHandlers[callbackName] = fn
end

function getCallbackHandler(callbackName)
	return callbackHandlers[callbackName]
end

function setCallbackResource(callbackName, resourceName)
	callbackResources[callbackName] = resourceName
end

function getCallbackResource(callbackName)
	return callbackResources[callbackName]
end

local function getKey(callbackName, ticket)
	return ("%s:%s"):format(callbackName, ticket)
end

function addCallbackResolution(callbackName, ticket, fn)
	callbackResolutions[getKey(callbackName, ticket)] = fn
end

function removeCallbackResolution(callbackName, ticket)
	callbackResolutions[getKey(callbackName, ticket)] = nil
end

function getCallbackResolution(callbackName, ticket)
	return callbackResolutions[getKey(callbackName, ticket)]
end

function generateTicket()
	callbackTicketSequence = callbackTicketSequence + 1
	if callbackTicketSequence > 2147483646 then
		callbackTicketSequence = 1
	end
	return ("%s:%s"):format(GetGameTimer(), callbackTicketSequence)
end
