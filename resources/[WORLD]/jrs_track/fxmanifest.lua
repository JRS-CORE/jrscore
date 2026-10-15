fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core horse race tracks - build checkpoint routes, save them and race'
version '1.0.0'

shared_scripts {
    'shared/jrs_kit.lua',
    'shared/config.lua',
    'shared/locale.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/webhook.lua',
    'server/server.lua',
}

client_scripts { 'client/client.lua' }

files { 'locales/*.json' }

dependencies { 'jrs_core', 'oxmysql' }

jrs_api 'ext'
