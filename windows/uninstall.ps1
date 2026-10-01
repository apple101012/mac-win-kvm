# Remove the Windows server side (Deskflow itself too, unless -KeepDeskflow).
param([switch]$KeepDeskflow)
. "$PSScriptRoot\common.ps1"
$ErrorActionPreference = 'Continue'
Get-Process deskflow, deskflow-core, OpenRGB -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Helper | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Remove-Item -Force $StartupLink, $GuiSettings, $OpenRgbLink, $HelperLink -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $StateDir, $TlsDir -ErrorAction SilentlyContinue
if (-not $KeepDeskflow) {
    & $Winget uninstall --id Deskflow.Deskflow -e --silent
}
Write-Host 'Removed. (trust\server.sha256 stays in the repo; it is regenerated on the next install.)'
