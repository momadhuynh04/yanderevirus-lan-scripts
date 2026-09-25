<#
.SYNOPSIS
    OPTIONAL - enlarge the pagefile so two game instances fit in memory.

.DESCRIPTION
    Measured during a real two-instance run:
        instance 1 commit : 12.50 GB
        instance 2 commit :  8.38 GB
        total             : ~21 GB
        commit available  : 0.10 GB   <- exhausted, instance 2 died with OOM

    If the pagefile sits on a full system drive, Windows shrinks it, the commit
    limit collapses, and the second instance dies with
    "Could not allocate memory: System out of memory!".

    This moves the bulk of the pagefile to a roomier drive.

    You do NOT need this to play over LAN with a second machine - each machine
    only runs one instance there.  It is only for the single-PC two-instance
    test.

    Run it normally; it asks for administrator rights itself.
    REBOOT afterwards.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Requesting administrator rights - click Yes on the UAC prompt..." -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File', "`"$PSCommandPath`"") `
        -Verb RunAs
    exit
}

$ErrorActionPreference = 'Stop'

# pick the drive with the most free space, other than the system drive
$sysDrive = $env:SystemDrive.TrimEnd(':')
$target = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Free -gt 20GB -and $_.Name -ne $sysDrive } |
    Sort-Object Free -Descending | Select-Object -First 1

if (-not $target) { throw "no non-system drive with more than 20 GB free" }

Write-Host "--- before ---"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("  commit limit : {0:N2} GB" -f ($os.TotalVirtualMemorySize/1MB))
Get-CimInstance Win32_PageFileUsage |
    Select-Object Name, @{n='AllocGB';e={[math]::Round($_.AllocatedBaseSize/1024,2)}} |
    Format-Table -AutoSize | Out-String | Write-Host

$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile) {
    $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false }
    Write-Host "  automatic pagefile management: disabled"
    Start-Sleep -Seconds 3
} else {
    Write-Host "  automatic pagefile management: already disabled"
}

# small pagefile on the system drive - the kernel needs one there for dumps
$c = Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -like "$sysDrive`:*" }
if ($c) {
    $c | Set-CimInstance -Property @{ InitialSize = 2048; MaximumSize = 4096 }
} else {
    Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{
        Name = "$sysDrive`:\pagefile.sys"; InitialSize = 2048; MaximumSize = 4096 } | Out-Null
}
Write-Host "  ${sysDrive}: pagefile -> 2048 / 4096 MB"

# the real one
$dName = "$($target.Name):\pagefile.sys"
$d = Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -like "$($target.Name):*" }
if ($d) {
    $d | Set-CimInstance -Property @{ InitialSize = 16384; MaximumSize = 40960 }
} else {
    Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{
        Name = $dName; InitialSize = 16384; MaximumSize = 40960 } | Out-Null
}
Write-Host "  $dName -> 16384 / 40960 MB" -ForegroundColor Green

Write-Host "`n--- configured ---"
Get-CimInstance Win32_PageFileSetting |
    Select-Object Name, InitialSize, MaximumSize |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host "REBOOT now, then run .\Test-Two-Instances.ps1" -ForegroundColor Cyan
