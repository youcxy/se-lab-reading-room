# One-click LOCAL deployment for this PC.
# This machine uses phpStudy's portable MySQL 8.0.12 (root/root) instead of the
# MySQL95 service / F:\ paths used on the teammate's PC, so start_all.ps1 fails here.
# Re-running is safe: it only rebuilds the DB when -ResetDb is given.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_local.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_local.ps1 -ResetDb -Demo
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_local.ps1 -FgEndpoint "https://<your-fg-url>"
param(
    [switch]$ResetDb,
    [switch]$Demo,
    [string]$FgEndpoint = "http://127.0.0.1:9100/billing",
    [string]$MysqlDir = "D:\phpstudy_pro\Extensions\MySQL8.0.12",
    [string]$DbRootPassword = "root",
    [int]$BackendPort = 8080,
    [int]$FrontendPort = 5173,
    [int]$MockPort = 9100
)

$ErrorActionPreference = "Stop"

# Some shells inject BOTH HTTPS_PROXY and https_proxy (case-only duplicates), which
# makes PS 5.1 Start-Process throw "An item with the same key has already been added".
# Keep the values but collapse the duplicates before launching any service.
$proxyValues = @{}
foreach ($n in @('HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY', 'ALL_PROXY')) {
    $v = [Environment]::GetEnvironmentVariable($n, 'Process')
    if ($v) { $proxyValues[$n] = $v }
}
foreach ($n in @('https_proxy', 'http_proxy', 'all_proxy', 'no_proxy', 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'NO_PROXY')) {
    [Environment]::SetEnvironmentVariable($n, $null, 'Process')
}
foreach ($k in $proxyValues.Keys) { [Environment]::SetEnvironmentVariable($k, $proxyValues[$k], 'Process') }

$code = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scripts = Join-Path $code "scripts"
$backend = Join-Path $code "backend"
$frontend = Join-Path $code "frontend\reading-room-front"
$mysql = Join-Path $MysqlDir "bin\mysql.exe"
$mysqld = Join-Path $MysqlDir "bin\mysqld.exe"
$myini = Join-Path $MysqlDir "my.ini"
$jar = Join-Path $backend "target\studyroom-backend-1.0.0.jar"

function Say($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m) }

function Test-Port([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect("127.0.0.1", $p, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(500, $false)) { $c.Close(); return $false }
        $c.EndConnect($iar)
        $c.Close()
        return $true
    } catch { return $false }
}

function Wait-Port([int]$p, [int]$sec) {
    for ($i = 0; $i -lt $sec; $i++) { if (Test-Port $p) { return $true }; Start-Sleep -Seconds 1 }
    return $false
}

function Wait-Url([string]$url, [int]$sec) {
    for ($i = 0; $i -lt $sec; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Invoke-Sql([string]$file) {
    # keep stderr inside cmd: with $ErrorActionPreference=Stop, PowerShell turns
    # mysql's "Using a password ... insecure" warning into a NativeCommandError.
    $cmd = "`"$mysql`" --default-character-set=utf8mb4 -u root -p$DbRootPassword < `"$file`" 2>&1"
    $out = cmd /c $cmd | Where-Object { $_ -notmatch 'Using a password' }
    if ($LASTEXITCODE -ne 0) { throw "SQL failed ($file): $out" }
}

# 1) MySQL
if (Test-Port 3306) {
    Say "MySQL 3306 already listening"
} else {
    if (-not (Test-Path $mysqld)) { throw "mysqld.exe not found: $mysqld" }
    Say "Starting portable MySQL 8.0.12 ..."
    Start-Process -FilePath $mysqld -ArgumentList @("--defaults-file=$myini", "--console") `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $scripts "mysql.out.log") `
        -RedirectStandardError (Join-Path $scripts "mysql.err.log")
    if (-not (Wait-Port 3306 30)) { throw "MySQL did not come up; see scripts\mysql.err.log" }
    Say "MySQL is up"
}

# 2) application account + schema
$userSql = Join-Path $env:TEMP "studyroom_create_user.sql"
@'
CREATE USER IF NOT EXISTS 'study'@'localhost' IDENTIFIED WITH mysql_native_password BY 'Study@123456';
CREATE USER IF NOT EXISTS 'study'@'%' IDENTIFIED WITH mysql_native_password BY 'Study@123456';
GRANT ALL PRIVILEGES ON reading_room.* TO 'study'@'localhost';
GRANT ALL PRIVILEGES ON reading_room.* TO 'study'@'%';
FLUSH PRIVILEGES;
'@ | Set-Content -Path $userSql -Encoding ASCII
Invoke-Sql $userSql
Remove-Item $userSql -Force

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$dbs = & $mysql -u root -p$DbRootPassword -N -B -e "SHOW DATABASES" 2>$null
$ErrorActionPreference = $prevEap
if ($ResetDb -or ($dbs -notcontains "reading_room")) {
    Say "Initializing database reading_room ..."
    Invoke-Sql (Join-Path $code "sql\init.sql")
    if ($Demo) { Invoke-Sql (Join-Path $code "sql\test_data.sql") }
} else {
    Say "reading_room already exists (use -ResetDb to rebuild)"
}

# 3) local FunctionGraph simulator (same handlers as the cloud functions)
if (Test-Port $MockPort) {
    Say "mock FunctionGraph already running"
} else {
    $py = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $py) { throw "python not found in PATH" }
    Start-Process -FilePath $py -ArgumentList @((Join-Path $scripts "mock_fg.py")) `
        -WorkingDirectory $code -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $scripts "mock_fg.out.log") `
        -RedirectStandardError (Join-Path $scripts "mock_fg.err.log")
    if (-not (Wait-Port $MockPort 15)) { throw "mock FunctionGraph failed; see scripts\mock_fg.err.log" }
    Say "mock FunctionGraph up on $MockPort"
}

# 4) Spring Boot backend
if (Wait-Url "http://127.0.0.1:$BackendPort/api/health" 1) {
    Say "backend already running"
} else {
    if (-not (Test-Path $jar)) { throw "backend jar missing: $jar (run: mvn -B -DskipTests package)" }
    $java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { (Get-Command java).Source }
    $env:FG_ENDPOINT = $FgEndpoint
    $env:STUDY_DB_USER = "study"
    $env:STUDY_DB_PASSWORD = "Study@123456"
    Start-Process -FilePath $java -ArgumentList @("-Dfile.encoding=UTF-8", "-jar", $jar) `
        -WorkingDirectory $backend -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $backend "serve.log") `
        -RedirectStandardError (Join-Path $backend "serve.err.log")
    if (-not (Wait-Url "http://127.0.0.1:$BackendPort/api/health" 40)) { throw "backend not healthy; see backend\serve.err.log" }
    Say "backend up on $BackendPort"
}

# 5) Vue / Vite frontend
if (Test-Port $FrontendPort) {
    Say "frontend already running"
} else {
    $node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
    $vite = Join-Path $frontend "node_modules\vite\bin\vite.js"
    if (-not $node -or -not (Test-Path $vite)) { throw "node or vite missing; run npm install first" }
    Start-Process -FilePath $node -ArgumentList @($vite, "--host", "127.0.0.1") `
        -WorkingDirectory $frontend -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $frontend "dev.out.log") `
        -RedirectStandardError (Join-Path $frontend "dev.err.log")
    if (-not (Wait-Port $FrontendPort 20)) { throw "frontend failed; see frontend\reading-room-front\dev.err.log" }
    Say "frontend up on $FrontendPort"
}

# 6) verification
$health = Invoke-RestMethod -Uri "http://127.0.0.1:$BackendPort/api/health" -TimeoutSec 5
$quote = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$BackendPort/api/cloud/quote" `
    -ContentType "application/json" -Body '{"unitPrice":4.00,"minutes":30}' -TimeoutSec 5
Write-Host ""
Write-Host "================ DEPLOYED ================"
Write-Host "  Frontend : http://127.0.0.1:$FrontendPort/"
Write-Host "  Backend  : http://127.0.0.1:$BackendPort/api/health"
Write-Host "  Cloud fn : http://127.0.0.1:$MockPort/health (mock)"
Write-Host "  Accounts : s001 / s003 / s004 / s005 / m001 / a001 , password 123456"
Write-Host ("  Health   : " + ($health | ConvertTo-Json -Compress -Depth 5))
Write-Host ("  Quote    : " + ($quote | ConvertTo-Json -Compress -Depth 5))
Write-Host "========================================="
