fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

author 'JRS TEAM'
description 'JRS Core hunting pets - hunting dogs and birds with training, tracking and scavenging'
version '1.0.0'

shared_scripts {
    'shared/locale.lua',
    'shared/jrs_kit.lua',
    'shared/config_shared.lua',
    'shared/config_dogs.lua',
    'shared/config_birds.lua',
}

client_scripts {
    'client/client_shop.lua',
    'client/npcs.lua',
    'client/client_dogs.lua',
    'client/client_birds.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/server_dogs.lua',
    'server/server_birds.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/script.js',
    'html/style.css',
    'html/images/**/*',
}

dependencies {
    'jrs_core',
    'jrs_inventory',
    'oxmysql',
}

lua54 'yes'

jrs_api 'ext'
