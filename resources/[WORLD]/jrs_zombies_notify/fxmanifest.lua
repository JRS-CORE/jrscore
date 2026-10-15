fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'jrs_zombies_notify'
author 'JRS TEAM (original script by jrsmatrex)'
description 'Zombie growl sound alerts used by jrs_zombies'
version '1.1.0'

ui_page 'html/ui.html'
client_script 'client.lua'

files {
    'html/ui.html',
    'html/styles.css',
    'html/scripts.js',
    'html/*.mp3',
}

export 'Alert'