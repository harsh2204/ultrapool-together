[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageFiles = @('mod', 'docs', 'Install.ps1', 'Install.cmd', 'Uninstall.ps1', 'Launch.cmd', 'Install.command', 'Launch.command', 'Uninstall.command', 'MacOS.py', 'README.md')
$paths = foreach ($name in $packageFiles) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Package file is missing: $name" }
    $path
}
$distPath = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $distPath -Force | Out-Null
$archivePath = Join-Path $distPath 'UltrapoolTogether.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryPath = Join-Path $distPath ([Guid]::NewGuid().ToString('N') + '.zip')
try {
    $archive = [System.IO.Compression.ZipFile]::Open($temporaryPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($path in $paths) {
            $files = if (Test-Path -LiteralPath $path -PathType Container) {
                Get-ChildItem -LiteralPath $path -File -Recurse
            } else {
                Get-Item -LiteralPath $path
            }
            foreach ($file in $files) {
                $relative = $file.FullName.Substring($PSScriptRoot.Length + 1).Replace('\', '/')
                $entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal)
                # Unix file modes make Finder launchers executable even for ZIPs
                # produced on Windows (Compress-Archive discards these modes).
                $entry.ExternalAttributes = if ($relative.EndsWith('.command')) { [int]0x81ED0000 } else { [int]0x81A40000 }
            }
        }
    } finally {
        $archive.Dispose()
    }
    # Windows .NET marks ZIP entries as DOS-created. Set the central-directory
    # creator platform to Unix so macOS honors the executable modes above.
    # This source-only archive has no comments or ZIP64-sized entries.
    $zipBytes = [System.IO.File]::ReadAllBytes($temporaryPath)
    $endOffset = $zipBytes.Length - 22
    if ($endOffset -lt 0 -or [BitConverter]::ToUInt32($zipBytes, $endOffset) -ne 0x06054B50) {
        throw 'Unexpected ZIP directory format.'
    }
    $entryCount = [BitConverter]::ToUInt16($zipBytes, $endOffset + 10)
    $centralOffset = [int][BitConverter]::ToUInt32($zipBytes, $endOffset + 16)
    for ($index = 0; $index -lt $entryCount; $index++) {
        if ([BitConverter]::ToUInt32($zipBytes, $centralOffset) -ne 0x02014B50) {
            throw 'Unexpected ZIP entry format.'
        }
        $zipBytes[$centralOffset + 5] = 3
        $nameLength = [BitConverter]::ToUInt16($zipBytes, $centralOffset + 28)
        $extraLength = [BitConverter]::ToUInt16($zipBytes, $centralOffset + 30)
        $commentLength = [BitConverter]::ToUInt16($zipBytes, $centralOffset + 32)
        $centralOffset += 46 + $nameLength + $extraLength + $commentLength
    }
    [System.IO.File]::WriteAllBytes($temporaryPath, $zipBytes)
    Move-Item -LiteralPath $temporaryPath -Destination $archivePath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}
Write-Host "Created $archivePath"
Write-Host 'This archive contains mod code and installation scripts. Each player must supply their own installed game.'
