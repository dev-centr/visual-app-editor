# Builds the Windows release and wraps it in an Inno Setup installer.
# Usage: packaging/windows/build-installer.ps1 [-Version 0.1.0] [-Arch x64|arm64] [-SkipBuild]
param(
  [string]$Version = '',
  [ValidateSet('x64', 'arm64')][string]$Arch = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $root
if (-not $Version) { $Version = ((Select-String pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value) }
$build = if ($env:GITHUB_RUN_NUMBER) { "ci.$env:GITHUB_RUN_NUMBER" } else { 'local' }
if (-not $SkipBuild) {
  flutter build windows --release --dart-define=VAE_VERSION=$Version --dart-define=VAE_BUILD=$build
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
}
$src = Join-Path $root "build\windows\$Arch\runner\Release"
if (-not (Test-Path "$src\visual_app_editor.exe")) { throw "Missing $src\visual_app_editor.exe" }
$iscc = @(
  (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
  foreach ($v in 7, 6) {
    "${env:ProgramFiles(x86)}\Inno Setup $v\ISCC.exe"
    "$env:ProgramFiles\Inno Setup $v\ISCC.exe"
    "$env:LOCALAPPDATA\Programs\Inno Setup $v\ISCC.exe"
  }
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 or 7 (ISCC.exe) not found. Install it: choco install innosetup  (or winget install JRSoftware.InnoSetup)' }
$out = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $out | Out-Null
& $iscc "/DAppVersion=$Version" "/DArch=$Arch" "/DSourceDir=$src" "/DOutputDir=$out" "$PSScriptRoot\visual_app_editor.iss"
if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }
Get-ChildItem $out -Filter "VisualAppEditor-$Version-windows-$Arch-setup.exe"
