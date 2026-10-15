
exports('OpenCanoeRentingShop', function(storeId, city)
    OpenCanoeRentingShop(storeId, city)
end)

exports('IsCarryingCanoe', function()
    local retval, entity = IsCarryingCanoe()
    return retval -- returns boolean
end)

exports('GetCanoeEntityObject', function()
    local retval, entity = IsCarryingCanoe()
    return entity -- returns 0 if invalid.
end)

exports('IsModelCanoe', function(model)
    return IsModelCanoe(model) -- returns boolean
end)