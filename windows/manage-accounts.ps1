param([switch]$CheckOnly,[string]$ProfileDir=(Join-Path $env:USERPROFILE '.codearts2api'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'task-common.ps1')
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$config = Get-Content -LiteralPath (Join-Path $profileDir 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$baseUrl = 'http://' + $config.listen
$headers = @{ Authorization = 'Bearer ' + $config.api_key }
$loginExe = Join-Path $profileDir 'bin\codearts-login.exe'

function Get-Accounts {
    return @((Invoke-RestMethod -Uri ($baseUrl + '/status') -Headers $headers -TimeoutSec 5).accounts)
}

function Show-Accounts {
    $accounts = @(Get-Accounts)
    Write-Host ('当前账号数：' + $accounts.Count)
    $accounts | Select-Object name, nickname, disabled, cooling, active_concurrent, token_remaining | Format-Table -AutoSize
}

function Wait-Idle {
    for ($i = 0; $i -lt 30; $i++) {
        $active = @((Get-Accounts) | Where-Object { $_.active_concurrent -gt 0 })
        if ($active.Count -eq 0) { return }
        if ($i -eq 0) { Write-Host '等待正在进行的请求结束。请暂时停止发送新请求。' }
        Start-Sleep -Seconds 2
    }
    throw '仍有活跃请求。请停止 DSH 当前任务后，再选择重载账号。登录凭证已保留。'
}

function Reload-Accounts {
    Wait-Idle
    try { Stop-Proxy } finally { Start-Proxy }
}

function Stop-Proxy {
    $null=Get-OwnedProxyTask $ProfileDir
    Stop-ScheduledTask -TaskName 'CodeArts2API-LocalProxy'
    $proxyExe = Join-Path $profileDir 'bin\codearts2api.exe'
    Get-Process -Name 'codearts2api' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $proxyExe } | ForEach-Object {
        Stop-Process -Id $_.Id
        $null = $_.WaitForExit(5000)
    }
    if (@(Get-Process -Name 'codearts2api' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $proxyExe }).Count -gt 0) { throw '代理未能停止，未开始写入新凭证。' }
}

function Start-Proxy {
    $null=Get-OwnedProxyTask $ProfileDir
    Start-ScheduledTask -TaskName 'CodeArts2API-LocalProxy'
    for ($i = 0; $i -lt 30; $i++) {
        try { $null = Get-Accounts; return } catch { Start-Sleep -Milliseconds 500 }
    }
    throw '代理恢复启动失败，请查看 task-proxy.log。'
}

try {
    if (!(Test-Path -LiteralPath $loginExe)) { throw ('缺少登录程序：' + $loginExe) }
    if ($CheckOnly) {
        Show-Accounts
        Write-Host '账号管理入口检查通过。未发起模型请求。'
        exit 0
    }
    & (Join-Path $profileDir 'start-proxy.ps1') -ProfileDir $ProfileDir
    while ($true) {
        Show-Accounts
        Write-Host '1 添加账号  |  2 重新登录已有账号  |  3 重载/查看状态  |  0 退出'
        $choice = Read-Host '请选择'
        if ($choice -eq '0') { break }
        if ($choice -eq '3') { Reload-Accounts; continue }
        if ($choice -notin @('1', '2')) { continue }
        Write-Host '请先在浏览器退出当前华为账号，再登录你要添加的另一个账号。'
        Write-Host '密码和验证码只填写在华为官方页面。重复登录同一账号不会增加额度。'
        $null = Read-Host '准备好后按回车打开登录页'
        $loginArgs = @('-auth-dir', $config.auth_dir)
        $selectedId = ''
        if ($choice -eq '2') {
            $files = @(Get-ChildItem -LiteralPath $config.auth_dir -Filter 'codearts-*.json' | ForEach-Object {
                $account = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                [pscustomobject]@{ Path = $_.FullName; Id = $account.account_id; Name = $account.user_name }
            })
            for ($i = 0; $i -lt $files.Count; $i++) { Write-Host ($i.ToString() + ': ' + $files[$i].Name + ' ' + $files[$i].Id) }
            $index = 0
            if (![int]::TryParse((Read-Host '输入账号序号'), [ref]$index) -or $index -lt 0 -or $index -ge $files.Count) { Write-Host '无效序号'; continue }
            $selected = $files[$index]
            $selectedId = $selected.Id
            $backup = Join-Path $profileDir ('backups\relogin-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            $null = New-Item -ItemType Directory -Path $backup -Force
            Copy-Item -LiteralPath $selected.Path -Destination $backup
            $loginArgs += @('-account-id', $selected.Id, '-auth-file', $selected.Path)
        }
        $before = @(Get-Accounts).Count
        Wait-Idle
        Write-Host '登录期间暂时停止本地代理，避免后台刷新覆盖凭证；登录结束后自动恢复。'
        $loginExit = 1
        try {
            Stop-Proxy
            & $loginExe @loginArgs | Tee-Object -Variable loginOutput
            $loginExit = $LASTEXITCODE
        } finally { Start-Proxy }
        if ($loginExit -ne 0) { Write-Host '登录未成功，原有凭证仍可使用。'; continue }
        $idLine = @($loginOutput | Where-Object { $_ -is [string] -and $_.StartsWith('LOCAL_ACCOUNT_ID=') } | Select-Object -Last 1)
        if ($idLine.Count -eq 1) { $selectedId = $idLine[0].Substring('LOCAL_ACCOUNT_ID='.Length) }
        if ($selectedId) {
            $body = @{ uid = $selectedId } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Method Post -Uri ($baseUrl + '/admin/api/accounts/enable') -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 5
            $null = Invoke-RestMethod -Method Post -Uri ($baseUrl + '/admin/api/accounts/clear-cooldown') -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 5
        }
        $after = @(Get-Accounts).Count
        Write-Host ('重载成功，账号数：' + $after + '。DSH 地址和密钥无需修改。')
        if ($choice -eq '1' -and $after -le $before) { Write-Host '账号数没有增加，可能登录了同一账号。请退出浏览器账号后重试。' }
    }
} catch {
    Write-Host ('操作失败：' + $_.Exception.Message) -ForegroundColor Red
    if (!$CheckOnly) { $null = Read-Host '按回车关闭' }
    exit 1
}
