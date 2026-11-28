# 一键启动：MySQL 检查 → 本地云函数模拟 → 后端 → 前端
# 用法：右键“使用 PowerShell 运行”，或在 PowerShell 里执行
#   powershell -ExecutionPolicy Bypass -File scripts\start_all.ps1
param(
    [switch]$Rebuild,
    [int]$BackendPort = 8080,
    [int]$FrontendPort = 5173,
    [int]$MockPort = 9100
)

$ErrorActionPreference = "Stop"

# 解析 npm（fnm 管理的 Node 只在特定目录，PATH 里可能没有）
function Resolve-Npm {
    $c = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $alias = Join-Path $env:APPDATA "fnm\aliases\default\npm.cmd"
    if (Test-Path $alias) { return $alias }
    return $null
}

# 解析 mvn（PATH 里没有时去常见安装目录找）
function Resolve-Mvn {
    $c = Get-Command mvn.cmd -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $cands = @()
    foreach ($root in @("E:\", "D:\", "C:\")) {
        if (Test-Path $root) {
            $cands += Get-ChildItem $root -Directory -Filter "apache-maven*" -ErrorAction SilentlyContinue
        }
    }
    foreach ($d in $cands) {
        $exe = Get-ChildItem $d.FullName -Recurse -Filter "mvn.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}
$code = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backend = Join-Path $code "backend"
$frontend = Join-Path $code "frontend\reading-room-front"
$jar = Join-Path $backend "target\studyroom-backend-1.0.0.jar"

function Say($t) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $t) }

# 1. MySQL
$svc = Get-Service MySQL95 -ErrorAction SilentlyContinue
if (-not $svc) { Say "未找到 MySQL95 服务，请先确认 MySQL 9.5 已安装"; exit 1 }
if ($svc.Status -ne "Running") {
    Say "MySQL95 未运行，尝试启动（如提示权限不足，请用管理员身份运行本脚本）"
    Start-Service MySQL95
    Start-Sleep -Seconds 3
}
Say ("MySQL95 = " + (Get-Service MySQL95).Status)

# 2. 本地云函数模拟（端口 9100）
$mockUp = $false
try { $null = Invoke-WebRequest -Uri "http://127.0.0.1:$MockPort/health" -UseBasicParsing -TimeoutSec 2; $mockUp = $true } catch { }
if (-not $mockUp) {
    $py = (Get-Command python -ErrorAction SilentlyContinue)
    if (-not $py) { Say "未找到 python，无法启动云函数模拟（计费将降级为本地计算）" }
    else {
        Start-Process -FilePath $py.Source -ArgumentList @((Join-Path $code "scripts\mock_fg.py")) `
            -WorkingDirectory $code -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $code "scripts\mock_fg.out.log") `
            -RedirectStandardError (Join-Path $code "scripts\mock_fg.err.log")
        Start-Sleep -Seconds 3
        Say "云函数模拟已启动 http://127.0.0.1:$MockPort"
    }
} else { Say "云函数模拟已在运行" }

# 3. 后端
if ($Rebuild -or -not (Test-Path $jar)) {
    $mvn = Resolve-Mvn
    if (-not $mvn) { Say "未找到 mvn，无法打包；请先在 IDEA 里执行 package" ; exit 1 }
    Say "打包后端（mvn -B -DskipTests package）"
    Push-Location $backend
    & $mvn -B -DskipTests package | Out-Null
    Pop-Location
}
$running = $false
try { $null = Invoke-WebRequest -Uri "http://127.0.0.1:$BackendPort/api/health" -UseBasicParsing -TimeoutSec 2; $running = $true } catch { }
if (-not $running) {
    $java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { (Get-Command java).Source }
    $env:FG_ENDPOINT = "http://127.0.0.1:$MockPort/billing"
    $env:STUDY_DB_USER = "study"
    $env:STUDY_DB_PASSWORD = "Study@123456"
    Start-Process -FilePath $java -ArgumentList @("-Dfile.encoding=UTF-8", "-jar", $jar) `
        -WorkingDirectory $backend -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $backend "serve.log") `
        -RedirectStandardError (Join-Path $backend "serve.err.log")
    Start-Sleep -Seconds 12
    Say "后端已启动 http://127.0.0.1:$BackendPort"
} else { Say "后端已在运行" }

# 4. 前端
$feUp = $false
try { $null = Invoke-WebRequest -Uri "http://127.0.0.1:$FrontendPort/" -UseBasicParsing -TimeoutSec 2; $feUp = $true } catch { }
if (-not $feUp) {
    $npm = Resolve-Npm
    if (-not $npm) { Say "未找到 npm，请先安装 Node 或把 fnm 的 node 加到 PATH" ; exit 1 }
    if (-not (Test-Path (Join-Path $frontend "node_modules"))) {
        Say "首次运行，安装前端依赖（npm install）"
        Push-Location $frontend
        & $npm install --no-audit --no-fund | Out-Null
        Pop-Location
    }
    Start-Process -FilePath $npm -ArgumentList @("run", "dev", "--", "--host", "127.0.0.1") `
        -WorkingDirectory $frontend -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $frontend "dev.out.log") `
        -RedirectStandardError (Join-Path $frontend "dev.err.log")
    Start-Sleep -Seconds 10
    Say "前端已启动 http://127.0.0.1:$FrontendPort"
} else { Say "前端已在运行" }

Write-Host ""
Write-Host "================ 系统已就绪 ================"
Write-Host ("  打开浏览器：http://127.0.0.1:" + $FrontendPort + "/")
Write-Host "  演示账号（口令均为 123456）："
Write-Host "    s001 张三（普通） / s003 王五（月卡） / s004 赵六（包天卡）"
Write-Host "    s005 钱七（信用 55，不能预约） / m001 店长 / a001 管理员"
Write-Host ("  后端健康检查：http://127.0.0.1:" + $BackendPort + "/api/health")
Write-Host "==========================================="
