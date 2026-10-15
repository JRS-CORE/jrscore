CREATE TABLE IF NOT EXISTS `jrs_horse_training` (
    `horse_id` INT(11) NOT NULL,
    `health_xp` INT(11) NOT NULL DEFAULT 0,
    `stamina_xp` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`horse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
