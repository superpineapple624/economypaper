param(
    [string]$DoFile = "code\00_master.do"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$stataExe = "D:\StataMP-64.exe"
if (-not (Test-Path $stataExe)) {
    throw "Stata executable not found: $stataExe"
}

if (-not (Test-Path $DoFile)) {
    throw "Do-file not found: $DoFile"
}

Write-Host "Running Stata..."
Write-Host "Executable: $stataExe"
Write-Host "Do-file   : $DoFile"
Write-Host ""

& $stataExe /e do $DoFile
exit $LASTEXITCODE
