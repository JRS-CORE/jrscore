fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_zombies'
author 'JRS TEAM (original script by jrsmatrex)'
description 'Zombie outbreak events in the towns - standalone, no framework needed'
version '1.1.0'

shared_script 'config.lua'
client_script 'client/client.lua'
server_script 'server/server.lua'

dependency 'jrs_zombies_notify'