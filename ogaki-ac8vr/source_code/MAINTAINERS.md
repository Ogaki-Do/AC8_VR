# Maintainer guide

## Architecture

Lua owns game-object discovery, configuration, final widget placement and presentation intent. Native code owns validated draw corrections, duplicate-tick guards and D3D12/OpenXR work. The [file map](../docs/CONFIGURATION.md) describes every distributed DLL/Lua file.

Core waits for all section factories, then initializes them in explicit order, independent of filenames. Callback dispatch order is **presentation → layout → utility → intro**. Inherited HUD setup is deferred until HUDLayout enables it. Failed initialization requires a fresh Lua environment instead of retrying a partially initialized set.

Shared `R.context` tracks controller, HUD, root and a HUD identity epoch. Object calls require lifetime membership. Owned-widget walks are shared within one engine tick and invalidated with the epoch; incomplete walks retain fallback discovery. GameState resolves through the current controller with guarded fallback. Cache reflection metadata, not changing game-state results.

## Native modules

`modules.json` is the build manifest. `src/plugin.cpp` exports the UEVR entry points; the six translation units link into one DLL.

| Source | Responsibility |
|---|---|
| `src/cinematic/cinematic-game-hooks.cpp` | Presentation mask/camera/projection, F7 bridge, pause navigation, native fade, world labels and bomb corrections. |
| `src/hud/world-targets.cpp` | Reversible reflected billboard scaling. |
| `src/renderer/hud-renderer.cpp` | HUD texture observation, native glow, OpenXR handoff and per-eye composition. |
| `src/hud/hud-tick-guards.cpp` | Extra HUD/message viewport-tick suppression to preserve warning state. |
| `src/hud/offscreen-indicators.cpp` | Scoped locator geometry translation/scaling. |
| `src/hud/target-lock-reticle.cpp` | Automatically validated seeker artwork sizing. |

Source/header comments explain purpose and ownership. `src/backend` holds binary guards and XR ABI declarations. `src/renderer/native` contains the authored pass graph/root signatures. `src/renderer/hud-route-assets` is the source asset bundle; the matching player copy is `../plugins/ac8-hud-assets`.

## Building

Install Visual Studio C++ Build Tools with x64 MSVC and a Windows SDK containing `fxc.exe`. Vendored UEVR C headers are included; a UEVR source checkout is unnecessary.

From `source_code`:

```powershell
.\build.ps1
```

This discovers MSVC/SDK installations and builds with C++17, `/O2 /W4 /WX /MT`. Output is `build/AC8_VR-Runtime.dll`. The default also recompiles six mod HLSL entry points into the source asset directory. Use `-SkipShaders` only when shader source/includes are unchanged. Original native bytecode assets are required inputs, not generated from the mod HLSL.

After validation, copy the DLL into `../plugins` and copy only the 44 files listed in `runtime-assets.txt` from the source asset folder into `../plugins/ac8-hud-assets`. The source folder also contains shader includes and reference-only assets; keep those out of the player folder. Never package `build`. Restart the game to replace a loaded DLL.

## Runtime invariants

- **Cinematic ownership:** save settings before entry and keep recovery journals until restoration succeeds. PlaneCamera and HUD defaults defer to presentation ownership. F7 queues work onto the engine thread.
- **Camera settings:** apply absolute values only on aircraft/configuration/ownership changes. Preserve manual tuning between changes. Verify writes and roll back partial failures.
- **Loading:** the current game instance must own a visible active mission-loading screen. A persistent icon or newly created flight HUD is insufficient. Check pre/post engine phases; avoid arbitrary loading timeouts.
- **Pause/warning ticks:** preserve native updates; suppress only verified duplicate viewport routes for live owned objects. Unknown/mixed routes and stale evidence forward. Stack inspection is functional routing.
- **World labels:** temporary native metrics restore after the scoped update. Persistent box sizing stays in Lua so introduction animation remains native. Never compound the previous applied scale.
- **Target color:** limit changes to eligible current-world material instances. Keep original/last-written values and restore only while ownership matches. Do not broaden this to flattened cyan pixels.
- **Policy packets:** geometry still updates every frame. Reuse identical serialization/parsing, but send a full heartbeat each frame; native expiry is 250 ms of wall time. Invalid/expired packets clear policy.
- **GPU ownership:** current submission geometry and acquired/waited image permission are separate requirements. Serialize validation, GPU submission and release; preserve resource/fence ownership on failure/reset. Never write a released image.
- **Compatibility:** verify hash, PE metadata, instruction signatures and reflected layouts. Asset names alone do not prove runtime ownership or field offsets.

## Cadence

Wingman geometry runs every three engine ticks, with slower missing-widget rediscovery. Camera configuration is checked every 60 ticks. Policy candidates and pause objects have bounded discovery intervals; required state reads/heartbeats retain their cadence. Startup scanning ends after 90 engine seconds. Measure before adding per-frame global enumeration.

## Persistence and development support

Public capture hotkeys, debug dashboards, navigation/sample buffers and status writers are removed. Startup/error logging and in-memory control/error state remain. Restoration journals and layout cache remain because runtime recovery reads them. Texture copies, stack routing and activation readbacks are functional despite terms such as “capture” or “sample”.

Private tests and recorded fixtures stay outside public exports. Compile-time fixture seams in source are inert in normal builds; never define their macros for players. Exclude test directories/runners, captures, saved games, keys/extraction tools, backups and author-generated journals.

## Editing and validation

Comments should explain intent, ownership, coordinate spaces and restoration. Names should describe behavior. Existing event/JSON identifiers and schema `version` fields may remain for compatibility. Preserve vendor notices and community credit. Never insert personal paths.

For a hook change, update compatibility guards and private regression coverage before headset testing. Before release, check fresh launch, pause navigation, F/A-18C↔F-4E switching, radar modes, target introduction, tutorials/radio, loading and mission exit. Report automated checks separately from live acceptance.

## Package versioning

The root `VERSION` file is the public package version. Keep the README, installation guide, changelog, GitHub tag (`vX.Y.Z`) and player archive (`AC8-VR-vX.Y.Z.zip`) aligned. Increase the patch number for fixes and the minor number for added features while the project is pre-1.0. Do not replace an already published version with different contents. Internal Lua schema versions and UEVR API compatibility numbers are independent.
