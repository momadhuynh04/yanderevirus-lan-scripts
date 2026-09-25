<#
.SYNOPSIS
    Undo Setup-LAN.ps1 - put the shipped emulator config back.
#>
$GameDir  = Split-Path -Parent $PSScriptRoot
$Settings = Join-Path $GameDir 'Yandere Virus_Data\Plugins\x86_64\steam_settings'

foreach ($n in 'configs.user.ini', 'configs.main.ini') {
    $p = Join-Path $Settings $n
    if (Test-Path "$p.orig") {
        Copy-Item "$p.orig" $p -Force
        Write-Host "restored $n" -ForegroundColor Green
    } else {
        Write-Host "no backup for $n - skipped" -ForegroundColor Yellow
    }
}
$bc = Join-Path $Settings 'custom_broadcasts.txt'
if (Test-Path $bc) { Remove-Item $bc; Write-Host "removed custom_broadcasts.txt" -ForegroundColor Green }
