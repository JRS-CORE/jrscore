fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

lua54 'yes'

author 'JRS TEAM'
description 'jrs core Character System'
-- v4.0.4: fixed client-side freeze during new character creation - added
-- GetGameTimer() timeout guards to unbounded model/component/anim streaming
-- wait loops in the finalize/apply-appearance chain (Data_Character_Load,
-- ReloadCloth, HasBodyComponentsLoaded, NPCAssetsToPed, IsPedReadyToRender,
-- NativeUpdatePedVariation, UpdateCustomhairstyle/Clothes, loadskinjrs,
-- globalApparence/EyeColourValue anim dict waits) so a stalled streamed
-- asset can no longer hang the creator forever.
-- v4.0.5: same fix applied to sexeStatusChanged and PedTrueFalse - clicking
-- the Sexe or "play as a ped" toggle on the first creator screen swaps the
-- preview model via an unbounded HasModelLoaded wait, which froze the whole
-- creator (and its cursor) if that model failed to stream. Also replaced the
-- native <input type="date"> birth date field with a click-only day/month/
-- year picker: native date/select popups in the RedM NUI overlay open as an
-- OS-level surface the game's cursor hook doesn't route clicks into, which
-- both allowed typing nonsense dates (e.g. year 9999) and could itself lock
-- up the mouse.
-- v4.0.7: English / Arabic picker on the spawn-city book. It routes through
-- the existing chooseLanguage() -> jrs_core:SetLanguage path (no second
-- language setting), and the book now carries Arabic copy (Config.SpawnBook.Ar
-- and each city's Ar) so the whole page switches, not just its buttons.
-- v4.0.8: new characters failed to save after picking a spawn city.
-- characters.character_desc was latin1, so Arabic lore threw mid-creation and
-- left a bare character (no clothes/hair/birth date) at jrs_core's default
-- spawn. Column self-heals to utf8mb4, JRSCleanText is UTF-8 safe, a failed
-- creation rolls its row back, printconsole no longer drops error text, and
-- the first spawn gets barber data. Also: creator panels lighter + creation
-- form spacing.
-- v4.0.10: characters with no jrs_character_creator row (left behind by a
-- creation that threw mid-save) spawned with no legs/lower body. The spawn
-- payload sent empty peddata, so the client fell back to the legacy
-- ReloadCloth path. The server now rebuilds peddata from skinPlayer
-- (ResolveCreatorPedData), matching GetPedData.
-- v4.1.0: UI reskinned to the jrs_stores look (ui/css/character_theme.css):
-- store master texture + dark overlays, header plate, #292929/#c4c0b8 tab
-- frames, square corners, neutral greys; Arabic keeps its own face.
-- v4.1.1: fixed "EDIT APPARENCE" -> "EDIT APPEARANCE" typo in en locales;
-- Reset button in the appearance editor now re-applies its translated label
-- every time the menu opens (was only set once at boot, froze at that
-- locale); removed Valentine entirely from the new-character Spawn Book
-- (config/config.lua Config.SpawnBook.Cities).
-- v4.1.2: Spawn Book (ui/css/spawn.css) reskinned to match the jrs_stores
-- look used by the rest of the creator - store master texture panels,
-- square corners, Georgia/Arial typography, #292929/#4a4a4a/#c4c0b8 tab
-- frames - instead of its old standalone leather-book design. Class names
-- and layout are unchanged so ui/script.js needed no edits.
-- v4.1.3: reverted the v4.1.1 main-loop cursor-forcing change outside the
-- character-creation gate - it made the native mouse cursor render
-- persistently even outside the creator UI, a regression from the previous
-- (correct) behavior. Loop is back to its exact pre-session form. Added
-- JRSSafeNetworkConceal(): guards every NetworkConcealPlayer call (native
-- 0xBBDF066252829606) behind NetworkIsPlayerActive so it is skipped instead
-- of hard-crashing the client when called before the local player is a
-- fully registered network entity (seen as "SCRIPT ERROR: native
-- bbdf066252829606: exception at address RedM_b1491_GTAProcess.exe+...").
-- v4.1.4: real fix attempt for the invisible-native-cursor bug (ported from
-- the never-deployed 2026-09-18 cursor-toggle-fix design, since the backup
-- that would have carried it holds the pre-fix code, not the fix itself).
-- RedM can silently no-op SetNuiFocus(true,true)/SetCursorLocation(x,y) when
-- it already believes that is the current value - no state transition, no
-- CEF pointer redraw - leaving the cursor invisible even though our tracked
-- flags say focus/cursor are applied and nothing ever retries. Added
-- JRSNudgeCursorLocation() (lands on a neighbouring point first so the
-- recenter is always a genuine delta), JRSRecoverNuiCursor() now forces a
-- real SetNuiFocus(false,false)->(true,true) edge instead of repeating
-- (true,true), and the main loop gained a periodic 4s unconditional call to
-- JRSRecoverNuiCursor() while focus/cursor are wanted, independent of
-- whether the tracked flags look correct. Static analysis only - not yet
-- verified against a live client.
-- v4.1.5: (1) live-tested batch of fixes from user screenshots. Removed
-- Occupation entirely: HTML input, ui/script.js validateCharacterIdentity,
-- server.lua's ch_occupation_is_required gate, AND a second, previously
-- missed client.lua-side validateCharacterIdentity() (client/client.lua,
-- the NextChar NUI callback) that silently rejected with no visible error
-- once the field no longer existed in the DOM - this was the real remaining
-- blocker on "Next". (2) creatorHasActiveEditTarget() (ui/script.js) now
-- also treats #GlobalCharacterMenu as an active edit target, so the
-- rotate/zoom View Controls panel shows on the pins/body-map screen too,
-- not only once a sub-panel (hair, eyes, etc.) is open. (3) closed an
-- admin/staff slot-limit loophole: Config.Creator.Slots.role in
-- config/config.lua granted owner/superadmin/admin/mod/vip/server_owner/
-- full_access 3-5 character slots regardless of Config.Char_Count; cleared
-- to {} so every account, staff included, is capped at 1. Verified live
-- against jrs_users - 5/5 accounts already at chars<=1 before this change,
-- but the role table would have overridden that for any staff login.
-- v4.1.6: Skin Tone / Eye Colour swatches (ui/css/character_theme.css
-- .coloursDiv, #ColourListEye) rebuilt to match jrs_clothing's and
-- jrs_barber's tint-picker look (their appearance_theme.css #TintSettings
-- .coloursDiv / #ColourList) - a 6-column card grid on the store master
-- texture with a lift+glow hover/selected state - instead of the old plain
-- row of small round dots. Rebuilt on this file's own --jc-* tokens since
-- NUI pages can't share CSS custom properties across resources. Verified
-- in the static preview harness (see reference_nui_inline_preview_harness
-- memory) - renders as a proper grid, selection glow confirmed via
-- :has(.Colour.selected), which this CEF build already uses successfully
-- in jrs_clothing/jrs_barber.
-- v4.1.7: the Palette control (clothing/barber advanced values) replaced the
-- 0-255 circular meter with jrs_clothing's own numbered-chip picker
-- (.jrs-actual-color-chip/.jrs-actual-color-grid - the SAME component its
-- native colour picker uses, verified by reading jrs_clothing/ui/clothing/
-- script.js's jrsRenderActualVariantPicker, since its appearance_theme.css
-- .coloursDiv/#ColourList grid turned out to be dead/unused CSS, not the
-- live picker). Scoped to Palette only (small discrete option count,
-- capped at 24 chips with a circular-meter fallback above that) - the
-- continuous 0-255 tint sliders (primary/secondary/detail dye) are
-- unchanged, since jrs_clothing has no live equivalent for those either.
-- New ui/script.js buildPaletteChipMarkup(); new .jrs-actual-color-* rules
-- in ui/css/character_theme.css on this file's own --jc-* tokens.
-- v4.1.8: Skin Tone/Eye Colour swatches from v4.1.6 were too big (grid
-- columns filled the panel's full width) - fixed cell size to a compact
-- 28px (repeat(auto-fill, 28px)) instead of 6 stretchy fr columns, closer
-- to the pre-v4.1.6 26px dots. Eye Colour swatches inside Global Settings
-- (createEyeColourGlobalSelector) were sharing the EyeColourValue callback
-- with the face-pin eye editor, which forces a head-zoom camera move +
-- DisplayPins=false on first use - fine for the pin popup, but yanked the
-- camera and hid the pins/panel when triggered from the wide Global
-- Settings shot instead. Global Settings now sends skipCameraFocus=true
-- and the callback (client.lua EyeColourValue) honours it. Also hardened
-- creatorCategoryLabel() to never surface a bare hash/id (e.g.
-- "-1132439862") as an item name - falls back to "Accessory" instead of a
-- raw number when nothing readable is left after cleanup. Bumped the
-- creator's two attached lamp props' intensity (10.0/5.0 -> 14.0/8.0) for
-- better player visibility, per user request; a full lighting-system port
-- from elsewhere was not attempted this pass (kept scope to a safe tuning
-- given the current 2-point rig is already reasonable).
-- v4.1.9: (1) Palette chip cap raised 24 -> 30 (makeup categories default
-- to a 25-option palette, which was one over the old cap and fell back to
-- the circular meter). (2) Palette chip block now unshifted to the front
-- of the inline settings grid (top-left), matching jrs_barber's own layout
-- instead of wherever it fell in the advancedValues array order. (3) New
-- SelectorLight(): Character Selection uses the same dim interior (78337)
-- as the creator but had no lighting of its own (Light() only ever
-- targeted CachePed, not the selector's per-slot preview peds) - added one
-- static hanging lamp at the selector camera's look-at point, on for as
-- long as the selector is open. No player-facing brightness control yet
-- (scoped out this pass, deliberately, given how much else changed
-- tonight - revisit as its own follow-up).
-- v4.2.0: real native-colour chip picker for the barber/hair "Style"
-- control, matching jrs_clothing's actual jrsRenderActualVariantPicker
-- mechanism (not just the Palette control from v4.1.7). Lua side
-- (client.lua, the JRS_ASSETS[...].variants branch of the hairstyle
-- contextual-data builder ~line 7000) now dedupes variants by their real
-- signature (albedo/normal/material/palette/tint - identical fields
-- jrs_clothing's menufunction.lua keys on, confirmed by inspecting its
-- ClothingAssets table shape, which JRS_ASSETS mirrors) and sends
-- actualColorOptions/nativeColor alongside the existing tints/variation
-- data. UI side: new buildNativeColorChipMarkup() (ui/script.js), shown
-- above the Style meter when native colour options exist, posts through
-- the SAME sendVariation()/varValue endpoint the Style slider already
-- uses - no new apply-side plumbing, so the existing (working) variant
-- application path is unchanged. Scoped to barber/hairstyle drawables only
-- (the screenshots in this thread were all "HAIR & BARBER"); clothing
-- garment items were not touched - their variant/tint data wasn't traced
-- this pass, and clothingContext already skips advancedValues/tints
-- entirely today.
-- 4.2.1: fixed "character spawns in the wrong place" during the very first
-- CHARACTER INFO screen for brand-new players. releaseLoadingPresentation's
-- 'creator' reveal used to fade the screen back in a flat 80ms after Chromium
-- painted the form, with no link to the saloon room (CreatorConfig.CharSelect,
-- interior 78337) actually streaming in. On a cold join that room isn't
-- loaded that fast, so the player was revealed standing in the raw unstreamed
-- exterior terrain instead of the bar. Added waitForCreatorSceneReady(): a
-- bounded (4s) poll on HasCollisionLoadedAroundEntity + IsInteriorEntitySetActive
-- for every CharSelect.interior_sets entry, same pattern already used for the
-- final in-world spawn (client.lua ~9985) and the death respawn (~2489). Only
-- the 'creator' path waits; 'selector' and the 45s forced-recovery path are
-- untouched. If streaming never finishes, it still reveals after the timeout
-- instead of leaving the player on a stuck black screen.
-- 4.2.2: fixed the appearance editor's body-part pin lines crossing wildly
-- across the screen (dot for one label appearing near a screen corner,
-- connected by a long diagonal line to its correctly-placed card). Cause:
-- OpenApperanceMenu (client.lua ~6434) discarded the visibility flag that
-- GetScreenCoordFromWorldCoord returns for the head/eyes/facial/mouth/chest/
-- thigh/clothes bones and sent whatever x/y it got back regardless - when a
-- bone falls outside the current editor camera framing (routine while the
-- camera is zoomed into a single category, e.g. the head/face close-up), that
-- x/y is unreliable and can land anywhere up to the screen edges, while the
-- label itself stays where it was first placed. Added resolvePinScreenPos():
-- when a bone reports not-visible this frame, reuse that pin's last known
-- good screen position instead of the unreliable one, self-correcting once
-- the bone is back in view. Same fix pattern the character selector's own
-- pin code already used (client.lua, checks `visible == true` before adding
-- a selector pin) - the appearance editor's pins just never had it.
-- 4.2.3: three follow-ups from the same "wrong place" report, reproduced by
-- the user needing to Cancel and re-enter the creator before it looked
-- right. (1) waitForCreatorSceneReady's bound was raised 4s -> 12s - 4s
-- was not enough for this room's IMAP dressing to stream on a cold join.
-- (2) The clothing/barber item settings panel (client.lua's built-in
-- OutfitMenu, ui/script.js) used to be moved into the selected row and
-- laid out inline, pushing the rows below it down. It now stays in its
-- static index.html slot and floats top-right via CSS (position: fixed,
-- ui/css/inline_item_settings.css), matching the real jrs_clothing/
-- jrs_barber resources' #VariationSettings panel position - same screen
-- slot, same --creator-edge-x/-y responsive vars. Only where it renders
-- changed; its content/behaviour (native colour chips, tone sliders,
-- circular meters) is untouched. (3) The creator room's attached key
-- lights (client.lua's Light()) looked underlit next to the room's bright
-- candle/chandelier decor, more noticeable on the clothing editor's closer
-- camera framing - intensity raised 14.0/8.0 -> 20.0/12.0, now driven from
-- one constant per lamp instead of three separately hardcoded literals.
-- 4.2.4: Creator room lighting boosted from 20.0/12.0 -> 45.0/25.0 to resolve
-- underexposed character models against the bright candle background, and
-- made configurable via Config.Creator.Lighting in config.lua.
-- 4.2.5: Completely resolved appearance editor body-part pin displacement and
-- crossing connector lines when zooming in or focusing on the character.
-- (1) Swapped world-offset projections with ped-local offsets via
-- GetOffsetFromEntityInWorldCoords, ensuring accurate feature points that rotate
-- cleanly with the character. (2) Strictly enforce viewport visibility: bones
-- outside camera frustum/screen bounds (e.g. legs and upper body when zoomed
-- into the head) report visible = false and are immediately hidden in NUI
-- instead of lingering across the chest with long lines. (3) Dynamic card
-- layout in script.js with vertical anti-overlap distribution (distributeSide)
-- and safe boundary clamping outside the player silhouette. (4) Added dedicated
-- "Toggle Pins" button in View Controls and keyboard shortcut ('H').
-- 4.2.6: fixed "SCRIPT ERROR: attempt to call a nil value (global
-- 'RefreshInterior')" crashing the creator's interior-prep step
-- (preparePlayerForCreator, the wait-for-scene-ready poll, and the final
-- in-world spawn reveal all called the bare RefreshInterior(intId) native
-- after ActivateInteriorEntitySet). RefreshInterior isn't defined as a
-- global in this RedM build (jrs_moonshine already worked around the same
-- gap via pcall - see its client/main.lua refreshInterior helper); all three
-- call sites here now guard with `if type(RefreshInterior) == 'function'`
-- before calling it, matching this file's existing native-guard pattern
-- (e.g. `type(SetEntityAlpha) == 'function'`) instead of crashing the client.
-- 4.2.7: (1) ui/script.js's loadContextualDatas crashed with "Cannot read
-- properties of undefined (reading 'forEach')" whenever a "variation"
-- category's contextualData arrived with no tints array (legitimate - not
-- every variation category has a tint control) - the crash aborted the rest
-- of that render pass, which could leave sibling categories in the same
-- batch (including skin/hair/eye colour swatches) unrendered. Guarded with
-- `(contextualData.tints || [])`. (2) ui/css/character_theme.css - a
-- complete, already-written restyle of the whole creator (proper spacing,
-- the responsive short-window rules, RTL layout fixes, the Language Menu's
-- real look) - was never linked from index.html, so the creator had been
-- rendering on the older, rougher global_menu.css layout underneath it the
-- whole time; linked it last as its own header comment already says it's
-- meant to. (3) Added the language switcher the existing
-- setLanguageSwitchVisible()/PRE_SPAWN_SCREENS/#LanguageMenu plumbing was
-- already built for but never had a button wired to it (setLanguageSwitchVisible
-- targeted a '#LanguageSwitchAction' id that did not exist in index.html) -
-- new '#OpenLanguageMenu' button next to the Character Info header, using the
-- already-translated 'language.change' key, shown/hidden by the same
-- PRE_SPAWN_SCREENS mechanism that already covers every pre-spawn screen.
-- 4.2.8: appearance-editor body-part pins (Head/Eyes/Face/Mouth/Upper Body/
-- Clothes/Legs) - the label card's screen position was captured once when a
-- pin first appeared and never moved again, while its dot kept tracking the
-- body part live every ~45ms; once the camera moved (zooming into a
-- category close-up) the dot drifted away from its frozen card and the
-- connector lines stretched out and crossed each other. ui/script.js's
-- updateDotPos now re-anchors the whole pin (card + dot) to the live
-- coordinate every tick, so the card always tracks its body part at a
-- fixed short offset instead of drifting apart from it.
-- 4.2.9: the Identity Registry step (jrs_idcard's registration form, opened
-- via StartNewCharacterCreationSession from ContinueCreator/
-- BackToApparenceFromSpawn) could stop accepting keystrokes in any field a
-- few seconds after opening. jrs_character never releases its own
-- jrsNuiFocusWanted flag during that handoff (by design, so it can reclaim
-- focus when the player comes back), but its background focus watchdog
-- treats that flag as "my UI still needs focus" and, every 4 seconds,
-- deliberately forces a genuine SetNuiFocus(false,false) -> (true,true) edge
-- to work around a RedM quirk where repeating the same focus value is a
-- no-op (see JRSRecoverNuiCursor). That edge is harmless while jrs_character's
-- own page holds the focused element, but while jrs_idcard's registry page
-- has a text field focused instead, the transient false blurs it - so typing
-- would reliably break roughly every 4 seconds. Added jrsExternalUiFocusActive,
-- set true right before handing off to jrs_idcard and cleared the moment its
-- onComplete/onCancel callback returns control; the watchdog's periodic
-- re-commit (450ms) and forced cursor-recovery edge (4s) both skip while it's
-- true, leaving jrs_idcard's own focus/cursor handling alone.
-- 4.2.10: coming back from the Identity Registry (both to City Selection and
-- back to Appearance) left the mouse looking frozen for a beat. jrs_idcard's
-- 'create'/cancel NUI callbacks call its own setMenu(false) - a genuine
-- SetNuiFocus(false, false) - right before invoking the onComplete/onCancel
-- callback added in 4.2.9; that callback only cleared jrsExternalUiFocusActive
-- and let the normal watchdog notice global focus was gone on its next
-- ~450ms poll, which was a visible/occasionally-sticky delay rather than an
-- immediate handoff. Both onComplete and onCancel closures (in ContinueCreator
-- and BackToApparenceFromSpawn) now call JRSApplyNuiFocus(true, true, false)
-- straight away to reclaim focus for the spawn book / appearance editor the
-- instant control returns, instead of waiting on the watchdog.
-- 4.2.11: appearance-editor body-part dots could still land on top of each
-- other (head/eyes/face/mouth are only a few centimeters apart in world
-- space, which projects to a handful of screen pixels once the character
-- is small on screen, e.g. the creator's overview zoom before a category
-- is picked). ui/script.js's positionPin now runs a small declutter pass
-- (declutterDotPositions) that nudges any two visible dots closer than
-- 34px straight apart before positioning them, so the circles stay
-- distinct instead of overlapping.
-- 4.2.12: two fixes for "sometimes a player doesn't get spawned/respawned
-- properly, or ends up seeing a broken model / the character creator
-- instead" reports. (1) server/server.lua's loadCharacters() silently
-- returns when jrs_core already reports the player's character as ready -
-- the intended guard against reopening the selector on a stale request -
-- but this exact branch also fires whenever THIS resource alone is
-- restarted while a player stays connected mid-session: jrs_core keeps its
-- own state (character still "ready"), but this resource's client script
-- reloads from scratch, and client/client.lua's `characterGateActive` local
-- defaults to true on every fresh script load (freezing controls, hiding
-- HUD/radar) until the normal selector/creator flow clears it - a flow that
-- never runs again for an already-ready character, leaving the player stuck
-- frozen/HUD-less until a full reconnect. The server now also sends a new
-- `jrs_character_creator:AlreadyReady` event in that branch; the client
-- releases the gate (SetJRSCharacterGate(false, 'already_ready_resync'))
-- only if it was actually still active, a no-op for every other call to
-- getCharacters. (2) client/client.lua's FinalizeCharacter reveal gate
-- already bounds its component-streaming wait to 8s and reveals anyway past
-- that point rather than risk a permanent black screen (a deliberate,
-- pre-existing tradeoff on the heaviest cold joins) - but if that bound was
-- hit, nothing ever tried again, leaving a visibly broken ped (e.g. an
-- unstreamed placeholder/box-shaped head) for the rest of the session.
-- Added a bounded (15s) background watcher that keeps checking
-- NativeHasPedComponentLoaded and fires one NativeUpdatePedVariation
-- refresh - not a re-request, just a render refresh of components already
-- requested - the moment streaming actually finishes, so the visual
-- self-corrects without requiring a relog.
-- 4.2.13: the appearance-editor Face/Mouth pins still crossed lines even
-- after 4.2.8/4.2.11's live-tracking and declutter passes. Root cause: the
-- mouth pin's dot (rightOffset -0.04) lands on the same screen side as the
-- head/facial dots once the character-facing-camera mirroring is accounted
-- for, right next to the facial dot - but its label card was hardcoded to
-- float the OPPOSITE direction ("left") from facial's card ("right"), so
-- their connector lines swept across each other's territory. Flipped
-- mouth's `direction` to "right" (client.lua, OpenApperanceMenu's mouth
-- pin) so its card floats the same side as its neighbours and the lines
-- stay parallel.
-- 4.2.14: Identity Registry (jrs_idcard's registration form, opened via
-- ContinueCreator/BackToApparenceFromSpawn) could render but not accept any
-- click or keystroke - reported live after 4.2.9's jrsExternalUiFocusActive
-- flag and jrs_idcard's own setMenu() re-assert (2.3.5) were both already in
-- place, so neither alone was the full fix. Root cause: jrs_character's own
-- creator page already holds SetNuiFocus(true, true) at the moment it hands
-- off to jrs_idcard; jrsExternalUiFocusActive only stops jrs_character's
-- watchdog from re-committing that same value, it never actually releases
-- it. jrs_idcard's own SetNuiFocus(true, true) call on open is therefore the
-- exact same silent same-value no-op JRSRecoverNuiCursor above already
-- documents for this RedM build - the CEF page paints (ui_page swap is
-- independent of focus) but input routing never makes a real transition, so
-- nothing responds. Both ContinueCreator and BackToApparenceFromSpawn now
-- call JRSApplyNuiFocus(false, false, false) - a genuine release - right
-- before invoking StartNewCharacterCreationSession, so jrs_idcard's own
-- acquisition is a real off->on edge; the existing JRSApplyNuiFocus(true,
-- true, false) reclaim in both completion/cancel callbacks was already
-- correct and untouched.
-- 4.2.15: reported live right after 4.2.14 - "Continue"/create out of the
-- Identity Registry started responding, but "BACK TO APPEARANCE" (cancel)
-- still froze input. 4.2.14 only forced a genuine focus edge going INTO
-- jrs_idcard; the comment on the create-side reclaim assumed jrs_idcard's
-- own callback always runs setMenu(false) first, but its cancel path
-- apparently does not do the same release consistently, so the existing
-- JRSApplyNuiFocus(true, true, false) reclaim on return could still repeat
-- an already-true value and no-op. Both reclaim points (create and cancel)
-- in ContinueCreator and BackToApparenceFromSpawn now force their own real
-- SetNuiFocus(false, false) drop immediately before reclaiming, so neither
-- depends on jrs_idcard's own release behavior on either path.
-- 4.2.16: reverted 4.2.13's mouth `direction = "right"` (client.lua) back to
-- "left" - it stopped one crossing but strayed from the murphy_creator
-- reference's head/mouth vs eyes/facial pairing, and would break again for
-- a different camera state. Real fix: ui/script.js's createPin now decides
-- each pin's card side itself (pinActualDirection), from where its dot
-- actually lands relative to the cluster's on-screen centre when the menu
-- opens, instead of a fixed per-category guess - every card floats away
-- from the centre, so connector lines point outward and never sweep across
-- a neighbour's, for whatever camera angle/zoom the menu happens to open
-- at. The per-category `direction` field in client.lua's pin tables is now
-- a fallback only.
-- 4.2.17: reverted 4.2.16's dynamic card-side computation on explicit
-- request - the user wants the appearance-editor pins matching
-- murphy_creator exactly, not a self-correcting layout. ui/script.js's
-- createPin/positionPin are back to using client.lua's per-category
-- `direction` literally (head/mouth left, eyes/facial/upperbody right,
-- clothes/lowerbody left - already identical to the murphy_creator
-- reference). Kept 4.2.8's live dot+card tracking and 4.2.11's dot
-- declutter, since those are plain stability fixes, not a style choice.
-- 4.2.18: appearance-editor pin ACCURACY, not the crossing/style issue -
-- Mouth's dot was offset -0.04 to one side + 0.07 forward off the head
-- bone, landing near the jaw/cheek instead of the lips (mouth is a midline
-- feature, it shouldn't be offset sideways at all); centered it and pulled
-- it closer to the face. Clothes' dot was only -0.10 below the chest bone
-- (collar height), barely separated from Upper Body's own dot; dropped to
-- -0.35 (torso-middle/stomach height), clearly between Upper Body and
-- Legs as requested.
-- 4.2.19: appearance-editor pin offsets ported directly from
-- murphy_creator's own values (client/NUI/NUIMessages.lua) instead of
-- further guessing - head/eyes/facial/mouth now use Murphy's exact
-- magnitudes (0.07 side, 0.10/0.05/-0.07/-0.03 up) and chest/thigh are
-- dead-centered with only a Z drop (-0.20/-0.50), matching Murphy exactly.
-- forwardOffset dropped to 0 everywhere (Murphy never pushes forward,
-- only side+up) - that forward push was likely why dots drifted off their
-- real anatomical spot under perspective at close zoom. Kept this file's
-- own rightOffset sign convention rather than Murphy's literal signs,
-- since ped-local right and Murphy's raw world-X are different axes and
-- flipping signs would have desynced the direction="left"/"right" pairing
-- fixed in 4.2.17. Clothes kept its own centered/torso-middle tuning
-- (Murphy's own clothes offset is a large sideways shop-icon placement,
-- not an anatomical spot, and would undo the "middle of the body" fix).
-- 4.2.20: DIAGNOSTIC ONLY (not a fix) - "BACK TO APPEARANCE"/"Continue" from
-- the Identity Registry reported live as still freezing with zero console
-- errors even after 4.2.14/4.2.15's genuine-focus-edge fixes, and in the
-- latest report neither direction shows any menu at all. No print in
-- console means we cannot tell how far execution actually got before it
-- stalled. Added ^5[jrs_character][diag]^7-tagged print() calls at every
-- step of ContinueCreator/BackToApparenceFromSpawn (NUI callback fired,
-- identity valid/invalid, jrs_idcard export found or not, right before/after
-- calling StartNewCharacterCreationSession, entry of both onComplete/
-- onCancel callbacks, right before the OpenApperanceMenu() infinite-loop
-- call). A matching set was added to jrs_idcard/client/client.lua's
-- 'close'/'create' NUI callbacks and StartNewCharacterCreationSession
-- (coordinate with whoever owns that file before removing). Next repro:
-- open F8 BEFORE clicking, reproduce, and read which [diag] lines did and
-- did not print to localize the stall to a specific side/step. Safe to
-- strip once the real cause is found.
-- 4.2.21: proved Murphy's fixed head/mouth-vs-eyes/facial pairing cannot
-- stay crossing-free once the camera is close enough (a user screenshot's
-- exact traced coordinates mathematically crossed Head-with-Eyes and
-- Mouth-with-Face, despite the pairing itself being correct - Murphy's
-- own fixed, more distant camera likely never hit this). ui/script.js's
-- createPin now brute-forces every left/right combination for just the
-- 4 head-area pins (the only ones sharing a bone, and the only ones ever
-- seen crossing), scores each by real geometric clearance (segment
-- min-distance, not just non-intersection - a near-touch still reads as
-- crossing once real font metrics shift a pixel or two), and among the
-- safe combinations keeps the one closest to Murphy's own pairing.
-- Verified against 4 real screenshots' exact traced coordinates (a live
-- static-server + postMessage harness, not guessing): the one that
-- actually crossed now renders with zero crossings, and the three that
-- were already fine keep Murphy's exact default with zero pins moved.
-- 4.2.22: reverted 4.2.21's crossing-avoidance side resolver on explicit
-- request - even fully zero-crossing, it regrouped which pins share a
-- side (e.g. head+eyes instead of Murphy's head+mouth) whenever a shot's
-- geometry needed it, and the user wants murphy_creator's exact fixed
-- pairing with no exceptions, not a self-correcting one. ui/script.js's
-- createPin/positionPin are back to using client.lua's per-category
-- `direction` literally, with no override - identical to 4.2.17. This
-- reintroduces the possibility of the two lines crossing again at an
-- extreme close zoom, exactly as murphy_creator's own code would in that
-- case - a deliberate, requested tradeoff, not an oversight.
-- 4.2.23: restored 4.2.21's crossing-avoidance side resolver - reverting
-- to pure Murphy pairing (4.2.22) reproduced the same crossing again
-- within the same live test session, confirming Murphy's fixed pairing
-- and guaranteed-no-crossing genuinely cannot both hold at every camera
-- distance. ui/script.js's createPin/positionPin resolve each cluster
-- pin's side from real geometry again (brute-force + min-distance safety
-- margin, matching Murphy's own default whenever that default is already
-- crossing-free).
-- 4.2.24: "blurry flat terrain / wrong place" in the creator, take two.
-- waitForCreatorSceneReady (client.lua) had three real gaps: (1) it called
-- RequestCollisionAtCoord ONCE before the loop - a collision request only
-- lasts the frame it is made, so HasCollisionLoadedAroundEntity could not
-- reliably turn true; it now re-requests collision + IMAPs every 50ms tick.
-- (2) nothing pointed the streamer at the room (only the ped moved); added
-- SetFocusPosAndVel + NewLoadSceneStartSphere for the wait (ClearFocus is
-- already done by stopAllLoadingScreens right after). (3) the bound was 8s
-- in the code even though 4.2.3 documented 12s; now 20s, plus a fixed 1.5s
-- settle window after collision loads so the distant LOD is swapped out
-- before the fade-in. Still bounded - it never leaves the player stuck.
-- Backup: _jrs/_backups/character_scene_ready_2026_09_19. NOT live-verified.
-- 4.2.25: requested "wait as long as it takes until the room, the player and
-- everything are ready". waitForCreatorSceneReady now also requires the ped
-- to be IsPedReadyToRender, its hard bound is 3 minutes (dead-man net only),
-- and armLoadingPresentation's 45s emergency release no longer forces the
-- creator reveal while that wait is running (it re-checks every 5s).
-- 4.2.26: creator UI audit. Static checks (JS syntax, referenced files, NUI
-- callbacks, EN/AR key parity, _U keys) were clean except 8 t() keys with no
-- locale entry: the Reset / Cancel-creation / Delete-character confirm dialogs
-- and their buttons always showed English in Arabic. Added them to
-- ui/locales/en.js + ar.js; the Reset dialog got its own key
-- (charCreation.resetWarning) since it shared cancelWarning with a different
-- 4.2.27: fixed player spawning half-buried / sunken into the ground.
-- FinalizeCharacter previously set the ped to `coords.z - 1.0` to force
-- collision loading, but never restored the ped to the accurate ground surface
-- after collision finished loading, leaving the ped standing one metre deep.
-- Both FinalizeCharacter and JRSPerformDeathRespawn now dynamically query
-- GetGroundZFor_3dCoord (with PlaceEntityOnGroundProperly fallback) to snap
-- the player cleanly on top of the terrain before playing the wake-up animation
-- and revealing the screen.
-- 4.2.28: fixed character selector ped sinking / burying into the ground.
-- waitForSelectorSceneReady previously used SetEntityCoordsNoOffset with the
-- queried ground surface height, which ignores ped bounding box and aligns the
-- ped's pelvis with the terrain, leaving the lower body 0.9m underground.
-- Replaced with SetEntityCoords (with proper ped offset) and PlaceEntityOnGroundProperly
-- so character selector peds stand cleanly on top of the terrain.
-- 4.2.29: fixed in-game admin character selection reselection handoff:
-- 1. openSelectorFromAdmin immediately blacks out the screen and arms loading presentation so player
--    never sees character unloading or naked template ped in the wild.
-- 2. Fixed loadingHold passing true to NUI on in-game switches due to GetResourceState('jrs_loadingscreen') == 'started',
--    which permanently hid SelectCharMenu pins and create button behind CSS jrs-loading-hold. Replaced with JRSIsExternalLoadingScreenActive().
-- 3. Fixed MoveCam aborting when CachePed is nil, and re-asserted scripted camera + RenderScriptCams after SetPlayerModel recreation.
-- 4.2.31: fixed "SCRIPT ERROR: @jrs_character/client/client.lua:5020: bad argument #1
-- to 'for iterator' (table expected, got nil)" occurring when loading barber overlays
-- and hairstyle components. barber_overlay_all_layers was uninitialized when clotheitem
-- was invoked with overlay ~= false, causing pairs(barber_overlay_all_layers) to crash.
-- Also added defensive table guards for barberCache, makeup, permanent, and baseoverlay
-- across clotheitem, loadbarberoverlay, loadbarberoverlayOnCharacter, RemoveOverlays,
-- and ReequipAllhairstyle.
-- 4.2.32: creator View Controls + edit panel "sometimes stuck".
-- Toggle Pins toggled on pointerdown AND click, so it never changed; now
-- click only. Up/Down/Center no longer auto-repeat (each restarted a 1s cam
-- interp every 55ms). A lost pointerup no longer leaves a hold or the drag-
-- rotate running (pointer capture, buttons==0 check, 6s hold cap). NUI
-- latest-value channels free themselves after 1.5s if Lua never answers
-- (was 10s of dead buttons); creatorViewControl is pcall-wrapped and
-- sliderCharChange guards unknown ids so both always cb. Edit panel title
-- had a stray data-i18n="character_nose" (every panel read Nose); list is
-- cleared before rebuild. Backup: _jrs/_backups/character_view_controls_2026_09_24.
-- 4.2.33: clicking a field in the identity form sometimes "zoomed". The
-- window-focus cursor recovery toggled NUI focus off/on right after the click,
-- dropping the caret, so typed W/A/S/D hit the camera shortcuts. Recovery now
-- skips when the player just clicked / a text field is focused; camera keys
-- are off while the identity form is open or any text field has focus; the
-- wheel only zooms over the scene, never over a panel or field.
-- 4.2.34: full robustness pass ("fix the character script completely").
-- server: jrs_inventoryApi resolved lazily - the load-time export call threw
-- "No such export" (seen in fxserver.log) when jrs_inventory was starting,
-- aborting the rest of the runtime module (dead_state etc. never registered);
-- Hair_Pomade registration retries and re-registers on jrs_inventory restart.
-- Server callbacks now answer rate-limited/unknown requests (false, reason)
-- instead of dropping them, so the client never waits forever.
-- client: new client/nui_guard.lua wraps every RegisterNUICallback in pcall
-- and always answers the page once (a Lua error used to hang the button for
-- 10-40s). Bounded the last unbounded waits: loadDataToPed, legacy skin
-- Head/BodyType ready loops, loadskin model load (15s), selector ped model
-- (15s + mp fallback for removed/invalid models), skin-tone albedo wait (10s).
-- GetPedData reload no longer crashes on a false/nil reply (it left
-- processingLoadSkin stuck and wiped CachePedData).
-- Backup: _jrs/_backups/character_full_fix_2026_09_24. NOT live-verified.
-- v4.2.37: Identity Registry (jrs_idcard new-character form) now arrives
-- pre-filled with height (180 cm x ped scale), complexion (skin tone), hair
-- colour (tint0 -> RDO_HAIR_COLORS name, "Bald" with no hair) and eye colour,
-- in the player's language (JRSBuildIdCardAppearance). Fields stay editable;
-- returning from the spawn book keeps what the player typed.
-- v4.2.38: height formula. scale = HeightMin + (slider/100)*(HeightMax-HeightMin),
-- cm = round(HeightBaseCm[gender] * scale) (HeightBaseCm Male 180 / Female 168
-- in data/client.lua). JRSHeightToCm (client.lua) feeds the ID registry;
-- creatorHeightCm (ui/script.js) shows it live on the Height slider ("180 سم")
-- instead of "Style 50". Male 171-189 cm, Female 160-176 cm.
version '4.2.52-jrs-service'

dependencies {
    'oxmysql',
    'jrs_core',
    'jrs_inventory',
    'jrs_clothing',
    'jrs_barber'
}

shared_scripts {
    '@jrs_core/shared/jrs_lang.lua',
    'locales/*.lua',
    'config/config.lua',
    'data/shared.lua'
}

client_scripts {
    '@jrs_core/shared/pad_guard.lua',
    '@jrs_core/shared/jrs_lang_nui.lua',
    '@jrs_clothing/shared/clothing/assets.lua',
    '@jrs_clothing/shared/clothing/builtin_footwear.lua',
    'data/client.lua',
    'client/nui_guard.lua',
    'client/client.lua',
    'client/language.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

ui_page 'ui/index.html'

files {
    'ui/**/*'
}

exports {
    'loading',
    'IsCharacterReady',
    'IsCharacterGateActive'
}

export 'getMaleFromLang'

escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'data/*.lua',
    'ui/locales/*.js',
    'sql/*.sql',
    '*.sql',
}

