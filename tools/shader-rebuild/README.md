# AC8 VR optional shader rebuild tool (0.1.0)

This tool recompiles the six mod-authored HUD shaders using Windows' `d3dcompiler_47.dll`. It needs Windows PowerShell 5.1 or PowerShell 7, but no Visual Studio, Windows SDK, internet connection or administrator privileges. Extract the whole folder before running it. Do not copy it into UEVR's `scripts` directory.

**This is not a general fix for missing glow.** Shaders are portable DXBC bytecode; the GPU driver performs hardware-specific pipeline compilation. Rebuilding this bytecode does not prewarm the driver cache, add OpenVR support, support different private UEVR addresses, or remove the release's fixed HUD texture-size assumptions. The native game pass shaders are already bytecode and cannot be rebuilt from HLSL with this package.

## Rebuild only

Open PowerShell in this extracted folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AC8_VR-RebuildShaders.ps1
```

The execution-policy argument applies only to this process; the tool does not change saved system policy. Review the readable script before running it. The six results go into `compiled-shaders`. No game/profile files change in this mode. Nothing is downloaded, scheduled or installed automatically.

## Check the installed assets and rebuild

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AC8_VR-RebuildShaders.ps1 -ProfilePath "$env:APPDATA\UnrealVRMod\AceCombat8"
```

This checks the 44 required asset filenames and compares their hashes against release 0.1.0. Missing files stop the operation; changed files produce warnings because custom/rebuilt shaders can legitimately differ. It also checks the saved runtime choice. The saved choice does not prove which runtime is active in the game.

Optionally add `-UEVRBackendPath "D:\YourUEVRFolder\UEVRBackend.dll"` to compare the backend against the exact release-supported hash. Substitute your actual installation path. A mismatch is a compatibility warning, not an instruction to bypass the guard.

## Install the rebuilt custom shaders

Close Ace Combat first, then use the same command with `-Install`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AC8_VR-RebuildShaders.ps1 -ProfilePath "$env:APPDATA\UnrealVRMod\AceCombat8" -Install
```

All six shaders compile before any installed shader changes. Existing files are backed up in a unique folder under `compiled-shaders`; a replacement failure attempts to restore the complete backed-up set. The command prints the backup path. To undo a successful installation, close the game and copy those six backed-up files into the profile's `plugins\ac8-hud-assets` folder.

The DLL, Lua scripts, settings, native shader bytecode and the other assets are not replaced. Output can be redirected with `-OutputDirectory`; it must not be the installed asset folder.

## Validation and limits

Tested with PowerShell 7 and Windows PowerShell 5.1 on the maintainer's machine, including installation into an isolated mock profile. All six rebuilt files matched the release byte-for-byte there. This verifies the tool's local build path, not compatibility or frame time on another GPU.

For missing glow, verify OpenXR/DirectX 12, the exact UEVR build, complete assets, the actual HUD texture dimensions and whether the renderer is activating. See the companion modder guide for the source audit and performance investigation notes. This tool writes no recurring diagnostic logs and does not run inside the game.
