-- jrs_playerinfo | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core player info - /info shows your character, job and money'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/locale.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'jrs_core',
    'oxmysql',
}

jrs_api 'ext'
