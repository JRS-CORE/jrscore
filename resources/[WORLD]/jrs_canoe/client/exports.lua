-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | exports for other resources
exports('OpenCanoeRentingShop', function(storeId, city) OpenCanoeRentingShop(storeId, city) end)
exports('IsCarryingCanoe', function() return (IsCarryingCanoe()) end)
exports('GetCanoeEntityObject', function() return select(2, IsCarryingCanoe()) end)    -- 0 when none
exports('IsModelCanoe', function(model) return IsModelCanoe(model) end)
