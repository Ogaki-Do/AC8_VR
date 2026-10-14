# AC8 VR source

Read [MAINTAINERS.md](MAINTAINERS.md) for architecture, build steps and invariants. `modules.json` lists the six modules linked into `AC8_VR-Runtime.dll`; `src/plugin.cpp` supplies its exported entry points.

Lua lives in [../scripts](../scripts). Shader/native assets are in `src/renderer/hud-route-assets`, with installation copies in `../plugins/ac8-hud-assets`. Preserve vendor notices under `vendor/uevr`.
