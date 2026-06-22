#requires -Version 5.1
<#
.SYNOPSIS
    Guarded Windows service repair toolkit.
.DESCRIPTION
    Diagnoses by default and performs explicit repairs against one selected service.
    Critical Windows services and shared service-host processes are protected.
.NOTES
    Created by Dewald Pretorius - L2 IT Support Engineer.
#>

[CmdletBinding()]
param(
    [string]$ServiceName,
    [switch]$RepairAllSafe,
    [switch]$StartService,
    [switch]$StopService,
    [switch]$RestartService,
    [switch]$StartDependencies,
    [ValidateSet('Automatic','AutomaticDelayedStart','Manual','Disabled')]
    [string]$SetStartupType,
    [switch]$TerminateStuckProcess,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.1'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ExitCode = 0

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows_Service_Repair_$Stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$LogPath = Join-Path $OutputPath 'repair.log'
$BackupPath = Join-Path $OutputPath 'backup'
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

$ProtectedServices = @(
    'RpcSs','DcomLaunch','RpcEptMapper','EventLog','PlugPlay','Power','Winmgmt',
    'SamSs','LSM','ProfSvc','UserManager','Schedule','CryptSvc','BFE','mpssvc'
)

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DRYRUN')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN'    { Write-Host $Message -ForegroundColor Yellow }
        'ERROR'   { Write-Host $Message -ForegroundColor Red }
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        'DRYRUN'  { Write-Host "DRY RUN: $Message" -ForegroundColor Cyan }
        default   { Write-Host $Message }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This repair requires an elevated PowerShell session.'
    }
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$HighImpact
    )
    if ($DryRun -or $Yes) { return $true }
    $token = if ($HighImpact) { 'REPAIR' } else { 'YES' }
    return (Read-Host "$Message Type $token to continue") -eq $token
}

function Get-SelectedService {
    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        throw 'Specify -ServiceName for repair actions.'
    }
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        throw "Service '$ServiceName' was not found."
    }
    return $service
}

function Get-SelectedServiceCim {
    if ([string]::IsNullOrWhiteSpace($ServiceName)) { return $null }
    $escapedName = $ServiceName.Replace("'", "''")
    return Get-CimInstance Win32_Service -Filter "Name='$escapedName'" -ErrorAction SilentlyContinue
}

function Assert-ServiceCanBeChanged {
    param([Parameter(Mandatory)][string]$Name)
    if ($ProtectedServices -contains $Name) {
        throw "Service '$Name' is protected by this toolkit. Use an approved service-specific procedure instead."
    }
}

function Save-State {
    param([Parameter(Mandatory)][string]$Stage)

    $selected = Get-SelectedServiceCim
    $state = [ordered]@{
        Stage = $Stage
        Generated = (Get-Date).ToString('o')
        ScriptVersion = $ScriptVersion
        Computer = $env:COMPUTERNAME
        User = "$env:USERDOMAIN\$env:USERNAME"
        IsAdministrator = (Test-IsAdministrator)
        SelectedService = if ($selected) {
            $selected | Select-Object Name, DisplayName, State, Status, StartMode, ProcessId, PathName, StartName, ExitCode, ServiceSpecificExitCode
        } else { $null }
        Dependencies = if ($selected) {
            @(Get-Service -Name $selected.Name -ErrorAction SilentlyContinue | ForEach-Object { $_.ServicesDependedOn } | Select-Object Name, DisplayName, Status, StartType)
        } else { @() }
        Dependents = if ($selected) {
            @(Get-Service -Name $selected.Name -ErrorAction SilentlyContinue | ForEach-Object { $_.DependentServices } | Select-Object Name, DisplayName, Status, StartType)
        } else { @() }
        ServiceInventory = @(Get-Service -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType)
    }

    $path = Join-Path $OutputPath "$Stage.json"
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Log "Saved $Stage state to $path." 'SUCCESS'
}

function Save-ServiceBackup {
    if ([string]::IsNullOrWhiteSpace($ServiceName)) { return }
    $service = Get-SelectedServiceCim
    if (-not $service) { return }

    $service | Export-Clixml -LiteralPath (Join-Path $BackupPath 'service-before.clixml')
    & sc.exe qc $ServiceName 2>&1 | Set-Content -LiteralPath (Join-Path $BackupPath 'sc-qc.txt') -Encoding UTF8
    & sc.exe qfailure $ServiceName 2>&1 | Set-Content -LiteralPath (Join-Path $BackupPath 'sc-qfailure.txt') -Encoding UTF8
    & sc.exe sdshow $ServiceName 2>&1 | Set-Content -LiteralPath (Join-Path $BackupPath 'sc-security-descriptor.txt') -Encoding UTF8
    Write-Log 'Exported the selected service configuration before repair.' 'SUCCESS'
}

function Start-ServiceDependenciesRecursive {
    param(
        [Parameter(Mandatory)][System.ServiceProcess.ServiceController]$Service,
        [hashtable]$Visited = @{}
    )

    foreach ($dependency in @($Service.ServicesDependedOn)) {
        if ($Visited.ContainsKey($dependency.Name)) { continue }
        $Visited[$dependency.Name] = $true
        Start-ServiceDependenciesRecursive -Service $dependency -Visited $Visited

        $current = Get-Service -Name $dependency.Name -ErrorAction Stop
        if ($current.Status -ne 'Running') {
            if ($DryRun) {
                Write-Log "Would start dependency '$($current.Name)'." 'DRYRUN'
            } else {
                Start-Service -Name $current.Name -ErrorAction Stop
                (Get-Service -Name $current.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
                Write-Log "Started dependency '$($current.Name)'." 'SUCCESS'
            }
        }
    }
}

function Invoke-StartDependencies {
    Require-Administrator
    $service = Get-SelectedService
    Assert-ServiceCanBeChanged -Name $service.Name
    if (-not (Confirm-Action "Start stopped dependencies required by '$ServiceName'?")) { throw 'User cancelled.' }
    Start-ServiceDependenciesRecursive -Service $service
}

function Invoke-StartSelectedService {
    Require-Administrator
    $service = Get-SelectedService
    Assert-ServiceCanBeChanged -Name $service.Name
    if (-not (Confirm-Action "Start service '$ServiceName'?")) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would start service '$ServiceName'." 'DRYRUN'
        return
    }

    Start-ServiceDependenciesRecursive -Service $service
    Start-Service -Name $service.Name -ErrorAction Stop
    (Get-Service -Name $service.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-Log "Service '$ServiceName' is running." 'SUCCESS'
}

function Invoke-StopSelectedService {
    Require-Administrator
    $service = Get-SelectedService
    Assert-ServiceCanBeChanged -Name $service.Name
    $runningDependents = @($service.DependentServices | Where-Object { $_.Status -eq 'Running' })
    if ($runningDependents.Count -gt 0) {
        throw "Service '$ServiceName' has running dependent services. Stop them using an approved service-specific procedure."
    }
    if (-not (Confirm-Action "Stop service '$ServiceName'? Applications may be interrupted." -HighImpact)) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would stop service '$ServiceName'." 'DRYRUN'
        return
    }

    Stop-Service -Name $service.Name -ErrorAction Stop
    (Get-Service -Name $service.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    Write-Log "Service '$ServiceName' is stopped." 'SUCCESS'
}

function Invoke-RestartSelectedService {
    Require-Administrator
    $service = Get-SelectedService
    Assert-ServiceCanBeChanged -Name $service.Name
    if (-not (Confirm-Action "Restart service '$ServiceName'? Applications may be interrupted.")) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would restart service '$ServiceName'." 'DRYRUN'
        return
    }

    Start-ServiceDependenciesRecursive -Service $service
    if ($service.Status -eq 'Running') {
        Restart-Service -Name $service.Name -Force -ErrorAction Stop
    } else {
        Start-Service -Name $service.Name -ErrorAction Stop
    }
    (Get-Service -Name $service.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-Log "Service '$ServiceName' restarted and is running." 'SUCCESS'
}

function Invoke-SetStartupType {
    Require-Administrator
    $service = Get-SelectedService
    Assert-ServiceCanBeChanged -Name $service.Name
    if (-not (Confirm-Action "Set startup type for '$ServiceName' to '$SetStartupType'?" -HighImpact)) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would set '$ServiceName' startup type to '$SetStartupType'." 'DRYRUN'
        return
    }

    switch ($SetStartupType) {
        'Automatic' {
            Set-Service -Name $service.Name -StartupType Automatic
            & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$($service.Name)" /v DelayedAutoStart /t REG_DWORD /d 0 /f | Out-Null
        }
        'AutomaticDelayedStart' {
            & sc.exe config $service.Name start= delayed-auto 2>&1 | Add-Content -LiteralPath $LogPath
            if ($LASTEXITCODE -ne 0) { throw 'Could not configure delayed automatic startup.' }
        }
        'Manual' { Set-Service -Name $service.Name -StartupType Manual }
        'Disabled' { Set-Service -Name $service.Name -StartupType Disabled }
    }

    $after = Get-SelectedServiceCim
    if (-not $after) { throw 'Could not verify the service after changing startup type.' }
    switch ($SetStartupType) {
        'Automatic' {
            if ($after.StartMode -ne 'Auto') { throw 'Startup type verification failed.' }
            $delayed = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.Name)" -Name DelayedAutoStart -ErrorAction SilentlyContinue).DelayedAutoStart
            if ($delayed -eq 1) { throw 'Service remained configured for delayed automatic startup.' }
        }
        'AutomaticDelayedStart' {
            $delayed = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.Name)" -Name DelayedAutoStart -ErrorAction SilentlyContinue).DelayedAutoStart
            if ($after.StartMode -ne 'Auto' -or $delayed -ne 1) { throw 'Delayed automatic startup verification failed.' }
        }
        'Manual' { if ($after.StartMode -ne 'Manual') { throw 'Startup type verification failed.' } }
        'Disabled' { if ($after.StartMode -ne 'Disabled') { throw 'Startup type verification failed.' } }
    }
    Write-Log "Startup type for '$ServiceName' changed to '$SetStartupType' and verified." 'SUCCESS'
}

function Invoke-TerminateStuckProcess {
    Require-Administrator
    $service = Get-SelectedService
    Assert-ServiceCanBeChanged -Name $service.Name
    $cim = Get-SelectedServiceCim

    if (-not $cim -or $cim.State -notmatch 'Pending') {
        throw "Service '$ServiceName' is not in a pending state. Process termination is refused."
    }
    if ([int]$cim.ProcessId -le 4) {
        throw "Service '$ServiceName' does not have a safe terminable process ID."
    }

    $sharing = @(Get-CimInstance Win32_Service -Filter "ProcessId=$($cim.ProcessId)" -ErrorAction SilentlyContinue)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($cim.ProcessId)" -ErrorAction Stop
    $exeName = [IO.Path]::GetFileName([string]$process.ExecutablePath)
    if ($sharing.Count -gt 1 -or $exeName -ieq 'svchost.exe') {
        throw "Process $($cim.ProcessId) is shared by multiple services or hosted by svchost.exe. Termination is refused."
    }

    if (-not (Confirm-Action "Force terminate process $($cim.ProcessId) for stuck service '$ServiceName'?" -HighImpact)) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log "Would terminate process $($cim.ProcessId) for '$ServiceName'." 'DRYRUN'
        return
    }

    $processId = [int]$cim.ProcessId
    Stop-Process -Id $processId -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
        throw "Process $processId remained active after termination was requested."
    }
    Write-Log "Terminated stuck dedicated process $processId for '$ServiceName' and verified its exit." 'SUCCESS'
}

function Invoke-SafeRepairSet {
    Invoke-StartDependencies
    Invoke-RestartSelectedService
}

Write-Log "Windows Service Repair Toolkit $ScriptVersion started. DryRun=$DryRun"
Save-State -Stage 'before'
Save-ServiceBackup

$hasRepair = $RepairAllSafe -or $StartService -or $StopService -or $RestartService -or $StartDependencies -or -not [string]::IsNullOrWhiteSpace($SetStartupType) -or $TerminateStuckProcess
if (-not $hasRepair) {
    Write-Log 'Diagnostic-only run completed. No repair switch was selected.' 'SUCCESS'
    Save-State -Stage 'after'
    exit 0
}

try {
    if ($RepairAllSafe)          { Invoke-SafeRepairSet }
    if ($StartDependencies)      { Invoke-StartDependencies }
    if ($StartService)           { Invoke-StartSelectedService }
    if ($StopService)            { Invoke-StopSelectedService }
    if ($RestartService)         { Invoke-RestartSelectedService }
    if ($SetStartupType)         { Invoke-SetStartupType }
    if ($TerminateStuckProcess)  { Invoke-TerminateStuckProcess }
} catch {
    if ($_.Exception.Message -eq 'User cancelled.') {
        $ExitCode = 10
        Write-Log 'Repair cancelled by the user.' 'WARN'
    } elseif ($_.Exception.Message -match 'elevated') {
        $ExitCode = 4
        Write-Log $_.Exception.Message 'ERROR'
    } elseif ($_.Exception.Message -match 'protected|refused|Specify|not found') {
        $ExitCode = 2
        Write-Log $_.Exception.Message 'ERROR'
    } else {
        $ExitCode = 20
        Write-Log $_.Exception.Message 'ERROR'
    }
} finally {
    try { Save-State -Stage 'after' } catch { Write-Log "Post-repair snapshot failed: $($_.Exception.Message)" 'WARN' }
}

if ($ExitCode -eq 0) {
    Write-Log "Completed successfully. Output: $OutputPath" 'SUCCESS'
} else {
    Write-Log "Completed with exit code $ExitCode. Output: $OutputPath" 'ERROR'
}
exit $ExitCode
