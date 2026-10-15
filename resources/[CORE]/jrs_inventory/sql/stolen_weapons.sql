-- Manual fallback migration for the jrs_inventory stolen-weapon flag.
-- The resource performs this migration automatically alongside the weapon
-- serial system (see server/weapon_serials.lua: ensureStolenColumn).

ALTER TABLE `jrs_weaponloadout`
    ADD COLUMN `stolen` TINYINT(1) NOT NULL DEFAULT 0;
