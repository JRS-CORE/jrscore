-- JRS Character database installation / upgrade
CREATE TABLE IF NOT EXISTS `jrs_character_creator` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `charid` INT NOT NULL,
  `peddata` LONGTEXT NOT NULL,
  `informations` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `jrs_character_creator_charid_unique` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Character role-play profile fields
-- Adds role-play profile fields used by the integrated character creator.
-- This migration does not delete or modify existing character data.

ALTER TABLE `jrs_characters`
    ADD COLUMN IF NOT EXISTS `dateofbirth` DATE NULL;

ALTER TABLE `jrs_characters`
    ADD COLUMN IF NOT EXISTS `nickname` VARCHAR(50)
    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '';

ALTER TABLE `jrs_characters`
    ADD COLUMN IF NOT EXISTS `occupation` VARCHAR(80)
    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '';

-- Playtime aging fields.
ALTER TABLE `jrs_characters`
    ADD COLUMN IF NOT EXISTS `playtime_seconds` BIGINT UNSIGNED NOT NULL DEFAULT 0;

ALTER TABLE `jrs_characters`
    ADD COLUMN IF NOT EXISTS `base_age` SMALLINT UNSIGNED NULL DEFAULT NULL;

ALTER TABLE `jrs_characters`
    ADD COLUMN IF NOT EXISTS `age_years` SMALLINT UNSIGNED NULL DEFAULT NULL;
