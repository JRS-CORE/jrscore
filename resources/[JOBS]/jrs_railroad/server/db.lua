-- jrs_railroad | server: database access
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Every table has a few small functions here; the rest of the resource never writes SQL itself.

DB = {}

local function rows(sql, args) return MySQL.query.await(sql, args) or {} end
local function first(sql, args) return rows(sql, args)[1] end
local function run(sql, args) MySQL.query.await(sql, args) end
local function changed(result) return type(result) == 'table' and (result.affectedRows or 0) > 0 end
local function count(sql, args) local r = first(sql, args) return r and r.cnt or 0 end

-- ------------------------------------------------------------------ trains

function DB.GetOwnedTrains(citizenid) return MySQL.query.await('SELECT * FROM railroad_trains WHERE citizenid = @cid', { ['@cid'] = citizenid }) end
function DB.GetTrainById(id) return first('SELECT * FROM railroad_trains WHERE id = @id LIMIT 1', { ['@id'] = id }) end
function DB.CountTrains(citizenid) return count('SELECT COUNT(*) AS cnt FROM railroad_trains WHERE citizenid = @cid', { ['@cid'] = citizenid }) end
function DB.GetCompanyTrains(companyId) return rows('SELECT * FROM railroad_trains WHERE company_id = @comp', { ['@comp'] = companyId }) end

function DB.InsertTrain(citizenid, companyId, model, label, fuel, water, condition)
    return MySQL.insert.await(
        'INSERT INTO railroad_trains (citizenid, company_id, train_model, label, fuel, water, `condition`) VALUES (@cid, @comp, @model, @label, @fuel, @water, @cond)',
        { ['@cid'] = citizenid, ['@comp'] = companyId, ['@model'] = model, ['@label'] = label, ['@fuel'] = fuel, ['@water'] = water, ['@cond'] = condition })
end

function DB.DeleteTrain(id, citizenid)
    return changed(MySQL.query.await('DELETE FROM railroad_trains WHERE id = @id AND citizenid = @cid', { ['@id'] = id, ['@cid'] = citizenid }))
end

function DB.UpdateTrainFuel(id, fuel) run('UPDATE railroad_trains SET fuel = @v WHERE id = @id', { ['@id'] = id, ['@v'] = fuel }) end
function DB.UpdateTrainWater(id, water) run('UPDATE railroad_trains SET water = @v WHERE id = @id', { ['@id'] = id, ['@v'] = water }) end
function DB.UpdateTrainCondition(id, condition) run('UPDATE railroad_trains SET `condition` = @v WHERE id = @id', { ['@id'] = id, ['@v'] = condition }) end

function DB.UpdateTrainState(id, fuel, water, condition)
    run('UPDATE railroad_trains SET fuel = @fuel, water = @water, `condition` = @cond WHERE id = @id',
        { ['@id'] = id, ['@fuel'] = fuel, ['@water'] = water, ['@cond'] = condition })
end

function DB.ParkTrain(id, stationId, fuel, water, condition)
    run('UPDATE railroad_trains SET is_parked = 1, parked_station = @station, fuel = @fuel, water = @water, `condition` = @cond WHERE id = @id',
        { ['@id'] = id, ['@station'] = stationId, ['@fuel'] = fuel, ['@water'] = water, ['@cond'] = condition })
end

function DB.UnparkTrain(id) run('UPDATE railroad_trains SET is_parked = 0, parked_station = NULL WHERE id = @id', { ['@id'] = id }) end
function DB.AddMiles(id, miles) run('UPDATE railroad_trains SET total_miles = total_miles + @v WHERE id = @id', { ['@id'] = id, ['@v'] = miles }) end

-- `column` always comes from Config.Upgrades, never from a player
function DB.UpdateUpgrade(id, column, level)
    run('UPDATE railroad_trains SET `' .. column .. '` = @lvl WHERE id = @id', { ['@id'] = id, ['@lvl'] = level })
end

-- ------------------------------------------------------------------ a player's standing in a company

local function member(citizenid, companyId) return { ['@cid'] = citizenid, ['@comp'] = companyId } end

function DB.GetCompanyData(citizenid) return MySQL.query.await('SELECT * FROM railroad_companies WHERE citizenid = @cid', { ['@cid'] = citizenid }) end

function DB.GetCompanyMembership(citizenid, companyId)
    return first('SELECT * FROM railroad_companies WHERE citizenid = @cid AND company_id = @comp LIMIT 1', member(citizenid, companyId))
end

function DB.JoinCompany(citizenid, companyId)
    MySQL.insert.await('INSERT INTO railroad_companies (citizenid, company_id, `rank`) VALUES (@cid, @comp, 1)', member(citizenid, companyId))
end

function DB.EnsureCompanyMembership(citizenid, companyId)
    if not DB.GetCompanyMembership(citizenid, companyId) then DB.JoinCompany(citizenid, companyId) end
end

-- adds `amount` to one numeric column of the membership row
local function bump(citizenid, companyId, column, amount)
    DB.EnsureCompanyMembership(citizenid, companyId)
    local args = member(citizenid, companyId)
    args['@v'] = amount
    run('UPDATE railroad_companies SET ' .. column .. ' = ' .. column .. ' + @v WHERE citizenid = @cid AND company_id = @comp', args)
end

function DB.AddCompanyXP(citizenid, companyId, xp) bump(citizenid, companyId, 'xp', xp) end
function DB.IncrementMissions(citizenid, companyId) bump(citizenid, companyId, 'missions_completed', 1) end
function DB.AddEarnings(citizenid, companyId, amount) bump(citizenid, companyId, 'total_earnings', amount) end

function DB.SetCompanyRank(citizenid, companyId, rank)
    DB.EnsureCompanyMembership(citizenid, companyId)
    local args = member(citizenid, companyId)
    args['@rank'] = rank
    run('UPDATE railroad_companies SET `rank` = @rank WHERE citizenid = @cid AND company_id = @comp', args)
end

-- ------------------------------------------------------------------ one-time rewards

function DB.HasClaimedReward(citizenid, rewardId)
    return first('SELECT id FROM railroad_rewards WHERE citizenid = @cid AND reward_id = @rid LIMIT 1', { ['@cid'] = citizenid, ['@rid'] = rewardId }) ~= nil
end

function DB.ClaimReward(citizenid, rewardId)
    MySQL.insert.await('INSERT INTO railroad_rewards (citizenid, reward_id) VALUES (@cid, @rid)', { ['@cid'] = citizenid, ['@rid'] = rewardId })
end

-- ------------------------------------------------------------------ owned companies and their cash register

function DB.GetCompanyOwnership(companyId) return first('SELECT * FROM railroad_companies_owned WHERE company_id = @comp LIMIT 1', { ['@comp'] = companyId }) end
function DB.GetAllOwnedCompanies() return rows('SELECT * FROM railroad_companies_owned') end
function DB.GetOwnedCompaniesByCitizen(citizenid) return rows('SELECT * FROM railroad_companies_owned WHERE owner_citizenid = @cid', { ['@cid'] = citizenid }) end
function DB.GetOwnedCompanyCount() return count('SELECT COUNT(*) AS cnt FROM railroad_companies_owned') end

function DB.PurchaseCompany(companyId, citizenid, ownerName)
    return MySQL.insert.await('INSERT IGNORE INTO railroad_companies_owned (company_id, owner_citizenid, owner_name) VALUES (@comp, @cid, @name)',
        { ['@comp'] = companyId, ['@cid'] = citizenid, ['@name'] = ownerName })
end

function DB.SellCompany(companyId, citizenid)
    return changed(MySQL.query.await('DELETE FROM railroad_companies_owned WHERE company_id = @comp AND owner_citizenid = @cid',
        { ['@comp'] = companyId, ['@cid'] = citizenid }))
end

function DB.SetCompanyName(companyId, name)
    run('UPDATE railroad_companies_owned SET company_name = @name WHERE company_id = @comp', { ['@comp'] = companyId, ['@name'] = name })
end

function DB.GetCashRegister(companyId)
    local r = first('SELECT cash_register FROM railroad_companies_owned WHERE company_id = @comp LIMIT 1', { ['@comp'] = companyId })
    return r and r.cash_register or 0
end

function DB.AddToCashRegister(companyId, amount)
    run('UPDATE railroad_companies_owned SET cash_register = cash_register + @amt WHERE company_id = @comp', { ['@comp'] = companyId, ['@amt'] = amount })
end

-- false when the register holds less than `amount`
function DB.WithdrawFromCashRegister(companyId, amount)
    return changed(MySQL.query.await('UPDATE railroad_companies_owned SET cash_register = cash_register - @amt WHERE company_id = @comp AND cash_register >= @amt',
        { ['@comp'] = companyId, ['@amt'] = amount }))
end

-- ------------------------------------------------------------------ company-wide train upgrades

function DB.GetCompanyUpgrades(companyId) return rows('SELECT * FROM railroad_company_upgrades WHERE company_id = @comp', { ['@comp'] = companyId }) end

function DB.GetCompanyTrainUpgrade(companyId, trainModel)
    return first('SELECT * FROM railroad_company_upgrades WHERE company_id = @comp AND train_model = @model LIMIT 1', { ['@comp'] = companyId, ['@model'] = trainModel })
end

function DB.UpsertCompanyUpgrade(companyId, trainModel, column, level)
    run('INSERT INTO railroad_company_upgrades (company_id, train_model, `' .. column .. '`) VALUES (@comp, @model, @lvl) ON DUPLICATE KEY UPDATE `' .. column .. '` = @lvl',
        { ['@comp'] = companyId, ['@model'] = trainModel, ['@lvl'] = level })
end

-- ------------------------------------------------------------------ employees

function DB.ApplyAsDriver(companyId, citizenid, firstname, lastname)
    MySQL.insert.await('INSERT INTO railroad_employees (company_id, citizenid, firstname, lastname, status) VALUES (@comp, @cid, @fn, @ln, @status)',
        { ['@comp'] = companyId, ['@cid'] = citizenid, ['@fn'] = firstname, ['@ln'] = lastname, ['@status'] = 'pending' })
end

function DB.GetEmployeesByCompany(companyId)
    return rows([[
        SELECT e.*, COALESCE(m.xp, 0) AS company_xp, COALESCE(m.`rank`, 1) AS company_rank, COALESCE(m.missions_completed, 0) AS company_missions
        FROM railroad_employees e
        LEFT JOIN railroad_companies m ON e.citizenid = m.citizenid AND e.company_id = m.company_id
        WHERE e.company_id = @comp ORDER BY e.status, e.applied_at DESC
    ]], { ['@comp'] = companyId })
end

function DB.GetEmployeeByIds(companyId, citizenid)
    return first('SELECT * FROM railroad_employees WHERE company_id = @comp AND citizenid = @cid LIMIT 1', member(citizenid, companyId))
end

function DB.GetPlayerEmployment(citizenid)
    return rows('SELECT * FROM railroad_employees WHERE citizenid = @cid AND status = @status', { ['@cid'] = citizenid, ['@status'] = 'approved' })
end

function DB.GetPendingApplications(companyId)
    return rows('SELECT * FROM railroad_employees WHERE company_id = @comp AND status = @status ORDER BY applied_at ASC', { ['@comp'] = companyId, ['@status'] = 'pending' })
end

function DB.ApproveEmployee(id) run('UPDATE railroad_employees SET status = @status, approved_at = NOW() WHERE id = @id', { ['@id'] = id, ['@status'] = 'approved' }) end
function DB.RejectEmployee(id) run('UPDATE railroad_employees SET status = @status WHERE id = @id', { ['@id'] = id, ['@status'] = 'rejected' }) end
function DB.FireEmployee(id) run('DELETE FROM railroad_employees WHERE id = @id', { ['@id'] = id }) end
function DB.DeleteEmployeesByCompany(companyId) run('DELETE FROM railroad_employees WHERE company_id = @comp', { ['@comp'] = companyId }) end

local function bumpEmployee(id, column, amount)
    run('UPDATE railroad_employees SET ' .. column .. ' = ' .. column .. ' + @v WHERE id = @id', { ['@id'] = id, ['@v'] = amount })
end

function DB.AddEmployeeXP(id, xp) bumpEmployee(id, 'xp', xp) end
function DB.IncrementEmployeeMissions(id) bumpEmployee(id, 'missions_completed', 1) end
function DB.AddEmployeeEarnings(id, amount) bumpEmployee(id, 'total_earnings', amount) end
function DB.SetEmployeeRank(id, rank) run('UPDATE railroad_employees SET `rank` = @rank WHERE id = @id', { ['@id'] = id, ['@rank'] = rank }) end

-- ------------------------------------------------------------------ company supplies

function DB.GetCompanySupplies(companyId) return rows('SELECT * FROM railroad_company_supplies WHERE company_id = @comp', { ['@comp'] = companyId }) end

function DB.GetSupplyItem(companyId, item)
    return first('SELECT * FROM railroad_company_supplies WHERE company_id = @comp AND item_name = @item LIMIT 1', { ['@comp'] = companyId, ['@item'] = item })
end

function DB.AddSupplyItem(companyId, item, quantity)
    local args = { ['@comp'] = companyId, ['@item'] = item, ['@qty'] = quantity }
    if DB.GetSupplyItem(companyId, item) then
        run('UPDATE railroad_company_supplies SET quantity = quantity + @qty WHERE company_id = @comp AND item_name = @item', args)
    else
        MySQL.insert.await('INSERT INTO railroad_company_supplies (company_id, item_name, quantity) VALUES (@comp, @item, @qty)', args)
    end
end

-- false when there is not enough of it
function DB.TakeSupplyItem(companyId, item, quantity)
    return changed(MySQL.query.await('UPDATE railroad_company_supplies SET quantity = quantity - @qty WHERE company_id = @comp AND item_name = @item AND quantity >= @qty',
        { ['@comp'] = companyId, ['@item'] = item, ['@qty'] = quantity }))
end

function DB.DeleteSuppliesByCompany(companyId) run('DELETE FROM railroad_company_supplies WHERE company_id = @comp', { ['@comp'] = companyId }) end

-- ------------------------------------------------------------------ table setup on start
-- install/railroad.sql only has CREATE TABLE IF NOT EXISTS, so running it every start is harmless.

local function statementsOf(sql)
    local kept = {}
    for line in (sql .. '\n'):gmatch('([^\r\n]*)\r?\n') do
        if not line:match('^%s*%-%-') then kept[#kept + 1] = line end
    end

    local list = {}
    for piece in (table.concat(kept, '\n') .. ';'):gmatch('([^;]*);') do
        local trimmed = piece:gsub('^%s+', ''):gsub('%s+$', '')
        if #trimmed > 0 then list[#list + 1] = trimmed end
    end
    return list
end

function DB.EnsureTables()
    local sql = LoadResourceFile(GetCurrentResourceName(), 'install/railroad.sql')
    if not sql then
        return print('^1[jrs_railroad]^7 install/railroad.sql could not be read, automatic database setup skipped. Import it by hand.')
    end

    local list = statementsOf(sql)
    if #list == 0 then return print('^1[jrs_railroad]^7 install/railroad.sql has no statements.') end

    local failed = 0
    for _, statement in ipairs(list) do
        local ok, err = pcall(function() MySQL.query.await(statement) end)
        if not ok then
            failed = failed + 1
            print(('^1[jrs_railroad]^7 database setup statement failed: %s'):format(tostring(err)))
        end
    end

    if failed == 0 then
        print(('^2[jrs_railroad]^7 database tables are ready (%d statements).'):format(#list))
    else
        print(('^1[jrs_railroad]^7 database setup ended with %d failed statement(s); check the MySQL user may CREATE TABLE.'):format(failed))
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Config.AutoInstallDatabase == false then
        return print('^3[jrs_railroad]^7 Config.AutoInstallDatabase is false, skipping database setup.')
    end
    CreateThread(function()
        Wait(500)                                  -- let oxmysql connect first
        DB.EnsureTables()
    end)
end)
