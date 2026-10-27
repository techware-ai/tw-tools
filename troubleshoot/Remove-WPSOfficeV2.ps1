#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Completely removes WPS Office (Kingsoft) from Windows 10/11.

.DESCRIPTION
    Removes WPS Writer / Spreadsheets / Presentation / PDF / WPS Photos and all leftovers:
      - Runs WPS's own uninstaller(s) silently, then force-cleans
      - Processes, services (wpscloudsvr), scheduled tasks (update / notify)
      - Shell extensions, context-menu handlers, overlay icons, nav-pane cloud entry
      - File associations / ProgIDs (e.g. .png -> WPS Photos, .docx -> WPS Writer)
      - UserChoice entries pointing to WPS, OpenWith lists, association toasts
      - Run / startup keys, firewall rules, MS Office add-ins registered by WPS
      - Program folders, AppData, shortcuts (Desktop / Start Menu / Taskbar)
    Processes ALL user profiles (offline NTUSER.DAT / UsrClass.dat are loaded and unloaded).
    Works interactively (elevated) or as SYSTEM via RMM / Intune.
    Locked files are scheduled for deletion at next reboot.

    NOT touched: user documents (incl. "Documents\WPS Cloud Files") - check manually.

.PARAMETER SkipUninstaller
    Skip WPS's own uninst.exe and go straight to forced cleanup.

.PARAMETER Reboot
    Reboot automatically 60 seconds after completion.

.PARAMETER NoPause
    Don't wait for a key press at the end (pause is skipped automatically under SYSTEM / RMM).

.PARAMETER LogPath
    Folder for the transcript log. Default: C:\ProgramData\WPS-Removal\Logs

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Remove-WPSOffice.ps1
    powershell.exe -ExecutionPolicy Bypass -File .\Remove-WPSOffice.ps1 -Reboot
    powershell.exe -ExecutionPolicy Bypass -File .\Remove-WPSOffice.ps1 -LogPath D:\Logs

.OUTPUTS
    Exit codes (for RMM / Intune):
      0     WPS removed cleanly, no reboot needed
      3010  Removed, reboot required to finish (locked files queued)
      1     Items still remain after cleanup - check the log

.NOTES
    Version : 2.1.0
    Author  : Techware IT Services PLT
    Limitation: On Windows 11 the UCPD driver protects UserChoice keys, so per-user
    default apps that pointed to WPS must be reset via Settings > Apps > Default apps.
#>
[CmdletBinding()]
param(
    [switch]$SkipUninstaller,
    [switch]$Reboot,
    [switch]$NoPause,
    [string]$LogPath = "$env:ProgramData\WPS-Removal\Logs"
)

$ErrorActionPreference = 'Continue'
$ScriptVersion = '2.1.0'
$logDir = $LogPath
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ('WPS-Removal_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
Start-Transcript -Path $logFile -Force | Out-Null

# ---------------------------------------------------------------- patterns
$PathMatch   = 'Kingsoft|WPS Office|\\wps\\|wpscloud'
$ProgIdMatch = '^(KWPS|KET|KWPP|KPDF|WPS|Kingsoft)\.'
$ExeMatch    = '^(wps|et|wpp|wpspdf|wpsphoto|photolaunch|ksolaunch|wpscloudsvr|wpscenter|wpsoffice)\.exe$'
$ProcNames   = @('wps','et','wpp','wpspdf','wpsphoto','photolaunch','ksolaunch','wpscloudsvr',
                 'wpscenter','wpsnotify','wpsupdate','wpscloudlaunch','wpsoffice','promecefpluginhost')
$HKLM = 'Registry::HKEY_LOCAL_MACHINE'
$script:PendingReboot = $false
$script:Stats = @{ Removed = 0; Locked = 0; Failed = 0 }
$script:DefaultsToReset = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::OrdinalIgnoreCase)

# ---------------------------------------------------------------- helpers
function Write-Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Del($m)  { $script:Stats.Removed++; Write-Host "  [DEL] $m" -ForegroundColor Yellow }
function Write-Info($m) { Write-Host "  [..]  $m" }
function Write-Fail($m) { $script:Stats.Failed++; Write-Warning $m }

Write-Host "WPS Office Removal v$ScriptVersion  |  $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan

Add-Type -Namespace Win32 -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@ -ErrorAction SilentlyContinue

function Get-NativeRegPath([string]$p) { $p -replace '^(Microsoft\.PowerShell\.Core\\)?Registry::', '' }

function Remove-RegKey([string]$Key) {
    if (-not (Test-Path -LiteralPath $Key)) { return }
    try {
        Remove-Item -LiteralPath $Key -Recurse -Force -ErrorAction Stop
    } catch {
        & reg.exe delete "$(Get-NativeRegPath $Key)" /f 2>&1 | Out-Null
    }
    if (Test-Path -LiteralPath $Key) { Write-Fail "Could not delete key $(Get-NativeRegPath $Key)" }
    else { Write-Del (Get-NativeRegPath $Key) }
}

function Remove-RegValue([string]$Key, [string]$Name) {
    try {
        Remove-ItemProperty -LiteralPath $Key -Name $Name -Force -ErrorAction Stop
        Write-Del "$(Get-NativeRegPath $Key) -> $Name"
    } catch { Write-Fail "Could not remove value '$Name' in $(Get-NativeRegPath $Key)" }
}

function Remove-PathForce([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; Write-Del $Path; return } catch {}

    & takeown.exe /f "$Path" /r /d y 2>&1 | Out-Null
    & icacls.exe "$Path" /grant '*S-1-5-32-544:F' /t /c /q 2>&1 | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $Path) {
        # Locked (e.g. shell extension loaded in Explorer) -> delete on reboot
        $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)
        $dirs  = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                   Sort-Object { $_.FullName.Length } -Descending)
        foreach ($i in ($files + $dirs)) { [void][Win32.Native]::MoveFileEx($i.FullName, $null, 4) }
        [void][Win32.Native]::MoveFileEx($Path, $null, 4)
        $script:PendingReboot = $true
        $script:Stats.Locked++
        Write-Warning "Locked: $Path -> scheduled for deletion at next reboot"
    } else { Write-Del $Path }
}

function Remove-PathPattern([string]$Pattern) {
    if ($Pattern -match '[\*\?]') {
        Get-ChildItem -Path $Pattern -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-PathForce $_.FullName }
    } else { Remove-PathForce $Pattern }
}

function Stop-WpsProcesses {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Path -and $_.Path -match $PathMatch) -or
        (($ProcNames -contains $_.ProcessName.ToLower()) -and (-not $_.Path -or $_.Path -match $PathMatch))
    } | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; Write-Del "Process $($_.ProcessName) (PID $($_.Id))" } catch {}
    }
}

# ---------------------------------------------------------------- 0. user profiles / hives
Write-Step 'Loading user profiles'
$Profiles = foreach ($k in Get-ChildItem "$HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList") {
    $sid = $k.PSChildName
    if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { continue }
    $p = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
    [pscustomobject]@{
        SID     = $sid
        Path    = $p
        Hive    = "Registry::HKEY_USERS\$sid"
        Classes = "Registry::HKEY_USERS\${sid}_Classes"
    }
}

$LoadedHives = New-Object System.Collections.Generic.List[string]
foreach ($pr in $Profiles) {
    if (-not (Test-Path -LiteralPath $pr.Hive)) {
        $nt = Join-Path $pr.Path 'NTUSER.DAT'
        if (Test-Path -LiteralPath $nt) {
            & reg.exe load "HKU\$($pr.SID)" "$nt" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $LoadedHives.Add("HKU\$($pr.SID)") }
        }
    }
    if (-not (Test-Path -LiteralPath $pr.Classes)) {
        $uc = Join-Path $pr.Path 'AppData\Local\Microsoft\Windows\UsrClass.dat'
        if (Test-Path -LiteralPath $uc) {
            & reg.exe load "HKU\$($pr.SID)_Classes" "$uc" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $LoadedHives.Add("HKU\$($pr.SID)_Classes") }
        }
    }
    Write-Info "$($pr.Path)  ($($pr.SID))"
}

$UninstRoots = @(
    "$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
) + ($Profiles | ForEach-Object { "$($_.Hive)\Software\Microsoft\Windows\CurrentVersion\Uninstall" })

function Get-WpsUninstallKeys {
    foreach ($r in $UninstRoots) {
        Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue | Where-Object {
            ($_.GetValue('DisplayName') -match 'WPS Office|Kingsoft') -or
            ($_.GetValue('Publisher')   -match 'Kingsoft|Zhuhai') -or
            ($_.PSChildName -match 'Kingsoft')
        }
    }
}

# ---------------------------------------------------------------- 1. processes
Write-Step 'Stopping WPS processes'
Stop-WpsProcesses

# ---------------------------------------------------------------- 2. official uninstaller
if (-not $SkipUninstaller) {
    Write-Step 'Running WPS uninstaller(s) silently'
    foreach ($k in @(Get-WpsUninstallKeys)) {
        $us = [string]$k.GetValue('UninstallString')
        Write-Info "Found: $($k.GetValue('DisplayName')) $($k.GetValue('DisplayVersion'))"
        if (-not $us) { continue }
        if     ($us -match '^\s*"([^"]+)"\s*(.*)$')     { $exe = $Matches[1]; $uArgs = $Matches[2] }
        elseif ($us -match '^\s*(\S+?\.exe)\s*(.*)$')   { $exe = $Matches[1]; $uArgs = $Matches[2] }
        else { continue }
        if (-not (Test-Path -LiteralPath $exe)) { Write-Warning "Uninstaller missing: $exe"; continue }

        $uArgs = ("$uArgs /s").Trim()
        Write-Info "Running: `"$exe`" $uArgs"
        try {
            $proc = Start-Process -FilePath $exe -ArgumentList $uArgs -PassThru -WindowStyle Hidden -ErrorAction Stop
            if (-not $proc.WaitForExit(300000)) {
                Write-Warning 'Uninstaller timed out after 5 min - killing and continuing with forced cleanup'
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            } else { Write-Info "Exit code: $($proc.ExitCode)" }
        } catch { Write-Warning "Uninstaller failed: $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 5
    Stop-WpsProcesses
}

# ---------------------------------------------------------------- 3. services
Write-Step 'Removing WPS services'
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.PathName -match $PathMatch -or $_.Name -match '^wps|kingsoft' } |
    ForEach-Object {
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        & sc.exe delete "$($_.Name)" | Out-Null
        Write-Del "Service $($_.Name)"
    }

# ---------------------------------------------------------------- 4. scheduled tasks
Write-Step 'Removing WPS scheduled tasks'
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match 'wps|kingsoft' -or
    ((($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ') -match $PathMatch)
} | ForEach-Object {
    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    Write-Del "Task $($_.TaskPath)$($_.TaskName)"
}

# ---------------------------------------------------------------- 5. firewall rules
Write-Step 'Removing WPS firewall rules'
Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue |
    Where-Object { $_.Program -match $PathMatch } |
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue; Write-Del "Firewall rule $($_.DisplayName)" }

# ---------------------------------------------------------------- 6. shell extensions / COM
Write-Step 'Scanning COM / shell extensions (may take ~1 min)'
$WpsClsids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Test-WpsClsidKey($root, [string]$name) {
    foreach ($sub in 'InprocServer32', 'LocalServer32', 'DefaultIcon') {
        $s = $root.OpenSubKey("$name\$sub")
        if ($s) { $v = [string]$s.GetValue(''); $s.Close(); if ($v -match $PathMatch) { return $true } }
    }
    $s = $root.OpenSubKey("$name\Instance\InitPropertyBag")
    if ($s) { $v = [string]$s.GetValue('TargetFolderPath'); $s.Close(); if ($v -match $PathMatch) { return $true } }
    return $false
}

$ClsidScans = @()   # @{ Root=<.NET key>; PsPath=<PS path of CLSID key> }
foreach ($view in 'Registry64', 'Registry32') {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
    $ck = $base.OpenSubKey('SOFTWARE\Classes\CLSID')
    $ps = if ($view -eq 'Registry64') { "$HKLM\SOFTWARE\Classes\CLSID" } else { "$HKLM\SOFTWARE\WOW6432Node\Classes\CLSID" }
    if ($ck) { $ClsidScans += @{ Root = $ck; PsPath = $ps } }
}
foreach ($pr in $Profiles) {
    $ck = [Microsoft.Win32.Registry]::Users.OpenSubKey("$($pr.SID)_Classes\CLSID")
    if ($ck) { $ClsidScans += @{ Root = $ck; PsPath = "$($pr.Classes)\CLSID" } }
}

$ToDeleteClsid = @()
foreach ($scan in $ClsidScans) {
    foreach ($name in $scan.Root.GetSubKeyNames()) {
        if (Test-WpsClsidKey $scan.Root $name) {
            [void]$WpsClsids.Add($name)
            $ToDeleteClsid += "$($scan.PsPath)\$name"
        }
    }
    $scan.Root.Close()
}
Write-Info "WPS CLSIDs found: $($WpsClsids.Count)"

# Context menu / drag-drop / property sheet handlers
$ClassRoots = @("$HKLM\SOFTWARE\Classes", "$HKLM\SOFTWARE\WOW6432Node\Classes") +
              ($Profiles | Where-Object { Test-Path -LiteralPath $_.Classes } | ForEach-Object { $_.Classes })

foreach ($r in $ClassRoots) {
    foreach ($obj in '*', 'Directory', 'Directory\Background', 'Folder', 'AllFilesystemObjects', 'Drive', 'lnkfile') {
        foreach ($h in 'ContextMenuHandlers', 'DragDropHandlers', 'PropertySheetHandlers', 'CopyHookHandlers') {
            $hk = "$r\$obj\shellex\$h"
            Get-ChildItem -LiteralPath $hk -ErrorAction SilentlyContinue | Where-Object {
                $WpsClsids.Contains($_.PSChildName) -or
                $WpsClsids.Contains([string]$_.GetValue('')) -or
                $_.PSChildName -match 'wps|kingsoft|kso'
            } | ForEach-Object { Remove-RegKey $_.PSPath }
        }
    }
}

# Overlay icons, approved extensions, namespace (WPS Cloud in This PC / nav pane)
$ExplorerRoots = @("$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer",
                   "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer") +
                 ($Profiles | ForEach-Object { "$($_.Hive)\Software\Microsoft\Windows\CurrentVersion\Explorer" })
foreach ($e in $ExplorerRoots) {
    Get-ChildItem -LiteralPath "$e\ShellIconOverlayIdentifiers" -ErrorAction SilentlyContinue | Where-Object {
        $WpsClsids.Contains([string]$_.GetValue('')) -or $_.PSChildName -match 'wps|kingsoft|kso'
    } | ForEach-Object { Remove-RegKey $_.PSPath }

    foreach ($ns in 'Desktop\NameSpace', 'MyComputer\NameSpace') {
        Get-ChildItem -LiteralPath "$e\$ns" -ErrorAction SilentlyContinue |
            Where-Object { $WpsClsids.Contains($_.PSChildName) } |
            ForEach-Object { Remove-RegKey $_.PSPath }
    }
    $hd = "$e\HideDesktopIcons\NewStartPanel"
    if (Test-Path -LiteralPath $hd) {
        (Get-Item -LiteralPath $hd).GetValueNames() | Where-Object { $WpsClsids.Contains($_) } |
            ForEach-Object { Remove-RegValue $hd $_ }
    }
}
foreach ($ap in "$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved",
                "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved") {
    if (Test-Path -LiteralPath $ap) {
        (Get-Item -LiteralPath $ap).GetValueNames() | Where-Object { $WpsClsids.Contains($_) } |
            ForEach-Object { Remove-RegValue $ap $_ }
    }
}
foreach ($k in $ToDeleteClsid) { Remove-RegKey $k }

# MS Office add-ins registered by WPS
$OfficeAddinRoots = @("$HKLM\SOFTWARE\Microsoft\Office", "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Office") +
                    ($Profiles | ForEach-Object { "$($_.Hive)\Software\Microsoft\Office" })
foreach ($o in $OfficeAddinRoots) {
    foreach ($app in 'Word', 'Excel', 'PowerPoint', 'Outlook') {
        Get-ChildItem -LiteralPath "$o\$app\Addins" -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match 'wps|kingsoft|^kso' } |
            ForEach-Object { Remove-RegKey $_.PSPath }
    }
}

# ---------------------------------------------------------------- 7. file associations / ProgIDs
Write-Step 'Detecting WPS ProgIDs / file associations'
$WpsProgIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$Checked    = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$ExtKeys    = New-Object System.Collections.Generic.List[string]

function Test-WpsProgId([string]$id) {
    foreach ($r in $ClassRoots) {
        foreach ($sub in 'shell\open\command', 'DefaultIcon') {
            $p = "$r\$id\$sub"
            if (Test-Path -LiteralPath $p) {
                $v = (Get-Item -LiteralPath $p -ErrorAction SilentlyContinue).GetValue('')
                if ("$v" -match $PathMatch) { return $true }
            }
        }
    }
    return $false
}

foreach ($r in $ClassRoots) {
    foreach ($k in Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue) {
        $n = $k.PSChildName
        if ($n -match $ProgIdMatch) { [void]$WpsProgIds.Add($n); continue }
        if ($n.StartsWith('.')) {
            $ExtKeys.Add($k.PSPath)
            $cands = @([string]$k.GetValue(''))
            $ow = $k.OpenSubKey('OpenWithProgids')
            if ($ow) { $cands += $ow.GetValueNames(); $ow.Close() }
            foreach ($c in $cands) {
                if (-not $c -or $Checked.Contains($c)) { continue }
                [void]$Checked.Add($c)
                if (Test-WpsProgId $c) { [void]$WpsProgIds.Add($c) }
            }
        }
    }
}
Write-Info "WPS ProgIDs found: $($WpsProgIds.Count)"
$WpsProgIds | Sort-Object | ForEach-Object { Write-Info "  $_" }

function Test-IsWpsProgId([string]$id) { $id -and ($WpsProgIds.Contains($id) -or $id -match $ProgIdMatch) }

Write-Step 'Cleaning file associations'
# Extension keys: default handler + OpenWithProgids
foreach ($ek in $ExtKeys) {
    $key = Get-Item -LiteralPath $ek -ErrorAction SilentlyContinue
    if (-not $key) { continue }
    if (Test-IsWpsProgId ([string]$key.GetValue(''))) {
        & reg.exe delete "$(Get-NativeRegPath $ek)" /ve /f 2>&1 | Out-Null
        Write-Del "$(Get-NativeRegPath $ek) (default handler)"
    }
    $owp = "$ek\OpenWithProgids"
    if (Test-Path -LiteralPath $owp) {
        (Get-Item -LiteralPath $owp).GetValueNames() | Where-Object { Test-IsWpsProgId $_ } |
            ForEach-Object { Remove-RegValue $owp $_ }
    }
}
# ProgID keys + Applications\*.exe
foreach ($r in $ClassRoots) {
    foreach ($id in $WpsProgIds) { Remove-RegKey "$r\$id" }
    Get-ChildItem -LiteralPath "$r\Applications" -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $ExeMatch } |
        ForEach-Object { Remove-RegKey $_.PSPath }
}

# Per-user FileExts (UserChoice / OpenWithList / OpenWithProgids) + toasts
foreach ($pr in $Profiles) {
    $fe = "$($pr.Hive)\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
    foreach ($k in Get-ChildItem -LiteralPath $fe -ErrorAction SilentlyContinue) {
        $kp = $k.PSPath

        $owp = "$kp\OpenWithProgids"
        if (Test-Path -LiteralPath $owp) {
            (Get-Item -LiteralPath $owp).GetValueNames() | Where-Object { Test-IsWpsProgId $_ } |
                ForEach-Object { Remove-RegValue $owp $_ }
        }

        $owl = "$kp\OpenWithList"
        if (Test-Path -LiteralPath $owl) {
            $item = Get-Item -LiteralPath $owl
            $mru  = [string]$item.GetValue('MRUList')
            foreach ($vn in $item.GetValueNames()) {
                if ($vn -eq 'MRUList') { continue }
                if ([string]$item.GetValue($vn) -match $ExeMatch) {
                    Remove-RegValue $owl $vn
                    $mru = $mru.Replace($vn, '')
                }
            }
            if ($mru -ne [string]$item.GetValue('MRUList')) {
                Set-ItemProperty -LiteralPath $owl -Name 'MRUList' -Value $mru -ErrorAction SilentlyContinue
            }
        }

        $ucLocked = $null
        foreach ($uc in 'UserChoice', 'UserChoiceLatest') {
            $ucp = "$kp\$uc"
            if (-not (Test-Path -LiteralPath $ucp)) { continue }
            $progId = [string](Get-Item -LiteralPath $ucp).GetValue('ProgId')
            if (-not $progId -and (Test-Path -LiteralPath "$ucp\ProgId")) {
                $progId = [string](Get-Item -LiteralPath "$ucp\ProgId").GetValue('ProgId')
            }
            if (Test-IsWpsProgId $progId) {
                & reg.exe delete "$(Get-NativeRegPath $ucp)" /f 2>&1 | Out-Null
                if (Test-Path -LiteralPath $ucp) { $ucLocked = $progId }   # protected by Windows (UCPD)
                else { Write-Del "$($k.PSChildName) $uc -> $progId" }
            }
        }
        if ($ucLocked) {
            [void]$script:DefaultsToReset.Add("$($k.PSChildName)")
            Write-Info "Default app protected by Windows: $($k.PSChildName) -> $ucLocked (reset via Settings)"
        }
    }

    $toast = "$($pr.Hive)\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts"
    if (Test-Path -LiteralPath $toast) {
        (Get-Item -LiteralPath $toast).GetValueNames() |
            Where-Object { $n = $_; ($n -match $ProgIdMatch) -or ($WpsProgIds | Where-Object { $n.StartsWith("$_`_") }) } |
            ForEach-Object { Remove-RegValue $toast $_ }
    }
}

# RegisteredApplications
$RegAppKeys = @("$HKLM\SOFTWARE\RegisteredApplications", "$HKLM\SOFTWARE\WOW6432Node\RegisteredApplications") +
              ($Profiles | ForEach-Object { "$($_.Hive)\Software\RegisteredApplications" })
foreach ($ra in $RegAppKeys) {
    if (-not (Test-Path -LiteralPath $ra)) { continue }
    $item = Get-Item -LiteralPath $ra
    $item.GetValueNames() | Where-Object { $_ -match 'WPS|Kingsoft' -or [string]$item.GetValue($_) -match 'WPS|Kingsoft' } |
        ForEach-Object { Remove-RegValue $ra $_ }
}

# ---------------------------------------------------------------- 8. registry: software, run, uninstall
Write-Step 'Cleaning registry (Software, Run keys, Uninstall entries)'
$SoftKeys = @("$HKLM\SOFTWARE\Kingsoft", "$HKLM\SOFTWARE\WOW6432Node\Kingsoft") +
            ($Profiles | ForEach-Object { "$($_.Hive)\Software\Kingsoft" })
foreach ($s in $SoftKeys) { Remove-RegKey $s }

$RunKeys = @("$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
             "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
             "$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce") +
           ($Profiles | ForEach-Object {
               "$($_.Hive)\Software\Microsoft\Windows\CurrentVersion\Run"
               "$($_.Hive)\Software\Microsoft\Windows\CurrentVersion\RunOnce"
           })
foreach ($rk in $RunKeys) {
    if (-not (Test-Path -LiteralPath $rk)) { continue }
    $item = Get-Item -LiteralPath $rk
    $item.GetValueNames() | Where-Object { [string]$item.GetValue($_) -match $PathMatch -or $_ -match 'wps|kingsoft' } |
        ForEach-Object { Remove-RegValue $rk $_ }
}
$SAKeys = @("$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
            "$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32") +
          ($Profiles | ForEach-Object { "$($_.Hive)\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" })
foreach ($sa in $SAKeys) {
    if (-not (Test-Path -LiteralPath $sa)) { continue }
    (Get-Item -LiteralPath $sa).GetValueNames() | Where-Object { $_ -match 'wps|kingsoft' } |
        ForEach-Object { Remove-RegValue $sa $_ }
}

foreach ($k in @(Get-WpsUninstallKeys)) { Remove-RegKey $k.PSPath }

# ---------------------------------------------------------------- 9. files & shortcuts
Write-Step 'Removing folders and shortcuts'
Stop-WpsProcesses

$MachinePaths = @(
    "$env:ProgramFiles\Kingsoft",
    "${env:ProgramFiles(x86)}\Kingsoft",
    "$env:ProgramFiles\WPS Office",
    "${env:ProgramFiles(x86)}\WPS Office",
    "$env:ProgramData\Kingsoft",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\WPS Office",
    "$env:PUBLIC\Desktop\WPS*.lnk"
)
foreach ($p in $MachinePaths) { Remove-PathPattern $p }

foreach ($pr in $Profiles) {
    $u = $pr.Path
    foreach ($p in @(
        "$u\AppData\Local\Kingsoft",
        "$u\AppData\Roaming\Kingsoft",
        "$u\AppData\LocalLow\Kingsoft",
        "$u\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\WPS Office",
        "$u\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\WPS*.lnk",
        "$u\Desktop\WPS*.lnk",
        "$u\OneDrive*\Desktop\WPS*.lnk",
        "$u\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\WPS*.lnk"
    )) { Remove-PathPattern $p }
}

# Any remaining shortcut whose target points into WPS
$sh = New-Object -ComObject WScript.Shell
$LnkFolders = @("$env:PUBLIC\Desktop", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs") +
              ($Profiles | ForEach-Object {
                  "$($_.Path)\Desktop"
                  "$($_.Path)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
                  "$($_.Path)\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch"
              })
foreach ($f in $LnkFolders) {
    Get-ChildItem -LiteralPath $f -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { if ($sh.CreateShortcut($_.FullName).TargetPath -match $PathMatch) { Remove-PathForce $_.FullName } } catch {}
    }
}
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh)

# ---------------------------------------------------------------- 10. unload hives & summary
Write-Step 'Unloading offline user hives'
[GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Seconds 2
foreach ($h in $LoadedHives) {
    & reg.exe unload "$h" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Start-Sleep -Seconds 3; [GC]::Collect(); & reg.exe unload "$h" 2>&1 | Out-Null }
    Write-Info "Unloaded $h (exit $LASTEXITCODE)"
}

Write-Step 'Verification'
$left = @()
$left += Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -match $PathMatch } | ForEach-Object { "Process: $($_.ProcessName)" }
$left += @("$env:ProgramFiles\Kingsoft", "${env:ProgramFiles(x86)}\Kingsoft") | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { "Folder: $_" }
$left += @(Get-WpsUninstallKeys) | ForEach-Object { "Uninstall entry: $($_.GetValue('DisplayName'))" }
foreach ($pr in $Profiles) {
    foreach ($sub in 'AppData\Local\Kingsoft', 'AppData\Roaming\Kingsoft', 'AppData\LocalLow\Kingsoft') {
        $f = Join-Path $pr.Path $sub
        if (Test-Path -LiteralPath $f) { $left += "Folder: $f" }
    }
}

# Items still present only because they are queued for deletion at reboot are not failures
$pendingOnly = $script:PendingReboot -and (@($left | Where-Object { $_ -notlike 'Folder:*' }).Count -eq 0)

$exitCode = if ($left.Count -eq 0 -and -not $script:PendingReboot) { 0 }
            elseif ($left.Count -eq 0 -or $pendingOnly)          { 3010 }
            else                                                  { 1 }

# ---------------------------------------------------------------- 11. final status report
function Write-StatusRow([string]$Item, [string]$Result, [string]$Status) {
    $tag, $color = switch ($Status) {
        'OK'   { '[ OK ]', 'Green' }
        'WARN' { '[WARN]', 'Yellow' }
        'FAIL' { '[FAIL]', 'Red' }
        default { '[INFO]', 'Gray' }
    }
    Write-Host ('  {0} ' -f $tag) -ForegroundColor $color -NoNewline
    Write-Host ('{0,-30} {1}' -f $Item, $Result)
}

$leftProc    = @($left | Where-Object { $_ -like 'Process:*' })
$leftUninst  = @($left | Where-Object { $_ -like 'Uninstall entry:*' })
$leftProgDir = @($left | Where-Object { $_ -like 'Folder:*' -and $_ -match 'Program Files' })
$leftUserDir = @($left | Where-Object { $_ -like 'Folder:*' -and $_ -notmatch 'Program Files' })
$folderState = if ($pendingOnly) { 'WARN' } else { 'FAIL' }
$folderText  = if ($pendingOnly) { 'deleted at next reboot' } else { 'still present' }

$line = '=' * 70
Write-Host "`n$line" -ForegroundColor Cyan
Write-Host "  WPS OFFICE REMOVAL - RESULT   (v$ScriptVersion  |  $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm'))" -ForegroundColor Cyan
Write-Host $line -ForegroundColor Cyan

if ($leftProc.Count -eq 0)    { Write-StatusRow 'WPS processes'        'None running' 'OK' }
else                          { Write-StatusRow 'WPS processes'        "$($leftProc.Count) still running" 'FAIL' }
if ($leftUninst.Count -eq 0)  { Write-StatusRow 'Programs & Features'  'No WPS entries' 'OK' }
else                          { Write-StatusRow 'Programs & Features'  "$($leftUninst.Count) entry(s) remain" 'FAIL' }
if ($leftProgDir.Count -eq 0) { Write-StatusRow 'Program Files\Kingsoft' 'Removed' 'OK' }
else                          { Write-StatusRow 'Program Files\Kingsoft' $folderText $folderState }
if ($leftUserDir.Count -eq 0) { Write-StatusRow 'User profile folders' "Clean ($(@($Profiles).Count) profile(s) checked)" 'OK' }
else                          { Write-StatusRow 'User profile folders' "$($leftUserDir.Count) $folderText" $folderState }
if ($script:DefaultsToReset.Count -eq 0) { Write-StatusRow 'Default apps' 'No WPS associations' 'OK' }
else                          { Write-StatusRow 'Default apps' "$($script:DefaultsToReset.Count) to reset manually" 'WARN' }

Write-Host ''
Write-StatusRow 'Items removed'       $script:Stats.Removed 'INFO'
Write-StatusRow 'Queued for reboot'   $script:Stats.Locked  $(if ($script:Stats.Locked) { 'WARN' } else { 'INFO' })
Write-StatusRow 'Errors'              $script:Stats.Failed  $(if ($script:Stats.Failed) { 'FAIL' } else { 'OK' })

if ($left.Count -gt 0) {
    Write-Host "`n  Remaining items:" -ForegroundColor $(if ($pendingOnly) { 'Yellow' } else { 'Red' })
    $left | ForEach-Object { Write-Host "    - $_" -ForegroundColor $(if ($pendingOnly) { 'Yellow' } else { 'Red' }) }
}
if ($script:DefaultsToReset.Count -gt 0) {
    Write-Host "`n  Default apps still pointing to WPS (protected by Windows, can't be changed by script):" -ForegroundColor Yellow
    Write-Host "    $($script:DefaultsToReset -join ', ')"
    Write-Host '    -> Signed in as the affected user: Settings > Apps > Default apps > Reset' -ForegroundColor Yellow
}

Write-Host "`n$line" -ForegroundColor Cyan
switch ($exitCode) {
    0    { Write-Host '  OVERALL: CLEAN - WPS Office fully removed.' -ForegroundColor Green
           Write-Host '  Reboot recommended (unloads WPS shell extensions from Explorer).' -ForegroundColor Gray }
    3010 { Write-Host '  OVERALL: REMOVED - REBOOT REQUIRED to finish deleting locked files.' -ForegroundColor Yellow }
    default { Write-Host '  OVERALL: INCOMPLETE - some items remain, check the log.' -ForegroundColor Red }
}
Write-Host "  Exit code : $exitCode"
Write-Host "  Log file  : $logFile"
Write-Host $line -ForegroundColor Cyan

Stop-Transcript | Out-Null

if ($Reboot) { & shutdown.exe /r /t 60 /c 'WPS Office removal complete - restarting in 60 seconds' }

# ---------------------------------------------------------------- 12. pause / exit
# Pause only when a technician is actually looking at the window.
# Skipped for SYSTEM (RMM / Intune), non-interactive sessions, ISE/VS Code, or -NoPause.
$isSystem    = ([Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem
$interactive = [Environment]::UserInteractive -and -not $isSystem -and -not $NoPause -and
               $Host.Name -eq 'ConsoleHost' -and
               -not ([Environment]::GetCommandLineArgs() -match '^-NonI')

if ($interactive) {
    if ($Reboot) { Write-Host "`n  PC will restart in 60 seconds (run 'shutdown /a' to cancel)." -ForegroundColor Yellow }
    Write-Host "`n  Press any key to close..." -ForegroundColor Cyan -NoNewline
    try {
        $Host.UI.RawUI.FlushInputBuffer()   # ignore keys pressed while the script was running
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch { [void](Read-Host) }
    Write-Host ''
}

exit $exitCode
