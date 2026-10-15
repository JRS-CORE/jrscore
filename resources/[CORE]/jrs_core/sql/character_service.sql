-- JRS Core character-service safe migration
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `multijobs` LONGTEXT NULL;
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `skills` LONGTEXT NULL;
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `onduty` TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `character_desc` VARCHAR(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '';
-- Existing latin1 column rejects Arabic lore and aborts character creation:
ALTER TABLE `jrs_characters` MODIFY COLUMN `character_desc` VARCHAR(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '';
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `gender` VARCHAR(16) NULL DEFAULT NULL;
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `last_played` TIMESTAMP NULL DEFAULT NULL;
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `appearance_version` INT NOT NULL DEFAULT 1;
ALTER TABLE `jrs_characters` ADD COLUMN IF NOT EXISTS `health_state` LONGTEXT NULL;
