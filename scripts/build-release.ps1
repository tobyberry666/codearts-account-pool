param([string]$Version='v0.1.1',[string]$GoExecutable='go')
$ErrorActionPreference='Stop'
if($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?$'){throw 'Invalid version'}
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try{
    & $GoExecutable test ./... -timeout 120s
    if($LASTEXITCODE -ne 0){throw 'Go tests failed'}
    $dist=Join-Path $root 'dist'
    $null=New-Item -ItemType Directory -Path $dist -Force
    $name='codearts-account-pool-'+$Version+'-windows-amd64'
    $stage=Join-Path $dist ('.stage-'+[guid]::NewGuid().ToString('N'))
    $bundle=Join-Path $stage $name
    $null=New-Item -ItemType Directory -Path (Join-Path $bundle 'bin') -Force
    $oldGoos=$env:GOOS;$oldGoarch=$env:GOARCH;$oldCgo=$env:CGO_ENABLED
    try{
        $env:GOOS='windows';$env:GOARCH='amd64';$env:CGO_ENABLED='0'
        & $GoExecutable build -trimpath -buildvcs=false -o (Join-Path $bundle 'bin\codearts2api.exe') ./cmd/server
        if($LASTEXITCODE -ne 0){throw 'Server build failed'}
        & $GoExecutable build -trimpath -buildvcs=false -o (Join-Path $bundle 'bin\codearts-login.exe') ./cmd/login
        if($LASTEXITCODE -ne 0){throw 'Login build failed'}
    }finally{$env:GOOS=$oldGoos;$env:GOARCH=$oldGoarch;$env:CGO_ENABLED=$oldCgo}
    foreach($file in @('README.md','LICENSE','NOTICE.md','CHANGELOG.md','Install.cmd','config.example.json')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $bundle}
    foreach($dir in @('windows','docs')){$null=New-Item -ItemType Directory -Path (Join-Path $bundle $dir) -Force}
    foreach($file in @('install.ps1','start-proxy.ps1','stop-proxy.ps1','run-proxy-task.ps1','manage-accounts.ps1','task-common.ps1')){
        [IO.File]::WriteAllText((Join-Path $bundle ('windows\'+$file)),[IO.File]::ReadAllText((Join-Path $root ('windows\'+$file))),[Text.UTF8Encoding]::new($true))
    }
    foreach($file in @('architecture.md','troubleshooting.md','account-pool-windows.md','upstream-readme.md')){Copy-Item -LiteralPath (Join-Path $root ('docs\'+$file)) -Destination (Join-Path $bundle 'docs')}
    $tokens=$null;$parseErrors=$null
    foreach($file in (Get-ChildItem -LiteralPath (Join-Path $bundle 'windows') -Filter '*.ps1')){
        $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        if($parseErrors.Count){throw ('PowerShell parse failure: '+$file.Name)}
    }
    $testScript=Join-Path $stage 'test-install.ps1'
    [IO.File]::WriteAllText($testScript,[IO.File]::ReadAllText((Join-Path $root 'windows\test-install.ps1')),[Text.UTF8Encoding]::new($true))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testScript -BundleDir $bundle
    if($LASTEXITCODE -ne 0){throw 'Windows PowerShell installer test failed'}
    $zip=Join-Path $dist ($name+'.zip')
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    try{
        foreach($entry in $archive.Entries){
            $path=$entry.FullName.Replace('\','/')
            if($path -match '(^|/)(auths|data|backups|\.git)(/|$)|(^|/)(config\.json|connection\.txt|task-proxy\.log)$|(^|/)codearts-[^/]+\.json$'){throw ('Forbidden release entry: '+$path)}
        }
    }finally{$archive.Dispose()}
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'),($hash+'  '+[IO.Path]::GetFileName($zip)+"`n"),[Text.UTF8Encoding]::new($false))
    Write-Host ('Release verified: '+$zip)
}finally{Pop-Location}
