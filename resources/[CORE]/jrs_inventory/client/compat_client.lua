-- Extended inventory client events.
local function closeInv() TriggerEvent('jrs_inventory:CloseInv') end
exports('closeInventory', closeInv)
RegisterNetEvent('jrs_inventory:CloseCustomInv', closeInv)
-- extra scripts block the inventory during some actions; JRS has no block state.
RegisterNetEvent('jrs_inventory:blockInventory', function() end)
