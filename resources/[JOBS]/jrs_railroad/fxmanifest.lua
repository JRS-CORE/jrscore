-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

author 'JRS TEAM'
description 'JRS Core railroad - buy and run trains, companies, cargo, passengers and tickets'
version '1.0.0'

shared_scripts {
    'shared/locale.lua',
    'shared/jrs_kit.lua',
    'shared/config.lua',
}

client_scripts {
    'client/utils.lua',
    'client/main.lua',
    'client/train_spawn.lua',
    'client/train_control.lua',
    'client/train_switches.lua',
    'client/train_ambient.lua',
    'client/train_hud.lua',
    'client/cargo.lua',
    'client/missions.lua',
	'client/tickets.lua',
    'client/passengers.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/webhook.lua',
    'server/main.lua',
    'server/companies.lua',
    'server/upgrades.lua',
    'server/missions.lua',
    'server/company_ownership.lua',
    'server/employees.lua',
    'server/supplies.lua',
	'server/ticketsserver.lua',
	'server/ambient.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'locales/*.json',
    'install/railroad.sql',
}

dependencies {
    'jrs_core',
    'jrs_inventory',
    'oxmysql',
}

lua54 'yes'

jrs_api 'ext'
