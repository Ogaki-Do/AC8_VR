param([switch]$SkipShaders)
$ErrorActionPreference='Stop'
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $vsRoot){throw 'Install Visual Studio C++ build tools first'}
$compilerRoot=(Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC\Tools\MSVC') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1).FullName
$kitRoot=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots').KitsRoot10
if(-not (Test-Path -LiteralPath (Join-Path $kitRoot 'Include'))){$kitRoot=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'}
$kitVersion=(Get-ChildItem -LiteralPath (Join-Path $kitRoot 'Include') -Directory | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'um\windows.h')} | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1).Name
$env:INCLUDE="$compilerRoot\include;$kitRoot\Include\$kitVersion\ucrt;$kitRoot\Include\$kitVersion\shared;$kitRoot\Include\$kitVersion\um;$kitRoot\Include\$kitVersion\winrt"
$env:LIB="$compilerRoot\lib\x64;$kitRoot\Lib\$kitVersion\ucrt\x64;$kitRoot\Lib\$kitVersion\um\x64"
$compiler=Join-Path $compilerRoot 'bin\Hostx64\x64\cl.exe'
$fxc=Join-Path $kitRoot "bin\$kitVersion\x64\fxc.exe"
Push-Location -LiteralPath $PSScriptRoot
try{
 New-Item -ItemType Directory -Path build -Force | Out-Null
 $modules=Get-Content -LiteralPath modules.json -Raw | ConvertFrom-Json
 $objects=@()
 foreach($module in $modules.PSObject.Properties){
  $name=$module.Name;$obj="build/$name.obj"
  & $compiler /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /c "/Duevr_plugin_initialize=ac8_${name}_initialize" "/Duevr_plugin_required_version=ac8_${name}_version" $module.Value "/Fo:$obj"
  if($LASTEXITCODE -ne 0){throw "Module build failed: $name"};$objects+=$obj
 }
 & $compiler /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /LD src/plugin.cpp @objects /Fo:build/ac8_vr.obj /Fe:build/AC8_VR-Runtime.dll /link /INCREMENTAL:NO /OUT:build/AC8_VR-Runtime.dll user32.lib d3d12.lib dxgi.lib dxguid.lib gdi32.lib bcrypt.lib d3dcompiler.lib
 if($LASTEXITCODE -ne 0){throw 'Combined AC8_VR-Runtime.dll link failed'}
 if(-not $SkipShaders){
  $shaderRoot='src/renderer'
  foreach($spec in @(@('hud_route_preview.hlsl','VS','vs_5_0','hud-route-VS.dxbc'),@('hud_route_preview.hlsl','PS','ps_5_0','hud-route-PS.dxbc'),@('hud_policy_pass.hlsl','MaskPS','ps_5_0','hud-mask-PS.dxbc'),@('hud_policy_pass.hlsl','PrefilterPS','ps_5_0','hud-filter-PS.dxbc'),@('hud_route_scene.hlsl','SceneVS','vs_5_0','hud-scene-VS.dxbc'),@('hud_route_scene.hlsl','ScenePS','ps_5_0','hud-scene-PS.dxbc'))){
   & $fxc /nologo /WX /O3 /T $spec[2] /E $spec[1] /Fo "$shaderRoot/hud-route-assets/$($spec[3])" "$shaderRoot/$($spec[0])"
   if($LASTEXITCODE -ne 0){throw "Shader build failed: $($spec[1])"}
  }
 }
 Write-Output 'Built one DLL: build/AC8_VR-Runtime.dll'
}finally{Pop-Location}
