#requires -Version 5.1
<#
.SYNOPSIS
    Windows Service Health Checker.
.DESCRIPTION
    Read-only Windows service status reporter for helpdesk support.
#>
[CmdletBinding()]
param([string]$OutputPath)

$RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Service_Health_Reports' }
New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
function New-Check { param($Category,$Name,$Status,$Value,$Recommendation) [PSCustomObject]@{Category=$Category;Name=$Name;Status=$Status;Value=$Value;Recommendation=$Recommendation} }
$checks = @()
$key = @('Winmgmt','EventLog','wuauserv','BITS','Spooler','Dhcp','Dnscache','LanmanWorkstation','LanmanServer','MpsSvc','ClickToRunSvc')
foreach($name in $key){
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if($svc){ $checks += New-Check 'Key Services' $svc.DisplayName ($(if($svc.Status -eq 'Running'){'OK'}else{'Info'})) "Name=$($svc.Name); Status=$($svc.Status); StartType=$($svc.StartType)" 'Review against the reported issue.' }
    else { $checks += New-Check 'Key Services' $name 'Info' 'Not found' 'May not exist on this Windows build.' }
}
$all = Get-Service | Select-Object Name,DisplayName,Status,StartType,DependentServices,ServicesDependedOn
$autoNotRunning = $all | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | Select-Object Name,DisplayName,Status,StartType
$disabled = $all | Where-Object { $_.StartType -eq 'Disabled' } | Select-Object Name,DisplayName,Status,StartType
$checks += New-Check 'Summary' 'Automatic services not running' 'Info' (@($autoNotRunning).Count) 'Review if related to the user issue.'
$checks += New-Check 'Summary' 'Disabled services count' 'Info' (@($disabled).Count) 'Review only if relevant to issue scope.'
$checks | Export-Csv (Join-Path $OutputPath "service_health_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$checks | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputPath "service_health_$RunStamp.json") -Encoding UTF8
$autoNotRunning | Export-Csv (Join-Path $OutputPath "automatic_not_running_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$disabled | Export-Csv (Join-Path $OutputPath "disabled_services_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$html = "<h1>Windows Service Health - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p><h2>Checks</h2>$($checks | ConvertTo-Html -Fragment)<h2>Automatic Services Not Running</h2>$($autoNotRunning | ConvertTo-Html -Fragment)"
$html | ConvertTo-Html -Title 'Service Health Checker' | Set-Content (Join-Path $OutputPath "service_health_$RunStamp.html") -Encoding UTF8
$checks | Format-Table -AutoSize -Wrap
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
