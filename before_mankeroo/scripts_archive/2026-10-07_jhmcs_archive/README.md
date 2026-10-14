# JHMCS & 360° Target Tracking Project Archive
**Archive Date**: 2026-10-07  
**Game**: ACE COMBAT 8 (UEVR / OpenXR)  
**Status**: Paused / Archived

---

## 1. Project Objectives
- Achieve 360° off-boresight target tracking (JHMCS: Joint Helmet Mounted Cueing System) in VR.
- Maintain target boxes, distance text, callsigns, wingman indicators, and missile lock reticles visible and accurately positioned around the cockpit.

---

## 2. Key Findings & Architecture Discovered
1. **Target Container Architecture (`ChronicleTargetContainerActorBP`)**:
   - The game spawns a 3D Actor (`ChronicleTargetContainerActorBP_C` inheriting `LiveTargetContainerActor`) for each tracked target in the level.
   - It contains 11 components including:
     - `ContainerBox` (`MaterialBillboardComponent`): The target reticle square.
     - `DistanceText` (`TextRenderComponent`): Distance in meters.
     - `ObjectCallsignText` (`TextRenderComponent`): Target name / callsign.
     - `AllianceText` (`TextRenderComponent`): Friend/Foe alliance.
   - Physical Location: The containers are placed at the real 3D world coordinates in the sky (6,000m ~ 8,000m out), matching the target aircraft formation.

2. **Native HUD Combiner Culling Cone**:
   - AC8's `LiveTargetContainerManager` (outer: `LiveMainHUDParent4K_C`) runs a native C++ cone check for the forward cockpit HUD combiner (~25°-30° boresight).
   - Manipulating rendering camera FOV (`PlayerController:FOV`) does not bypass this HUD combiner check.

3. **Root Cause of Off-Screen Behavior ("機体真後ろに吸われるように移動していった")**:
   - When a target exceeds the forward HUD cone, the container's 3D update ceases or detaches.
   - Because the player jet is moving forward at high velocity (200~280 m/s), any 3D coordinate that stops updating or lags in world space creates an intense parallax effect from the cockpit perspective, appearing to be sucked directly behind the aircraft (6 o'clock).
   - In addition, flat-screen 2D screen-edge clamping algorithms invert coordinates mathematically when an object crosses the $Z < 0$ plane (behind the viewer).

4. **Engine Functions Discovered for Future Exploration**:
   - `LiveTargetSelectionComponent.SetIsWideMode(bool)`: Native wide-mode target acquisition.
   - `LiveTargetSelectionComponent.SetIsAngleFirst(bool)`: Angle-priority lock selection.
   - `LiveTargetSelectionComponent.GetAllLockedOnTargets()`: Lock array access.
   - `LiveTargetSelectionComponent.SelectedTarget`: Direct pointer to locked enemy Pawn actor (`BP_OP0018_uavc_CP_C` etc.).

---

## 3. Archived Files
- `ac8_m_jhmcs.lua` (v15: FOV + reflection + telemetry)
- `ac8_manager_deep_probe.lua`
- `Jhmcs.lua`
- `AC8_JHMCS_TEST_PLANA.lua`, `PLANB.lua`, `PLANC.lua`
- `data/ac8_native_range_probe.txt`: Log verifying live drone formation positions in 3D space.
- `data/ac8_target_parameters_dump.txt`: 39KB dump of container components and materials.
- `data/ac8_target_manager_probe.txt`: Reflection of `LiveTargetSelectionComponent` and manager UFunctions.
- `data/ac8_target_billboard_diagnostic.txt`
- `data/ac8_target_deep_dump.txt`

---

## 4. How to Restore
Copy `ac8_m_jhmcs.lua` back into:
- `%APPDATA%\UnrealVRMod\AceCombat8\scripts\ac8_m_jhmcs.lua`
- `D:\Ogaki\Desktop\Ace-uevr-test\scripts\ac8_m_jhmcs.lua`
