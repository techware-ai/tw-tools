# ============================================================
# BSOD STATUS CHECK — TECHWARE IT SERVICES PLT
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

# ── SECTION 2: BSOD EVENT LOG ────────────────────────────────
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
        $stopCode = if ($_.Message -match '0x[0-9A-Fa-f]{8}') { $Matches[0] } else { "N/A" }
        Write-Host "    • $($_.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  |  Stop Code: $stopCode" -ForegroundColor White
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
                "Run MemTest86 for 2+ passes (bootable USB)"
            )
        }
        "0x0000001A" = @{
            Name    = "MEMORY_MANAGEMENT"
            Cause   = "Faulty RAM or RAM compatibility issue"
            Steps   = @(
                "Run MemTest86 (bootable USB) → let run minimum 2 passes",
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
                "Check disk health with CrystalDiskInfo (look for Caution/Bad)",
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
                "Check disk health with CrystalDiskInfo",
                "Run MemTest86 to rule out RAM issue",
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
                "Run MemTest86 for RAM verification",
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
        Write-Host "    5. Run MemTest86 to check RAM" -ForegroundColor White
        Write-Host "    6. Check disk health with CrystalDiskInfo" -ForegroundColor White
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

Write-Host ""
Write-Host $divider -ForegroundColor DarkCyan
Write-Host "  Report generated by TECHWARE IT SERVICES PLT" -ForegroundColor DarkCyan
Write-Host "  For support: support@techware.my" -ForegroundColor DarkCyan
Write-Host $divider -ForegroundColor DarkCyan
Write-Host ""
