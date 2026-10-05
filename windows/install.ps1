# Install / update the Windows server side. Safe to re-run.
param([switch]$SkipFirewall)
. "$PSScriptRoot\common.ps1"

function Step($m) { Write-Host "==> $m" }

if (-not (Test-Path $DeskflowCore)) {
    Step 'Installing Deskflow (winget)'
    Invoke-Native { & $Winget install --id Deskflow.Deskflow -e --silent --accept-package-agreements --accept-source-agreements }
    if (-not (Test-Path $DeskflowCore)) { throw 'Deskflow install failed' }
}

if (-not (Test-Path $CertFile)) {
    Step "Generating server TLS certificate at $CertFile"
    New-Item -ItemType Directory -Force $TlsDir | Out-Null
    $tmp = Join-Path $env:TEMP 'macwinkvm-cert'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Invoke-Native { & $OpenSsl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp\k.pem" -out "$tmp\c.pem" -days 3650 -subj '/CN=Deskflow' }
    if ($LASTEXITCODE) { throw 'openssl failed' }
    [IO.File]::WriteAllText($CertFile, [IO.File]::ReadAllText("$tmp\k.pem") + [IO.File]::ReadAllText("$tmp\c.pem"))
    Remove-Item -Recurse -Force $tmp
}
if (Write-IfChanged $ServerFpFile ((Get-CertFingerprint $CertFile) + "`n")) {
    Step "Server fingerprint written to trust\server.sha256 (copy this file into the Mac's trust/ folder so the Mac trusts this desktop)"
}

if (Test-Path $MacFpFile) {
    if (Write-IfChanged $TrustedClients ([IO.File]::ReadAllText($MacFpFile))) { Step 'Trusted the Mac client certificate' }
} else {
    Write-Warning 'trust\mac.sha256 not found yet: run the Mac install, copy its trust/mac.sha256 here, then re-run this script. The Mac cannot connect until then.'
}

$running = @(Get-Process deskflow, deskflow-core -ErrorAction SilentlyContinue)
$changed = Write-IfChanged $ServerConf (Get-ExpectedServerConfig)
$expectedGui = Get-ExpectedGuiSettings
$guiCurrent = if (Test-Path $GuiSettings) { [IO.File]::ReadAllText($GuiSettings) } else { '' }
$guiOk = -not (Compare-GuiSettings $expectedGui $guiCurrent)
if (-not $guiOk) {
    # the GUI rewrites its settings on exit, so stop it before writing
    $running | Stop-Process -Force; Start-Sleep 1; $running = @()
    Write-IfChanged $GuiSettings $expectedGui | Out-Null
    Step 'Wrote Deskflow GUI settings'
}

if (-not (Test-Path $StartupLink)) {
    Step 'Starting Deskflow at login'
    New-Shortcut $StartupLink $DeskflowGui '' $DeskflowDir
}

if (-not $SkipFirewall -and -not (Test-FirewallRestricted)) {
    Step 'Limiting the Deskflow firewall rules to the home LAN + ZeroTier (approve the admin prompt)'
    $subnets = ($Settings.allowedSubnets | ForEach-Object { "'$_'" }) -join ','
    $cmd = "Get-NetFirewallRule -DisplayName 'Deskflow*' | Set-NetFirewallRule -RemoteAddress @($subnets)"
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @('-NoProfile', '-Command', $cmd)
    if (-not (Test-FirewallRestricted)) { throw 'Firewall rules are still open to everyone (was the admin prompt declined?)' }
}

if ($LightingOn) {
    # Lighting talks to the keyboard over USB (kvmlight/sinowealth.py); only needs the hidapi package.
    Invoke-Native { & python -c "import hid" }
    if ($LASTEXITCODE) { Step 'Installing hidapi (USB access for keyboard lighting)'; Invoke-Native { & python -m pip install --user --quiet 'hidapi>=0.14,<1' } }
}

# The helper always runs: it's the watchdog that frees input stuck on a Mac that went away (docs/adr/0002),
# and it drives the keyboard lighting when that's enabled.
if (-not (Test-Path $HelperLink)) { Step 'Starting the background helper at login'; New-Shortcut $HelperLink (Get-Pythonw) "-m kvmlight.helper `"$ServerLog`"" $Repo }
$codeTime = (Get-ChildItem (Join-Path $Repo 'kvmlight'), (Join-Path $Repo 'settings.json') -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
$helperStale = Get-Helper | Where-Object { $_.CreationDate -lt $codeTime }
if ($helperStale) { Step 'Restarting the background helper (code or settings changed)'; $helperStale | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }
Start-Helper

if ($changed -and $running) { Step 'Config changed, restarting Deskflow'; $running | Stop-Process -Force; Start-Sleep 1; $running = @() }
Get-Process deskflow-core -ErrorAction SilentlyContinue | Where-Object { -not (Get-Process deskflow -ErrorAction SilentlyContinue) } | Stop-Process -Force
if (-not (Get-Process deskflow -ErrorAction SilentlyContinue)) {
    Step 'Starting Deskflow'
    Start-Process $DeskflowGui -WorkingDirectory $DeskflowDir
}
Step 'Done. Run windows\doctor.ps1 to verify.'
