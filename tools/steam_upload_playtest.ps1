# Steam playtest upload script for Lemonade Stand Simulator
# App ID: 5000810
#
# Usage:
#   .\tools\steam_upload_playtest.ps1 -SteamUser your_steam_user [-SteamCmd path\steamcmd.exe]
#
# Requires:
#   - GodotSteam editor in tools/godotsteam-editor
#   - steamcmd.exe installed (https://partner.steamgames.com/doc/sdk/uploading)
#   - A "playtest" branch configured in Steamworks App Admin
#   - Depot ID updated in tools/app_build_5000810.vdf if yours is not 5000811
#
# The script removes steam_appid.txt from the exported build so Steam's
# SteamAppID environment variable is used instead of Spacewar (480).

param(
	[string]$SteamUser = $env:STEAM_USER,
	[string]$SteamCmd = $env:STEAMCMD,
	[string]$AppBuildVdf = "tools/app_build_5000810.vdf",
	[string]$ExportPreset = "Windows Desktop",
	[string]$ExportPath = "export/LemonadeStand.exe",
	[string]$Branch = "playtest"
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
if (-not (Test-Path $SteamCmd)) {
	throw "steamcmd.exe not found at: $SteamCmd. Install SteamCMD or set STEAMCMD env variable."
}

$godot = "tools/godotsteam-editor/godotsteam.471.editor.win64.console.exe"
if (-not (Test-Path $godot)) {
	throw "Godot editor not found at $godot."
}

Write-Host "Exporting release build..." -ForegroundColor Cyan
& $godot --headless --path $projectRoot --export-release $ExportPreset $ExportPath
if ($LASTEXITCODE -ne 0) {
	throw "Godot export failed."
}

$exportDir = Split-Path $ExportPath -Parent
$expectedFiles = @("LemonadeStand.exe", "LemonadeStand.pck")
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

Write-Host "Uploading build to Steam branch '$Branch'..." -ForegroundColor Cyan
& $SteamCmd +login $SteamUser +app_build_update 5000810 "$AppBuildVdf" +quit
if ($LASTEXITCODE -ne 0) {
	throw "Steam upload failed."
}

Write-Host "Upload complete. Build should be live on '$Branch' branch." -ForegroundColor Green
Write-Host "Add testers in Steamworks -> App Admin -> Steam Playtest (or Branches)."
