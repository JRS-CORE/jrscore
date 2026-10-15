# JRS Stables 2.2.2 — menu presentation and sounds

The horse and wagon menu is now 500 pixels wide (previously 420), with a viewport limit for smaller screens. Currency purchase controls have a dark gray textured background, a visible border, hover/focus feedback, and grayscale money/gold images. Confirmation payment controls use the same treatment.

Four new original local WAV samples provide a soft menu opening, closing, selection tap and purchase confirmation. They replace the old leaderboard opening/closing sounds. Language and horse/wagon family refreshes do not replay the opening or closing sound. Volume is set to `0.28` near the top of `ui/js/stable-sounds.js`; samples are under `ui/audio/` and are declared in the manifest. Horse feeding and care sounds are separate from this menu change.

The update is installed in the provided live `jrs_stables` resource. Run `restart jrs_stables` to load it. The resource was not restarted by the assistant.

Verified in browser previews for Arabic and English at 1920x1080, 1280x720, 800x600 and 390x844: layout, purchase buttons, original buying callbacks, transparent page background, sound triggers and decoding. Existing horse selection, training, revival, equipment persistence and wagon UI regressions passed. Audio playback in RedM itself has not been tested.
