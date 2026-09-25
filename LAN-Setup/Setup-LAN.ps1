<#
.SYNOPSIS
    Yandere Virus - LAN co-op setup for one machine.

.DESCRIPTION
    The game ships Goldberg (gbe_fork) in place of the real Steam client, so
    co-op works over a virtual LAN with no Steam account and no internet.

    Two things must be true for two machines to see each other:

      1. Each machine needs a DIFFERENT SteamID.  configs.user.ini lives inside
         the game folder and hardcodes one, so copying the folder to a second
         PC gives both machines the same identity and nothing works.

      2. Both machines need the SAME listen_port, because that is the channel
         the emulator uses to find peers on the network.

    This script fixes both, and can also open the firewall and add a broadcast
    address for the VPN subnet.

.PARAMETER Player
    A number identifying this machine, 1..16.  Every machine in the session must
    use a DIFFERENT number - that is what gives each one its own SteamID.
    Numbering does not imply a role; the host is whoever clicks Host Game.

    1 keeps the identity the release shipped with (MRGoldberg); 2 and up get
    Player2, Player3, ...

.PARAMETER AutoLAN
    Detect the adapter that carries the default route (home LAN, Hamachi,
    ZeroTier, Tailscale, ...) and write custom_broadcasts.txt from its subnet.

.PARAMETER AutoRadmin
    Detect the Radmin VPN adapter specifically.  Falls back to the default
    route if no Radmin adapter is present.

.PARAMETER RadminCIDR
    Set the broadcast subnet manually, e.g. 26.0.0.0/24.

.PARAMETER PlayerName
    Name shown in game.  Leave empty for the default (MRGoldberg on player 1,
    PlayerN otherwise).

    The game has no rename option of its own - it reads the name from the Steam
    persona, which the emulator supplies from account_name in configs.user.ini.
    That is exactly what this writes.  Steam allows 32 bytes, so longer names
    are trimmed.

.PARAMETER Firewall
    Add an inbound firewall rule for the emulator UDP port.

.EXAMPLE
    .\Setup-LAN.ps1 -Player 1 -AutoRadmin -Firewall
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 16)]
    [int]$Player,

    [switch]$AutoLAN,

    [switch]$AutoRadmin,

    [string]$RadminCIDR = '',

    [int]$ListenPort = 47584,

    [string]$PlayerName = '',

    [switch]$Firewall
)

$ErrorActionPreference = 'Stop'

# The firewall rule needs administrator rights.  Rather than making the user
# remember to open an elevated shell, re-launch ourselves through UAC -- but
# only when -Firewall was actually asked for.
if ($Firewall) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Firewall rule needs administrator rights - click Yes on the UAC prompt..." -ForegroundColor Yellow
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"",
                     '-Player', $Player, '-Firewall')
        if ($AutoLAN)    { $argList += '-AutoLAN' }
        if ($AutoRadmin) { $argList += '-AutoRadmin' }
        if ($RadminCIDR)  { $argList += @('-RadminCIDR', $RadminCIDR) }
        if ($PlayerName)  { $argList += @('-PlayerName', $PlayerName) }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
        exit
    }
}

$GameDir  = Split-Path -Parent $PSScriptRoot
$Settings = Join-Path $GameDir 'Yandere Virus_Data\Plugins\x86_64\steam_settings'

if (-not (Test-Path $Settings)) {
    throw "steam_settings not found at:`n  $Settings`nIs this script inside the game folder?"
}

# Individual Steam64 IDs start at 76561197960265728 + accountID.
# Player 1 keeps the ID the release shipped with; Player 2 gets the next one.
$SteamId     = 76561197960265728 + 22202 + ($Player - 1)

if ($PlayerName -ne '') {
    $AccountName = $PlayerName
} elseif ($Player -eq 1) {
    $AccountName = 'MRGoldberg'
} else {
    $AccountName = "Player$Player"
}

# Steam persona names cap out at 32 bytes; the emulator truncates silently
if ([Text.Encoding]::UTF8.GetByteCount($AccountName) -gt 32) {
    $trimmed = ''
    foreach ($ch in $AccountName.ToCharArray()) {
        if ([Text.Encoding]::UTF8.GetByteCount($trimmed + $ch) -gt 32) { break }
        $trimmed += $ch
    }
    Write-Host "  player name longer than 32 bytes - trimmed to '$trimmed'" -ForegroundColor Yellow
    $AccountName = $trimmed
}

Write-Host "== Yandere Virus LAN setup ==" -ForegroundColor Cyan
Write-Host "  game folder  : $GameDir"
Write-Host "  player       : $Player"
Write-Host "  account name : $AccountName"
Write-Host "  steam id     : $SteamId"
Write-Host ""

# --- 1. identity ---------------------------------------------------------
$UserIni = Join-Path $Settings 'configs.user.ini'
$Backup  = "$UserIni.orig"
if ((Test-Path $UserIni) -and -not (Test-Path $Backup)) {
    Copy-Item $UserIni $Backup
    Write-Host "  backed up original -> configs.user.ini.orig"
}

$userContent = @"
[user::general]
account_name=$AccountName
account_steamid=$SteamId
language=english
"@
[IO.File]::WriteAllText($UserIni, ($userContent + "`r`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "  wrote configs.user.ini" -ForegroundColor Green

# --- 2. networking -------------------------------------------------------
$MainIni = Join-Path $Settings 'configs.main.ini'
$MainBak = "$MainIni.orig"
if ((Test-Path $MainIni) -and -not (Test-Path $MainBak)) {
    Copy-Item $MainIni $MainBak
    Write-Host "  backed up original -> configs.main.ini.orig"
}

$mainContent = @"
[main::connectivity]
disable_networking=0
listen_port=$ListenPort
offline=0
"@
[IO.File]::WriteAllText($MainIni, ($mainContent + "`r`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "  wrote configs.main.ini (listen_port=$ListenPort)" -ForegroundColor Green

# --- 3. broadcast address for the VPN subnet -----------------------------
if (($AutoLAN -or $AutoRadmin) -and $RadminCIDR -eq '') {
    $adapter = $null

    if ($AutoRadmin) {
        $adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceAlias -match 'Radmin' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1
        if ($null -eq $adapter) {
            Write-Host "  no Radmin adapter present - falling back to the default route" -ForegroundColor Yellow
        }
    }

    if ($null -eq $adapter) {
        # whichever NIC carries the default route is the network we actually use
        $adapter = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPv4DefaultGateway -and $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up'
            } |
            Select-Object -First 1 |
            ForEach-Object {
                Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notlike '169.254.*' } |
                    Select-Object -First 1
            }
    }

    if ($null -eq $adapter) {
        Write-Host "  could not auto-detect an adapter - pass -RadminCIDR manually" -ForegroundColor Red
    } else {
        $o = $adapter.IPAddress.Split('.')
        $RadminCIDR = "{0}.{1}.{2}.0/{3}" -f $o[0], $o[1], $o[2], $adapter.PrefixLength
        Write-Host "  detected: $($adapter.InterfaceAlias)  $($adapter.IPAddress)/$($adapter.PrefixLength)  ->  $RadminCIDR" -ForegroundColor Green
    }
}

if ($RadminCIDR -ne '') {
    $parts   = $RadminCIDR -split '/'
    $pfx     = [int]$parts[1]
    $ipBytes = [IPAddress]::Parse($parts[0]).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $net   = [BitConverter]::ToUInt32($ipBytes, 0)
    $mask  = [uint32]((([uint64]4294967295) -shl (32 - $pfx)) -band [uint64]4294967295)
    $wild  = [uint32](([uint64]4294967295) -bxor [uint64]$mask)
    $bcB   = [BitConverter]::GetBytes([uint32]($net -bor $wild))
    [Array]::Reverse($bcB)
    $bc    = ([IPAddress]::new($bcB)).ToString()

    $bcFile = Join-Path $Settings 'custom_broadcasts.txt'
    [IO.File]::WriteAllText($bcFile, "$bc`r`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host "  wrote custom_broadcasts.txt -> $bc" -ForegroundColor Green
}

# --- 4. firewall ---------------------------------------------------------
if ($Firewall) {
    $name = "Yandere Virus LAN UDP $ListenPort"
    try {
        if ($null -eq (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow `
                -Protocol UDP -LocalPort $ListenPort -Profile Any | Out-Null
            Write-Host "  firewall: added inbound UDP $ListenPort" -ForegroundColor Green
        } else {
            Write-Host "  firewall: rule already present"
        }
    } catch {
        Write-Host "  firewall: failed - run this script as Administrator" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "--- resulting config ---"
Get-Content $UserIni | Where-Object { $_ -match '^\s*(account_name|account_steamid)=' } | ForEach-Object { "  $_" }
Get-Content $MainIni | Where-Object { $_ -match '^\s*(disable_networking|listen_port)=' } | ForEach-Object { "  $_" }
Write-Host ""
Write-Host "Next: make sure both machines can ping each other, then start the game." -ForegroundColor Cyan
Write-Host "See README.md for how to actually join (it is NOT the Quick Join button)." -ForegroundColor Cyan
