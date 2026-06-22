# Windows Service Health Checker and Repair Toolkit

PowerShell tooling for Windows service health reporting and guarded single-service repair, created by **Dewald Pretorius**.

## Files

- `Windows_Service_Health_Checker.ps1` — read-only service inventory, status, startup and dependency reporting.
- `Windows_Service_Repair_Toolkit.ps1` — guarded repairs for one explicitly selected service.
- `Launch_Service_Repair.bat` — interactive technician menu.

## Diagnostic default

Run without a repair switch to collect service inventory and selected-service context without changing the computer:

```powershell
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName Spooler
```

## Safe repair set

The safe repair set starts stopped dependencies, then starts or restarts the selected service and verifies that it reaches `Running`:

```powershell
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName Spooler -RepairAllSafe -DryRun
```

## Individual repair actions

```powershell
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName Spooler -StartService
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName Spooler -RestartService
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName ExampleSvc -StopService
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName ExampleSvc -StartDependencies
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName ExampleSvc -SetStartupType Automatic
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName ExampleSvc -SetStartupType AutomaticDelayedStart
.\Windows_Service_Repair_Toolkit.ps1 -ServiceName ExampleSvc -TerminateStuckProcess
```

## Repair behaviour

- Starts required dependencies recursively.
- Starts, stops or restarts one selected service.
- Supports `Automatic`, `AutomaticDelayedStart`, `Manual` and `Disabled` startup types.
- Verifies requested service state and startup configuration.
- Can terminate a process only when the service is pending, the process is dedicated to that service and it is not hosted by shared `svchost.exe`.
- Refuses to stop a service while running dependent services remain active.

## Protected services

The toolkit refuses changes to selected critical Windows services, including RPC, DCOM, Event Log, Plug and Play, Power, WMI, Security Accounts Manager, Task Scheduler, Base Filtering Engine and Windows Firewall services.

Use a Microsoft or vendor-approved service-specific procedure for protected services.

## Evidence and backups

Each run creates a timestamped desktop folder containing:

- `before.json` and `after.json`
- `repair.log`
- Selected-service CLIXML backup
- `sc qc` output
- Service failure-action output
- Service security-descriptor output

These files record the original state but are not automatically replayed. Review them before manual rollback.

## Safety

- Diagnosis is the default.
- `-DryRun` previews repairs.
- Standard actions require typing `YES` unless `-Yes` is supplied.
- Stop, startup-type and process-termination actions require typing `REPAIR`.
- Real repairs require elevation.
- The tool never creates a service, deletes a service, edits a binary path or terminates a shared service-host process.
- Startup-type changes can prevent applications or agents from functioning; validate the intended vendor configuration first.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully, including diagnosis or dry-run |
| 2 | Invalid target or safety refusal |
| 4 | Elevation required |
| 10 | User cancelled |
| 20 | Repair or verification failed |

## Interactive launcher

Double-click:

```text
Launch_Service_Repair.bat
```

The scripts have been source-reviewed for Windows PowerShell 5.1 but have not been runtime-tested against every service, dependency chain or vendor agent.
