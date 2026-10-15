-- jrs_crawfish | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Text lookup with {name} placeholders:  Say('found', { count = 2, item = 'Crawfish' })
function Say(key, vars)
    local set = Config.Text[Config.Language] or Config.Text.en
    local line = set[key] or Config.Text.en[key] or key
    if vars then
        line = line:gsub('{(%w+)}', function(name) return tostring(vars[name] or '') end)
    end
    return line
end

-- number, or { min, max } -> a number
function RollAmount(value)
    if type(value) == 'table' then return math.random(value[1], value[2]) end
    return value or 0
end
