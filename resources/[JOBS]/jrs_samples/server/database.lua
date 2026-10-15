--------------------------------------------------------------------------------------------
-- JRS SAMPLES — Server: automatic database setup
-- Creates the jrs_samples table (and any missing indexes) on resource start.
-- Safe to run every start: nothing is dropped or overwritten.
--------------------------------------------------------------------------------------------
if not Config.AutoInstallDB then return end

MySQL.ready(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `jrs_samples` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `citizenid` varchar(50) NOT NULL,
                `sample_id` varchar(50) NOT NULL,
                `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
                PRIMARY KEY (`id`),
                UNIQUE KEY `idx_citizenid_sampleid` (`citizenid`, `sample_id`),
                KEY `idx_sample_id` (`sample_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]])

        -- Upgrade older installs that were created before idx_sample_id existed
        local hasIndex = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.statistics
            WHERE table_schema = DATABASE() AND table_name = 'jrs_samples' AND index_name = 'idx_sample_id'
        ]])
        if hasIndex == 0 then
            MySQL.query.await('ALTER TABLE `jrs_samples` ADD INDEX `idx_sample_id` (`sample_id`)')
            print('[jrs_samples] ^2Added missing index idx_sample_id^7')
        end
    end)

    if ok then
        print('[jrs_samples] ^2Database ready^7')
    else
        print('[jrs_samples] ^1Database setup failed:^7 ' .. tostring(err))
        print('[jrs_samples] ^3Import the jrs_samples table manually or check your MySQL user permissions.^7')
    end
end)
