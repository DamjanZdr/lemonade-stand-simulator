# Steam playtest upload script for Lemonade Stand Simulator
# Default target: playtest app 5329010 / depot 5329011
#
# Usage:
#   .\tools\steam_upload_playtest.ps1 -SteamUser your_steam_user [-SteamCmd path\steamcmd.exe]
#
# To upload to the main app (5000810) instead:
#   .\tools\steam_upload_playtest.ps1 -SteamUser your_steam_user -AppId 5000810 -AppBuildVdf tools/app_build_5000810.vdf -Branch playtest
#
# Requires:
#   - GodotSteam editor in tools/godotsteam-editor
#   - steamcmd.exe installed (https://partner.steamgames.com/doc/sdk/uploading)
#   - A branch configured in Steamworks App Admin for the target App ID
#   - Depot IDs matching the app_build_*.vdf files
#
# The script removes steam_appid.txt from the exported build so Steam's
# SteamAppID environment variable is used instead of Spacewar (480).

param(
	[string]$SteamUser = $env:STEAM_USER,
	[string]$SteamCmd = $env:STEAMCMD,
	[string]$AppId = "5329010",
	[string]$AppBuildVdf = "tools/app_build_5329010.vdf",
	[string]$ExportPreset = "Windows Desktop",
	[string]$ExportPath = "export/WhenLifeGivesYouLemons.exe",
	[string]$Branch = "default"
)

$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Split-Path $PSScriptRoot -Parent)
Set-Location $projectRoot

if (-not $SteamUser) {
	throw "Steam user is required. Pass -SteamUser or set STEAM_USER environment variable."
}
if (-not $SteamCmd) {
	$SteamCmd = "C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe"
}
# Accept the path with or without the .exe extension.
if ($SteamCmd -notlike "*.exe") {
	$SteamCmd = "$SteamCmd.exe"
}
if (-not (Test-Path $SteamCmd)) {
	throw "steamcmd.exe not found at: $SteamCmd. Install SteamCMD or set STEAMCMD env variable."
}
if (-not (Test-Path $AppBuildVdf)) {
	throw "App build config not found at: $AppBuildVdf"
}

$godot = "tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe"
if (-not (Test-Path $godot)) {
	throw "Godot editor not found at $godot."
}

# Clean stale exports so old filenames (LemonadeStand.*) don't get uploaded.
$exportDir = Split-Path $ExportPath -Parent
if (Test-Path $exportDir) {
	Get-ChildItem -Path $exportDir -Include @("*.exe", "*.pck", "steam_api64.dll") -Recurse -ErrorAction SilentlyContinue `
		| Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host "Exporting release build..." -ForegroundColor Cyan
& $godot --headless --path $projectRoot --export-release $ExportPreset $ExportPath
if ($LASTEXITCODE -ne 0) {
	throw "Godot export failed."
}

$expectedFiles = @("WhenLifeGivesYouLemons.exe", "WhenLifeGivesYouLemons.pck")
foreach ($file in $expectedFiles) {
	if (-not (Test-Path (Join-Path $exportDir $file))) {
		throw "Expected exported file missing: $file"
	}
}

# Make sure we never ship steam_appid.txt (which would force Spacewar 480).
$txt = Join-Path $exportDir "steam_appid.txt"
if (Test-Path $txt) {
	Remove-Item $txt -Force
	Write-Host "Removed steam_appid.txt from export folder." -ForegroundColor Yellow
}

# steam_api64.dll should be next to the .exe; copy it if missing.
$dll = Join-Path $exportDir "steam_api64.dll"
if (-not (Test-Path $dll)) {
	$templateDll = "tools/godotsteam-templates/win64/steam_api64.dll"
	if (Test-Path $templateDll) {
		Copy-Item $templateDll $dll -Force
		Write-Host "Copied steam_api64.dll from templates." -ForegroundColor Yellow
	}
}

Write-Host "Uploading build to App $AppId branch '$Branch'..." -ForegroundColor Cyan
# Use the absolute VDF path. ContentRoot inside the VDF is also absolute,
# so SteamCMD's own working directory does not matter.
$buildVdfPath = (Resolve-Path $AppBuildVdf).Path
$arguments = @( "+login", $SteamUser, "+run_app_build", $buildVdfPath, "+quit" )
# Run SteamCMD in the same window and capture output to a log. Credentials
# should already be cached from the first manual login.
$logPath = Join-Path $projectRoot "tools/steam_upload.log"
$errPath = Join-Path $projectRoot "tools/steam_upload.err"
$process = Start-Process -FilePath $SteamCmd -ArgumentList $arguments `
	-Wait -PassThru -WorkingDirectory $projectRoot -NoNewWindow `
	-RedirectStandardOutput $logPath -RedirectStandardError $errPath
if ($process.ExitCode -ne 0) {
	throw "Steam upload failed (exit code $($process.ExitCode)). See tools/steam_upload.log and tools/steam_upload.err."
}
Write-Host "SteamCMD output saved to $logPath" -ForegroundColor DarkGray

Write-Host "Upload complete. Build should be live on '$Branch' branch of App $AppId." -ForegroundColor Green
Write-Host "Add testers in Steamworks -> App Admin for App $AppId."
