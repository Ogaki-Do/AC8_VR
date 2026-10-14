# Configuration and file ownership

## DLL and Lua files

| File | Responsibility |
|---|---|
| `plugins/AC8_VR-Runtime.dll` | Native rendering, OpenXR presentation, validated draw hooks, pause/HUD duplicate-tick guards and target geometry corrections. |
| `scripts/AC8_VR-Core.lua` | Startup order, callback dispatch, current HUD context, lifetime checks and shared configuration access. |
| `scripts/AC8_VR-InheritedHUD.lua` | Community-derived cockpit calibration, instrument/radar/ladder controls and flight camera-shake suppression. |
| `scripts/AC8_VR-CinematicPresentation.lua` | Automatic cinematic/hangar detection, UI/camera ownership, F7 override and restoration. |
| `scripts/AC8_VR-LoadingTransitions.lua` | Loading-screen ownership, black cover, game-state lookup and native fade source. |
| `scripts/AC8_VR-WorldTargets.lua` | Labels, persistent box sizing, introduction animation preservation, assignment pins and scoped material saturation. |
| `scripts/AC8_VR-UIRendering.lua` | Glow lifecycle, widget policy rectangles, tutorial backgrounds and pause-menu attachment. |
| `scripts/AC8_VR-PlaneCamera.lua` | Aircraft/cockpit detection and absolute UEVR camera offsets. |
| `scripts/AC8_VR-HUDLayout.lua` | Final layout, radar/wingman relation, loading indicator, bomb attachment and one-time presentation defaults. |
| `scripts/AC8_VR-StartupMovies.lua` | Allowlisted startup notice timings and movie seeks. |
| `data/AC8_VR-PerPlaneCameraOffsets.lua` | Editable camera values and commented aircraft catalog. Keep this data file in `data`. |

## HUD defaults

Edit `HUD_PRESENTATION` near the top of `AC8_VR-HUDLayout.lua`. Defaults are depth **1.0**, scale **1.0**, curvature **113.625**, enabled **true**.

Depth is UI distance in metres, scale is UI size, and curvature is cylinder angle in degrees. This also selects cylindrical UI. Values apply once per Lua session, after cinematic/hangar recovery releases ownership. Depth/scale must be 0.01–100; curvature must be 1–359. They do not change world scale or the plane camera. Set `enabled=false` to opt out.

## Aircraft offsets

`data/AC8_VR-PerPlaneCameraOffsets.lua` returns a settings table. `forward`, `right` and `up` are absolute UEVR menu values, each between -100 and 100.

- Default and F/A-18C: forward -18, right 0, up 5.
- F-4E: forward -10, right 0, up 5.
- Other aircraft: default until their commented row is enabled and tuned.

The exact `BP_PlayerPlane_..._C` key identifies an aircraft class. Detection uses the current view target and verifies its first-person camera owner. Edits are checked every 60 engine ticks. Invalid edits retain the last valid configuration; a missing file disables overrides. Disabling previously owned offsets restores the configured default. Cinematics/hangars retain priority. Manual camera tuning persists until the next aircraft/configuration/ownership change.

## Advanced data controls

These files live under `data`. Keep valid JSON syntax and edit one setting at a time. Legacy storage names and schema versions remain for compatibility.

| File | Purpose |
|---|---|
| `ac8_workshop_v2_controls.json` | Group and individual widget placement/scale using stable widget paths. |
| `ac8_workshop_effect_controls.json` | Optional inherited HUD material/effect treatment. |
| `ac8_workshop_target_controls.json` | World-target box, label/font scales and line spacing. |
| `ac8_world_target_controls.json` | Flat-style label offsets, left-label drop and cyan target-material saturation. |
| `ac8_offscreen_group_controls.json` | Whole off-screen group horizontal offset/scale. |
| `ac8_target_arrow_shift_controls.json` | Native locator offsets and common scale. |
| `ac8_wingman_status_controls.json` | Wingman placement, radar-follow behavior and gap. |
| `ac8_bomb_landing_controls.json` | Landing projection FOV adjustment. |
| `ac8_hangar_coverage_controls.json` | Horizontal/vertical cinematic and hangar coverage. |
| `ac8_pause_controls.json` | Scoped pause duplicate-tick guard. |
| `ac8_transition_controls.json` | Optional transition controls and native fade response; dedicated mission-loading ownership remains independent. |
| `ac8_tutorial_fill_controls.json` | Tutorial frame/background scale, alpha and inset. |
| `ac8_cinematic_intent_control.json` | Optional manual command with a new string `revision` and `action="toggle"`; F7 is simpler. |
| `ac8_escort_draw_scale_enabled.flag` | Enables native billboard scale support; preserve the supplied file. |

Generated `ac8_cinematic_ui_restore.json` and `ac8_hangar_restore_v48.json` are recovery journals, not defaults to share. `ac8_hud_layout_cache.json` stores local calibration. A legacy `ac8_ladder.json` may be read for custom instrument values; fresh installs use supplied controls and built-in defaults.

## Color and masks

Target saturation works on current-world dynamic material instances and checks their cyan color parameter, preserving alpha and peak energy. It does not classify flattened tutorial, ocean or text pixels as allies. Shared HUD composition still uses alpha/color coverage tests for dark panels, borders and black fades; it is not completely threshold-free. Radio follows common glow. The broad tutorial no-glow rectangle is not reinstated.
