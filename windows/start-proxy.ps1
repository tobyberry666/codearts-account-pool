param([string]$ProfileDir=(Join-Path $env:USERPROFILE '.codearts2api'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'task-common.ps1')
try{
    $cfg=Get-Content -LiteralPath (Join-Path $ProfileDir 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $baseUrl='http://'+$cfg.listen
    $headers=@{Authorization='Bearer '+$cfg.api_key}
    function Test-Proxy {
        try{$null=Invoke-RestMethod -Uri ($baseUrl+'/status') -Headers $headers -TimeoutSec 2;return $true}catch{return $false}
    }
    if(!(Test-Proxy)){
        $null=Get-OwnedProxyTask $ProfileDir
        Start-ScheduledTask -TaskName 'CodeArts2API-LocalProxy'
        $ready=$false
        for($i=0;$i -lt 30;$i++){Start-Sleep -Milliseconds 500;if(Test-Proxy){$ready=$true;break}}
        if(!$ready){throw ('启动失败，请查看 '+(Join-Path $ProfileDir 'task-proxy.log'))}
    }
    Write-Host ('代理已运行：'+$baseUrl+'/v1')
}catch{Write-Host $_.Exception.Message -ForegroundColor Red;$null=Read-Host '按回车关闭';exit 1}
