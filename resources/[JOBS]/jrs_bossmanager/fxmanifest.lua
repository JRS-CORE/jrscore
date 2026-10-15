fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core boss menu - hire, promote, demote and fire employees of your job'
version '2.0.0'

shared_scripts {
    'shared/jrs_kit.lua',
    'config.lua',
    'shared/locale.lua',
}

client_script 'client/client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua',
}

dependencies { 'jrs_core', 'oxmysql' }

jrs_api 'ext'
