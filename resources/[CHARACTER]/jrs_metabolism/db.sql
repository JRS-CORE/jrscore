CREATE TABLE IF NOT EXISTS `character_rpg_stats` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `personaId` INT NOT NULL,
    `statHunger` DECIMAL(7,3) NOT NULL DEFAULT 0,
    `statThirst` DECIMAL(7,3) NOT NULL DEFAULT 0,
    `statHealth` INT NOT NULL DEFAULT 200,
    `statHealthCore` INT NOT NULL DEFAULT 100,
    `statStamina` DECIMAL(7,3) NOT NULL DEFAULT 1,
    `statStaminaCore` INT NOT NULL DEFAULT 100,
    PRIMARY KEY (`id`), UNIQUE KEY `personaId` (`personaId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
