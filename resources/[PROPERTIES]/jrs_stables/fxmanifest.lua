-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'JRS Stables'
author 'JRS TEAM'
description 'JRS Stables - horses and wagons, shared stable UI, ownership, cargo and care'
version '2.2.2'

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'config/main.lua',
    'config/comps.lua',
    'config/horses.lua',
    'config/horse_training.lua',
    'config/stables.lua',
    'config/trainers.lua',
    'config/translations.lua',
    'config/wagon_settings.lua',
    'config/wagon_sites.lua',
    'config/wagons.lua',
    'locale.lua',
    'languages/*.lua',
    'shared/wagon_locale.lua',
    'shared/tack.lua',
    'shared/horse_training.lua'
}

client_scripts {
    'client/dataview.lua',
    'client/wagons.lua',
    'client/main.lua',
    'client/horse_training.lua',
    'client/horseinfo.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/horse_training.lua',
    'server/main.lua',
    'server/wagons.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/js/*.*',
    'ui/css/*.*',
    'ui/fonts/*.*',
    'ui/audio/*.wav',
    'ui/img/*.*',
    'sql/wagons.sql',
    'sql/horse_training.sql',
    'licenses/*.*'
}

dependencies { 'jrs_core', 'jrs_inventory', 'oxmysql' }

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
