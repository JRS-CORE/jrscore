-- Manual fallback migration for the jrs_inventory weapon serial system.
-- The resource performs this migration automatically when
-- Config.WeaponSerials.AutoMigrate = true.

ALTER TABLE `jrs_weaponloadout`
    ADD COLUMN `serial_number` VARCHAR(64) NULL AFTER `id`;

UPDATE `jrs_weaponloadout`
SET `serial_number` = CONCAT('JRS-LEGACY-', LPAD(`id`, 12, '0'))
WHERE `serial_number` IS NULL OR `serial_number` = '';

ALTER TABLE `jrs_weaponloadout`
    ADD UNIQUE KEY `uniq_weapon_serial` (`serial_number`);
