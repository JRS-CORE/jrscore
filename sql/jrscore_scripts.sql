-- JRS Core - script tables (run AFTER jrscore.sql)
SET NAMES utf8mb4;

-- jrs_attached_objects items
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('natives_backshield',      'Native Back Shield',  'درع ظهر',       1.00, 1, 'item_standard', 1, 'Wear it on your back.',            'البسه على ظهرك.',           '0', 'clothing'),
('natives_arrow_pouch_bag', 'Arrow Pouch',         'جعبة سهام',     0.50, 1, 'item_standard', 1, 'A bundle of arrows on your back.', 'حزمة سهام على ظهرك.',       '0', 'clothing'),
('miner_hat',               'Miner Lamp Hat',      'خوذة منجم',     0.50, 1, 'item_standard', 1, 'A miner hat with a lamp.',         'خوذة منجم فيها مصباح.',     '0', 'clothing');

-- jrs_backpacks items (each backpack gets its own storage the first time it is opened)
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('backpack_simple',  'Simple Backpack',  'شنطة بسيطة',   1.00, 1, 'item_standard', 1, 'A small backpack (20 slots).',     'شنطة صغيرة (20 خانة).',  '0', 'tools'),
('backpack_ammo',    'Ammo Bag',         'شنطة ذخيرة',   1.00, 1, 'item_standard', 1, 'A bag for ammunition (20 slots).', 'شنطة للذخيرة (20 خانة).', '0', 'tools'),
('backpack_trapper', 'Trapper Backpack', 'شنطة الصياد',  1.50, 1, 'item_standard', 1, 'A trapper pack (30 slots).',       'شنطة صياد (30 خانة).',   '0', 'tools'),
('backpack_fish',    'Fishing Satchel',  'شنطة السمك',   1.50, 1, 'item_standard', 1, 'A fishing satchel (30 slots).',    'شنطة صيد سمك (30 خانة).', '0', 'tools'),
('backpack_nat',     'Explorer Backpack','شنطة المستكشف', 2.00, 1, 'item_standard', 1, 'An explorer backpack (40 slots).', 'شنطة مستكشف (40 خانة).', '0', 'tools'),
('backpack_normal',  'Backpack',         'شنطة',         2.00, 1, 'item_standard', 1, 'A regular backpack (50 slots).',   'شنطة عادية (50 خانة).',  '0', 'tools'),
('backpack_big',     'Large Backpack',   'شنطة كبيرة',   3.00, 1, 'item_standard', 1, 'A large backpack (80 slots).',     'شنطة كبيرة (80 خانة).',  '0', 'tools');

-- jrs_canteen items
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('canteen100', 'Full Canteen',  'مطارة ممتلئة', 0.50, 1, 'item_standard', 1, 'A full canteen of fresh water.',                'مطارة ممتلئة بماء عذب.',              '0', 'tools'),
('canteen75',  'Canteen (75%)', 'مطارة (75%)',   0.40, 1, 'item_standard', 1, 'A canteen, three quarters full.',               'مطارة فيها ثلاثة أرباع الماء.',        '0', 'tools'),
('canteen50',  'Canteen (50%)', 'مطارة (50%)',   0.30, 1, 'item_standard', 1, 'A canteen, half full.',                         'مطارة نصها ماء.',                      '0', 'tools'),
('canteen25',  'Canteen (25%)', 'مطارة (25%)',   0.20, 1, 'item_standard', 1, 'A canteen with a little water left.',           'مطارة باقي فيها شوية ماء.',            '0', 'tools'),
('canteen0',   'Empty Canteen', 'مطارة فاضية',  0.10, 1, 'item_standard', 1, 'Empty. Refill it while standing in a river or lake.', 'فاضية. عبّها وأنت واقف في نهر أو بحيرة.', '0', 'tools');

-- jrs_goldclaim
CREATE TABLE IF NOT EXISTS `jrs_goldrockers` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) DEFAULT NULL,
    `owner` varchar(50) DEFAULT NULL,
    `properties` text NOT NULL,
    `propid` int(11) NOT NULL,
    `proptype` varchar(50) DEFAULT NULL,
    `licensed` tinyint(1) NOT NULL DEFAULT 0,
    `claimname` varchar(100) DEFAULT NULL,
    `paydirt` int(3) NOT NULL DEFAULT 0,
    `water` int(3) NOT NULL DEFAULT 0,
    `quality` int(3) NOT NULL DEFAULT 100,
    PRIMARY KEY (`id`),
    UNIQUE KEY `propid` (`propid`),
    KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('goldrocker',         'Gold Rocker',          'هزّاز الذهب',       5.00, 1, 'item_standard', 1, 'Set it up near water to work a gold claim.', 'ركّبه قرب الماء عشان تشتغل على منجم ذهب.', '0', 'tools'),
('rocker_shovel',      'Rocker Shovel',        'مجرفة التنقيب',     1.50, 1, 'item_standard', 1, 'Dig paydirt while standing in a river.',     'احفر تراب الذهب وأنت واقف في النهر.',        '0', 'tools'),
('rocker_bucket',      'Empty Bucket',         'سطل فاضي',         0.50, 1, 'item_standard', 1, 'Fill it with water in a river.',             'عبّه ماء من النهر.',                         '0', 'tools'),
('rocker_bucket_full', 'Bucket of Water',      'سطل ماء',          2.00, 1, 'item_standard', 0, 'Water for a gold rocker.',                   'ماء لهزّاز الذهب.',                          '0', 'tools'),
('paydirt',            'Paydirt',              'تراب الذهب',       1.00, 1, 'item_standard', 0, 'Dirt that may hold gold.',                   'تراب ممكن يكون فيه ذهب.',                    '0', 'resources'),
('goldclaim_license',  'Gold Claim License',   'رخصة منجم ذهب',     0.10, 1, 'item_standard', 0, 'Makes a gold claim legal when placed.',      'تخلي منجم الذهب قانوني لما تركّبه.',         '0', 'documents');

-- MDT Database Schema
-- Import this file into your database before using the MDT

-- Criminal Records Table
CREATE TABLE IF NOT EXISTS `mdt_records` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `crime` VARCHAR(255) NOT NULL,
    `description` TEXT,
    `fine` INT DEFAULT 0,
    `jailtime` INT DEFAULT 0,
    `officer` VARCHAR(100) NOT NULL,
    `officer_cid` VARCHAR(50),
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Warrants Table
CREATE TABLE IF NOT EXISTS `mdt_warrants` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `reason` TEXT NOT NULL,
    `status` ENUM('active', 'served', 'expired') DEFAULT 'active',
    `officer` VARCHAR(100) NOT NULL,
    `officer_cid` VARCHAR(50),
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- BOLOs (Be On Lookout) Table
CREATE TABLE IF NOT EXISTS `mdt_bolos` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `description` TEXT,
    `last_seen` VARCHAR(255),
    `officer` VARCHAR(100) NOT NULL,
    `officer_cid` VARCHAR(50),
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_title` (`title`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Reports Table
CREATE TABLE IF NOT EXISTS `mdt_reports` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `type` VARCHAR(50) DEFAULT 'incident',
    `description` TEXT,
    `officers` JSON,
    `suspects` JSON,
    `evidence` JSON,
    `officer` VARCHAR(100) NOT NULL,
    `officer_cid` VARCHAR(50),
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_type` (`type`),
    INDEX `idx_officer` (`officer`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Report Comments (case building)
CREATE TABLE IF NOT EXISTS `mdt_report_comments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `report_id` INT NOT NULL,
    `author` VARCHAR(100) NOT NULL,
    `author_cid` VARCHAR(50),
    `content` TEXT NOT NULL,
    `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_report_id` (`report_id`),
    FOREIGN KEY (`report_id`) REFERENCES `mdt_reports`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Citizen Profiles (MDT-specific data like profile pictures)
CREATE TABLE IF NOT EXISTS `mdt_citizen_profiles` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `profile_picture` VARCHAR(512),
    `notes` TEXT,
    `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Staff Members Table
CREATE TABLE IF NOT EXISTS `mdt_staff` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `name` VARCHAR(100) NOT NULL,
    `role` VARCHAR(50) DEFAULT 'officer',
    `permissions` JSON,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Roles Table
CREATE TABLE IF NOT EXISTS `mdt_roles` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(50) NOT NULL UNIQUE,
    `label` VARCHAR(100) NOT NULL,
    `permissions` JSON,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit Logs Table
CREATE TABLE IF NOT EXISTS `mdt_audit_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `action` VARCHAR(50) NOT NULL,
    `target_type` VARCHAR(50),
    `target_id` VARCHAR(100),
    `target_name` VARCHAR(100),
    `details` TEXT,
    `performed_by` VARCHAR(50) NOT NULL,
    `performed_by_name` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_action` (`action`),
    INDEX `idx_performed_by` (`performed_by`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Charge Templates Table
CREATE TABLE IF NOT EXISTS `mdt_charge_templates` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `description` TEXT,
    `fine` INT DEFAULT 0,
    `jailtime` INT DEFAULT 0,
    `category` VARCHAR(50) DEFAULT 'misdemeanor',
    `created_by` VARCHAR(50),
    `created_by_name` VARCHAR(100),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_category` (`category`),
    INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Issued Charges Table (tracks charges applied to citizens)
CREATE TABLE IF NOT EXISTS `mdt_issued_charges` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `citizen_name` VARCHAR(100) NOT NULL,
    `charge_template_id` INT,
    `charge_name` VARCHAR(255) NOT NULL,
    `charge_description` TEXT,
    `fine` INT DEFAULT 0,
    `jailtime` INT DEFAULT 0,
    `time_served` INT DEFAULT 0,
    `is_served` TINYINT(1) DEFAULT 0,
    `officer` VARCHAR(100) NOT NULL,
    `officer_cid` VARCHAR(50),
    `report_id` INT,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `served_at` TIMESTAMP NULL,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_officer` (`officer`),
    INDEX `idx_is_served` (`is_served`),
    FOREIGN KEY (`charge_template_id`) REFERENCES `mdt_charge_templates`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Charge-Report Attachments Table (many-to-many relationship)
CREATE TABLE IF NOT EXISTS `mdt_charge_attachments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `charge_id` INT NOT NULL,
    `report_id` INT NOT NULL,
    `attached_by` VARCHAR(50) NOT NULL,
    `attached_by_name` VARCHAR(100) NOT NULL,
    `attached_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_charge_report` (`charge_id`, `report_id`),
    INDEX `idx_charge_id` (`charge_id`),
    INDEX `idx_report_id` (`report_id`),
    FOREIGN KEY (`charge_id`) REFERENCES `mdt_issued_charges`(`id`) ON DELETE CASCADE,
    FOREIGN KEY (`report_id`) REFERENCES `mdt_reports`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Fines Table
CREATE TABLE IF NOT EXISTS `mdt_fines` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `citizen_name` VARCHAR(100) NOT NULL,
    `issued_charge_ids` JSON,
    `total_amount` INT NOT NULL DEFAULT 0,
    `due_date` TIMESTAMP NULL,
    `status` ENUM('unpaid', 'paid', 'overdue') DEFAULT 'unpaid',
    `issued_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `paid_at` TIMESTAMP NULL,
    `officer_name` VARCHAR(100),
    `officer_cid` VARCHAR(50),
    `paid_to_officer` VARCHAR(100),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`),
    INDEX `idx_due_date` (`due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default Charge Templates
INSERT IGNORE INTO `mdt_charge_templates` (`name`, `description`, `fine`, `jailtime`, `category`) VALUES
    ('Assault', 'Physical assault on another person', 50, 2, 'felony'),
    ('Battery', 'Unlawful physical force against another', 75, 3, 'felony'),
    ('Theft', 'Stealing property valued under $50', 25, 0, 'misdemeanor'),
    ('Grand Theft', 'Stealing property valued $50 or more', 100, 6, 'felony'),
    ('Trespassing', 'Unauthorized entry onto private property', 15, 0, 'misdemeanor'),
    ('Public Intoxication', 'Being drunk in public', 10, 0, 'infraction'),
    ('Disorderly Conduct', 'Disturbing the peace', 20, 0, 'misdemeanor'),
    ('Vandalism', 'Willful destruction of property', 30, 0, 'misdemeanor'),
    ('Fraud', 'Deception for personal gain', 150, 12, 'felony'),
    ('Murder', 'Unlawful killing of another person', 0, 60, 'felony'),
    ('Horse Theft', 'Stealing a horse or other mount', 200, 24, 'felony'),
    ('Bank Robbery', 'Robbery of a banking institution', 500, 48, 'felony'),
    ('Resisting Arrest', 'Resisting or fleeing from law enforcement', 50, 1, 'misdemeanor'),
    ('Obstruction of Justice', 'Interfering with law enforcement duties', 40, 0, 'misdemeanor');

-- Default Roles
INSERT IGNORE INTO `mdt_roles` (`name`, `label`, `permissions`) VALUES
    ('admin', 'Administrator', '{"canCreateRecords": true, "canDeleteRecords": true, "canManageWarrants": true, "isAdmin": true}'),
    ('supervisor', 'Supervisor', '{"canCreateRecords": true, "canDeleteRecords": true, "canManageWarrants": true, "isAdmin": false}'),
    ('officer', 'Officer', '{"canCreateRecords": true, "canDeleteRecords": false, "canManageWarrants": false, "isAdmin": false}');


-- JRS: characters in the shape the MDT queries (citizenid / charinfo / job / money / metadata)
CREATE OR REPLACE VIEW `jrs_mdt_players` AS
SELECT
    CAST(`charidentifier` AS CHAR) AS `citizenid`,
    JSON_OBJECT('firstname', `firstname`, 'lastname', `lastname`) AS `charinfo`,
    JSON_OBJECT('name', `job`, 'label', `job`, 'grade', JSON_OBJECT('level', `jobgrade`)) AS `job`,
    JSON_OBJECT('cash', `money`) AS `money`,
    `meta` AS `metadata`
FROM `jrs_characters`;

-- jrs_passports
CREATE TABLE IF NOT EXISTS `passports` (
  `identityId` varchar(50) NOT NULL DEFAULT '',
  `identifier` varchar(50) NOT NULL,
  `charidentifier` int(11) NOT NULL,
  `steamname` varchar(50) NOT NULL,
  `firstname` varchar(50) NOT NULL,
  `lastname` varchar(50) NOT NULL,
  `dob` varchar(50) NOT NULL,
  `sex` int(1) NOT NULL DEFAULT 0,
  `registration_date` varchar(50) NOT NULL,
  `expiration_date` int(11) NOT NULL DEFAULT 0,
  `avatar_url` longtext NOT NULL,
  PRIMARY KEY (`identityId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin ROW_FORMAT=DYNAMIC;

INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('passport', 'Passport', 'جواز سفر', 0.05, 1, 'item_standard', 1, 'Your identity papers.', 'أوراق هويتك.', '0', 'documents');

-- jrs_railroad items (tables are created by the script on start)
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('trainticket', 'Train Ticket', 'تذكرة قطار', 0.01, 1, 'item_standard', 0, 'A ticket for one train journey.', 'تذكرة لرحلة قطار وحدة.', '0', 'documents'),
('oilcan',      'Can of Oil',   'علبة زيت',   1.00, 1, 'item_standard', 0, 'Engine oil to repair a locomotive.', 'زيت محرك لإصلاح القطار.', '0', 'tools');

-- horse care items (shop / crafting goods)
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('horsebrush',               'Horse Brush',   'فرشاة حصان',   0.30, 1, 'item_standard', 0, 'Brush your horse to clean it.',          'نظّف حصانك بالفرشاة.',        '0', 'horse'),
('oil_lantern',              'Oil Lantern',   'فانوس زيت',    0.80, 1, 'item_standard', 0, 'Hang it on your horse at night.',        'علّقه على حصانك بالليل.',     '0', 'horse'),
('consumable_horse_reviver', 'Horse Reviver', 'منعش الخيل',   0.20, 1, 'item_standard', 0, 'Brings an injured horse back on its feet.', 'يرجّع الحصان المصاب يوقف.', '0', 'horse'),
('consumable_haycube',       'Haycube',       'مكعب تبن',     0.20, 1, 'item_standard', 0, 'Horse food.',                            'أكل للخيل.',                  '0', 'horse'),
('consumable_carrots',       'Carrots',       'جزر',          0.10, 1, 'item_standard', 1, 'Horses love them.',                      'الخيل تحبه.',                 '0', 'horse'),
('consumable_apple',         'Apple',         'تفاح',         0.10, 1, 'item_standard', 1, 'A juicy fruit. Horses like it too.',     'فاكهة طيبة، والخيل تحبها.',   '0', 'food');

-- jrs_usable_items: items not in the base item list
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('pipepeace',              'Peace Pipe',              'غليون السلام',        0.20, 1, 'item_standard', 1, 'A ceremonial pipe.',         'غليون احتفالي.',        '0', 'misc'),
('pocket_watch_silver',    'Silver Pocket Watch',     'ساعة جيب فضية',       0.10, 1, 'item_standard', 1, 'A silver pocket watch.',      'ساعة جيب من الفضة.',    '0', 'misc'),
('pocket_watch_antique',   'Antique Pocket Watch',    'ساعة جيب أثرية',      0.10, 1, 'item_standard', 1, 'An old pocket watch.',        'ساعة جيب قديمة.',       '0', 'misc'),
('pocket_watch_reutlinger','Reutlinger Pocket Watch', 'ساعة جيب رويتلنغر',   0.10, 1, 'item_standard', 1, 'A fine Reutlinger watch.',    'ساعة جيب فاخرة.',       '0', 'misc');

-- Items the base JRS scripts (jrs_crafting recipes) use but the item list did not have
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('Axe',                     'Axe',                       'فأس',                 2.00, 1, 'item_standard', 0, 'A woodcutting axe.',              'فأس لقطع الخشب.',           '0', 'tools'),
('BigGameMeat',             'Big Game Meat',             'لحم صيد كبير',        0.50, 1, 'item_standard', 0, 'Raw meat from big game.',         'لحم نيء من صيد كبير.',      '0', 'food'),
('CookedBigGameMeat',       'Cooked Big Game Meat',      'لحم صيد كبير مطبوخ',  0.40, 1, 'item_standard', 1, 'Cooked big game meat.',           'لحم صيد كبير مطبوخ.',       '0', 'food'),
('SaltedCookedBigGameMeat', 'Salted Big Game Meat',      'لحم صيد مملّح',        0.40, 1, 'item_standard', 1, 'Salted and cooked.',              'مملّح ومطبوخ.',             '0', 'food'),
('bedroll',                 'Bedroll',                   'فرشة نوم',            2.00, 1, 'item_standard', 0, 'For sleeping outdoors.',          'للنوم في البر.',            '0', 'tools'),
('birdstew',                'Bird Stew',                 'مرق طيور',            0.40, 1, 'item_standard', 1, 'A warm bird stew.',               'مرق طيور دافي.',            '0', 'food'),
('carrot',                  'Carrot',                    'جزر',                 0.10, 1, 'item_standard', 1, 'A fresh carrot.',                 'جزرة طازجة.',               '0', 'food'),
('consumable_applepie',     'Apple Pie',                 'فطيرة تفاح',          0.30, 1, 'item_standard', 1, 'A sweet apple pie.',              'فطيرة تفاح حلوة.',          '0', 'food'),
('cookedbird',              'Cooked Bird',               'طير مطبوخ',           0.30, 1, 'item_standard', 1, 'Roasted bird meat.',              'لحم طير مشوي.',             '0', 'food'),
('cookedpork',              'Cooked Pork',               'لحم خنزير مطبوخ',     0.30, 1, 'item_standard', 1, 'Cooked pork.',                    'لحم خنزير مطبوخ.',          '0', 'food'),
('cookedsmallgame',         'Cooked Small Game',         'صيد صغير مطبوخ',      0.30, 1, 'item_standard', 1, 'Cooked small game meat.',         'لحم صيد صغير مطبوخ.',       '0', 'food'),
('pelt',                    'Pelt',                      'جلد',                 1.00, 1, 'item_standard', 0, 'An animal pelt.',                 'جلد حيوان.',                '0', 'resources'),
('plainsmallgame',          'Plain Small Game',          'صيد صغير',            0.30, 1, 'item_standard', 1, 'Plain cooked small game.',        'صيد صغير مطبوخ عادي.',      '0', 'food'),
('porknapples',             'Pork and Apples',           'لحم مع تفاح',         0.40, 1, 'item_standard', 1, 'Pork cooked with apples.',        'لحم مطبوخ مع تفاح.',        '0', 'food'),
('rawbirdmeat',             'Raw Bird Meat',             'لحم طير نيء',         0.25, 1, 'item_standard', 0, 'Raw bird meat.',                  'لحم طير نيء.',              '0', 'food'),
('rope',                    'Rope',                      'حبل',                 0.50, 1, 'item_standard', 0, 'A length of rope.',               'حبل.',                      '0', 'tools'),
('steakeggs',               'Steak and Eggs',            'ستيك وبيض',           0.40, 1, 'item_standard', 1, 'A hearty breakfast.',             'فطور دسم.',                 '0', 'food'),
('vegstew',                 'Vegetable Stew',            'مرق خضار',            0.40, 1, 'item_standard', 1, 'A vegetable stew.',               'مرق خضار.',                 '0', 'food');

-- items used by the jrs_crafting recipes / jrs_hunting rewards
INSERT IGNORE INTO `jrs_items` (`item`, `label`, `label_ar`, `limit`, `can_remove`, `type`, `usable`, `descriptions`, `descriptions_ar`, `metadata`, `category`) VALUES
('consumable_special_horse_stimulant_crafted','Special Horse Stimulant','منشّط الحصان الخاص',0.25,1,'item_standard',1,'A homemade special horse stimulant.','منشط حصان خاص مصنوع يدوياً.','0','field_kit'),
('turkey_meat','Turkey Meat','لحم ديك رومي',0.25,1,'item_standard',0,'Raw turkey meat. Roast it at a campfire.','لحم ديك رومي نيء. اشوه على نار المخيم.','0',NULL),
('consumable_big_game_meat_cooked','Plain Big Game Meat','لحم صيد كبير مشوي',0.25,1,'item_standard',1,'Roast hearty big game meat over the campfire flame.','شواء لحم صيد كبير مشبع على نار المخيم.','0','provisions'),
('consumable_crustacean_meat_cooked','Plain Crustacean Meat','لحم قشريات مطبوخ',0.25,1,'item_standard',1,'Cook fresh crustacean meat over hot embers.','طبخ لحم القشريات الطازج على الجمر الحار.','0','provisions'),
('consumable_exotic_bird_cooked','Plain Exotic Bird','لحم طيور نادرة مشوي',0.25,1,'item_standard',1,'Roast exotic bird meat over campfire embers.','شواء لحم الطيور النادرة على جمر المخيم.','0','provisions'),
('consumable_flakey_fish_cooked','Plain Flakey Fish','سمك طري مشوي',0.25,1,'item_standard',1,'Cook a flakey fish fillet over the open coals.','طبخ شريحة سمك طرية على الجمر المكشوف.','0','provisions'),
('consumable_game_meat_cooked','Plain Game Meat','لحم طرائد مشوي',0.25,1,'item_standard',1,'Roast tender game meat over the campfire coals.','شواء لحم طرائد طري على جمر المخيم.','0','provisions'),
('consumable_gristly_mutton_cooked','Plain Gristly Mutton','لحم ضأن مشوي',0.25,1,'item_standard',1,'Roast mutton over the campfire flame.','شواء لحم الضأن على نار المخيم.','0','provisions'),
('consumable_mature_venison_cooked','Plain Mature Venison','لحم غزال مشوي',0.25,1,'item_standard',1,'Roast a steak of mature venison over the campfire.','شواء شريحة لحم غزال ناضج على نار المخيم.','0','provisions'),
('consumable_plump_bird_cooked','Plain Plump Bird','لحم طيور مشوي',0.25,1,'item_standard',1,'Roast fresh bird meat over the campfire flame.','شواء لحم الطيور الطازج على نار المخيم.','0','provisions'),
('consumable_prime_beef_cooked','Plain Prime Beef','لحم بقر مشوي',0.25,1,'item_standard',1,'Roast a cut of prime beef over the campfire flame.','شواء قطعة لحم بقري ممتاز على نار المخيم.','0','provisions'),
('consumable_succulent_fish_cooked','Plain Succulent Fish','سمك شهي مشوي',0.25,1,'item_standard',1,'Cook succulent salmon or trout over the campfire flame.','طبخ سمك السلمون أو التراوت الشهي على نار المخيم.','0','provisions'),
('consumable_tender_pork_cooked','Plain Tender Pork','لحم طري مشوي',0.25,1,'item_standard',1,'Roast fresh pork over the open flame.','شواء لحم طازج على اللهب المكشوف.','0','provisions'),
('gun_oil','Gun Oil','زيت الأسلحة',0.10,1,'item_standard',1,'Single use. Equip a firearm and use it to clean all the dirt off the weapon.','استخدام مرة واحدة. جهّز سلاحاً نارياً واستخدمه لتنظيف السلاح من كل الأوساخ.','0','tools'),
('sapphire_ring','Sapphire Ring',NULL,0.10,1,'item_standard',1,'',NULL,'{','valuable'),
('beak','Beak','منقار',0.05,1,'item_standard',0,'A bird beak, used in crafting.','منقار طير، يستخدم في الصناعة.','0','hunting'),
('birdfeather','Bird Feather','ريشة طير',0.01,1,'item_standard',0,'A small bird feather.','ريشة طير صغيرة.','0','hunting'),
('claws','Claws','مخالب',0.05,1,'item_standard',0,'Sharp animal claws.','مخالب حيوان حادة.','0','hunting'),
('feathers','Feathers','ريش',0.02,1,'item_standard',0,'A bundle of feathers.','حزمة ريش.','0','hunting'),
('kcondorb','Condor Beak','منقار نسر الكوندور',0.10,1,'item_standard',0,'The beak of a great condor.','منقار نسر كوندور كبير.','0','hunting'),
('kcondorf','Condor Feather','ريشة نسر الكوندور',0.02,1,'item_standard',0,'A long condor feather.','ريشة كوندور طويلة.','0','hunting'),
('turtleshell','Turtle Shell','صدفة سلحفاة',0.50,1,'item_standard',0,'A hard turtle shell.','صدفة سلحفاة قاسية.','0','hunting');

-- jrs_housing (also created by the script on start)
CREATE TABLE IF NOT EXISTS `jrs_houses` (
  `house` INT NOT NULL,
  `owner_charid` INT NOT NULL,
  `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
  `keys` LONGTEXT NULL,
  `bought_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`house`),
  KEY `idx_owner` (`owner_charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
