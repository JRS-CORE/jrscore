-- Shared server-side employment policy. No client event or inventory item can
-- grant identity eligibility. Offline hires use the same character registry.
JRSJobIdentity = {}
function JRSJobIdentity.CanAssign(charId, job)
    local cfg = Config.JobIdentity or {}
    if cfg.Required == false then return true end
    job = tostring(job or ''):lower():match('^%s*(.-)%s*$')
    if job == 'unemployed' then return true end
    if job == '' then return false, 'invalid_job' end
    charId = tostring(charId or '')
    if charId == '' then return false, 'identity_required' end
    local ok, rows = pcall(function()
        return exports.oxmysql:executeSync(
            'SELECT `charid` FROM `jrs_idcard` WHERE `charid` = ? LIMIT 1', { charId })
    end)
    if not ok or type(rows) ~= 'table' then return false, 'identity_unavailable' end
    if not rows[1] or tostring(rows[1].charid) ~= charId then return false, 'identity_required' end
    return true
end
exports('CanAssignCharacterJob', JRSJobIdentity.CanAssign)
