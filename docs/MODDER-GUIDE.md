# AC8 VR: callbacks, polling and compatibility

Source audit: 14 October 2026, release 0.1.0 / commit `407028a`. This describes the released implementation, not a claim that its performance has been validated on every system. Community reports are useful leads; the reported CPU bottleneck, shader failure and script-reset leak have not yet been reproduced or measured by the maintainer.

## Short explanation for players

The mod runs small pieces of work at game-engine events. Timers decide when to look for newly created HUD objects, check edited settings, or adjust something the game has moved. Status labels describe the current state in memory; they are not automatically logs. Callback scheduling puts camera, layout and other operations in a predictable order.

That structure is necessary, but the implementation can still be inefficient. Finding many widgets or recalculating their geometry can be expensive even when done only periodically. Several scans falling on the same frame can produce a hitch. The next investigation should measure those operations, not assume that a variable named `status`, `report` or `nextScan` is itself the cause.

## How startup and scheduling work

Each public Lua file registers one or more section factories in `AC8VRModules`. `scripts/AC8_VR-Core.lua` waits for every required section before starting any of them, then initializes them in an explicit order. File loading order does not determine that order.

**Removing any one of the nine Lua files before a fresh script start can prevent the entire Lua runtime from starting.** An improvement after removing `AC8_VR-UIRendering.lua`, or another file, does not by itself identify that file as the expensive component. For isolation experiments, keep section registration intact and selectively bypass one operation in a controlled test build. Confirm `AC8VRModules.state` is `ready` and record which functions were disabled.

`R.host` supplies a callback adapter. `R.connect` registers one host callback per event type and dispatches registered functions in domain order: `presentation`, `layout`, `utility`, `intro`. Functions within a domain run in registration order. Each function is protected with `pcall`; the most recent error for that callback is retained in `R.errors`.

This is synchronous callback dispatch, not a pool of background workers or Windows scheduled tasks. Some callbacks are engine events and others are render-related events. Their ordering, object lifetime and thread context matter; moving work between them is not automatically safe.

`R.tick` advances at pre-engine-tick. Context also refreshes at post-engine-tick and pre-viewport draw without advancing that counter. A tick is **not** guaranteed to equal a headset refresh or an eye render. At 60 engine ticks/second, 30 ticks is about 0.5 seconds; at 120 it is about 0.25 seconds. Other timers accumulate callback delta time. These two kinds of interval should not be treated as interchangeable.

## Examples of actual schedules

| System | Released behavior | Reason and profiling concern |
|---|---|---|
| Shared HUD context | Pre/post engine tick and pre-viewport draw when connected | Tracks the current controller, HUD and root. Repeated reflected lookups have a cost. |
| HUD policy discovery (`AC8_VR-UIRendering.lua`) | About every 0.5 accumulated seconds | Enumerates UserWidgets, walks owned widget trees, and can fall back to global Widget enumeration. A primary hitch candidate. |
| HUD policy geometry | Post-engine-tick | Builds current visible/clipped regions and sends the policy heartbeat. Unchanged serialization is cached; geometry work still occurs. |
| Tutorial background handling (`AC8_VR-UIRendering.lua`) | Normally every 30 ticks; every tick while paused | Cached candidates are reused during an active tutorial, with periodic rediscovery. While paused without a matched tutorial, the current code can enumerate UserWidgets every tick. This is a concrete optimization candidate. |
| Wingman placement (`AC8_VR-HUDLayout.lua`) | Geometry check every 3 ticks; settings every 30; discovery retries every 60 | Follows radar size changes. Increasing delays saves work at the cost of visible lag. Existing-object checks differ from discovery. |
| Plane camera settings (`AC8_VR-PlaneCamera.lua`) | File reread every 60 ticks | Supports editing offsets while playing. Changed text is validated before replacing the current configuration. |
| Cinematic state (`AC8_VR-CinematicPresentation.lua`) | Camera classification about every 0.1 seconds; optional command every 0.25 seconds | Responds to cinematic/gameplay transitions and F7. The optional command JSON is absent from the current package; its guarded reader remains. |
| Shared JSON reader | Results, including missing files, cached for 30 ticks per filename | Reduces duplicate parsing. It still performs periodic file reads after expiry. |
| Mission-loading ownership (`AC8_VR-LoadingTransitions.lua`) | Pre/post engine checks; subsystem search retries every 60 ticks while missing | Keeps the cover in place through the transition into flight. Blindly throttling visibility checks can reintroduce flashes. |
| Startup movies (`AC8_VR-StartupMovies.lua`) | Searches about every 0.05 seconds during its first 90 accumulated seconds | A plausible opening/cinematic hitch contributor. The startup window is finite. |

These are representative high-interest paths, not a complete inventory of every callback. A loop's processing limit does not necessarily limit the cost of `get_objects_matching(false)`: the engine may build the full result before Lua starts iterating it.

## Status, diagnostics and file writes

The release still contains internal status strings, counters, error values and some stale development names. For example, `waiting_for_f9` remains a renderer state label even though the public runtime does not expose the old F9 debug toggle. Empty timed reporting branches also remain in a few Lua sections. These are cleanup debt, not evidence that a capture is running.

`R.log` is a no-op. Legacy Lua adapters receive that quiet logger. `R.errors` stores the latest error per callback in memory; it does not append an unbounded disk log. Repeated exceptions can still waste CPU, and some in-memory report tables still allocate data.

Native code retains initialization/failure messages through UEVR's logging API. These are distinct from the removed periodic capture/status dumps. The renderer catches some initialization failures internally and returns successful plugin initialization with rendering disabled, so a `glow initialized=1` message alone does **not** prove that glow is rendering.

The audited Lua file-writing sites are functional recovery/calibration writes:

- `ac8_cinematic_ui_restore.json`: saved presentation settings for restoration.
- `ac8_hangar_restore_v48.json`: saved hangar settings for restoration.
- `ac8_hud_layout_cache.json`: local layout calibration.

Core's write allowlist also includes legacy `ac8_ladder.json`; that permission alone is not an active writer. Shader/constants assets named `event-*` and `pso-*` are packaged renderer inputs, not files captured from a user's session. The source audit found no active old Right Arrow capture/report writer.

Do not remove restoration journals or error handling just because they look diagnostic. To investigate I/O, measure writes and their frequency in the affected state. Do not add per-frame file logging to a frame-time problem.

## Why missing glow is not necessarily shader compilation

The bundled `.dxbc` shaders are DirectX shader bytecode. The graphics driver performs hardware-specific compilation when creating pipeline state. They are not an NVIDIA-only or author-PC shader cache. Rebuilding the six mod-authored shaders can check source compilation or replace missing/corrupt bytecode, but is not a general AMD, headset or UEVR compatibility fix. The native game pass shaders are supplied bytecode, without HLSL source in this repository.

The released glow path has these separate limitations:

1. **OpenXR and DirectX 12.** OpenVR does not have the equivalent per-eye glow submission path in this release.
2. **Exact UEVR backend.** The bridge verifies a backend SHA-256 and private wrapper instruction signatures before attaching. A different nightly may fail those checks. Do not remove checks while retaining the same hard-coded addresses. A portable replacement should obtain supported OpenXR entry points through the API and retain session/image ownership validation.
3. **HUD texture dimensions and format.** Generation expects a 2560 x 1338 BGRA source. That is a texture size, not the user's monitor or headset resolution. A different source size is rejected. Supporting it requires a deliberate scaling/resource strategy, not just deleting the size comparison.
4. **HUD class/layout assumptions.** Several Lua systems recognize `LiveMainHUDParent4K_C` literally, and some controls use authored layout units. This is a portability concern; the class name alone does not prove the game selects another class on FHD. Capture the actual class and painted geometry before generalizing it.
5. **Submission validation.** The effect requires a current scene projection and curved HUD layer, compatible formats, full copy coverage and valid acquire/wait/release ownership. Unsupported layer layouts or reset states can leave glow disabled.

Relevant sources: `source_code/src/renderer/openxr_handoff.h`, `hud_route_glow.h`, `native/native_generation.h`, `hud-renderer.cpp`, and `scripts/AC8_VR-Core.lua` / `AC8_VR-UIRendering.lua`.

Microsoft references: [shader compilation](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-part1) and [Direct3D shader caches](https://microsoft.github.io/DirectX-Specs/d3d/ShaderCache.html).

## How to produce useful comparisons

Record the release/commit, exact UEVR build or backend hash, GPU/driver, CPU, OpenXR runtime, stereo method, in-game resolution/window mode, headset resolution/refresh, and whether the test follows a fresh game start or script reset. If available, record the actual UI texture dimensions and current HUD class. These are different measurements.

Separate no-glow, misplaced-HUD, periodic-hitch and sustained-low-FPS reports. Compare one change at a time in the same mission/camera state. Include CPU/GPU frame times and hitch timing, not only average FPS or GPU utilization.

Measure callback duration, discovery count and returned object count with opt-in bounded instrumentation. Report aggregates after the test, avoiding object addresses, personal paths and continuous dumps. Distinguish time spent in the Lua body from time inside reflected engine calls. Compare fresh launch against repeated script resets before calling a growing-memory observation a confirmed leak; retained callbacks/resources, garbage collection and driver caches need separate investigation.

Promising changes are owner-scoped discovery, invalidation when HUD ownership changes, caching candidate identities while checking lifetimes, reducing paused non-tutorial rescans, and distributing expensive searches across ticks. Preserve current-frame geometry, pause transitions and GPU resource ownership checks. Every optimization needs behavior tests as well as frame-time evidence.

The current compatibility priority is OpenXR across resolutions, GPU vendors and UEVR builds. OpenVR requires separate work. This audit does not establish a single cause for all community reports.
