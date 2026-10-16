-- jrs_guarma | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- The server picks the price from the config: the client only says which port and which option.
JRS.Callback('jrs_guarma:pay', function(src, portId, index)
    local port = Config.Ports[portId]
    local pay = port and port.payments[tonumber(index) or 0]
    if not pay or not JRS.Char(src) then return false end
    if not JRS.Near(src, port.port, 5.0) then return false, L('too_far') end
    if not JRS.Cooldown(src, 'sail', 10) then return false end

    if pay.item then
        local need = math.max(1, pay.amount or 0)
        if not JRS.Has(src, pay.item, need) then return false, L('cant_pay') end
        if (pay.amount or 0) > 0 and not JRS.Remove(src, pay.item, pay.amount) then return false, L('cant_pay') end
    elseif (pay.money or 0) > 0 and not JRS.TakeMoney(src, pay.money) then
        return false, L('cant_pay')
    end
    return true
end)
