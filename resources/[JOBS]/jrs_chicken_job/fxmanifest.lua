fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'JRS TEAM'
description 'JRS Chicken Job'
version '3.4.0'

lua54 'yes'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'config.lua'
}

client_scripts {
    'client/animations.lua',
    'client/main.lua'
}

server_scripts {
    '@jrs_logs/capture.lua',
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql',
    'jrs_core',
    'jrs_inventory'
}

escrow_ignore {
    'config/*.lua',
    'config.lua',
    'locales/*.lua',
    'html/locales/*.js',
    'ui/locales/*.js',
    'sql/*.sql',
    '*.sql',
    'data/*.json'
}
