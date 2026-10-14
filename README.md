# AC8 VR

**Version 0.1.0** — initial release candidate. Player download: `AC8-VR-v0.1.0.zip`. See [release history](CHANGELOG.md).

A UEVR profile and companion plugin for Ace Combat 8, focused on cockpit HUD placement, world targets, cinematic presentation, and transitions between menus and flight.

## Start here

- [Installation, updating and uninstalling](INSTALLATION.md)
- [Complete feature list](features.txt)
- [Settings and file responsibilities](docs/CONFIGURATION.md)
- [Source and maintainer guide](source_code/MAINTAINERS.md)
- [Compatibility](docs/COMPATIBILITY.md)
- [Credits and third-party notices](THIRD_PARTY_NOTICES.md)

Requires **UEVR** and the **Bypass EAC (Easy Anti-cheat) mod**. Instructions for setting up the bypass yourself are available in the **Flat2VR Modding Discord** (https://discord.gg/flat2vr). Neither prerequisite is included here.

Use the compatible UEVR build described in the compatibility guide, with **OpenXR, DirectX 12 and Native Stereo**. Native hooks validate specific game/backend binaries; another UEVR build may inject successfully while some enhancements remain disabled.

## Highlights

- Repositioned and scaled cockpit HUD, with wingman status following the radar's top edge.
- World-target label placement, preserved target introduction animation, and smaller off-screen indicators.
- Reconstructed native HUD glow with widget-specific blending and common radio-text treatment.
- Mission-loading cover and native fade handling, plus cinematic/hangar camera ownership and restoration.
- Pause-menu navigation that advances one entry per input.
- Editable per-aircraft camera positions and one-time HUD depth, scale and curvature defaults.

## Files

`scripts/`, `data/`, `plugins/`, `config.txt`, `cvars_data.txt` and `VERSION` form the installable profile. `source_code/` contains DLL/shader source, the build script and required rendering assets. Players do not need to compile anything.

The release uses **one DLL, nine runtime Lua scripts, and one Lua camera-settings file**. All distributed DLL/Lua names use the `AC8_VR-` prefix. Install the script set together; numeric load-order prefixes are unnecessary.

## Current limits

The tuned aircraft offsets are for the F/A-18C and F-4E. Other catalog identifiers are commented examples with default, unmeasured offsets. Wingman placement can briefly lag a radar change. Tutorial/movie content can still receive some HUD glow, and emission regions may remain visible during some dark transitions. Bottom-edge clipping of off-screen artwork remains a known limitation. Quest headset appearance can differ from a single-eye capture.

This is an unofficial community project. See the feature list for the implemented behavior and the maintainer guide for its boundaries.
