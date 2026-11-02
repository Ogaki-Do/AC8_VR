PORTABLE GLOWFIX - CLEAN COMMUNITY TEST - 20 OCTOBER 2026

For the existing Colin / Mortem / Ogaki Ace Combat 8 VR profiles using the
shared AC8_VR-Runtime.dll. This is a glow connection fix, not a new profile.
It uses a standard OpenXR API layer instead of private UEVR backend addresses.
Requires DirectX 12, OpenXR and Native Stereo. OpenVR is not supported.
The connection is not tied to one UEVR build; other builds still need testing.

INSTALL (game closed)
1. Open your active UEVR AceCombat8 profile folder. Normally:
   %APPDATA%\UnrealVRMod\AceCombat8
   If using a linked/custom profile folder, use the folder UEVR actually loads.
2. Copy your entire existing plugins and scripts folders somewhere OUTSIDE
   the profile as a backup. Name it something recognizable, e.g. Before GlowFix.
   Do not leave a backup .dll in plugins: UEVR could load both copies.
3. Extract this ZIP elsewhere, then copy its plugins and scripts folders into
   AceCombat8, merging folders and replacing matching files. Keep all existing
   unrelated files. Do not delete your profile or replace its config.txt.
   Also replace an older scripts/AC8_VR-GlowFix.lua if it is present.
4. Start the game normally and inject UEVR. Enter a mission and check the HUD
   in the headset. Glow starts automatically. F9 toggles it for visual comparison.

WHAT TO TEST
- Can you see the authored glow in BOTH headset eyes? Compare F9 on/off.
- Pause/resume, leave/re-enter a mission and watch for missing/duplicated HUD.
- If you normally change resolution/window mode, check that glow recovers.
- Confirm your normal HUD layout, aircraft camera and controls still work.
Please DM Colin whether it works and any visual issue. No report/log collection
is required or included; a short description or optional headset video is enough.

WHAT THIS PACKAGE CHANGES
- Replaces plugins/AC8_VR-Runtime.dll: its glow renderer/connection is updated;
  the published non-glow native features are built from unchanged source.
- Adds plugins/AC8_VR-OpenXRBridge.dll and
  plugins/ac8-openxr-layer/AC8-glow.json (keep these together).
- Supplies the required plugins/ac8-hud-assets binary assets.
- Adds/replaces scripts/AC8_VR-GlowFix.lua: a small activation fallback only.
  Full profiles keep their existing glow controller and exclusion policy.
  The helper does not move widgets, change brightness, or alter saved settings.
  Appearance still depends on your profile's existing HUD brightness/policy.

No CPU profiling, GPU timing/readback, diagnostic recorder, report generation,
installer, checksum file or automatic upload is included. Normal UEVR plugin
load/error messages can still appear in UEVR's own log. Existing diagnostic
scripts from an earlier test are not removed by merging this ZIP: move those
out separately if you installed any. This package itself adds no such collector.

REMOVE / RESTORE (game closed)
Move the test plugins/scripts folders out of the profile, then copy your backed-up
plugins/scripts folders back into place. This restores overwritten assets/DLLs
and removes the added bridge/helper together. Keep the test copy elsewhere only
if you want it. No registry, global OpenXR runtime or saved graphics changes are
made by this patch; layer activation is process-local and ends with the game.

This is an offline-checked community test; this exact stripped package still
needs headset confirmation. The underlying portable connection was verified
locally before stripping the measurements. Do not mix with Colin's private
profiling/Features.bin build; that build uses a separate loader arrangement.
