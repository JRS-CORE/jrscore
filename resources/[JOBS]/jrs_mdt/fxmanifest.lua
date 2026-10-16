-- jrs_mdt | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core MDT - records, warrants, reports, charges and fines for the law'
version '1.0.0'

ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/i18n.js', 'web/app.js', 'locales/*.json' }

shared_scripts {
    'shared/jrs_kit.lua',
    'shared/config.lua',
    'shared/locale.lua',
}

client_scripts {
    'client/00_jrs_adapter.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/00_jrs_adapter.lua',
    'server/*.lua',
}

dependencies { 'jrs_core', 'oxmysql' }

jrs_api 'ext'
