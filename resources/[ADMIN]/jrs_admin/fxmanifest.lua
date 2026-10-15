-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
author 'JRS TEAM'
description 'JRS admin menu'
lua54 'yes'

shared_script {
    '@jrs_core/shared/jrs_lang.lua',
    'config.lua',
    'languages/translation.lua',
    'languages/ar.lua',
    'languages/runtime.lua',
}

client_scripts {
    '@jrs_core/shared/jrs_lang_nui.lua',
    'client/ui.lua',
    'client/kit.lua',
    'client/datapeds.lua',
    'client/dataprops.lua',
    'client/functions.lua',
    'client/admin.lua',
    'client/boosters.lua',
    'client/database.lua',
    'client/devTools.lua',
    'client/teleport.lua',
    'client/users.lua',
    'client/reports.lua',
    'client/client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'logs.lua',
    'server/*.lua',
}

ui_page 'html/index.html'

files { -- Credits to https://github.com/LVRP-BEN/bl_coords for clipboard copy method
    'html/index.html',
    'html/index.js',
    'html/style.css',
    'html/assets/css/ranch.css',
    'html/assets/css/components/*.css',
    'html/assets/fonts/*.ttf',
    'html/img/*.png',
    'html/lib/fa/all.min.css',
    'html/lib/webfonts/*.woff2',
}

dependencies { 'jrs_core', 'jrs_inventory', 'oxmysql' }

-- Version check dont touch
version '2.6'

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
