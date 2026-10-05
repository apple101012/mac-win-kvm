# Health check for the Windows server side. Exit code = number of failures.
. "$PSScriptRoot\common.ps1"
$ErrorActionPreference = 'Continue'
$script:fails = 0
function Check([string]$Name, [scriptblock]$Test, [string]$Fix = '') {
    $ok = $false; try { $ok = [bool](& $Test) } catch { }
    if ($ok) { Write-Host "PASS  $Name" } else { $script:fails++; Write-Host "FAIL  $Name$(if ($Fix) { "  -> $Fix" })" }
}
function Warn([string]$Name, [scriptblock]$Test, [string]$Fix) {
    $ok = $false; try { $ok = [bool](& $Test) } catch { }
    if ($ok) { Write-Host "PASS  $Name" } else { Write-Host "WARN  $Name  -> $Fix" }
}

Check 'Deskflow installed' { Test-Path $DeskflowCore } 'run windows\install.ps1'
Check 'server TLS certificate exists' { Test-Path $CertFile } 'run windows\install.ps1'
Check 'trust\server.sha256 matches the certificate' { ([IO.File]::ReadAllText($ServerFpFile).Trim()) -eq (Get-CertFingerprint $CertFile) } 'run install, then copy trust\server.sha256 to the Mac''s trust folder'
Warn  'Mac client certificate trusted' { (Test-Path $MacFpFile) -and ([IO.File]::ReadAllText($TrustedClients).Trim() -eq [IO.File]::ReadAllText($MacFpFile).Trim()) } 'copy trust/mac.sha256 from the Mac into trust\, then re-run windows\install.ps1'
Check 'server.conf matches settings.json' { [IO.File]::ReadAllText($ServerConf) -eq (Get-ExpectedServerConfig) } 'run windows\install.ps1'
Check 'Deskflow GUI settings applied' { (Test-Path $GuiSettings) -and ((Compare-GuiSettings (Get-ExpectedGuiSettings) ([IO.File]::ReadAllText($GuiSettings))).Count -eq 0) } 'run windows\install.ps1'
Check 'starts at login' { Test-Path $StartupLink } 'run windows\install.ps1'
Check 'firewall limited to LAN + ZeroTier' { (Get-DeskflowFirewallRules).Count -gt 0 -and (Test-FirewallRestricted) } 'run windows\install.ps1 and approve the admin prompt'
Check 'Deskflow GUI running' { Get-Process deskflow -ErrorAction Stop } 'start Deskflow from the Start menu'
Check 'Deskflow server running' { Get-Process deskflow-core -ErrorAction Stop } 'open Deskflow from the tray and press Start'
Check "listening on port $($Settings.port)" { Get-NetTCPConnection -State Listen -LocalPort $Settings.port -ErrorAction Stop } 'check the Deskflow log'

Check 'background helper (watchdog) starts at login' { Test-Path $HelperLink } 'run windows\install.ps1'
Check 'background helper (watchdog) running' { @(Get-Helper).Count -gt 0 } 'run windows\install.ps1'
if ($LightingOn) {
    Check 'hidapi installed' { Invoke-Native { & python -c "import hid" }; $LASTEXITCODE -eq 0 } 'run windows\install.ps1'
    Check 'keyboard colour set' { $t = Get-Content $HelperLog -Tail 30; ($t -match 'colour [0-9A-F]{6}|lighting back') -and -not (($t | Select-Object -Last 1) -match '^\S+ keyboard:') } "see $HelperLog"
}
Warn  'Ethernet power saving off (Green Ethernet, Power Saving Mode)' { @(Get-NetAdapterAdvancedProperty -Name Ethernet -ErrorAction Stop | Where-Object { $_.DisplayName -in 'Green Ethernet','Power Saving Mode' -and $_.DisplayValue -ne 'Disabled' }).Count -eq 0 } 'causes 100-800 ms lag; see README Troubleshooting'

if ($script:fails) { Write-Host "`n$($script:fails) problem(s) found." } else { Write-Host "`nAll good." }
exit $script:fails
