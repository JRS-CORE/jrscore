fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'JRS TEAM'
description 'JRS Core death logs - who died, how and by whom, to the console and Discord'
version '1.0.0'

-- Discord: set jrs_death_logs_webhook "https://discord.com/api/webhooks/..." in server.cfg

shared_scripts { 'shared/jrs_kit.lua' }
client_scripts { 'client/main.lua' }
server_scripts { 'server/main.lua' }

dependencies { 'jrs_core' }

jrs_api 'ext'
