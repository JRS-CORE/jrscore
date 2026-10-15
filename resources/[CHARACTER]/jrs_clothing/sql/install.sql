-- Jrs_clothing schema

CREATE TABLE IF NOT EXISTS `jrs_clothing_current` (
  `charid` INT NOT NULL,
  `clothes` LONGTEXT NOT NULL,
  `outfit_id` VARCHAR(50) DEFAULT NULL,
  `hidden_categories` LONGTEXT NULL,
  PRIMARY KEY (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `jrs_clothing_outfits` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `charid` INT NOT NULL,
  `outfit_id` VARCHAR(50) NOT NULL,
  `price` DECIMAL(10,2) NOT NULL DEFAULT 0,
  `name` VARCHAR(255) NOT NULL DEFAULT '',
  `clothes` LONGTEXT NOT NULL,
  `singleitems` LONGTEXT NOT NULL,
  `gender` VARCHAR(32) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `jrs_clothing_outfit_unique` (`outfit_id`),
  KEY `jrs_clothing_outfit_charid_idx` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `jrs_clothing_wearables` (
  `charid` INT NOT NULL,
  `outfit_id` VARCHAR(50) NOT NULL,
  `skin` LONGTEXT NOT NULL,
  PRIMARY KEY (`charid`, `outfit_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `jrs_appearance_legacy_backup` (
  `charid` INT NOT NULL,
  `compPlayer` LONGTEXT NOT NULL,
  `skinPlayer` LONGTEXT NOT NULL,
  `migrated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `jrs_appearance_onboarding` (
  `charid` INT NOT NULL,
  `stage` VARCHAR(32) NOT NULL DEFAULT 'clothing',
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
