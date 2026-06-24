#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Techware IT Tools - System Check v1.0
.DESCRIPTION
    Unified system diagnostic script covering system info, disk health,
    driver audit, and network diagnostics.
    Run as Administrator via:
    irm "https://raw.githubusercontent.com/techware-ai/tw-tools/main/troubleshoot/system_check1.0.ps1" | iex
.NOTES
    Support: support@techware.my
#>

# ============================================================
#  GLOBALS & INIT
# ============================================================
$ScriptVersion  = "1.0"
$ScriptName     = "Techware IT Tools - System Check v$ScriptVersion"
$SupportEmail   = "support@techware.my"
$RunDate        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ReportPath     = "$env:USERPROFILE\Desktop\TW_SystemCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

$Output         = [System.Collections.Generic.List[string]]::new()

# ── Colour palette ──────────────────────────────────────────
$C = @{
    Header  = 'Cyan'
    Section = 'Yellow'
    OK      = 'Green'
    Warn    = 'Yellow'
    Error   = 'Red'
    Info    = 'White'
    Dim     = 'DarkGray'
}

# ── Helper functions ─────────────────────────────────────────
function Write-Header {
    Clear-Host
    $line = "=" * 70
    Write-Host $line -ForegroundColor $C.Header
    Write-Host "  $ScriptName" -ForegroundColor $C.Header
    Write-Host "  Run: $RunDate" -ForegroundColor $C.Dim
    Write-Host "  $SupportEmail" -ForegroundColor $C.Dim
    Write-Host $line -ForegroundColor $C.Header
    Write-Host ""
}

function Write-Section {
    param([string]$Title, [int]$Num)
    $line = "-" * 70
    Write-Host ""
    Write-Host $line -ForegroundColor $C.Section
    Write-Host "  [$Num] $Title" -ForegroundColor $C.Section
    Write-Host $line -ForegroundColor $C.Section
    $script:Output.Add("")
    $script:Output.Add($line)
    $script:Output.Add("  [$Num] $Title")
    $script:Output.Add($line)
}

function Out {
    param([string]$Text = "", [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
    $script:Output.Add($Text)
}

function Out-KV {
    param([string]$Key, [string]$Value, [string]$Color = "White")
    $line = "  {0,-30} {1}" -f $Key, $Value
    Write-Host $line -ForegroundColor $Color
    $script:Output.Add($line)
}

function Out-Status {
    param([string]$Key, [string]$Value, [string]$Status)
    $color = switch ($Status) {
        "OK"   { $C.OK }
        "WARN" { $C.Warn }
        "ERR"  { $C.Error }
        default { $C.Info }
    }
    $line = "  {0,-30} {1}" -f $Key, $Value
    Write-Host $line -ForegroundColor $color
    $script:Output.Add($line)
}

# ============================================================
#  SECTION 1 — SYSTEM INFORMATION
# ============================================================
function Get-SystemInfo {
    Write-Section "System Information" 1

    try {
        $cs  = Get-CimInstance Win32_ComputerSystem
        $os  = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $mb  = Get-CimInstance Win32_BaseBoard
        $bios = Get-CimInstance Win32_BIOS

        # Basic identity
        Out-KV "Hostname"          $env:COMPUTERNAME
        Out-KV "Manufacturer"      $cs.Manufacturer
        Out-KV "Model"             $cs.Model
        Out-KV "Serial Number"     $bios.SerialNumber
        Out-KV "Motherboard"       "$($mb.Manufacturer) $($mb.Product)"
        Out ""

        # OS
        Out-KV "Windows Version"   $os.Caption
        Out-KV "Build"             $os.BuildNumber
        Out-KV "Architecture"      $os.OSArchitecture
        Out-KV "Install Date"      ($os.InstallDate.ToString("yyyy-MM-dd"))
        Out-KV "Registered User"   $cs.UserName
        Out ""

        # CPU
        Out-KV "CPU"               $cpu.Name.Trim()
        Out-KV "Cores / Threads"   "$($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"
        Out-KV "CPU Speed"         "$([math]::Round($cpu.MaxClockSpeed/1000,2)) GHz"
        Out ""

        # RAM
        $ramGB    = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        $freeGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedGB   = [math]::Round($ramGB - $freeGB, 2)
        $ramPct   = [math]::Round(($usedGB / $ramGB) * 100, 0)
        $ramColor = if ($ramPct -gt 85) { $C.Error } elseif ($ramPct -gt 70) { $C.Warn } else { $C.OK }

        Out-KV "Total RAM"         "$ramGB GB"
        Out-Status "RAM Used"      "$usedGB GB / $ramGB GB ($ramPct%)" $(if ($ramPct -gt 85) {"ERR"} elseif ($ramPct -gt 70) {"WARN"} else {"OK"})

        # RAM sticks
        $dimms = Get-CimInstance Win32_PhysicalMemory
        foreach ($d in $dimms) {
            $gb   = [math]::Round($d.Capacity / 1GB, 0)
            $slot = $d.DeviceLocator
            Out-KV "  Slot: $slot"  "$gb GB  $($d.Speed) MHz  $($d.Manufacturer)"
        }
        Out ""

        # Uptime
        $boot   = $os.LastBootUpTime
        $uptime = (Get-Date) - $boot
        Out-KV "Last Boot"         $boot.ToString("yyyy-MM-dd HH:mm:ss")
        Out-KV "Uptime"            "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
        Out ""

        # Temperature note
        Out "  [i] Temperatures: Use HWiNFO64 for accurate CPU/GPU readings." -Color $C.Dim
        Out "      https://www.hwinfo.com/download/" -Color $C.Dim

    } catch {
        Out "  [!] Error collecting system info: $_" $C.Error
    }
}

# ============================================================
#  SECTION 2 — DISK HEALTH
# ============================================================
function Get-DiskHealth {
    Write-Section "Disk Health" 2

    try {
        $disks = Get-PhysicalDisk
        foreach ($disk in $disks) {
            Out ""
            Out-KV "Disk"              "$($disk.FriendlyName)"
            Out-KV "Media Type"        $disk.MediaType
            Out-KV "Bus Type"          $disk.BusType
            Out-KV "Size"              "$([math]::Round($disk.Size / 1GB, 0)) GB"

            $healthColor = switch ($disk.HealthStatus) {
                "Healthy"   { $C.OK }
                "Warning"   { $C.Warn }
                "Unhealthy" { $C.Error }
                default     { $C.Info }
            }
            Out-Status "Health Status" $disk.HealthStatus $(switch ($disk.HealthStatus) {"Healthy" {"OK"} "Warning" {"WARN"} "Unhealthy" {"ERR"} default {"INFO"}})

            # Reliability counters
            try {
                $rel = $disk | Get-StorageReliabilityCounter
                Out-KV "Read Errors"       $(if ($rel.ReadErrorsTotal -gt 0) { "⚠ $($rel.ReadErrorsTotal)" } else { "0" })
                Out-KV "Write Errors"      $(if ($rel.WriteErrorsTotal -gt 0) { "⚠ $($rel.WriteErrorsTotal)" } else { "0" })
                if ($rel.Wear -ne $null -and $rel.Wear -gt 0) {
                    $wearColor = if ($rel.Wear -gt 80) { "ERR" } elseif ($rel.Wear -gt 50) { "WARN" } else { "OK" }
                    Out-Status "SSD Wear %" "$($rel.Wear)%" $wearColor
                }
            } catch {
                Out-KV "Reliability"   "Not available on this disk/OS"
            }
            Out ""
        }

        # Logical disk free space
        Out "  Logical Drive Space:" -Color $C.Dim
        $volumes = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "^[A-Z]:\\" }
        foreach ($v in $volumes) {
            if ($v.Used -ne $null -and ($v.Used + $v.Free) -gt 0) {
                $total = $v.Used + $v.Free
                $pct   = [math]::Round(($v.Used / $total) * 100, 0)
                $gb    = [math]::Round($total / 1GB, 1)
                $free  = [math]::Round($v.Free / 1GB, 1)
                $status = if ($pct -gt 90) {"ERR"} elseif ($pct -gt 80) {"WARN"} else {"OK"}
                Out-Status "  $($v.Root)" "$free GB free of $gb GB ($pct% used)" $status
            }
        }

    } catch {
        Out "  [!] Error collecting disk info: $_" $C.Error
    }

    Out ""
    Out "  [i] For detailed SMART data, use CrystalDiskInfo:" -Color $C.Dim
    Out "      https://crystalmark.info/en/software/crystaldiskinfo/" -Color $C.Dim
}

# ============================================================
#  SECTION 3 — DRIVER AUDIT
# ============================================================
function Get-DriverAudit {
    Write-Section "Driver Audit" 3

    $cutoff7  = (Get-Date).AddDays(-7)
    $cutoff14 = (Get-Date).AddDays(-14)

    try {
        # Recent driver changes (last 14 days)
        Out "  Drivers changed in the last 14 days:" -Color $C.Warn
        $recent = Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.DriverDate -ne $null -and $_.DriverDate -gt $cutoff14 } |
            Sort-Object DriverDate -Descending

        if ($recent.Count -eq 0) {
            Out "  None found." -Color $C.OK
        } else {
            foreach ($d in $recent) {
                $age   = ((Get-Date) - $d.DriverDate).Days
                $color = if ($d.DriverDate -gt $cutoff7) { $C.Warn } else { $C.Info }
                $line  = "  {0,-35} {1,-20} {2} days ago" -f $d.DeviceName, $d.DriverVersion, $age
                Write-Host $line -ForegroundColor $color
                $script:Output.Add($line)
            }
        }

        Out ""
        Out "  Unsigned / No Signature drivers:" -Color $C.Warn

        $unsigned = Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.IsSigned -eq $false -or $_.Signer -eq $null -or $_.Signer -eq "" } |
            Where-Object { $_.DeviceName -ne $null -and $_.DeviceName -ne "" } |
            Sort-Object DeviceName

        if ($unsigned.Count -eq 0) {
            Out "  All drivers are signed. Good." -Color $C.OK
        } else {
            foreach ($d in $unsigned) {
                $line = "  ⚠ {0,-35} {1}" -f $d.DeviceName, $d.DriverVersion
                Write-Host $line -ForegroundColor $C.Warn
                $script:Output.Add($line)
            }
        }

        Out ""
        Out "  Failed / Error devices in Device Manager:" -Color $C.Error

        $errDevices = Get-CimInstance Win32_PnPEntity |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
            Sort-Object Name

        if ($errDevices.Count -eq 0) {
            Out "  No device errors found." -Color $C.OK
        } else {
            foreach ($d in $errDevices) {
                $line = "  ✖ {0,-40} Code: {1}" -f $d.Name, $d.ConfigManagerErrorCode
                Write-Host $line -ForegroundColor $C.Error
                $script:Output.Add($line)
            }
        }

    } catch {
        Out "  [!] Error collecting driver info: $_" $C.Error
    }
}

# ============================================================
#  SECTION 4 — NETWORK DIAGNOSTICS
# ============================================================
function Get-NetworkDiag {
    Write-Section "Network Diagnostics" 4

    try {
        # Active adapters
        Out "  Network Adapters (Active):" -Color $C.Dim
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        foreach ($a in $adapters) {
            Out-KV "  $($a.Name)" "$($a.Status)  $($a.LinkSpeed)  MAC: $($a.MacAddress)"
        }

        Out ""
        Out "  IP Configuration:" -Color $C.Dim
        $ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^127\." }
        foreach ($ip in $ips) {
            $gw = (Get-NetRoute -InterfaceIndex $ip.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop | Select-Object -First 1
            Out-KV "  $($ip.InterfaceAlias)" "IP: $($ip.IPAddress)  GW: $gw  Prefix: $($ip.PrefixLength)"
        }

        Out ""
        Out "  DNS Servers:" -Color $C.Dim
        $dns = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses }
        foreach ($d in $dns) {
            Out-KV "  $($d.InterfaceAlias)" ($d.ServerAddresses -join ", ")
        }

        Out ""
        Out "  Connectivity Tests:" -Color $C.Dim

        # Gateway ping
        $gwIP = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
        if ($gwIP) {
            $gwPing = Test-Connection -ComputerName $gwIP -Count 2 -Quiet -ErrorAction SilentlyContinue
            Out-Status "  Gateway ($gwIP)" $(if ($gwPing) { "Reachable" } else { "UNREACHABLE" }) $(if ($gwPing) { "OK" } else { "ERR" })
        }

        # DNS resolution test
        try {
            $resolve = Resolve-DnsName "google.com" -ErrorAction Stop
            Out-Status "  DNS Resolution (google.com)" "OK → $($resolve[0].IPAddress)" "OK"
        } catch {
            Out-Status "  DNS Resolution (google.com)" "FAILED" "ERR"
        }

        # Internet connectivity
        $internet = Test-Connection "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue
        Out-Status "  Internet (8.8.8.8)" $(if ($internet) { "Reachable" } else { "UNREACHABLE" }) $(if ($internet) { "OK" } else { "ERR" })

        # Latency to common endpoints
        Out ""
        Out "  Latency:" -Color $C.Dim
        $targets = @("8.8.8.8", "1.1.1.1", "google.com")
        foreach ($t in $targets) {
            try {
                $ping = Test-Connection $t -Count 3 -ErrorAction Stop
                $avg  = [math]::Round(($ping.ResponseTime | Measure-Object -Average).Average, 0)
                $color = if ($avg -gt 150) { "ERR" } elseif ($avg -gt 80) { "WARN" } else { "OK" }
                Out-Status "  $t" "${avg}ms avg" $color
            } catch {
                Out-Status "  $t" "No response" "ERR"
            }
        }

        # Open listening ports (top 20)
        Out ""
        Out "  Listening Ports (top 20):" -Color $C.Dim
        $ports = Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Select-Object -First 20
        foreach ($p in $ports) {
            $line = "  Port {0,-6} {1}" -f $p.LocalPort, $p.LocalAddress
            Write-Host $line -ForegroundColor $C.Dim
            $script:Output.Add($line)
        }

    } catch {
        Out "  [!] Error collecting network info: $_" $C.Error
    }
}

# ============================================================
#  SECTION 5 — LAST BOOT & UPTIME SUMMARY
# ============================================================
function Get-BootSummary {
    Write-Section "Last Boot & Uptime Summary" 5

    try {
        $os     = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime

        Out-KV "Last Boot Time"    $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss")
        Out-KV "Current Uptime"    "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m $($uptime.Seconds)s"

        # Unexpected shutdown (KP41 events)
        Out ""
        Out "  Kernel-Power Event 41 (unexpected shutdown) — last 10 events:" -Color $C.Warn
        try {
            $kp41 = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; ProviderName='Microsoft-Windows-Kernel-Power'} -MaxEvents 10 -ErrorAction Stop
            foreach ($e in $kp41) {
                $line = "  {0}  {1}" -f $e.TimeCreated.ToString("yyyy-MM-dd HH:mm"), $e.Message.Split("`n")[0]
                Write-Host $line -ForegroundColor $C.Warn
                $script:Output.Add($line)
            }
        } catch {
            Out "  No Kernel-Power 41 events found — good." -Color $C.OK
        }

        # Fast startup / hibernate state
        Out ""
        $fastBoot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ErrorAction SilentlyContinue).HiberbootEnabled
        Out-KV "Fast Startup"      $(if ($fastBoot -eq 1) { "Enabled" } else { "Disabled" })

    } catch {
        Out "  [!] Error collecting boot info: $_" $C.Error
    }
}

# ============================================================
#  SECTION 6 — WINDOWS VERSION & ACTIVATION
# ============================================================
function Get-WindowsInfo {
    Write-Section "Windows Version & Activation" 6

    try {
        $os    = Get-CimInstance Win32_OperatingSystem
        $cs    = Get-CimInstance Win32_ComputerSystem
        $winVer = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

        Out-KV "Edition"           $os.Caption
        Out-KV "Version"           $winVer.DisplayVersion
        Out-KV "Build"             "$($winVer.CurrentBuildNumber).$($winVer.UBR)"
        Out-KV "Install Date"      $os.InstallDate.ToString("yyyy-MM-dd")
        Out ""

        # Activation status
        try {
            $lic = Get-CimInstance SoftwareLicensingProduct |
                Where-Object { $_.PartialProductKey -and $_.Name -match "Windows" } |
                Select-Object -First 1
            $status = switch ($lic.LicenseStatus) {
                1 { "Licensed (Activated)" }
                2 { "Out-of-Box Grace" }
                3 { "Out-of-Tolerance Grace" }
                4 { "Non-Genuine Grace" }
                5 { "Notification" }
                6 { "Extended Grace" }
                default { "Unknown ($($lic.LicenseStatus))" }
            }
            $aColor = if ($lic.LicenseStatus -eq 1) { "OK" } else { "WARN" }
            Out-Status "Activation Status" $status $aColor
            Out-KV "Product Key (partial)" $lic.PartialProductKey
        } catch {
            Out-KV "Activation"    "Unable to query license status"
        }

        Out ""
        # Pending reboot check
        $pendingReboot = $false
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        )
        foreach ($key in $rebootKeys) {
            if (Test-Path $key) { $pendingReboot = $true }
        }
        Out-Status "Pending Reboot"    $(if ($pendingReboot) { "YES — reboot required" } else { "No" }) $(if ($pendingReboot) { "WARN" } else { "OK" })

        Out ""
        Out "  [i] Windows Repair (SFC, DISM, CHKDSK) is intentionally excluded" -Color $C.Dim
        Out "      from auto-run. Run manually when needed:" -Color $C.Dim
        Out "        sfc /scannow" -Color $C.Dim
        Out "        DISM /Online /Cleanup-Image /RestoreHealth" -Color $C.Dim
        Out "        chkdsk C: /f /r" -Color $C.Dim

    } catch {
        Out "  [!] Error collecting Windows info: $_" $C.Error
    }
}

# ============================================================
#  EXPORT REPORT
# ============================================================
function Export-Report {
    Write-Section "Export Report" 7

    try {
        $sep = ("=" * 70)
        $header = [string[]]@(
            $sep,
            "  $ScriptName",
            "  Generated : $RunDate",
            "  Device    : $env:COMPUTERNAME",
            "  Support   : $SupportEmail",
            $sep
        )
        $all = $header + [string[]]$Output.ToArray()
        [System.IO.File]::WriteAllLines($ReportPath, $all, [System.Text.Encoding]::UTF8)
        Write-Host ""
        Write-Host "  Report saved to:" -ForegroundColor $C.OK
        Write-Host "  $ReportPath" -ForegroundColor $C.Header
    } catch {
        Write-Host "  [!] Failed to save report: $_" -ForegroundColor $C.Error
    }
}

# ============================================================
#  FOOTER
# ============================================================
function Write-Footer {
    $line = "=" * 70
    Write-Host ""
    Write-Host $line -ForegroundColor $C.Header
    Write-Host "  Techware IT Tools — System Check v$ScriptVersion complete." -ForegroundColor $C.Header
    Write-Host "  $SupportEmail" -ForegroundColor $C.Dim
    Write-Host $line -ForegroundColor $C.Header
    Write-Host ""
}

# ============================================================
#  MAIN — RUN ALL SECTIONS
# ============================================================
Write-Header

Get-SystemInfo
Get-DiskHealth
Get-DriverAudit
Get-NetworkDiag
Get-BootSummary
Get-WindowsInfo
Export-Report

Write-Footer
