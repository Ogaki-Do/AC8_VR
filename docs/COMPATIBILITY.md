# Compatibility

The accepted configuration uses Windows x64, DirectX 12, OpenXR and UEVR Native Stereo. Headset checks were performed on Quest 3; other combinations need confirmation.

The plugin uses public UEVR APIs and guarded private game/backend call sites. API-version compatibility alone is insufficient for every feature. Unsupported signatures leave the corresponding feature inactive; do not bypass those checks.

## Verified binaries

| Binary | SHA-256 |
|---|---|
| `UEVRBackend.dll` | `70CCBAAF4C357DEAACC3990FD01A911A029D31DCCF0E5ABC01C7A9073E4F50C1` |
| `AceCombat8.exe` | `51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F` |

The backend's installation folder is irrelevant. A public download/version label for this exact UEVR build must be supplied with the release; these hashes identify it without exposing a local path. Do not assume newer upstream versions have matching private addresses. UEVR and game executables are not bundled.

Maintainers can verify candidates with PowerShell `Get-FileHash -Algorithm SHA256` and their own local file path.

## Rendering assumptions

The glow path expects the validated 2560 × 1338 HUD source and supported OpenXR layer/resource formats. It requires current-frame scene/cylinder geometry and acquired/waited image ownership. The authored pass chain has fixed intermediate dimensions. Changing these assumptions requires source validation.

Headset testing remains necessary after binary, shader or cleanup changes. Automated checks cover geometry, guards and simulated lifecycle behavior; they cannot establish final headset appearance.
