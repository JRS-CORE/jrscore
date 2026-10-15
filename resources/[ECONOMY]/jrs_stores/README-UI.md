# JRS Stores 2.5.0

The store uses the same original menu background, header, slots, buttons and fonts as the installed JRS admin interface. Assets are bundled locally; the admin resource is not a runtime dependency. The NUI supports mouse interaction, scrolling, search, draggable/centered positioning, quantity dialogs, separate buying/selling baskets and a fixed checkout button. Outside the menu is transparent.

Arabic and English follow the player's character language in `jrs_core`. Product labels/descriptions come from `jrs_inventory`, including its Arabic item definitions. Arabic quantity inputs are accepted.

Removed dedicated gun stores: Valentinegunstore, SaintDgunstore, Rhodesgunstore, Annesburggunstore and Tumbleweedgunstore. Their catalogues, map blips, NPCs and weapon/ammo UI pictures are removed, along with weapon categories/products in general stores. The 13 other stores remain, including fishing shops and butchers. The fishing rod remains a fishing tool and uses the installed inventory's confirmed owned-equipment grant API.

Prices and currency come from the server catalogue. Random prices now display the same values charged by the server. Selling uses actual owned stack IDs and confirmed item removal. Failed purchase grants refund the charge. Dynamic stock and optional decay pricing are applied consistently to the displayed price and transaction. A basket reports completed products and retains unsuccessful selections. Store sessions check location, character identity and configured jobs/grades, and expire after abandoned sessions.

Dependencies remain `jrs_core` and `jrs_inventory`; both use the installed extended API. Existing configurable locations, opening hours, NPCs, blips, prices, stock values, job restrictions and G interaction key are retained for non-weapon stores. No SQL migration is required. `jrs_stores:Client:OpenShop` and `jrs_stores:Server:ChangeStoreStatus` remain available. Weapon-shop ownership compatibility queries return no owned weapon storefront; weapon shops belong to the separate `jrs_weapons` resource.

Restart with `restart jrs_stores` after deployment. Automated checks cover the actual Lua transaction handlers and installed inventory adapter, both UI languages, four screen sizes, scrolling, baskets and cleanup. These checks do not execute live RedM gameplay or write to the live database.
