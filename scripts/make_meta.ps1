# Export information_schema metadata of reading_room to TSV files used by build_db_doc.py.
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\make_meta.ps1
param(
    [string]$Mysql = "C:\Program Files\MySQL\MySQL Server 9.5\bin\mysql.exe",
    [string]$DbUser = "root",
    [string]$DbPassword = "Root@123456",
    [string]$DbName = "reading_room"
)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$colsFile = Join-Path $PSScriptRoot "_cols.tsv"
$idxFile = Join-Path $PSScriptRoot "_idx.tsv"

$colsSql = "SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, IFNULL(COLUMN_DEFAULT,''), COLUMN_COMMENT " +
           "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DbName' ORDER BY TABLE_NAME, ORDINAL_POSITION"
$idxSql = "SELECT TABLE_NAME, INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX), IF(MAX(NON_UNIQUE)=0,'UNIQUE','INDEX') " +
          "FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='$DbName' GROUP BY TABLE_NAME, INDEX_NAME ORDER BY TABLE_NAME, INDEX_NAME"

function Dump([string]$sql, [string]$file) {
    $cmd = "`"$Mysql`" --default-character-set=utf8mb4 -u $DbUser -p$DbPassword -B -N -e `"$sql`""
    $lines = cmd /c $cmd 2>$null
    if ($LASTEXITCODE -ne 0) { throw "metadata query failed: $sql" }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($file, (($lines -join "`r`n") + "`r`n"), $utf8)
    Write-Output ("[ok] " + (Split-Path -Leaf $file) + " rows=" + $lines.Count)
}

Dump $colsSql $colsFile
Dump $idxSql $idxFile
Write-Output "metadata exported; now run: python scripts\build_db_doc.py"
