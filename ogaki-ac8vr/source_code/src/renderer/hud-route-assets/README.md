# Renderer assets

Runtime inputs and build/reference material for the native HUD effect chain. `event-*` files hold authored constant-buffer data; `pso-*` files hold shader bytecode. Their numeric IDs are stable lookup keys used by `native_chain_specs.h`, not runtime capture outputs. `menu-deco-BC7.bin` supplies the authored texture.

`hud-*.dxbc` files are compiled from the mod HLSL by `source_code/build.ps1`; the two HLSL includes are editable shared helpers. When packaging, copy only the 44 filenames in `source_code/runtime-assets.txt` into `plugins/ac8-hud-assets`. The two `.hlsli` files, this README, all 13 `*-VS-rectangle.bin` files, and the four unused reference final-blend inputs (`pso-4278-VS.dxbc`, `pso-4278-PS.dxbc`, `event-3384-View.bin`, `event-3384-VS-constants.bin`) stay with source/reference material. No live image recordings or private test replays belong here.

These inputs include game-derived rendering material; see the repository third-party notices.
