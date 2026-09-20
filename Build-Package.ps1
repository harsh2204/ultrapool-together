[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageFiles = @('mod', 'Install.ps1', 'Install.cmd', 'Uninstall.ps1', 'Launch.cmd', 'README.md')
$paths = foreach ($name in $packageFiles) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Package file is missing: $name" }
    $path
}
$distPath = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $distPath -Force | Out-Null
$archivePath = Join-Path $distPath 'UltrapoolTogether.zip'
Compress-Archive -LiteralPath $paths -DestinationPath $archivePath -Force
Write-Host "Created $archivePath"
Write-Host 'This archive contains mod code and installation scripts. Each player must supply their own installed game.'
