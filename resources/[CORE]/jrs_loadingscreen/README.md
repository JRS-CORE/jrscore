# jrs_loadingscreen 2.5.0

JRS loading screen for RedM with direct `jrs_core` / `jrs_character` handoff.

## Start order

```cfg
ensure jrs_core
ensure jrs_loadingscreen
ensure jrs_character
```

## Main configuration

UI/media settings are in `web/config_main.js`.

### Video

```js
VIDEO: {
    ENABLE: true,
    VIDEO: "background.mp4",
    MUTE_VIDEO: false,
},
```

When video is enabled, the image slideshow is automatically inactive at runtime.
The first local image remains available only as an instant fallback while the MP4 starts.

### Images

```js
IMAGES: {
    ENABLE_SLIDER: true,
    SLIDER_DURATION: 10000,
    ENABLE_OVERLAY: true,
    OVERLAY_FRAME_DURATION: 80,
    ENABLE_BORDER_IMAGE: true,
    IMAGE_LIST: [
        { NAME: "image_1.jpg" },
    ],
},
```

Images are used only when `VIDEO.ENABLE` is `false`.

### Audio

`MUSIC.VOLUME` is the initial master volume (0-100). The volume slider controls both
music and audible video audio. Mute also controls both sources.

`VIDEO.MUTE_VIDEO = true` is a hard lock: shared controls will never unmute that video.
When video audio is enabled, music does not auto-play over it. If `MUSIC.ENABLE` is
`false`, only the master Mute/Volume controls remain visible; music-only transport
buttons are hidden.

The player's master mute/volume choices are stored locally by the loading screen.

## Character Selection / SKIP

With the matching JRS character integration:

1. Character Selection paints behind the loading screen.
2. `jrs_character` emits `jrs_loadingscreen:client:characterSelectionReady`.
3. The character UI exposes the English `SKIP` control.
4. Pressing SKIP closes the loading screen immediately.
5. If SKIP is not pressed, `Config.CharacterSkip.autoCloseSeconds` closes it automatically.
6. Character Creator closes the loading screen immediately when its presentation is ready.

Default:

```lua
Config.CharacterSkip = {
    enabled = true,
    buttonText = 'SKIP',
    autoCloseSeconds = 60,
}
```

`jrs_loadingscreen` never calls `SetNuiFocus`. Cursor ownership belongs to
`jrs_character`, avoiding the loadscreen/character mouse race.

## Player avatar

Avatar priority in `source = 'auto'` mode:

1. Steam avatar
2. Discord avatar
3. Local default avatar

Configure in `config/server.lua`.

Steam key in `server.cfg`:

```cfg
set jrs_loadingscreen_steam_api_key "YOUR_STEAM_WEB_API_KEY"
```

Discord bot token in `server.cfg`:

```cfg
set jrs_loadingscreen_discord_token "YOUR_BOT_TOKEN"
```

Never place either secret in the resource files.

Profile HTTP requests have a timeout (`Config.ProfileLookup.httpTimeoutMs`) so a slow
Steam/Discord service cannot leave a player stuck connecting indefinitely.

## UI content

- Main UI/media/social config: `web/config_main.js`
- Team/hints/news/rules: `web/config_staff.js`
- JRS/close/SKIP settings: `config/shared.lua`
- Steam/Discord settings: `config/server.lua`

Visible UI text is English-only.

## 2.5.0 audit fixes

- Corrected resource manifest to `fx_version 'cerulean'`.
- Removed all regular-NUI focus ownership from the loading resource.
- Rebuilt video/music mute and volume as one consistent master audio state.
- Removed the video mute listener that previously undid the shared mute button.
- Prevented disabled video from preloading/playing from static HTML.
- Video and image slideshow are mutually exclusive at runtime.
- Fixed image mode when overlay transitions are disabled.
- Fixed carousel positioning for 1-4 cards (no duplicate slot reuse).
- Reduced carousel auto-scroll work using `requestAnimationFrame` timing.
- Removed the external Font Awesome dependency; interactive controls use local glyphs.
- Added Steam/Discord HTTP timeout fallback.
- Fixed stale manifest/readme versioning and removed obsolete behavior documentation.
- Preserved HD / 1080p / 2K / 4K responsive layout rules.
