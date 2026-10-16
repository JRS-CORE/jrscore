-- jrs_usable_items | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core usable items - pipes, cigars, cigarettes and pocket watches with animations'
version '1.0.0'

shared_scripts {
    'shared/jrs_kit.lua',
    'config.lua',
}
server_scripts { 'server/*.lua' }
client_scripts { '@jrs_core/client/dataview.lua', 'client/*.lua' }

dependencies { 'jrs_core', 'jrs_inventory' }

jrs_api 'ext'
