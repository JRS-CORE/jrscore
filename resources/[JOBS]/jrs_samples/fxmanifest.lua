fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core animal samples - sedate animals, collect samples, leaderboard and milestones'
version '1.0.0'

shared_scripts {
    'shared/locale.lua',
    'shared/jrs_kit.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/taglistener.js',
    'client/tagging.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua',
}

dependencies { '/onesync', 'jrs_core', 'oxmysql' }

jrs_api 'ext'
