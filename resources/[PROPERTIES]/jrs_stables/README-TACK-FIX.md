# JRS Stables 2.2.1 — horse equipment persistence

The wildlife visibility controller in `jrs_core/client/animals.lua` previously applied a random outfit to every newly seen animal, including stable horses. This replaced the horse outfit after JRS Stables equipped purchased tack. The controller now keeps the horse outfit and retains visibility repair and wildlife customization.

JRS Stables now loads each horse's saved equipment before editing, stores a dense array of hashes, reads legacy sparse/numeric JSON, and equips the full saved set once the horse is ready to render. Removing a tail uses the tail category, rather than the blanket category.

Equipment purchase and saving use one server callback. The server checks the owner, stable distance and currency, calculates the cost from configuration, saves free removals, and refunds a charged purchase if the database write fails. A failed save leaves the stable menu open. Editing another category retains the horse's existing saddle and blanket; switching horses clears the previous editing state.

The `jrs_stables-tack-fix.zip` package contains the complete `jrs_stables` resource plus the single corrected `jrs_core/client/animals.lua` file. Merge the core file into the existing resource; the package does not contain a complete core replacement. The files have already been installed in the provided resource paths. Restart the server to load both changes, then return and call the horse again to reload saved equipment. No live database migration or data editing is required by this fix.

Validation: actual Lua callbacks with a simulated database and entities, original/fixed wildlife coroutines, ownership/distance/payment/refund and legacy JSON cases, render readiness and respawn, Arabic/English browser purchase flow, existing horse training and wagon regressions. The server was not restarted and an in-game RedM test was not performed.
