# Reset the reading_room database to the initial seed data (1 room, 10 seats, 7 users, price 4.00).
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\reset_db.ps1
#        -Demo  also writes the demo scenario (test_data.sql)
param(
    [string]$Mysql = "C:\Program Files\MySQL\MySQL Server 9.5\bin\mysql.exe",
    [string]$DbUser = "root",
    [string]$DbPassword = "Root@123456",
    [string]$DbName = "reading_room",
    [string]$Base = "http://127.0.0.1:8080",
    [switch]$Demo
)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Run-Sql([string]$file) {
    $path = Join-Path $root $file
    if (-not (Test-Path $path)) { throw "missing sql file: $path" }
    $cmd = "`"$Mysql`" --default-character-set=utf8mb4 -u $DbUser -p$DbPassword < `"$path`""
    $out = cmd /c $cmd 2>&1 | Where-Object { $_ -notmatch 'Using a password' }
    if ($LASTEXITCODE -ne 0) { throw "sql failed: $file -> $out" }
    Write-Output ("[ok] " + $file)
}

Run-Sql "sql\init.sql"
if ($Demo) { Run-Sql "sql\test_data.sql" }

try {
    Invoke-RestMethod -Method Post -Uri "$Base/api/clock/reset" -ContentType "application/json" | Out-Null
    Write-Output "[ok] sim clock reset"
} catch {
    Write-Output "[skip] backend not reachable, clock reset skipped"
}

Write-Output "database reset done: reading_room = 1 room / 10 seats / 7 users / price 4.00"
