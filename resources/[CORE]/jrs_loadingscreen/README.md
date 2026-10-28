# JRS Loading Screen

A sleek, optimized Western-themed loading screen designed natively for **JRS Core**.

---

## Overview

`jrs_loadingscreen` features video or background slideshow playback, audio management with master volume/mute controls, and seamless character selection handoff.

## Features

- **Media Support**: High-definition video background (`.mp4`) with automatic image slideshow fallback.
- **Unified Audio**: Master volume slider and instant mute toggle for background music and video audio.
- **Seamless Transition**: Coordinates handoff with the character system without cursor or focus conflicts.
- **Dynamic Avatar**: Fetches Steam or Discord avatar with local fallback and HTTP timeout safety.
- **Server Info**: Customizable rules, news cards, and staff display with responsive multi-resolution layouts (1080p, 2K, 4K).

---

## Configuration

| File | Purpose |
|---|---|
| `web/config_main.js` | Media settings (video/slider/music), server title, social links |
| `web/config_staff.js` | Team members, server rules, updates, and gameplay tips |
| `config/shared.lua` | Loading screen timeout and character skip options |
| `config/server.lua` | Steam API key and Discord avatar lookup configuration |

---

## Load Order

```cfg
ensure jrs_core
ensure jrs_loadingscreen
```

---

## License

Part of the **JRS Core** framework. Distributed under the **GNU General Public License v3.0**.
