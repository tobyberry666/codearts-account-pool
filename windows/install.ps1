param(
    [string]$ProfileDir=(Join-Path $env:USERPROFILE '.codearts2api'),
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'task-common.ps1')
$bundleRoot=Split-Path -Parent $PSScriptRoot
$ProfileDir=[IO.Path]::GetFullPath($ProfileDir)
$proxyExe=Join-Path $ProfileDir 'bin\codearts2api.exe'
if(!$PrepareOnly){
    $existing=Get-ScheduledTask -TaskName 'CodeArts2API-LocalProxy' -ErrorAction SilentlyContinue
    if($existing -and !(Test-ProxyTaskOwner $existing $ProfileDir)){throw '同名后台任务属于其他安装目录。现有任务和安装文件未修改；可选择 PrepareOnly 模式。'}
}
if(@(Get-Process -Name codearts2api -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $proxyExe}).Count){throw '已有代理正在运行。请先停止代理，再重新安装；不会覆盖正在使用的程序。'}
foreach($name in @('codearts2api.exe','codearts-login.exe')){
    if(!(Test-Path -LiteralPath (Join-Path $bundleRoot ('bin\'+$name)))){throw ('缺少程序：'+$name+'。请下载 Release 的 Windows ZIP 并完整解压。')}
}
foreach($dir in @($ProfileDir,(Join-Path $ProfileDir 'bin'),(Join-Path $ProfileDir 'auths'),(Join-Path $ProfileDir 'data'))){$null=New-Item -ItemType Directory -Path $dir -Force}
$configPath=Join-Path $ProfileDir 'config.json'
if(!(Test-Path -LiteralPath $configPath)){
    $bytes=New-Object byte[] 24
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    $key=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    $config=[ordered]@{
        listen='127.0.0.1:7866';api_key=$key
        auth_dir=(Join-Path $ProfileDir 'auths');state_file=(Join-Path $ProfileDir 'data\state.json')
        default_model='deepseek-v4.1-flash';max_concurrent=1;benefit_auto_claim=$true
        cooldown=@{soft_rate='60s';err_threshold=3;err_cooldown='10m'}
        watch=@{enabled=$false;poll_minutes=30;refresh_skew_minutes=30;keepalive_interval_minutes=15}
        upstream=@{timeout_seconds=120}
    }
    [IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
$cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if(!$cfg.api_key){throw '现有配置没有 api_key，请先补充本地随机密钥。安装器不会替换现有配置。'}
$backup=Join-Path $ProfileDir ('backups\install-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
if(Test-Path -LiteralPath $proxyExe){
    $null=New-Item -ItemType Directory -Path $backup -Force
    Copy-Item -LiteralPath (Join-Path $ProfileDir 'bin') -Destination $backup -Recurse
    foreach($name in @('start-proxy.ps1','run-proxy-task.ps1','manage-accounts.ps1','stop-proxy.ps1','task-common.ps1')){if(Test-Path -LiteralPath (Join-Path $ProfileDir $name)){Copy-Item -LiteralPath (Join-Path $ProfileDir $name) -Destination $backup}}
}
foreach($name in @('codearts2api.exe','codearts-login.exe')){Copy-Item -LiteralPath (Join-Path $bundleRoot ('bin\'+$name)) -Destination (Join-Path $ProfileDir ('bin\'+$name)) -Force}
foreach($name in @('start-proxy.ps1','run-proxy-task.ps1','manage-accounts.ps1','stop-proxy.ps1','task-common.ps1')){
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
    [IO.File]::WriteAllText((Join-Path $ProfileDir $name),$source,[Text.UTF8Encoding]::new($true))
}
$connection=@("Base URL: http://$($cfg.listen)/v1",'Provider API: OpenAI chat completions',"Local API key: $($cfg.api_key)",'Models: deepseek-v4.1-flash / deepseek-v4-pro-0813','This local key is not a Huawei account token. Do not share this file.') -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $ProfileDir 'connection.txt'),$connection,[Text.UTF8Encoding]::new($true))
if(!$PrepareOnly){
    $taskName='CodeArts2API-LocalProxy'
    $runner=Join-Path $ProfileDir 'run-proxy-task.ps1'
    $taskArgs='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$runner+'" -ProfileDir "'+$ProfileDir+'"'
    $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs
    $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $null=Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force
    $desktop=[Environment]::GetFolderPath('Desktop')
    foreach($entry in @(@('CodeArts 启动代理.cmd','start-proxy.ps1'),@('CodeArts 账号管理.cmd','manage-accounts.ps1'),@('CodeArts 停止代理.cmd','stop-proxy.ps1'))){
        $script=Join-Path $ProfileDir $entry[1]
        $content="@echo off`r`nchcp 65001 >nul`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`" -ProfileDir `"$ProfileDir`"`r`n"
        [IO.File]::WriteAllText((Join-Path $desktop $entry[0]),$content,[Text.UTF8Encoding]::new($false))
    }
}
Write-Host ('安装完成：'+$ProfileDir)
Write-Host '原有配置、密钥、账号和状态已保留。连接信息在 connection.txt（包含本地密钥，请勿分享）。'
if($PrepareOnly){Write-Host 'PrepareOnly：未注册后台任务、未创建桌面入口、未启动代理。'}else{Write-Host '请双击桌面的 CodeArts 账号管理.cmd，登录自己的账号。'}
