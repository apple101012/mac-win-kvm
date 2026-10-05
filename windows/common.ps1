# Shared paths and helpers for the Windows (server) side. Dot-source this file.
$ErrorActionPreference = 'Stop'

$Repo         = Split-Path -Parent $PSScriptRoot
$DeskflowDir  = 'C:\Program Files\Deskflow'
$DeskflowCore = Join-Path $DeskflowDir 'deskflow-core.exe'
$DeskflowGui  = Join-Path $DeskflowDir 'deskflow.exe'
$StateDir     = Join-Path $env:LOCALAPPDATA 'macwinkvm'
$ServerConf   = Join-Path $StateDir 'server.conf'
$ServerLog    = Join-Path $StateDir 'server.log'
$TlsDir       = 'C:\ProgramData\Deskflow\tls'           # Deskflow's fixed TLS dir on non-portable Windows
$CertFile     = Join-Path $TlsDir 'deskflow.pem'
$TrustedClients = Join-Path $TlsDir 'trusted-clients'
$GuiSettings  = Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
$StartupLink  = Join-Path ([Environment]::GetFolderPath('Startup')) 'Deskflow (macwinkvm).lnk'
$OpenSsl      = 'C:\Program Files\Git\usr\bin\openssl.exe'
$Winget       = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
$ServerFpFile = Join-Path $Repo 'trust\server.sha256'
$MacFpFile    = Join-Path $Repo 'trust\mac.sha256'
$HelperLink   = Join-Path ([Environment]::GetFolderPath('Startup')) 'Background helper (macwinkvm).lnk'
$HelperLog    = Join-Path $StateDir 'helper.log'
$SettingsFile = Join-Path $Repo 'settings.json'
if (-not (Test-Path $SettingsFile)) { throw "settings.json not found: copy settings.example.json to settings.json and fill it in (or ask Claude to set it up)" }
$Settings     = Get-Content $SettingsFile -Raw | ConvertFrom-Json
$LightingOn   = [bool]$Settings.lighting.enabled

# Windows PowerShell 5 turns any native stderr output into a terminating error under 'Stop'.
function Invoke-Native([scriptblock]$Block) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Block 2>$null } finally { $ErrorActionPreference = $old }
}

function Invoke-Generator([string]$Kind, [string[]]$KvArgs = @()) {
    Push-Location $Repo
    try { $out = Invoke-Native { & python -m kvmconfig.generate $Kind @KvArgs }; if ($LASTEXITCODE) { throw "generator failed: $Kind" } }
    finally { Pop-Location }
    ($out -join "`n") + "`n"
}

function Get-ExpectedServerConfig { Invoke-Generator 'server-config' }

function Get-ExpectedGuiSettings {
    Invoke-Generator 'server-settings' @("config_file=$ServerConf", "log_file=$ServerLog", "cert_file=$CertFile")
}

# Deskflow fingerprint format: v2:sha256:<lowercase hex of sha256(DER cert)>
function Get-CertFingerprint([string]$Pem) {
    $line = Invoke-Native { & $OpenSsl x509 -in $Pem -noout -fingerprint -sha256 }
    if ($LASTEXITCODE) { throw "openssl could not read $Pem" }
    'v2:sha256:' + (($line -split '=', 2)[1] -replace ':', '').ToLower()
}

function Write-IfChanged([string]$Path, [string]$Content) {
    $current = if (Test-Path $Path) { [IO.File]::ReadAllText($Path) } else { $null }
    if ($current -eq $Content) { return $false }
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding $false))
    $true
}

function Get-DeskflowFirewallRules { @(Get-NetFirewallRule -DisplayName 'Deskflow*' -ErrorAction SilentlyContinue) }

function Test-FirewallRestricted {
    $want = @($Settings.allowedSubnets | Sort-Object)
    $rules = Get-DeskflowFirewallRules | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' }
    foreach ($r in $rules) {
        $have = @(($r | Get-NetFirewallAddressFilter).RemoteAddress | ForEach-Object { Convert-Subnet $_ } | Sort-Object)
        if (($have -join ',') -ne ($want -join ',')) { return $false }
    }
    $true
}

# Windows reports 192.168.1.0/24 as 192.168.1.0/255.255.255.0
function Convert-Subnet([string]$s) {
    if ($s -match '^(.+)/(\d+\.\d+\.\d+\.\d+)$') {
        $bits = ([Net.IPAddress]::Parse($Matches[2]).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2) }) -join ''
        return "$($Matches[1])/$(($bits -replace '0', '').Length)"
    }
    $s
}

function Read-Ini([string]$Text) {
    $map = @{}; $section = ''
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1] }
        elseif ($line -match '^([^=]+)=(.*)$') { $map["$section/$($Matches[1])"] = $Matches[2] }
    }
    $map
}

# Returns the expected "section/key=value" entries missing from $Current (the GUI adds extra keys; those are fine).
function Compare-GuiSettings([string]$Expected, [string]$Current) {
    $want = Read-Ini $Expected; $have = Read-Ini $Current
    @($want.Keys | Where-Object { $have[$_] -ne $want[$_] } | ForEach-Object { "$_=$($want[$_])" })
}

function Get-Pythonw { Join-Path (Split-Path (Get-Command python).Source) 'pythonw.exe' }

function New-Shortcut([string]$Link, [string]$Target, [string]$Arguments, [string]$WorkDir) {
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($Link)
    $sh.TargetPath = $Target; $sh.Arguments = $Arguments; $sh.WorkingDirectory = $WorkDir; $sh.WindowStyle = 7
    $sh.Save()
}

function Get-Helper {
    @(Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" | Where-Object { $_.CommandLine -match 'kvmlight\.helper' })
}

# Started through WMI so they are not tied to the console/job that ran the install.
function Start-Detached([string]$CommandLine, [string]$WorkDir) {
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
    Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = $CommandLine; CurrentDirectory = $WorkDir; ProcessStartupInformation = $startup } | Out-Null
}

function Start-Helper {
    if (-not (Get-Helper)) {
        Start-Detached "`"$(Get-Pythonw)`" -m kvmlight.helper `"$ServerLog`"" $Repo
    }
}
