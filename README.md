# C200 Controller

A small native macOS app for the **Anker PowerConf C200** webcam (USB `291a:3369`). It shows a live preview, gives you sliders and switches for the camera's settings, saves presets, and keeps your settings applied when the camera is reconnected.

Not affiliated with Anker.

## Build

```sh
./build.sh            # builds build/C200 Controller.app
./build.sh install    # also copies it to ~/Applications
```

You only need the Xcode Command Line Tools. The app has no third-party dependencies. It's ad-hoc signed, so after each rebuild macOS asks for camera permission again.

## Controls

| Section | Controls |
|---|---|
| Framing | Field of view presets (95° / 78° / 65°), zoom 1–4×, pan/tilt ±10° |
| Image | Brightness, contrast, saturation, sharpness, gamma |
| Exposure & Color | Auto exposure or manual exposure time, auto white balance or temperature, anti-flicker |
| Focus | Autofocus or manual focus |
| Anker | HDR, mirror image |

Sliders only appear for controls the camera reports. Their ranges and defaults come from the camera. The arrow next to a value resets it to the camera's default.

## Presets and re-applying

- **Presets** save every setting except values an auto mode is controlling (for example, exposure time while auto exposure is on).
- The app remembers the last settings and re-applies them **on launch** and **whenever the camera is plugged back in**. The camera forgets its settings when it loses power.
- **Closing the window** keeps the app running in the background so it can keep re-applying settings. Open the app again to bring the window back. Quit with ⌘Q.
- **Launch at login** (bottom of the sidebar) starts the app in the background at login, with no window. macOS may ask you to allow it under System Settings › General › Login Items.

Settings are stored in `~/Library/Application Support/C200 Controller/settings.json`.

## How it works

The app sends standard UVC class requests to the camera's control pipe through IOKit (`Sources/CUVC`). It doesn't claim the USB interface, so video apps keep working while it runs. Anker's extra features live on vendor extension unit 6. FOV, mirror and HDR byte layouts come from [anker-powerconf-c200-linux-tools](https://github.com/erans/anker-powerconf-c200-linux-tools).

Camera quirks found while building this (firmware 7.5):

- **FOV presets are zoom shortcuts.** 95° = zoom 100, 78° = 175, 65° = 295. The app saves and re-applies the zoom value.
- **Mirror and HDR writes are ignored unless the camera is streaming.** The app watches for any app starting a stream (CoreMediaIO's "running somewhere" property) and re-sends them.
- **HDR always reads back as on**, so the app trusts its own saved value.
- **Sharpness below 50 reads back on a stretched scale while streaming.** For example, written 42 reads back as 36 and written 0 reads back as 217. The app corrects this when it reads the camera.
- **Hue** is advertised (range 0–3) but does nothing, so it's hidden.
- **Backlight compensation** reports a range of 0–0, and **gain** isn't supported.
