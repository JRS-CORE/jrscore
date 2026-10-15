-- jrs_paycheck | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'
server_only 'yes'

name 'jrs_paycheck'
author 'JRS TEAM'
description 'Wages for jobs and groups, paid on a timer'
version '2.0.0'

server_scripts {
    'config.lua',
    'server/main.lua',
}

dependency 'jrs_core'

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
