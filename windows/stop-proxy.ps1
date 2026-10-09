param([string]$ProfileDir=(Join-Path $env:USERPROFILE '.codearts2api'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'task-common.ps1')
$null=Get-OwnedProxyTask $ProfileDir
Stop-ScheduledTask -TaskName 'CodeArts2API-LocalProxy' -ErrorAction SilentlyContinue
$proxyExe=Join-Path $ProfileDir 'bin\codearts2api.exe'
Get-Process -Name codearts2api -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $proxyExe} | ForEach-Object {Stop-Process -Id $_.Id;$null=$_.WaitForExit(5000)}
Write-Host '代理已停止。账号和配置保留，下次双击启动入口即可恢复。'
