# Builds MarchHold: imports assets, runs the headless tests, exports the Windows
# game and wraps it in an installer (dist/MarchHold-Setup-<version>.exe).
#   powershell -ExecutionPolicy Bypass -File tools\build.ps1 [-SkipTests]
param(
    [string]$Godot = "$env:USERPROFILE\Tools\godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Iscc = "$env:USERPROFILE\Tools\InnoSetup6\ISCC.exe",
    [switch]$SkipTests
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$version = (Select-String -Path project.godot -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
Write-Host "MarchHold $version"

& $Godot --headless --path . --import | Out-Null
if (-not $SkipTests) {
    & $Godot --headless --path . -s res://tests/run_tests.gd
    if ($LASTEXITCODE -ne 0) { throw "Tests failed." }
}
New-Item -ItemType Directory -Force build, dist | Out-Null
foreach ($d in "build", "dist") { if (-not (Test-Path "$d/.gdignore")) { New-Item -ItemType File "$d/.gdignore" | Out-Null } }
& $Godot --headless --path . --export-release "Windows Desktop" build/MarchHold.exe
if (-not (Test-Path build/MarchHold.exe)) { throw "Export failed." }
& $Iscc "/DAppVersion=$version" installer\MarchHold.iss
if ($LASTEXITCODE -ne 0) { throw "Installer build failed." }
Get-ChildItem dist | Format-Table Name, @{n="MB"; e={[math]::Round($_.Length / 1MB, 1)}}
