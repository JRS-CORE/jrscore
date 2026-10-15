CREATE TABLE IF NOT EXISTS `mailbox_mails` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  
  `sender_id` VARCHAR(64) NOT NULL,
  `sender_firstname` VARCHAR(64) NOT NULL,
  `sender_lastname` VARCHAR(64) NOT NULL,
  
  `receiver_id` VARCHAR(64) NOT NULL,
  `receiver_firstname` VARCHAR(64) NOT NULL,
  `receiver_lastname` VARCHAR(64) NOT NULL,
  
  `message` LONGTEXT NOT NULL,
  `opened` TINYINT(1) NOT NULL DEFAULT 0,
  `received_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  PRIMARY KEY (`id`),
  KEY `idx_receiver` (`receiver_id`, `receiver_firstname`, `receiver_lastname`),
  KEY `idx_sender` (`sender_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
