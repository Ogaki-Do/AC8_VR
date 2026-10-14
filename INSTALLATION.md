# Installation

For **AC8 VR 0.1.0** (`AC8-VR-v0.1.0.zip`). The included `VERSION` file identifies this package.

## Requirements

- Ace Combat 8 for Windows, using the supported game build.
- **UEVR**, with the compatible backend described in [Compatibility](docs/COMPATIBILITY.md). Official site: [uevr.io](https://uevr.io/).
- The **Bypass EAC (Easy Anti-cheat) mod**. Instructions for doing this yourself are available in the **Flat2VR Modding Discord**, linked from the [UEVR website](https://uevr.io/).
- A working PC VR headset and OpenXR runtime; DirectX 12 rendering.

UEVR and the EAC bypass are separate prerequisites. Install UEVR wherever you prefer: the mod does not use a fixed path to `UEVRInjector.exe`.

## Install

1. Close the game. Back up your existing per-game UEVR profile, especially custom camera/layout settings.
2. Press **Win+R**, enter `%APPDATA%\UnrealVRMod\AceCombat8`, and open the folder. Create it if necessary. This is the profile for `AceCombat8.exe`.
3. Copy `VERSION`, `config.txt`, `cvars_data.txt`, `scripts`, `data`, and `plugins` from this package into that folder. Do not create an extra enclosing release folder.
4. Check that `plugins\AC8_VR-Runtime.dll`, the adjacent `plugins\ac8-hud-assets` folder, all nine scripts, and `data\AC8_VR-PerPlaneCameraOffsets.lua` are present.
5. Start your headset's PC VR connection and OpenXR runtime. Launch the game using your EAC-bypass setup, then run `UEVRInjector.exe` from **your own UEVR installation folder**.
6. Select `AceCombat8.exe`, choose **OpenXR**, enable plugins, and inject. The supplied profile uses Native Stereo. General injection/runtime setup is covered by the [official UEVR guide](https://docs.uevr.io/usage/overview.html).

Expected layout:

```text
%APPDATA%\UnrealVRMod\AceCombat8\
  VERSION
  config.txt
  cvars_data.txt
  scripts\AC8_VR-*.lua                 (nine files)
  data\AC8_VR-PerPlaneCameraOffsets.lua
  data\ac8_*                           (supplied settings)
  plugins\AC8_VR-Runtime.dll
  plugins\ac8-hud-assets\...
```

`source_code` and the guides are reference material. Do not put this DLL in the game's executable directory. The [UEVR plugin documentation](https://docs.uevr.io/plugins/getting_started.html) describes the per-game plugin location.

## Customization

HUD depth, scale and curvature apply once per script session from `HUD_PRESENTATION` near the top of `scripts\AC8_VR-HUDLayout.lua`. Later UEVR-menu adjustments remain for that session. Restarting or reloading scripts reapplies the Lua defaults; set `enabled=false` to opt out.

Edit camera values in `data\AC8_VR-PerPlaneCameraOffsets.lua`. `forward`, `right` and `up` are absolute UEVR menu values. Edits are checked every 60 engine ticks. Manual camera tuning stays until an aircraft/configuration change or return from cinematic/hangar ownership. See [Configuration](docs/CONFIGURATION.md).

Cinematics/hangars are detected automatically. **F7** is a manual presentation toggle; ordinary flight does not require it. Right Arrow is not a capture key in the public runtime.

## Updating

Close the game and back up the profile. Preserve your custom camera file and edited HUD/layout settings, then compare them with new defaults before restoring them. Replace the DLL, complete script set and asset folder together.

When upgrading from development builds, remove their old AC8 DLLs and Lua scripts before copying this set. An old combined runtime or diagnostic script can duplicate callbacks. Keep unrelated plugins/scripts unless their author documents a conflict.

Runtime recovery/cache JSON files are local state, not files to share with other players. Keep cinematic/hangar restoration journals during normal updates.

## Uninstalling

Close the game. Restore your backed-up per-game profile, or remove the mod files listed in `PROFILE-FILES.txt`: its scripts, settings, DLL and `ac8-hud-assets` folder. Restore your previous `config.txt` and `cvars_data.txt` to recover your prior UEVR settings. Leave unrelated files alone.

After uninstalling, you may also remove generated `ac8_cinematic_ui_restore.json`, `ac8_hangar_restore_v48.json` and `ac8_hud_layout_cache.json` from `data`. This does not uninstall UEVR, the EAC bypass or the game.

## Troubleshooting

- **Default HUD / no changes:** check folder nesting, missing Lua files, plugins disabled in the injector, and duplicate older scripts. Restart after correcting the installation.
- **Glow/presentation missing:** check OpenXR, DirectX 12, the asset folder and exact compatible game/backend builds. Guards intentionally disable unsupported hooks.
- **Camera does not change:** use cockpit view, check the aircraft key/Lua syntax, and let loading or cinematic ownership end. Untuned aircraft use the default row.
- **Manual HUD settings reset:** restarting or reloading scripts starts a new defaults session. Disable the defaults table to use your own saved settings.
- **Reporting problems:** include aircraft, game state and reproduction steps. Review logs/screenshots for personal information before sharing.
