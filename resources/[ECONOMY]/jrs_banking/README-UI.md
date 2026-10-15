# JRS Banking UI

Banking now uses the same local textures, header, slots, buttons and fonts as the installed `jrs_admin` interface. Assets are included here; the bank does not require the admin resource to be running.

The mouse interface includes cash deposits/withdrawals, gold deposits/withdrawals where enabled, transfers from your other branch accounts, safebox access and slot purchases. Transfer fees and safebox limits/prices come from `config.lua`. Accounts, balances, locations, opening hours and the configured G interaction key remain unchanged.

Arabic and English follow the player's character language in `jrs_core`. Arabic uses right-to-left layout and accepts Arabic digits. The panel includes mouse wheel scrolling, visible scrollbars, movable title bar, centering, and Escape/close controls. The game remains visible outside the panel.

Dependencies: existing `jrs_core`, `jrs_inventory`, and `oxmysql`. Keep the existing bank database; this UI update needs no SQL migration. The legacy `jrsinputs` menu is no longer used by this resource.

After copying the resource, run `restart jrs_banking` from your server console. Test a small deposit, withdrawal, transfer and safebox access in game. Automated Lua and browser checks cover the existing event argument order, configuration switches, validation, focus handoff, both languages, scrolling and four viewport sizes; they do not simulate the live RedM game or connect to the live database.
