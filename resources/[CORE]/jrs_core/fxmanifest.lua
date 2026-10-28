fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

author 'JRS TEAM'
description 'JRS unified core: core + native notifications + optional toast + inputs + menu + character services + bounded RPC'
version '2.5.6-habitats'

-- Compatibility aliases for resources that only declare legacy dependencies.
provide 'jrs_inputs'
provide 'jrs_menu'
provide 'jrs_notify'

--[[
  CLIENT/SCRIPT POOL SIZE INCREASES (merged in from jrs_poolsizes 2026-09-12)
  ----------------------------------------------------------------------------
  Folded into core instead of a standalone resource: `pool_size_increase` is
  just a manifest directive with no logic of its own, jrs_core is always
  ensured (section 09, well before the map packs in section 15's maps.cfg),
  and keeping it here means the pool bumps can never be left out of
  server.cfg by accident.

  Raises client entity/archetype pool limits for this map-heavy server.
  Without these, clients crashed on join with:

      Recursive error: An exception occurred (c0000005) during execution of
      the INIT_SESSION function for CExtraContentWrapper. The game will be
      terminated. Original error: <<unknown pool>> Pool Full, Size == 66700

  That happens while the game mounts streamed map content (587 .ymap + 423
  .ytyp across [spooni], [mlo_gk_guarma_pack], [yourmaps], [mapholder],
  [MAP], [SD], [housing]). `pool_size_increase` is read by the CLIENT, so
  exact pool names accepted by this RedM build can't be verified server-side;
  unknown names are ignored by the client rather than breaking anything.

  IF THE CRASH PERSISTS: the guaranteed fix is to reduce streamed content.
  [spooni] is by far the largest contributor (284 .ymap / 305 .ytyp / 2.4 GB).
  Comment it out of maps.cfg, confirm players can join, then re-add packs one
  at a time to find the real ceiling.

  NOTE: written with explicit parentheses. The bare form
  `pool_size_increase 'Name' 20000` is NOT valid Lua (a number cannot be
  chained as a second call argument) and makes the whole manifest fail to load.
]]
pool_size_increase('EntityBatch', 20000)
pool_size_increase('Object', 20000)
pool_size_increase('Building', 20000)
pool_size_increase('AnimatedBuilding', 5000)
pool_size_increase('Dummy Object', 10000)
pool_size_increase('fwArchetypePooledMap', 30000)

--[[
  SCRIPT-SIDE POOLS (added 2026-09-05)
  -----------------------------------
  Clients were also spamming, in-game rather than on join:

      Error: fwScriptGuid Pool Full, Size == 40000
      Error: ItemSet Pool Full, Size == 400

  fwScriptGuid holds one entry per entity that any script has taken a handle
  to, and ItemSet holds every itemset a script has created. Both were being
  drained by script leaks (jrs_pets enumerated the entire client ped pool
  twice a second; jrs_stable cleared its itemset instead of destroying it) -
  those are fixed in the resources themselves. These increases are headroom,
  not the fix: if the errors come back, something is leaking handles again,
  so look for a new world-wide entity enumeration or a CreateItemset without
  a DestroyItemset.
]]
pool_size_increase('fwScriptGuid', 40000)
pool_size_increase('ItemSet', 400)

ui_page 'html/ui.html'

files {
    'shared/jrs_lang_nui.lua',
    'shared/pad_guard.lua',
    'config/levels.lua',
    'html/locales/*.js',
    'html/jrs-i18n.css',
    'versions.json',
    'html/ui.html',
    'html/style.css',
    'html/editor.css',
    'html/grid.css',
    'html/jrs-i18n.js',
    'html/jrs-pad.js',
    'html/hud-icons.js',
    'html/hud-export-clipboard.js',
    'html/devtools_guard.js',
    'html/main.js',
    'html/level.js',
    'html/doublexp.js',
    'html/module-relay.js',
    'html/vendor/*.js',
    'html/*.ttf',
    'html/modules/**/*',
    'html/storeui/*.png',
    'html/theme/*.css',
    'html/img/*.png',
    'html/img/*.svg',
    'html/img/level/*.png',
    'html/img/jobs/*.png',
    'html/img/menu/*.png',
    'html/img/crosshair/*.png',
    'html/assets/fonts/*.ttf'
}

shared_scripts {
    'shared/callbacks.lua',
    'config/config.lua',
    'config/gameplay.lua',
    'config/economy.lua',
    'config/levels.lua',
    'shared/level_math.lua',
    'shared/jrs_lang.lua',
    'locales/*.lua',
    'modules/notify/config.lua'
}

client_scripts {
    'shared/pad_guard.lua',
    'shared/jrs_lang_nui.lua',

    'client/ui_manager.lua',
    'client/devtools_guard.lua',
    'client/rpc.lua',
    'modules/notify/client.lua',
    'modules/input/client.lua',
    'modules/menu/client.lua',

    'client/map_discoveries_data.lua',
    'client/map_discoveries.lua',
    'client/minimap.lua',
    'client/client.lua',
    'client/level_ui.lua',
    'client/job_xp.lua',
    'client/double_xp.lua',
    'client/character_ready.lua',
    'client/gameplay.lua',
    'client/gamepad.lua',
    'client/network_guard.lua',
    'client/blip_guard.lua',
    'client/hud_gate.lua',
    'client/hud_layout.lua',
    'client/crosshair.lua',
    'client/utilities.lua',
    'client/api.lua',
    'client/dataview.lua',
    'client/events.lua',
    'client/functions.lua',
    'client/notifications.lua',
    'client/tasks.lua',
    'client/client_functions.lua',
    'client/inputwheel.lua',
    'client/waypoint3d.lua',
    'client/traffic.lua',
    'client/animals.lua',
    'client/performance.lua',
    'client/player_dropped.lua',
    'client/feed.lua',
    'client/language.lua',
    'client/starter_origin.lua',
    'client/world_interiors.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/permissions.lua',
    'server/job_identity.lua',
    'server/daily_challenges.lua',
    'server/core.lua',
    'server/rpc.lua',
    'server/character_ready.lua',
    'server/character_service.lua',
    'modules/notify/server.lua',
    'server/hud_layout.lua',
    'server/hud_export.lua',
    'server/double_xp.lua',
    'server/xp.lua',
    'server/level_perks.lua',
    'server/job_perks.lua',
    'server/job_xp.lua',
    'server/economy_logging.lua',
    'server/tax_engine.lua',
    'server/starter_origin.lua',
    'server/version.lua',
    'server/api.lua',
    'server/init.lua',
    'server/events.lua',
    'server/commands.lua',
    'server/restart_manager.lua',
    'server/network_guard.lua',
    'server/connection.lua',
    'server/main.lua',
    'server/doubleConnection.lua',
    'server/instance.lua',
    'server/wheel.lua',
    'server/performance.lua',
    'server/devtools_guard.lua',
    'server/player_dropped.lua',
    'server/language.lua'
}

-- MySQL must be available before core persistence initializes.
dependency 'oxmysql'

escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'shared/jrs_lang.lua',
    'data/*.json',
    '[SQL]/*.sql',
    '*.sql',
}

-- extended API (GetCore, Core.Callback, notifications, death/respawn) for the extra scripts
client_scripts { 'client/compat_callbacks.lua', 'client/compat_api.lua', 'client/respawn.lua' }
server_scripts { 'server/compat_callbacks.lua', 'server/compat_api.lua', 'server/compat_state.lua' }

-- built-in menu / advanced inputs / theme exports (no separate jrs_menu, jrs_inputs)
shared_scripts { 'shared/ext_theme.lua' }
client_scripts { 'client/ext_menu.lua', 'client/ext_inputs.lua' }
files { 'html/theme/*' }
