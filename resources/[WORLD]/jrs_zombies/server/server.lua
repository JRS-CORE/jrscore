---------------------------------------------------------
-- send to client : spawn zombies
---------------------------------------------------------
RegisterNetEvent('jrs_zombies:server:triggerzombies', function(town)
	TriggerClientEvent('jrs_zombies:client:spawnzombies', -1, town)
end)