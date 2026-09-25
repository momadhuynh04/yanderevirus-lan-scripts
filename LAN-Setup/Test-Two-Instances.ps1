<#
.SYNOPSIS
    OPTIONAL - run two game instances on this one PC, to sanity-check that the
    emulator's LAN stack works before involving a second machine.

.DESCRIPTION
    Two instances must not share an identity, but both read the SAME
    steam_settings folder.  The emulator reads that folder once at startup, so
    this script starts instance 1 with the host identity, rewrites the config,
    then starts instance 2 with a different identity and a different UDP port.

    WARNING - this needs roughly 21 GB of commit charge.  On a 16 GB machine it
    will fail with "Could not allocate memory" unless the pagefile has been
    enlarged; run Set-Pagefile.ps1 first and reboot.

.EXAMPLE
    .\Test-Two-Instances.ps1
    .\Test-Two-Instances.ps1 -Width 640 -Height 360
#>
param(
    [int]$Width  = 800,
    [int]$Height = 450,
    [int]$ClientPort = 47585
)

$ErrorActionPreference = 'Stop'

$GameDir  = Split-Path -Parent $PSScriptRoot
$Exe      = Join-Path $GameDir 'Yandere Virus.exe'
$Settings = Join-Path $GameDir 'Yandere Virus_Data\Plugins\x86_64\steam_settings'
$UserIni  = Join-Path $Settings 'configs.user.ini'
$MainIni  = Join-Path $Settings 'configs.main.ini'

if (-not (Test-Path $Exe)) { throw "game exe not found: $Exe" }

foreach ($f in @($UserIni, $MainIni)) {
    if (-not (Test-Path "$f.orig")) { Copy-Item $f "$f.orig" }
}

function Set-Identity {
    param([string]$Name, [string]$SteamId, [int]$Port)
    @"
[user::general]
account_name=$Name
account_steamid=$SteamId
language=english
"@ | Set-Content -Path $UserIni -Encoding ASCII
    @"
[main::connectivity]
disable_networking=0
listen_port=$Port
offline=0
"@ | Set-Content -Path $MainIni -Encoding ASCII
}

$common = "-screen-width $Width -screen-height $Height -screen-fullscreen 0 -screen-quality 0 -window-mode windowed"
$log1   = Join-Path $PSScriptRoot 'instance1.log'
$log2   = Join-Path $PSScriptRoot 'instance2.log'

Set-Identity -Name 'HostPlayer' -SteamId '76561197960287930' -Port 47584
Write-Host "--- instance 1 (HostPlayer, udp 47584) ---" -ForegroundColor Cyan
$p1 = Start-Process -FilePath $Exe -ArgumentList "$common -logFile `"$log1`"" -PassThru
Write-Host "  pid=$($p1.Id), waiting 45s..."
Start-Sleep -Seconds 45
Write-Host "  alive = $(-not $p1.HasExited)"

Set-Identity -Name 'ClientPlayer' -SteamId '76561197960287931' -Port $ClientPort
Write-Host "--- instance 2 (ClientPlayer, udp $ClientPort) ---" -ForegroundColor Cyan
$p2 = Start-Process -FilePath $Exe -ArgumentList "$common -logFile `"$log2`"" -PassThru
Write-Host "  pid=$($p2.Id), waiting 45s..."
Start-Sleep -Seconds 45
Write-Host "  alive = $(-not $p2.HasExited)"

Write-Host "`n--- status ---"
Get-Process -Name 'Yandere Virus' -ErrorAction SilentlyContinue |
    Select-Object Id,
                  @{n='WS_GB';     e={[math]::Round($_.WorkingSet64/1GB,2)}},
                  @{n='Commit_GB'; e={[math]::Round($_.PrivateMemorySize64/1GB,2)}} |
    Format-Table -AutoSize | Out-String | Write-Host

$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("RAM free         : {0:N2} GB" -f ($os.FreePhysicalMemory/1MB))
Write-Host ("Commit available : {0:N2} GB" -f ($os.FreeVirtualMemory/1MB))

foreach ($pair in @(,@('1',$log1)) + @(,@('2',$log2))) {
    if (Test-Path $pair[1]) {
        $t = Get-Content $pair[1] -Raw
        $verdict = if ($t -match 'out of memory') { 'OOM' }
                   elseif ($t -match 'failed to create 2D texture') { 'VRAM-OOM' }
                   elseif ($t -match 'Crash!!!') { 'CRASH' }
                   else { 'clean' }
        Write-Host ("  instance{0}.log : {1}" -f $pair[0], $verdict)
    }
}

Write-Host "`nBoth instances left RUNNING. Close them when done." -ForegroundColor Cyan
Write-Host "Restore the shipped config with .\Restore-Config.ps1" -ForegroundColor Cyan
