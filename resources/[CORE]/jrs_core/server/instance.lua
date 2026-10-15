Namedinstances = {}

RegisterServerEvent("jrs_core:instanceplayers")
AddEventHandler("jrs_core:instanceplayers", function(setRoom)
    local src = source
    local instanceSource = nil

    if setRoom == 0 then
        instanceSource = 0
        for k, v in pairs(Namedinstances) do
            for i = #v.people, 1, -1 do
                if v.people[i] == src then
                    table.remove(v.people, i)
                end
            end
            if #v.people == 0 then
                Namedinstances[k] = nil
            end
        end
    else
        for k, v in pairs(Namedinstances) do
            if v.name == setRoom then
                instanceSource = k
                break
            end
        end

        if not instanceSource then
            repeat
                instanceSource = math.random(1, 63)
            until not Namedinstances[instanceSource]
        end
    end

    if instanceSource > 0 then
        if not Namedinstances[instanceSource] then
            Namedinstances[instanceSource] = {
                name = setRoom,
                people = {}
            }
        end
        Namedinstances[instanceSource].people[#Namedinstances[instanceSource].people + 1] = src
    end

    SetPlayerRoutingBucket(src, instanceSource)
    TriggerClientEvent('jrs_core:instanceChanged', src, instanceSource)
end)
