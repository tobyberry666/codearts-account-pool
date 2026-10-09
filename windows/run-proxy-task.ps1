param([string]$ProfileDir=(Join-Path $env:USERPROFILE '.codearts2api'))
$exePath=Join-Path $ProfileDir 'bin\codearts2api.exe'
$configPath=Join-Path $ProfileDir 'config.json'
$logPath=Join-Path $ProfileDir 'task-proxy.log'
if(!(Test-Path -LiteralPath $exePath)){Add-Content -LiteralPath $logPath -Value ('Proxy executable missing: '+$exePath);exit 1}
# Windows PowerShell may label native stderr as NativeCommandError in this log.
& $exePath -config $configPath >> $logPath 2>&1
exit $LASTEXITCODE
