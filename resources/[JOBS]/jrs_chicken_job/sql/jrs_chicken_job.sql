CREATE TABLE IF NOT EXISTS `jrs_chicken_cooldowns` (
  `identifier` varchar(100) NOT NULL,
  `last_mission` bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('chicken_thigh', 'Chicken Thigh', 'فخذ دجاج', 0.20, 1, 'item_standard', 1, 'Raw chicken thigh', 'فخذ دجاج نيء طازج', '0', 'food'),
('chicken_wing', 'Chicken Wing', 'جناح دجاج', 0.20, 1, 'item_standard', 1, 'Raw chicken wing', 'جناح دجاج نيء طازج', '0', 'food'),
('chicken_breast', 'Chicken Breast', 'صدر دجاج', 0.20, 1, 'item_standard', 1, 'Raw chicken breast', 'صدر دجاج نيء طازج', '0', 'food'),
('chicken_drumstick', 'Chicken Drumstick', 'ساق دجاج', 0.20, 1, 'item_standard', 1, 'Raw chicken drumstick', 'ساق دجاج نيء طازج', '0', 'food')
ON DUPLICATE KEY UPDATE `limit` = VALUES(`limit`), `label` = VALUES(`label`), `label_ar` = VALUES(`label_ar`), `descriptions` = VALUES(`descriptions`), `descriptions_ar` = VALUES(`descriptions_ar`);
