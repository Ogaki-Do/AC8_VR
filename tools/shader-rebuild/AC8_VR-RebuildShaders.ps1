# Optional offline utility. Never place this file in UEVR's scripts directory.
# Rebuilds portable DXBC, not a hardware-specific driver pipeline cache.
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'compiled-shaders'),
    [string]$ProfilePath,
    [string]$UEVRBackendPath,
    [switch]$Install
)
$ErrorActionPreference = 'Stop'
if ($Install -and -not $ProfilePath) { throw '-Install requires an explicit -ProfilePath.' }
if ($Install -and (Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue)) { throw 'Close Ace Combat before installing shaders.' }
Write-Output 'Rebuilding six mod-authored Shader Model 5 shaders using Windows D3DCompiler.'
Write-Output 'This does not warm the GPU driver cache or fix unsupported OpenVR, UEVR builds, HUD sizes or layouts.'
if ($UEVRBackendPath) {
    $hash = (Get-FileHash -LiteralPath $UEVRBackendPath -Algorithm SHA256).Hash
    if ($hash -ne '70CCBAAF4C357DEAACC3990FD01A911A029D31DCCF0E5ABC01C7A9073E4F50C1') {
        Write-Warning 'This backend differs from the 0.1.0 supported build. Rebuilding shaders cannot make its private hooks compatible.'
    } else { Write-Output 'Backend matches the 0.1.0 supported build.' }
}
$specs = @(
    @('hud_route_preview.hlsl','VS','vs_5_0','hud-route-VS.dxbc'),
    @('hud_route_preview.hlsl','PS','ps_5_0','hud-route-PS.dxbc'),
    @('hud_policy_pass.hlsl','MaskPS','ps_5_0','hud-mask-PS.dxbc'),
    @('hud_policy_pass.hlsl','PrefilterPS','ps_5_0','hud-filter-PS.dxbc'),
    @('hud_route_scene.hlsl','SceneVS','vs_5_0','hud-scene-VS.dxbc'),
    @('hud_route_scene.hlsl','ScenePS','ps_5_0','hud-scene-PS.dxbc')
)
$sourceRoot = Join-Path $PSScriptRoot 'shader-source'
foreach ($name in @('hud_route_preview.hlsl','hud_policy_pass.hlsl','hud_route_scene.hlsl','hud-route-assets/hud_route_authored_helpers.hlsli','hud-route-assets/scene_mapping.hlsli')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $name) -PathType Leaf)) { throw "Missing source: $name. Extract the entire tool package first." }
}
if ($ProfilePath) {
    $assetRoot = Join-Path $ProfilePath 'plugins/ac8-hud-assets'
    $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $resolvedAssets = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($assetRoot)
    if ($resolvedOutput.TrimEnd('\','/') -eq $resolvedAssets.TrimEnd('\','/')) {
        throw 'OutputDirectory must be separate from the installed asset folder; use -Install for backed-up replacement.'
    }
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime-assets.sha256.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.PSObject.Properties) {
        $path = Join-Path $assetRoot $entry.Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing runtime asset: $($entry.Name). Install the complete player package first." }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.Value) {
            Write-Warning "Asset differs from release 0.1.0: $($entry.Name). It may have been customized or rebuilt."
        }
    }
    $config = Join-Path $ProfilePath 'config.txt'
    if (Test-Path -LiteralPath $config) {
        $text = Get-Content -LiteralPath $config -Raw
        if ($text -match '(?m)^Frontend_RequestedRuntime=(.+)$' -and $Matches[1].Trim() -ne 'openxr_loader.dll') {
            Write-Warning 'Saved profile selects a runtime other than OpenXR. The released per-eye glow path requires OpenXR.'
        }
    }
}
if (-not ('AC8VRShaderCompiler' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AC8VRShaderCompiler {
    [ComImport, Guid("8BA5FB08-5195-40E2-AC58-0D989C3A0102"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface Blob {
        [PreserveSig] IntPtr GetBufferPointer();
        [PreserveSig] UIntPtr GetBufferSize();
    }
    [DllImport("d3dcompiler_47.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    private static extern int D3DCompileFromFile(string file, IntPtr defines, IntPtr includes,
        [MarshalAs(UnmanagedType.LPStr)] string entry,
        [MarshalAs(UnmanagedType.LPStr)] string profile, uint flags, uint flags2,
        out Blob code, out Blob errors);
    public static byte[] Compile(string file, string entry, string profile) {
        Blob code = null, errors = null;
        try {
            // Same O3 and warnings-as-errors flags as source_code/build.ps1.
            int hr = D3DCompileFromFile(file, IntPtr.Zero, new IntPtr(1), entry, profile,
                (1u << 15) | (1u << 18), 0, out code, out errors);
            if (hr < 0) {
                string message = errors == null ? "No compiler detail" : Marshal.PtrToStringAnsi(errors.GetBufferPointer());
                throw new InvalidOperationException("Shader compilation failed: " + message);
            }
            if (code == null) throw new InvalidOperationException("Compiler returned no bytecode.");
            int size = checked((int)code.GetBufferSize().ToUInt64());
            byte[] bytes = new byte[size];
            Marshal.Copy(code.GetBufferPointer(), bytes, 0, size);
            return bytes;
        } finally {
            if (code != null) Marshal.ReleaseComObject(code);
            if (errors != null) Marshal.ReleaseComObject(errors);
        }
    }
}
'@
}
# Compile the entire set before writing any output or installed shader.
$compiled = @{}
foreach ($spec in $specs) {
    $source = (Resolve-Path -LiteralPath (Join-Path $sourceRoot $spec[0])).Path
    $bytes = [AC8VRShaderCompiler]::Compile($source, $spec[1], $spec[2])
    if ($bytes.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'DXBC') { throw 'Compiler returned invalid bytecode.' }
    $compiled[$spec[3]] = $bytes
    Write-Output "Compiled $($spec[3]) ($($bytes.Length) bytes)"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
foreach ($name in $compiled.Keys) { [IO.File]::WriteAllBytes((Join-Path $outputRoot $name), $compiled[$name]) }
if ($Install) {
    # Keep originals and restore the full set if any replacement fails.
    $backup = Join-Path $outputRoot ('backup-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup | Out-Null
    foreach ($spec in $specs) { Copy-Item -LiteralPath (Join-Path $assetRoot $spec[3]) -Destination (Join-Path $backup $spec[3]) }
    try {
        if (Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue) { throw 'Ace Combat started; close it before installing shaders.' }
        foreach ($name in $compiled.Keys) { [IO.File]::WriteAllBytes((Join-Path $assetRoot $name), $compiled[$name]) }
    } catch {
        foreach ($spec in $specs) { Copy-Item -LiteralPath (Join-Path $backup $spec[3]) -Destination (Join-Path $assetRoot $spec[3]) -Force }
        throw
    }
    Write-Output "Installed six shaders. Originals saved in: $backup"
} else { Write-Output "Build complete: $outputRoot. Nothing installed. Use -ProfilePath <profile-folder> -Install to install explicitly." }
