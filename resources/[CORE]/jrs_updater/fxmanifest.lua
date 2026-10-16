fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'jrs_updater'
author 'JRS TEAM'
description 'JRS Core update checker - compares every installed jrs_* resource (core, inventory, loading screen, ...) with the GitHub repository'
version '1.0.0'

-- Version of the JRS Core pack this server was installed from.
-- Bump it together with every GitHub release (tag vX.Y.Z -> X.Y.Z).
jrscore_pack '1.0.0'

server_scripts {
    'config.lua',
    'server.lua'
}
