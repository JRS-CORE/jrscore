fx_version 'cerulean'
game 'rdr3'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Inventory unified resource: inventory + weapons + storage + ground + robbery + transactional trade'
version '2.4.6'

dependencies {
    'jrs_core',
    'oxmysql',
    'uiprompt'
}

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',
    'config/config.lua',
    'shared/personal_items.lua',
    'shared/player_interactions.lua',
    'config/robbery.lua',
    'config/weapons.lua',
    'modules/trade/config.lua'
}

client_scripts {
    '@jrs_core/shared/pad_guard.lua',
    '@jrs_core/shared/jrs_lang_nui.lua',
    '@uiprompt/uiprompt.lua',
    '@jrs_core/config/level_perks.lua',
    'client/main.lua',
    'client/utils.lua',
    'client/weapons.lua',
    'client/ground.lua',
    'client/social.lua',
    'client/inventory.lua',
    'client/robbery.lua',
    'modules/trade/client.lua'
}

server_exports {
    'CloseInv', 'GetWeaponTable', 'RegisterUsableItem', 'addItem', 'addItemSync',
    'canAcquireItem', 'canCarryItem', 'check_itemtable', 'createWeapon', 'createWeaponOwned', 'createstorage',
    'damageItem', 'getCarryInfo', 'getInventoryTotalWeight', 'getItemById', 'getItemCount', 'getItemLabel',
    'getItemNames', 'getMetaTypeById', 'getMetadata', 'getUserInventory', 'getUserInventoryItems',
    'getWeaponsMe', 'giveWeapon', 'jrs_inventoryApi', 'openstorage', 'preload_itemtable',
    'preload_weapontable', 'reloadItemTable', 'removeMetadataValue', 'repairItem', 'setDurability',
    'setMetadata', 'setMetadataValue', 'setWeaponCondition', 'subItem', 'subItemByID', 'subItemSync',
    'subWeapon', 'syncWeaponAmmo', 'tradeCanReceive', 'tradeDeliverEscrow', 'tradeGetSnapshot',
    'tradeReserveOffer', 'tradeReturnEscrow', 'updatestorage',
    'AcquireInventoryLock', 'ReleaseInventoryLock', 'IsInventoryLocked', 'InventoryTransaction',
    'RegisterInventoryHook', 'GetFreeWeight', 'GetMaxWeight', 'WheelItemInfo', 'UseItemFromWheel', 'reloadItemDefinitions',
    'OpenPlayerInventoryAdmin',
    'RegisterCustomStorage', 'OpenCustomStorage'
}

server_scripts {
    'server/item_translations.lua',
    'server/item_labels.lua',
    '@oxmysql/lib/MySQL.lua',
    'config/config_logs.lua',
    'server/logger.lua',
    'server/weapon_serials.lua',
    'server/jrsInventoryAPI.lua',
    'server/main.lua',
    'server/metadata.lua',
    'server/items.lua',
    'server/weapons.lua',
    'server/trade_api.lua',
    'server/transactions.lua',
    'server/storage.lua',
    'server/admin_search.lua',
    'server/ground.lua',
    'server/social.lua',
    'server/robbery.lua',
    'modules/trade/server.lua',
    'server/jrs_storage_api.lua'
}

ui_page 'html/index.html'

files {
    'html/locales/*.js',
    'html/jrs-i18n.css',
    'html/jrs-i18n.js',
    'html/locales/en.js',
    'html/locales/ar.js',
    'html/index.js',
    'html/config.js',
    'html/index.css',
    'html/index.html',
    'html/trade-relay.js',
    'html/modules/trade/**/*',
    'html/crock.ttf',
    'html/fx-crock.ttf',
    'html/images/*.png',
    'html/images/clothes/*.png',
    'html/images/clothe/*.png',
    'html/images/filter/*.png',
    'html/images/items/*.png',
    'html/images/theme/*.png',
    'html/sounds/*.mp3',
    'html/vendor/*.js',
    'sql/*.sql',
    'modules/trade/sql/*.sql'
}

escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'html/config.js',
    'html/locales/*.js',
    'sql/*.sql',
    'modules/trade/sql/*.sql',
}

