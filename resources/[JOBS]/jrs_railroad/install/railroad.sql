-- ============================================================
-- JRS Railroad - Full Database Installation
-- Run this ONCE on a fresh install
-- ============================================================

-- Train data (from v1)
CREATE TABLE IF NOT EXISTS `railroad_trains` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL DEFAULT '',
    `company_id` VARCHAR(50) NOT NULL DEFAULT '',
    `train_model` VARCHAR(50) NOT NULL,
    `label` VARCHAR(100) NOT NULL DEFAULT '',
    `fuel` INT(11) NOT NULL DEFAULT 100,
    `water` INT(11) NOT NULL DEFAULT 100,
    `condition` INT(11) NOT NULL DEFAULT 100,
    `upgrade_speed` INT(11) NOT NULL DEFAULT 0,
    `upgrade_fuel_cap` INT(11) NOT NULL DEFAULT 0,
    `upgrade_water_cap` INT(11) NOT NULL DEFAULT 0,
    `upgrade_durability` INT(11) NOT NULL DEFAULT 0,
    `total_miles` FLOAT NOT NULL DEFAULT 0,
    `is_parked` TINYINT(1) NOT NULL DEFAULT 1,
    `parked_station` VARCHAR(50) DEFAULT NULL,
    `parked_direction` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Legacy company membership (from v1)
CREATE TABLE IF NOT EXISTS `railroad_companies` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL DEFAULT '',
    `company_id` VARCHAR(50) NOT NULL DEFAULT '',
    `rank` INT(11) NOT NULL DEFAULT 1,
    `xp` INT(11) NOT NULL DEFAULT 0,
    `missions_completed` INT(11) NOT NULL DEFAULT 0,
    `total_earnings` FLOAT NOT NULL DEFAULT 0,
    `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_citizen_company` (`citizenid`, `company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Rewards tracking (from v1)
CREATE TABLE IF NOT EXISTS `railroad_rewards` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL DEFAULT '',
    `reward_id` VARCHAR(50) NOT NULL DEFAULT '',
    `claimed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_citizen_reward` (`citizenid`, `reward_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Company Ownership (v2)
CREATE TABLE IF NOT EXISTS `railroad_companies_owned` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `company_id` VARCHAR(50) NOT NULL,
    `owner_citizenid` VARCHAR(50) NOT NULL,
    `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
    `company_name` VARCHAR(100) DEFAULT NULL,
    `cash_register` FLOAT NOT NULL DEFAULT 0,
    `purchased_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_company` (`company_id`),
    INDEX `idx_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Employees / Drivers (v2)
CREATE TABLE IF NOT EXISTS `railroad_employees` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `company_id` VARCHAR(50) NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `firstname` VARCHAR(50) DEFAULT '',
    `lastname` VARCHAR(50) DEFAULT '',
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `xp` INT(11) NOT NULL DEFAULT 0,
    `rank` INT(11) NOT NULL DEFAULT 1,
    `missions_completed` INT(11) NOT NULL DEFAULT 0,
    `total_earnings` FLOAT NOT NULL DEFAULT 0,
    `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `approved_at` TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_company_citizen` (`company_id`, `citizenid`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Company Train Upgrades (v2) - owned by company, applies to all drivers
CREATE TABLE IF NOT EXISTS `railroad_company_upgrades` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `company_id` VARCHAR(50) NOT NULL,
    `train_model` VARCHAR(50) NOT NULL,
    `upgrade_speed` INT(11) NOT NULL DEFAULT 0,
    `upgrade_fuel_cap` INT(11) NOT NULL DEFAULT 0,
    `upgrade_water_cap` INT(11) NOT NULL DEFAULT 0,
    `upgrade_durability` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_company_model` (`company_id`, `train_model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Company Supplies (v2)
CREATE TABLE IF NOT EXISTS `railroad_company_supplies` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `company_id` VARCHAR(50) NOT NULL,
    `item_name` VARCHAR(50) NOT NULL,
    `quantity` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_company_item` (`company_id`, `item_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
