# Exercise the packaged Windows game with fresh profiles and the real game UI.
param([string]$Game)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
if (-not $Game) { $Game = Join-Path $project "build/MarchHold.exe" }
$profile = "MarchHold-QA-" + [guid]::NewGuid().ToString("N")
$qa = Join-Path ([IO.Path]::GetTempPath()) $profile
New-Item -ItemType Directory -Path $qa | Out-Null
$binary = Join-Path $qa "MarchHold.exe"
Copy-Item -LiteralPath $Game -Destination $binary
$script = (Join-Path $project "tests/play_match.gd").Replace('\', '/')
$scene = (Join-Path $qa "walkthrough.tscn").Replace('\', '/')
$template = Get-Content -Raw -LiteralPath (Join-Path $project "tests/play_match.tscn")
[IO.File]::WriteAllText($scene, $template.Replace("res://tests/play_match.gd", $script))
$config = @"
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="$profile"
run/main_scene="$scene"
"@
[IO.File]::WriteAllText((Join-Path $qa "override.cfg"), $config)
Write-Host "Playtest logs in $qa"
foreach ($mode in "standard", "grand_army") {
    $output = Join-Path $qa "$mode.log"
    $errors = Join-Path $qa "$mode-errors.log"
    $process = Start-Process -FilePath $binary -WorkingDirectory $qa -WindowStyle Hidden -Wait -PassThru -ArgumentList @("--headless", "--", $mode, "game", "rivals") -RedirectStandardOutput $output -RedirectStandardError $errors
    Get-Content -LiteralPath $output, $errors
    if ($process.ExitCode -ne 0 -or (Select-String -Path $output, $errors -Pattern "SCRIPT ERROR|^ERROR:|FAIL at") -or -not (Select-String -Path $output -SimpleMatch "Victory screen opened")) {
        throw "$mode release playtest failed. See $qa."
    }
}
Remove-Item -LiteralPath $binary
