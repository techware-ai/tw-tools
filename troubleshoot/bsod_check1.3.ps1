# ============================================================
# BSOD STATUS CHECK — TECHWARE IT SERVICES PLT
# Version : 1.3
# Easy-read report for end user / management
# Run as: PowerShell (Administrator)
# ============================================================

$divider  = "=" * 60
$computer = $env:COMPUTERNAME
$user     = $env:USERNAME
$date     = Get-Date -Format "dd/MM/yyyy hh:mm tt"

# ── Collect Data ─────────────────────────────────────────────

# 1. Minidump files
$dumpPath  = "C:\Windows\Minidump"
$dumpFiles = @()
if (Test-Path $dumpPath) {
    $dumpFiles = Get-ChildItem $dumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending
}

# 2. BugCheck events (Event ID 1001 = BSOD logged)
$bugChecks = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id      = 1001
} -MaxEvents 10 -ErrorAction SilentlyContinue

# 3. Kernel-Power 41 (unexpected shutdown / hard crash)
$kp41 = Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    Id           = 41
    ProviderName = 'Microsoft-Windows-Kernel-Power'
} -MaxEvents 10 -ErrorAction SilentlyContinue

# 4. Crash dump config
$crashReg    = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -ErrorAction SilentlyContinue
$dumpEnabled = switch ($crashReg.CrashDumpEnabled) {
    0 { "Disabled (BSODs will NOT be saved)" }
    1 { "Complete Memory Dump" }
    2 { "Kernel Memory Dump" }
    3 { "Small Memory Dump (Minidump)" }
    7 { "Automatic Memory Dump" }
    default { "Unknown" }
}

# 5. Overall status
$hasBSOD = ($dumpFiles.Count -gt 0) -or ($bugChecks.Count -gt 0) -or ($kp41.Count -gt 0)

# ── Print Report ──────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host $divider -ForegroundColor DarkCyan
Write-Host "  BSOD STATUS REPORT — TECHWARE IT SERVICES PLT" -ForegroundColor Cyan
Write-Host "  Version  : 1.3" -ForegroundColor DarkCyan
Write-Host $divider -ForegroundColor DarkCyan
Write-Host "  Computer : $computer"
Write-Host "  User     : $user"
Write-Host "  Date     : $date"
Write-Host $divider -ForegroundColor DarkCyan
Write-Host ""

# ── OVERALL RESULT ────────────────────────────────────────────
if (-not $hasBSOD) {
    Write-Host "  ✅  OVERALL STATUS : NO BSOD DETECTED" -ForegroundColor Green
    Write-Host ""
    Write-Host "  This computer has no recorded Blue Screen crash events." -ForegroundColor Gray
    Write-Host "  System appears stable based on available log data." -ForegroundColor Gray
} else {
    Write-Host "  ⚠️   OVERALL STATUS : BSOD / CRASH DETECTED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  One or more crash events were found. See details below." -ForegroundColor Yellow
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 1: MINIDUMP FILES ─────────────────────────────────
Write-Host ""
Write-Host "  [1] CRASH DUMP FILES" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $dumpPath)) {
    Write-Host "  Status  : ⚠️  Minidump folder does not exist" -ForegroundColor Yellow
    Write-Host "  Meaning : Windows is not saving crash files." -ForegroundColor Gray
    Write-Host "  Action  : Enable Small Memory Dump via System Properties." -ForegroundColor Gray
} elseif ($dumpFiles.Count -eq 0) {
    Write-Host "  Status  : ✅  No crash dump files found" -ForegroundColor Green
    Write-Host "  Meaning : No BSOD crash files have been recorded." -ForegroundColor Gray
} else {
    Write-Host "  Status  : ❌  $($dumpFiles.Count) crash dump file(s) found" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Recent crash files:" -ForegroundColor Yellow
    $dumpFiles | Select-Object -First 5 | ForEach-Object {
        $age = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 0)
        Write-Host "    • $($_.Name)   |  Date: $($_.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))  |  $($age) day(s) ago" -ForegroundColor White
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 2: BSOD EVENT LOG (ENHANCED) ─────────────────────
Write-Host ""
Write-Host "  [2] BSOD EVENT LOG (Windows System Log)" -ForegroundColor Cyan
Write-Host ""

if ($bugChecks.Count -eq 0) {
    Write-Host "  Status  : ✅  No BSOD events logged" -ForegroundColor Green
    Write-Host "  Meaning : Windows has not recorded any Blue Screen events." -ForegroundColor Gray
} else {
    Write-Host "  Status  : ❌  $($bugChecks.Count) BSOD event(s) found in System Log" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Recent BSOD events:" -ForegroundColor Yellow
    $bugChecks | Select-Object -First 5 | ForEach-Object {
        $stopCode   = if ($_.Message -match '0x[0-9A-Fa-f]{8}') { $Matches[0] } else { "N/A" }
        $faultyDriver = if ($_.Message -match 'probably caused by\s*:\s*(\S+)') { $Matches[1] }
                        elseif ($_.Message -match 'IMAGE_NAME:\s*(\S+)')          { $Matches[1] }
                        else { "N/A" }
        Write-Host "    • $($_.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  |  Stop Code: $stopCode  |  Driver: $faultyDriver" -ForegroundColor White
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 3: UNEXPECTED SHUTDOWN ───────────────────────────
Write-Host ""
Write-Host "  [3] UNEXPECTED SHUTDOWN / POWER LOSS" -ForegroundColor Cyan
Write-Host ""

if ($kp41.Count -eq 0) {
    Write-Host "  Status  : ✅  No unexpected shutdowns detected" -ForegroundColor Green
    Write-Host "  Meaning : System has been shutting down normally." -ForegroundColor Gray
} else {
    Write-Host "  Status  : ⚠️   $($kp41.Count) unexpected shutdown(s) found" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Recent unexpected shutdowns:" -ForegroundColor Yellow
    $kp41 | Select-Object -First 5 | ForEach-Object {
        $age = [math]::Round(((Get-Date) - $_.TimeCreated).TotalDays, 0)
        Write-Host "    • $($_.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  |  $($age) day(s) ago" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Note    : Can be caused by BSOD, power cut, or forced shutdown." -ForegroundColor Gray
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 4: DUMP SETTING ───────────────────────────────────
Write-Host ""
Write-Host "  [4] CRASH DUMP CONFIGURATION" -ForegroundColor Cyan
Write-Host ""

if ($crashReg.CrashDumpEnabled -eq 3 -or $crashReg.CrashDumpEnabled -eq 7 -or $crashReg.CrashDumpEnabled -eq 1) {
    Write-Host "  Status  : ✅  Crash logging is ENABLED" -ForegroundColor Green
} elseif ($crashReg.CrashDumpEnabled -eq 0) {
    Write-Host "  Status  : ❌  Crash logging is DISABLED" -ForegroundColor Red
} else {
    Write-Host "  Status  : ⚠️   Crash logging may not be optimal" -ForegroundColor Yellow
}

Write-Host "  Setting : $dumpEnabled" -ForegroundColor Gray
Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SUMMARY ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host ""

$items = @(
    @{ Label = "Crash Dump Files";         OK = $dumpFiles.Count -eq 0;  Detail = if ($dumpFiles.Count -gt 0) { "$($dumpFiles.Count) file(s) found" } else { "None found" } }
    @{ Label = "BSOD Event Log";           OK = $bugChecks.Count -eq 0;  Detail = if ($bugChecks.Count -gt 0) { "$($bugChecks.Count) event(s)" } else { "No events" } }
    @{ Label = "Unexpected Shutdowns";     OK = $kp41.Count -eq 0;       Detail = if ($kp41.Count -gt 0) { "$($kp41.Count) event(s)" } else { "No events" } }
    @{ Label = "Crash Dump Config";        OK = ($crashReg.CrashDumpEnabled -ne 0); Detail = $dumpEnabled }
)

foreach ($item in $items) {
    $icon   = if ($item.OK) { "✅" } else { "❌" }
    $color  = if ($item.OK) { "Green" } else { "Red" }
    $label  = $item.Label.PadRight(28)
    Write-Host "  $icon  $label : $($item.Detail)" -ForegroundColor $color
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 5: RECOMMENDED ACTION (only if BSOD found) ───────
if ($hasBSOD) {

    Write-Host ""
    Write-Host "  [5] RECOMMENDED ACTION" -ForegroundColor Cyan
    Write-Host ""

    # Stop code lookup table
    $stopCodeDB = @{
        "0x0000003B" = @{
            Name    = "SYSTEM_SERVICE_EXCEPTION"
            Cause   = "Faulty driver or system service conflict"
            Steps   = @(
                "Update or rollback recently installed drivers (Device Manager)",
                "Run SFC scan → Open CMD as Admin → sfc /scannow",
                "Run DISM → DISM /Online /Cleanup-Image /RestoreHealth",
                "Check Event Viewer → Windows Logs → System for related errors",
                "Boot to Safe Mode and test stability"
            )
        }
        "0x0000007E" = @{
            Name    = "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED"
            Cause   = "Driver crash or incompatible hardware driver"
            Steps   = @(
                "Identify faulty driver from minidump using WhoCrashed",
                "Update all drivers especially GPU, NIC, chipset",
                "Uninstall recently added hardware or software",
                "Run SFC → sfc /scannow",
                "Check Windows Update for pending patches"
            )
        }
        "0x00000050" = @{
            Name    = "PAGE_FAULT_IN_NONPAGED_AREA"
            Cause   = "Faulty RAM or driver accessing invalid memory"
            Steps   = @(
                "Run Windows Memory Diagnostic → Win+R → mdsched.exe → Restart now",
                "If multiple RAM sticks → test one stick at a time",
                "Reseat RAM sticks (remove and re-insert firmly)",
                "Update or rollback drivers especially GPU and antivirus",
                "Run SFC → sfc /scannow"
            )
        }
        "0x0000000A" = @{
            Name    = "IRQL_NOT_LESS_OR_EQUAL"
            Cause   = "Driver accessing memory at wrong processor level"
            Steps   = @(
                "Update or rollback recently changed drivers",
                "Use DDU to cleanly uninstall GPU drivers → reinstall fresh",
                "Check msinfo32 → Software Environment → System Drivers → sort by Date",
                "Disable XMP/EXPO in BIOS if RAM is overclocked",
                "Run Windows Memory Diagnostic → Win+R → mdsched.exe → Restart now"
            )
        }
        "0x0000001A" = @{
            Name    = "MEMORY_MANAGEMENT"
            Cause   = "Faulty RAM or RAM compatibility issue"
            Steps   = @(
                "Run Windows Memory Diagnostic → Win+R → mdsched.exe → Restart now",
                "Run Windows Memory Diagnostic → mdsched.exe",
                "Test RAM sticks one at a time to isolate faulty stick",
                "Check RAM is seated properly in correct slots (check motherboard manual)",
                "Disable XMP/EXPO profile in BIOS and test at stock speeds"
            )
        }
        "0x0000009F" = @{
            Name    = "DRIVER_POWER_STATE_FAILURE"
            Cause   = "Driver not handling sleep/wake correctly"
            Steps   = @(
                "Update all drivers especially USB, NIC, GPU, and chipset",
                "Disable Fast Startup → Control Panel → Power Options → Choose what power buttons do",
                "Run powercfg /energy in CMD as Admin → review report",
                "Check Device Manager for any yellow warning devices",
                "Update BIOS/UEFI firmware from manufacturer site"
            )
        }
        "0x00000024" = @{
            Name    = "NTFS_FILE_SYSTEM"
            Cause   = "Disk corruption or failing hard drive"
            Steps   = @(
                "Run CHKDSK → CMD as Admin → chkdsk C: /f /r → schedule on reboot",
                "Check disk health with PowerShell → see Section 12 (Disk SMART) in this report",
                "Run SFC → sfc /scannow",
                "Check SMART data → Get-PhysicalDisk | Get-StorageReliabilityCounter",
                "Back up data immediately if disk shows bad sectors"
            )
        }
        "0x0000007A" = @{
            Name    = "KERNEL_DATA_INPAGE_ERROR"
            Cause   = "Failing disk or RAM unable to read kernel data"
            Steps   = @(
                "Run CHKDSK → chkdsk C: /f /r /x (schedule on reboot)",
                "Check disk health with PowerShell → see Section 12 (Disk SMART) in this report",
                "Run Windows Memory Diagnostic → Win+R → mdsched.exe → Restart now",
                "Check disk cables/connections (desktop) or reseat SSD (laptop)",
                "Back up data immediately before further repair steps"
            )
        }
        "0x000000EF" = @{
            Name    = "CRITICAL_PROCESS_DIED"
            Cause   = "Critical Windows system process crashed or corrupted"
            Steps   = @(
                "Run SFC → sfc /scannow",
                "Run DISM → DISM /Online /Cleanup-Image /RestoreHealth",
                "Check for malware → Run Windows Defender offline scan",
                "Uninstall recent Windows Updates if issue started after update",
                "Use System Restore to revert to last known good state"
            )
        }
        "0x0000007B" = @{
            Name    = "INACCESSIBLE_BOOT_DEVICE"
            Cause   = "Windows cannot access the boot drive (driver or disk issue)"
            Steps   = @(
                "Boot from Windows USB → Run Startup Repair",
                "Check storage controller drivers in BIOS (AHCI vs RAID mode)",
                "Run CHKDSK from Windows Recovery → chkdsk C: /f /r",
                "Run SFC from Recovery → sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows",
                "Check if SSD/HDD is detected in BIOS"
            )
        }
        "0xC000021A" = @{
            Name    = "WHEA_UNCORRECTABLE_ERROR"
            Cause   = "Hardware error — CPU, RAM, or motherboard fault"
            Steps   = @(
                "Check CPU and GPU temperatures with HWiNFO64 (CPU < 90C, GPU < 85C)",
                "Disable CPU/RAM overclocking → reset BIOS to default",
                "Reseat RAM and check for bent CPU pins",
                "Run Windows Memory Diagnostic → Win+R → mdsched.exe → Restart now",
                "Check Event Viewer → System → WHEA-Logger for hardware error details"
            )
        }
    }

    # Extract stop codes from bugcheck events
    $foundCodes = @()
    if ($bugChecks.Count -gt 0) {
        $bugChecks | Select-Object -First 3 | ForEach-Object {
            if ($_.Message -match '0x[0-9A-Fa-f]{8}') {
                $code = $Matches[0].ToUpper()
                if ($foundCodes -notcontains $code) { $foundCodes += $code }
            }
        }
    }

    if ($foundCodes.Count -eq 0 -and $hasBSOD) {
        # BSOD detected but no stop code extracted (dump files only or KP41)
        Write-Host "  Stop Code : Could not extract stop code automatically" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  General Next Steps:" -ForegroundColor Yellow
        Write-Host "    1. Run WhoCrashed to read minidump → resplendence.com/whoCrashed" -ForegroundColor White
        Write-Host "    2. Run SFC → Open CMD as Admin → sfc /scannow" -ForegroundColor White
        Write-Host "    3. Run DISM → DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor White
        Write-Host "    4. Update all drivers (GPU, NIC, Chipset)" -ForegroundColor White
        Write-Host "    5. Run Windows Memory Diagnostic → Win+R → mdsched.exe → Restart now" -ForegroundColor White
        Write-Host "    6. Check disk health → see Section 12 (Disk SMART) in this report" -ForegroundColor White
    } else {
        foreach ($code in $foundCodes) {
            $info = $stopCodeDB[$code]
            Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
            if ($info) {
                Write-Host "  Stop Code : $code  ($($info.Name))" -ForegroundColor Red
                Write-Host "  Likely    : $($info.Cause)" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Next Steps:" -ForegroundColor Cyan
                $i = 1
                foreach ($step in $info.Steps) {
                    Write-Host "    $i. $step" -ForegroundColor White
                    $i++
                }
            } else {
                Write-Host "  Stop Code : $code  (Unknown / Uncommon)" -ForegroundColor Red
                Write-Host "  Likely    : Driver conflict, hardware fault, or OS corruption" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Next Steps:" -ForegroundColor Cyan
                Write-Host "    1. Search online: Windows BSOD $code fix" -ForegroundColor White
                Write-Host "    2. Run WhoCrashed → resplendence.com/whoCrashed" -ForegroundColor White
                Write-Host "    3. Run SFC → sfc /scannow" -ForegroundColor White
                Write-Host "    4. Run DISM → DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor White
                Write-Host "    5. Update all drivers and Windows" -ForegroundColor White
            }
            Write-Host ""
        }
    }

    # Always remind about data backup
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ⚠️  IMPORTANT : Back up user data before running repairs" -ForegroundColor Yellow
    Write-Host "  Tool : Macrium Reflect Free → macrium.com" -ForegroundColor Gray
    Write-Host ""
    Write-Host $divider -ForegroundColor DarkGray
}

# ── SECTION 6: LAST BOOT TIME & UPTIME ───────────────────────
Write-Host ""
Write-Host "  [6] LAST BOOT TIME & UPTIME" -ForegroundColor Cyan
Write-Host ""

$lastBoot   = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptime     = (Get-Date) - $lastBoot
$uptimeDays = [math]::Round($uptime.TotalDays, 0)

Write-Host "  Last Boot : $($lastBoot.ToString('dd/MM/yyyy hh:mm tt'))" -ForegroundColor White
Write-Host "  Uptime    : $uptimeDays day(s)" -ForegroundColor White
Write-Host ""

if ($uptimeDays -gt 30) {
    Write-Host "  Status  : ⚠️  PC has not been restarted in over 30 days" -ForegroundColor Yellow
    Write-Host "  Meaning : Pending updates may not be applied. Restart recommended." -ForegroundColor Gray
} elseif ($uptimeDays -gt 14) {
    Write-Host "  Status  : ⚠️  PC has not been restarted in over 14 days" -ForegroundColor Yellow
    Write-Host "  Meaning : Consider restarting to apply pending Windows updates." -ForegroundColor Gray
} else {
    Write-Host "  Status  : ✅  Uptime is normal" -ForegroundColor Green
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 7: WINDOWS VERSION & BUILD (ENHANCED) ────────────
Write-Host ""
Write-Host "  [7] WINDOWS VERSION & BUILD" -ForegroundColor Cyan
Write-Host ""

$os         = Get-CimInstance Win32_OperatingSystem
$winVer     = $os.Caption
$winBuild   = $os.BuildNumber
$winVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion

Write-Host "  OS      : $winVer" -ForegroundColor White
Write-Host "  Version : $winVersion" -ForegroundColor White
Write-Host "  Build   : $winBuild" -ForegroundColor White
Write-Host ""

# Windows 10 EOL warning (EOL: October 2025)
if ($winVer -match "Windows 10") {
    Write-Host "  Status  : ❌  Windows 10 is END OF LIFE (EOL)" -ForegroundColor Red
    Write-Host "  Meaning : Microsoft ended support in October 2025. No more security patches." -ForegroundColor Yellow
    Write-Host "  Action  : Upgrade to Windows 11 as soon as possible." -ForegroundColor Yellow
} else {
    # Flag outdated Win 11 builds
    $outdatedBuilds = @("22000","22621")
    if ($outdatedBuilds -contains $winBuild) {
        Write-Host "  Status  : ⚠️  Windows build may be outdated" -ForegroundColor Yellow
        Write-Host "  Meaning : Older builds have known BSOD issues. Update recommended." -ForegroundColor Gray
        Write-Host "  Action  : Settings → Windows Update → Check for updates" -ForegroundColor Gray
    } else {
        Write-Host "  Status  : ✅  Windows build appears current" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 8: RECENT DRIVER CHANGES (ENHANCED) ──────────────
Write-Host ""
Write-Host "  [8] RECENT DRIVER CHANGES (Last 7 Days)" -ForegroundColor Cyan
Write-Host ""

$sevenDaysAgo  = (Get-Date).AddDays(-7)
$recentDrivers = Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    Id           = 7045
    StartTime    = $sevenDaysAgo
} -ErrorAction SilentlyContinue

# Event ID 7034 = service crashed unexpectedly (catches driver crashes)
$crashedServices = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = 7034
    StartTime = $sevenDaysAgo
} -ErrorAction SilentlyContinue | Select-Object -First 5

if ($recentDrivers.Count -eq 0) {
    Write-Host "  Status  : ✅  No new drivers installed in last 7 days" -ForegroundColor Green
    Write-Host "  Meaning : Driver changes are unlikely cause of any BSOD." -ForegroundColor Gray
} else {
    Write-Host "  Status  : ⚠️  $($recentDrivers.Count) driver(s) installed in last 7 days" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Recent driver installs:" -ForegroundColor Yellow
    $recentDrivers | Select-Object -First 5 | ForEach-Object {
        $driverName = if ($_.Message -match "service name is '(.+?)'") { $Matches[1] } else { "Unknown" }
        Write-Host "    • $($_.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  |  $driverName" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Note    : Recent driver installs are the most common BSOD cause." -ForegroundColor Gray
    Write-Host "  Action  : If BSOD started after install → rollback via Device Manager." -ForegroundColor Gray
}

Write-Host ""

if ($crashedServices.Count -gt 0) {
    Write-Host "  ⚠️  Crashed Services / Drivers (last 7 days):" -ForegroundColor Yellow
    $crashedServices | ForEach-Object {
        $svcName = if ($_.Message -match "The (.+?) service terminated") { $Matches[1] } else { "Unknown service" }
        Write-Host "    • $($_.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  |  $svcName" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Note    : Crashed services can trigger BSOD if they are kernel-level drivers." -ForegroundColor Gray
    Write-Host ""
}

Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 9: RAM INFORMATION (NEW) ─────────────────────────
Write-Host ""
Write-Host "  [9] RAM INFORMATION" -ForegroundColor Cyan
Write-Host ""

$ramSticks  = Get-CimInstance Win32_PhysicalMemory
$totalRAMGB = [math]::Round(($ramSticks | Measure-Object Capacity -Sum).Sum / 1GB, 1)
$ramCount   = $ramSticks.Count

Write-Host "  Total RAM : $totalRAMGB GB  ($ramCount stick(s) installed)" -ForegroundColor White
Write-Host ""

$stickNum = 1
foreach ($stick in $ramSticks) {
    $sizeGB    = [math]::Round($stick.Capacity / 1GB, 0)
    $speedMHz  = $stick.Speed
    $mfr       = if ($stick.Manufacturer) { $stick.Manufacturer.Trim() } else { "Unknown" }
    $slot      = if ($stick.DeviceLocator) { $stick.DeviceLocator } else { "Slot $stickNum" }
    Write-Host "  Stick $stickNum   : $sizeGB GB  |  $speedMHz MHz  |  $mfr  |  $slot" -ForegroundColor White
    $stickNum++
}

Write-Host ""

# Check configured vs actual speed
$configuredSpeed = ($ramSticks | Measure-Object Speed -Maximum).Maximum
$actualSpeed     = (Get-CimInstance Win32_OperatingSystem).TotalVirtualMemorySize  # placeholder
$memProfile      = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -ErrorAction SilentlyContinue)

# Check XMP via SMBIOS configured clock speed
$smbiosSpeed = (Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object -First 1).ConfiguredClockSpeed
if ($smbiosSpeed -and $configuredSpeed -and ($smbiosSpeed -lt $configuredSpeed)) {
    Write-Host "  Status  : ⚠️  RAM running below rated speed" -ForegroundColor Yellow
    Write-Host "  Rated   : $configuredSpeed MHz  |  Running at: $smbiosSpeed MHz" -ForegroundColor Gray
    Write-Host "  Meaning : XMP/EXPO profile may not be enabled in BIOS." -ForegroundColor Gray
    Write-Host "  Action  : Enter BIOS → Enable XMP or EXPO profile for rated speed." -ForegroundColor Gray
} else {
    Write-Host "  Status  : ✅  RAM speed appears normal" -ForegroundColor Green
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 10: ANTIVIRUS STATUS (NEW) ───────────────────────
Write-Host ""
Write-Host "  [10] ANTIVIRUS STATUS" -ForegroundColor Cyan
Write-Host ""

$avProducts = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue

if (-not $avProducts) {
    Write-Host "  Status  : ⚠️  Could not query antivirus (may need to run on workstation OS)" -ForegroundColor Yellow
    Write-Host "  Note    : SecurityCenter2 is not available on Windows Server." -ForegroundColor Gray
} elseif ($avProducts.Count -eq 0) {
    Write-Host "  Status  : ❌  No antivirus detected" -ForegroundColor Red
    Write-Host "  Meaning : System has no registered antivirus product." -ForegroundColor Gray
    Write-Host "  Action  : Ensure Windows Defender is active or install an AV solution." -ForegroundColor Gray
} else {
    foreach ($av in $avProducts) {
        # productState hex decode: 0x1000 = enabled, 0x0010 = up to date
        $state      = $av.productState
        $isEnabled  = ($state -band 0x1000) -ne 0
        $isUpdated  = ($state -band 0x0010) -eq 0  # 0x0010 = OUT of date

        $avStatus   = if ($isEnabled) { "Active" } else { "Inactive" }
        $avUpdated  = if ($isUpdated) { "Up to date" } else { "OUT OF DATE ⚠️" }
        $avColor    = if ($isEnabled -and $isUpdated) { "Green" } else { "Red" }

        Write-Host "  AV Name : $($av.displayName)" -ForegroundColor White
        Write-Host "  Status  : $avStatus  |  Definitions: $avUpdated" -ForegroundColor $avColor
        Write-Host ""
    }

    # Warn if outdated AV detected
    $outdatedAV = $avProducts | Where-Object { ($_.productState -band 0x0010) -ne 0 }
    if ($outdatedAV) {
        Write-Host "  ⚠️  Warning : Outdated AV definitions can cause system instability." -ForegroundColor Yellow
        Write-Host "  Action  : Update antivirus definitions immediately." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 11: PENDING WINDOWS UPDATE (NEW) ─────────────────
Write-Host ""
Write-Host "  [11] PENDING WINDOWS UPDATES" -ForegroundColor Cyan
Write-Host ""

try {
    $updateSession  = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult   = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
    $pendingCount   = $searchResult.Updates.Count

    if ($pendingCount -eq 0) {
        Write-Host "  Status  : ✅  No pending Windows Updates" -ForegroundColor Green
        Write-Host "  Meaning : System is fully up to date." -ForegroundColor Gray
    } else {
        Write-Host "  Status  : ⚠️  $pendingCount pending update(s) found" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Pending updates:" -ForegroundColor Yellow
        $searchResult.Updates | Select-Object -First 5 | ForEach-Object {
            Write-Host "    • $($_.Title)" -ForegroundColor White
        }
        if ($pendingCount -gt 5) {
            Write-Host "    ... and $($pendingCount - 5) more" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  Note    : Pending updates may contain BSOD fixes and security patches." -ForegroundColor Gray
        Write-Host "  Action  : Settings → Windows Update → Update Now" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Status  : ⚠️  Could not query Windows Update service" -ForegroundColor Yellow
    Write-Host "  Action  : Manually check via Settings → Windows Update" -ForegroundColor Gray
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── SECTION 12: DISK SMART HEALTH (NEW) ──────────────────────
Write-Host ""
Write-Host "  [12] DISK HEALTH (SMART CHECK)" -ForegroundColor Cyan
Write-Host ""

$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue

if (-not $disks) {
    Write-Host "  Status  : ⚠️  Could not retrieve disk information" -ForegroundColor Yellow
} else {
    foreach ($disk in $disks) {
        $rel       = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $sizeGB    = [math]::Round($disk.Size / 1GB, 0)
        $diskColor = switch ($disk.HealthStatus) {
            "Healthy"  { "Green" }
            "Warning"  { "Yellow" }
            "Unhealthy"{ "Red" }
            default    { "Gray" }
        }

        Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  Disk     : $($disk.FriendlyName)" -ForegroundColor White
        Write-Host "  Type     : $($disk.MediaType)  |  Size: $sizeGB GB  |  Bus: $($disk.BusType)" -ForegroundColor White

        $healthIcon = switch ($disk.HealthStatus) {
            "Healthy"   { "✅" }
            "Warning"   { "⚠️" }
            "Unhealthy" { "❌" }
            default     { "❓" }
        }
        Write-Host "  Health   : $healthIcon $($disk.HealthStatus)  |  Status: $($disk.OperationalStatus)" -ForegroundColor $diskColor

        if ($rel) {
            $tempC        = if ($rel.Temperature)         { "$($rel.Temperature) °C" }         else { "N/A" }
            $powerOnHrs   = if ($rel.PowerOnHours)        { "$($rel.PowerOnHours) hrs" }        else { "N/A" }
            $readErr      = if ($null -ne $rel.ReadErrorsTotal)  { $rel.ReadErrorsTotal }  else { "N/A" }
            $writeErr     = if ($null -ne $rel.WriteErrorsTotal) { $rel.WriteErrorsTotal } else { "N/A" }
            $reallocSect  = if ($null -ne $rel.Wear)             { $rel.Wear }             else { "N/A" }

            Write-Host "  Temp     : $tempC  |  Power-On: $powerOnHrs" -ForegroundColor White
            Write-Host "  Errors   : Read: $readErr  |  Write: $writeErr  |  Wear: $reallocSect%" -ForegroundColor White

            # Flag warnings
            if ($rel.Temperature -and $rel.Temperature -gt 55) {
                Write-Host "  ⚠️  Warning : Disk temperature is HIGH ($($rel.Temperature)°C). Check airflow." -ForegroundColor Yellow
            }
            if ($rel.ReadErrorsTotal -and $rel.ReadErrorsTotal -gt 0) {
                Write-Host "  ⚠️  Warning : Read errors detected. Back up data immediately." -ForegroundColor Yellow
            }
            if ($rel.WriteErrorsTotal -and $rel.WriteErrorsTotal -gt 0) {
                Write-Host "  ⚠️  Warning : Write errors detected. Disk may be failing." -ForegroundColor Yellow
            }
            if ($rel.Wear -and $rel.Wear -le 10) {
                Write-Host "  ⚠️  Warning : SSD wear life is critically low ($($rel.Wear)%). Replace soon." -ForegroundColor Red
            }
            if ($rel.PowerOnHours -and $rel.PowerOnHours -gt 35000) {
                Write-Host "  ⚠️  Warning : Disk has very high usage ($($rel.PowerOnHours) hrs). Consider replacing." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  SMART    : Could not retrieve SMART counters for this disk." -ForegroundColor Gray
        }
        Write-Host ""
    }

    # Overall disk verdict
    $badDisks = $disks | Where-Object { $_.HealthStatus -ne "Healthy" }
    if ($badDisks) {
        Write-Host "  ❌  One or more disks are NOT healthy — back up data immediately!" -ForegroundColor Red
        Write-Host "  Action  : Run CHKDSK → CMD as Admin → chkdsk C: /f /r" -ForegroundColor Yellow
        Write-Host "  Action  : Schedule scan on next reboot if drive is in use." -ForegroundColor Yellow
    } else {
        Write-Host "  ✅  All disks report Healthy status." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host $divider -ForegroundColor DarkGray

# ── FOOTER ────────────────────────────────────────────────────
Write-Host ""
Write-Host $divider -ForegroundColor DarkCyan
Write-Host "  Report generated by TECHWARE IT SERVICES PLT" -ForegroundColor DarkCyan
Write-Host "  Version  : 1.3" -ForegroundColor DarkCyan
Write-Host "  For support: support@techware.my" -ForegroundColor DarkCyan
Write-Host $divider -ForegroundColor DarkCyan
Write-Host ""
