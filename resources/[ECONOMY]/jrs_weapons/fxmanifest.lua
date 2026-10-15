-- jrs_weapons | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game "rdr3"

name "jrs weapons"
author 'JRS TEAM'
lua54 'yes'
description 'A weapon handler with shops, crafting for jrs core framework'

shared_scripts {
  'config/weapons.lua',
  'config/language.lua',
  'config/ammo.lua',
  'config/config.lua',
}

client_script {
  'client/warmenu.lua',
  'client/client.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/server.lua'
}

file 'wepcomps.json'

--dont touch
version '2.3'

-- jrs_core / jrs_inventory serve the extended API to this resource
jrs_api 'ext'
