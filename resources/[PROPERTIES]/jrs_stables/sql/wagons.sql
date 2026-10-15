-- JRS Stables | New installations; legacy tables are upgraded by server/wagons.lua.
CREATE TABLE IF NOT EXISTS `player_wagons` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(100) NOT NULL,
  `charid` INT NOT NULL,
  `selected` TINYINT NOT NULL DEFAULT 0,
  `name` VARCHAR(100) NOT NULL,
  `model` VARCHAR(100) NOT NULL,
  `condition` DOUBLE NOT NULL DEFAULT 100,
  PRIMARY KEY (`id`), KEY `jrs_wagon_owner` (`identifier`, `charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
