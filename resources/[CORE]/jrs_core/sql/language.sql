-- Per-account language, chosen by the player on the character screen.
-- jrs_core adds this column automatically on boot when it is missing; this file
-- is here for clean installs and for anyone who prefers to apply it by hand.
-- NULL means the player has never picked: the character screen then shows the
-- language step before anything else.
ALTER TABLE `jrs_users` ADD COLUMN `language` VARCHAR(8) NULL DEFAULT NULL;
