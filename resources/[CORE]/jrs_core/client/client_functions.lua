local Functions = {}

-----------------------------------------------------------
--[[ Base Events  ]]--
-----------------------------------------------------------

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    Functions = nil

end)

-------------------------------------------------------------
--[[ Functions  ]]--
-----------------------------------------------------------

function GetFunctions()
    return Functions
end




Functions.GetPlayerData = function()

    local wait = true
    local data_result

    TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:getPlayerData", function(cb)
        data_result = cb
        wait = false
    end)

    while wait do
        Wait(25)
    end

    return data_result

end




Functions.GetTableLength = function(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end