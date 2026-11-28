# 停止本项目启动的三个进程：后端 jar、云函数模拟、前端 vite
# 用法：powershell -ExecutionPolicy Bypass -File scripts\stop_all.ps1
$ErrorActionPreference = "SilentlyContinue"

function KillByCommandLine([string]$pattern, [string]$label) {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'python.exe' OR Name = 'node.exe'"
    $hit = $procs | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$pattern*" }
    if (-not $hit) { Write-Host ("[skip] " + $label + " 未运行"); return }
    foreach ($p in $hit) {
        Stop-Process -Id $p.ProcessId -Force
        Write-Host ("[stop] " + $label + " pid=" + $p.ProcessId)
    }
}

KillByCommandLine "studyroom-backend-1.0.0.jar" "后端"
KillByCommandLine "mock_fg.py" "云函数模拟"
KillByCommandLine "reading-room-front" "前端 vite"

Start-Sleep -Seconds 2
foreach ($port in 8080, 5173, 9100) {
    $busy = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    Write-Host ("[port] " + $port + " " + $(if ($busy) { "仍被占用" } else { "已释放" }))
}
