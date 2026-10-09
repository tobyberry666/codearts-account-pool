param([Parameter(Mandatory=$true)][string]$BundleDir)
$ErrorActionPreference='Stop'
$testRoot=Join-Path $env:TEMP ('codearts-package-test-'+[guid]::NewGuid().ToString('N'))
$profileDir=Join-Path $testRoot 'profile with spaces 中文'
$installer=Join-Path $BundleDir 'windows\install.ps1'
if(!(Test-Path -LiteralPath $installer)){throw 'Missing portable installer'}
& $installer -ProfileDir $profileDir -PrepareOnly
if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw 'Installer failed'}
$configFile=Join-Path $profileDir 'config.json'
$cfg=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
if($cfg.listen -ne '127.0.0.1:7866' -or $cfg.max_concurrent -ne 1 -or $cfg.api_key.Length -lt 32){throw 'Invalid safe defaults'}
if($cfg.auth_dir -ne (Join-Path $profileDir 'auths') -or $cfg.state_file -ne (Join-Path $profileDir 'data\state.json')){
 foreach($path in @($profileDir,$cfg.auth_dir,$cfg.state_file)){
  Write-Host ('Path codepoints: '+(($path.ToCharArray() | ForEach-Object {([int]$_).ToString('X4')}) -join ' '))
 }
 throw 'Unicode configuration paths were corrupted'
}
foreach($file in @('bin\codearts2api.exe','bin\codearts-login.exe','start-proxy.ps1','run-proxy-task.ps1','manage-accounts.ps1','stop-proxy.ps1','task-common.ps1','connection.txt')){
 if(!(Test-Path -LiteralPath (Join-Path $profileDir $file))){throw ('Missing installed file: '+$file)}
}
if(@(Get-ChildItem -LiteralPath (Join-Path $profileDir 'auths') -File).Count -ne 0){throw 'Installer included credentials'}
$before=[IO.File]::ReadAllBytes($configFile)
& $installer -ProfileDir $profileDir -PrepareOnly
$after=[IO.File]::ReadAllBytes($configFile)
if([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String($after)){throw 'Reinstall changed existing key or config'}
. (Join-Path $profileDir 'task-common.ps1')
$runner=Join-Path $profileDir 'run-proxy-task.ps1'
$owned=[pscustomobject]@{Actions=@([pscustomobject]@{Execute='powershell.exe';Arguments=('-File "'+$runner+'" -ProfileDir "'+$profileDir+'"')})}
if(!(Test-ProxyTaskOwner $owned $profileDir)){throw 'Own profile task was rejected'}
if(Test-ProxyTaskOwner $owned (Join-Path $testRoot 'another profile')){throw 'Other profile task was accepted'}
$owned.Actions[0].Arguments='-File "'+$runner+'" -ProfileDir "'+(Join-Path $testRoot 'another profile')+'"'
if(Test-ProxyTaskOwner $owned $profileDir){throw 'Mismatched profile argument was accepted'}
Write-Host 'PASS: task ownership validation rejects other installations without operating real tasks.'
Write-Host 'PASS: clean install, no credentials, safe defaults, repeat install preserves config.'
