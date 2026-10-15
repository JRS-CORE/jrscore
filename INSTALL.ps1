#  JRS Core - Free Edition - offline installer
#  Copies every resource, writes server.cfg and imports the database.
#  Usage: double-click INSTALL.bat (or: powershell -ExecutionPolicy Bypass -File INSTALL.ps1)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Ask($label, $default) {
    $v = Read-Host ("{0} [{1}]" -f $label, $default)
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    return $v.Trim()
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Yellow
Write-Host '   JRS Core - Free Edition  |  Installer'      -ForegroundColor Yellow
Write-Host '==============================================' -ForegroundColor Yellow
Write-Host ''

# ---------- 1) Server data folder ----------
$target = Ask 'Server data folder (where server.cfg lives) / مجلد السيرفر' 'C:\txData\JRSCore'
if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
$resTarget = Join-Path $target 'resources'
if (-not (Test-Path -LiteralPath $resTarget)) { New-Item -ItemType Directory -Path $resTarget | Out-Null }

Write-Host ''
Write-Host '[1/3] Copying resources...' -ForegroundColor Cyan
Get-ChildItem -LiteralPath (Join-Path $here 'resources') -Directory | ForEach-Object {
    $dest = Join-Path $resTarget $_.Name
    if (Test-Path -LiteralPath $dest) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $bak = Join-Path $target ("_backup_" + $stamp)
        if (-not (Test-Path -LiteralPath $bak)) { New-Item -ItemType Directory -Path $bak | Out-Null }
        Write-Host ("      existing {0} moved to {1}" -f $_.Name, $bak) -ForegroundColor DarkYellow
        Move-Item -LiteralPath $dest -Destination (Join-Path $bak $_.Name)
    }
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse
    Write-Host ("      + {0}" -f $_.Name)
}

# ---------- 2) Database ----------
Write-Host ''
Write-Host '[2/3] Database' -ForegroundColor Cyan
$dbHost = Ask 'MySQL host' 'localhost'
$dbPort = Ask 'MySQL port' '3306'
$dbUser = Ask 'MySQL user' 'root'
$dbPassSecure = Read-Host 'MySQL password (empty = none)' -AsSecureString
$dbPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPassSecure))
$dbName = Ask 'Database name' 'jrscore'

$mysql = $null
$cmd = Get-Command mysql.exe -ErrorAction SilentlyContinue
if ($cmd) { $mysql = $cmd.Source }
if (-not $mysql) {
    $candidates = @(
        'C:\xampp\mysql\bin\mysql.exe',
        'C:\laragon\bin\mysql\*\bin\mysql.exe',
        'C:\Program Files\MariaDB*\bin\mysql.exe',
        'C:\Program Files\MySQL\MySQL Server*\bin\mysql.exe'
    )
    foreach ($c in $candidates) {
        $hit = Get-ChildItem -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $mysql = $hit.FullName; break }
    }
}

$sqlFile = Join-Path $here 'sql\jrscore.sql'
if ($mysql) {
    Write-Host ("      using {0}" -f $mysql)
    $auth = @('-h', $dbHost, '-P', $dbPort, '-u', $dbUser, '--default-character-set=utf8mb4')
    if ($dbPass) { $auth += ('-p' + $dbPass) }
    & $mysql @auth -e ("CREATE DATABASE IF NOT EXISTS ``{0}`` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" -f $dbName)
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect to MySQL / تعذر الاتصال بقاعدة البيانات' }
    foreach ($f in @($sqlFile, (Join-Path $here 'sql\jrscore_addons.sql'), (Join-Path $here 'sql\jrscore_scripts.sql'))) {
        cmd /c ('"{0}" {1} {2} < "{3}"' -f $mysql, (($auth | ForEach-Object { '"' + $_ + '"' }) -join ' '), $dbName, $f)
        if ($LASTEXITCODE -ne 0) { throw 'SQL import failed / فشل استيراد قاعدة البيانات' }
    }
    Write-Host '      database imported OK' -ForegroundColor Green
} else {
    Write-Host '      mysql.exe not found - import sql\jrscore.sql with HeidiSQL into the database:' -ForegroundColor DarkYellow
    Write-Host ("      {0}" -f $dbName) -ForegroundColor DarkYellow
}

# ---------- 3) server.cfg ----------
Write-Host ''
Write-Host '[3/3] server.cfg' -ForegroundColor Cyan
$license = Ask 'Cfx.re license key (https://portal.cfx.re)' 'changeme'
$slots = Ask 'Max players' '48'
$cfgPath = Join-Path $target 'server.cfg'
if (Test-Path -LiteralPath $cfgPath) {
    Copy-Item -LiteralPath $cfgPath -Destination ($cfgPath + '.before_jrscore') -Force
    Write-Host '      old server.cfg saved as server.cfg.before_jrscore' -ForegroundColor DarkYellow
}
$encPass = [Uri]::EscapeDataString($dbPass)
$conn = if ($dbPass) { "mysql://{0}:{1}@{2}:{3}/{4}?charset=utf8mb4" -f $dbUser, $encPass, $dbHost, $dbPort, $dbName } else { "mysql://{0}@{1}:{2}/{3}?charset=utf8mb4" -f $dbUser, $dbHost, $dbPort, $dbName }
$cfg = Get-Content -LiteralPath (Join-Path $here 'server.cfg') -Raw -Encoding UTF8
$cfg = $cfg.Replace('{{serverEndpoints}}', "endpoint_add_tcp `"0.0.0.0:30120`"`nendpoint_add_udp `"0.0.0.0:30120`"")
$cfg = $cfg.Replace('{{dbConnectionString}}', $conn)
$cfg = $cfg.Replace('{{maxClients}}', $slots)
$cfg = $cfg.Replace('{{svLicense}}', $license)
$cfg = $cfg.Replace('{{addPrincipalsMaster}}', '# add_principal identifier.fivem:YOUR_ID group.admin')
$cfg = $cfg.Replace('{{recipeName}}', 'JRS Core').Replace('{{recipeAuthor}}', 'JRS TEAM')
$cfg = $cfg.Replace('{{recipeDescription}}', 'JRS Core free RedM framework')
[IO.File]::WriteAllText($cfgPath, $cfg, (New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host 'DONE / تم التثبيت' -ForegroundColor Green
Write-Host ("Server folder: {0}" -f $target)
Write-Host 'In txAdmin: Settings > FXServer > Server Data Folder = the folder above, CFG File = server.cfg, OneSync = ON'
Write-Host ''
Read-Host 'Press Enter to close'
