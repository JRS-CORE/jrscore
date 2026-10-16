-- jrs_water_actions | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core water actions - wash and drink in rivers and lakes'
version '1.0.0'

shared_scripts {
    'shared/locale.lua',
    'shared/jrs_kit.lua',
    'config.lua',
}

client_scripts { 'client/main.lua' }

dependencies { 'jrs_core' }

jrs_api 'ext'
