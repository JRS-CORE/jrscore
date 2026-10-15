fx_version 'cerulean'
games { 'rdr3' }
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core Free - clothing store (pieces + colours)'
version '1.0.0-free'

provide 'jrs_clothing'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',
    'shared/callbacks.lua',
    'shared/clothing/config.lua',
    'shared/clothing/lang.lua',
    'shared/clothing/componentsbody.lua',
    'shared/clothing/assets.lua',
    'shared/clothing/builtin_footwear.lua',
    'shared/clothing/law_filter.lua',
}

client_scripts {
    '@jrs_core/shared/pad_guard.lua',
    'client/common/nui_bridge.lua',
    'client/clothing/engine.lua',
    'client/clothing/adapter.lua',
    'client/clothing/shop.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/common/adapter.lua',
    'server/clothing/database.lua',
    'server/clothing/server.lua',
}

ui_page 'ui/index.html'
files { 'ui/*' }

dependencies { 'oxmysql', 'jrs_core', 'jrs_inventory' }
