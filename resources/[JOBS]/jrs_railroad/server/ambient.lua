local ambientSpawned = false

JRS.Callback('jrs_railroad:shouldSpawnAmbient', function(source)
    if ambientSpawned then return false end
    ambientSpawned = true
    return true
end)

RegisterNetEvent('jrs_railroad:ambientDespawned', function()
    ambientSpawned = false
end)