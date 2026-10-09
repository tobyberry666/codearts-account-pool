function Test-ProxyTaskOwner($Task,[string]$ProfileDir){
    if(!$Task -or @($Task.Actions).Count -ne 1){return $false}
    $action=@($Task.Actions)[0]
    if([IO.Path]::GetFileName($action.Execute) -ne 'powershell.exe'){return $false}
    $fileMatch=[regex]::Match($action.Arguments,'(?i)(?:^|\s)-File\s+(?:"([^"]+)"|(\S+))')
    if(!$fileMatch.Success){return $false}
    $runner=$fileMatch.Groups[1].Value
    if(!$runner){$runner=$fileMatch.Groups[2].Value}
    $expected=Join-Path ([IO.Path]::GetFullPath($ProfileDir)) 'run-proxy-task.ps1'
    if(![string]::Equals([IO.Path]::GetFullPath($runner),$expected,[StringComparison]::OrdinalIgnoreCase)){return $false}
    $profileMatch=[regex]::Match($action.Arguments,'(?i)(?:^|\s)-ProfileDir\s+(?:"([^"]+)"|(\S+))')
    if($profileMatch.Success){
        $actual=$profileMatch.Groups[1].Value
        if(!$actual){$actual=$profileMatch.Groups[2].Value}
    }else{$actual=Join-Path $env:USERPROFILE '.codearts2api'}
    return [string]::Equals([IO.Path]::GetFullPath($actual),[IO.Path]::GetFullPath($ProfileDir),[StringComparison]::OrdinalIgnoreCase)
}

function Get-OwnedProxyTask([string]$ProfileDir){
    $task=Get-ScheduledTask -TaskName 'CodeArts2API-LocalProxy' -ErrorAction Stop
    if(!(Test-ProxyTaskOwner $task $ProfileDir)){throw '同名后台任务属于其他安装目录，未启动或停止它。此目录可使用 PrepareOnly 和前台运行方式。'}
    return $task
}
