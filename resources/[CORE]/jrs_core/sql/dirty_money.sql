-- JRS Core - Dirty Money database field
-- jrs_core creates this field automatically on resource start.
-- This file is provided for manual database setup if preferred.
ALTER TABLE `jrs_characters`
    ADD COLUMN `dirtymoney` DECIMAL(20,2) NOT NULL DEFAULT 0.00 AFTER `money`;
