[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory)][string[]]$ServiceName,
    [ValidateSet('Start','Restart','SetAutomatic','SetManual')][string]$Action='Restart',
    [string]$OutputPath="$env:USERPROFILE\Desktop\ServiceRepair"
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutputPath -Force|Out-Null
$Log=Join-Path $OutputPath ("repair-{0:yyyyMMdd-HHmmss}.log"-f(Get-Date))
function L($m){"$(Get-Date -Format s) $m"|Tee-Object -FilePath $Log -Append}
$p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(-not$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw'Run as Administrator.'}
Get-Service|Select Name,Status,StartType|Export-Csv (Join-Path $OutputPath 'before.csv') -NoTypeInformation
foreach($n in $ServiceName){
    $s=Get-Service $n -ErrorAction Stop
    switch($Action){
        'Start'{if($PSCmdlet.ShouldProcess($s.Name,'Start service')){Start-Service $s.Name}}
        'Restart'{if($PSCmdlet.ShouldProcess($s.Name,'Restart service')){Restart-Service $s.Name -Force}}
        'SetAutomatic'{if($PSCmdlet.ShouldProcess($s.Name,'Set startup Automatic')){Set-Service $s.Name -StartupType Automatic}}
        'SetManual'{if($PSCmdlet.ShouldProcess($s.Name,'Set startup Manual')){Set-Service $s.Name -StartupType Manual}}
    }
    L "$Action completed for $($s.Name)"
}
Start-Sleep 2
Get-Service $ServiceName|Select Name,Status,StartType|Export-Csv (Join-Path $OutputPath 'after.csv') -NoTypeInformation
L'Repair workflow finished.'
