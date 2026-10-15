# jrs_city

Version 1.2.1

Native RedM location notifications for `jrs_core`.

## How it works

The client reads RedM native map-zone hashes and resolves the current location using this priority:

1. Town
2. Printed map location
3. Written map location
4. Water locations
5. District
6. State

The notification is a single transparent NUI element, so its background, title, district, state, time, temperature and wind always appear and disappear together.

The bundled native zone metadata contains 320 mapped RedM zones.

## Install

```cfg
ensure jrs_core
ensure jrs_city
```

## Test

```text
/jrscitytest
```

With `Config.Debug = true`:

```text
/jrscitydebug
```

## Main settings

Edit `config.lua` to control notification size, position, duration, details and zone detection interval.

The default background is `html/assets/box_a_bg_1.png` and is rendered at 340px wide, smaller than its original 432px size.

## Exports

```lua
local zone = exports.jrs_city:GetCurrentZone()
local city = exports.jrs_city:GetCurrentCity()
local inValentine = exports.jrs_city:IsInCity('Valentine')
```


## Notification sound

The supplied MP3 is bundled as:

```text
html/assets/zone_open.mp3
```

Configure it in `config.lua`:

```lua
Config.Notification.Sound = {
    Enabled = true,
    File = 'assets/zone_open.mp3',
    Volume = 0.35,
}
```

The sound plays once each time a new zone notification is shown. It does not loop while the same zone remains active.
