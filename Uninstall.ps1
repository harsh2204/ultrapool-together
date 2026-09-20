[CmdletBinding(SupportsShouldProcess)]
param([string]$Destination = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$installRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
$manifestPath = Join-Path $installRoot 'ultrapool-together-install.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "No Ultrapool Together installation marker was found at $installRoot. Pass -Destination with the installed mod directory."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$recordedRoot = [System.IO.Path]::GetFullPath($manifest.install_root).TrimEnd('\', '/')
$gameRoot = [System.IO.Path]::GetFullPath($manifest.game_root).TrimEnd('\', '/')
if ($manifest.mod_id -ne 'UltrapoolTogether' -or $manifest.schema -ne 1 -or
    $recordedRoot -ne $installRoot -or $installRoot -eq $gameRoot -or
    $gameRoot.StartsWith($installRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $installRoot -eq [System.IO.Path]::GetPathRoot($installRoot).TrimEnd('\', '/')) {
    throw 'The installation marker is invalid or points at the original game directory.'
}

function Assert-PlainPath([string]$Path) {
    $current = $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Refusing to uninstall through a symbolic link or junction: $current"
            }
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
}

Assert-PlainPath $installRoot
$targets = @()
$directories = @($installRoot)
foreach ($relative in @($manifest.files)) {
    if ([string]::IsNullOrWhiteSpace($relative) -or [System.IO.Path]::IsPathRooted($relative)) {
        throw 'The installation marker contains an invalid file path.'
    }
    $target = [System.IO.Path]::GetFullPath((Join-Path $installRoot $relative))
    if (-not $target.StartsWith($installRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The installation marker contains a path outside the mod directory: $relative"
    }
    Assert-PlainPath $target
    if (Test-Path -LiteralPath $target -PathType Container) {
        throw "An expected installed file is now a directory; leaving it unchanged: $target"
    }
    $targets += $target
    $parent = [System.IO.Path]::GetDirectoryName($target)
    while ($parent -and $parent -ne $installRoot) {
        $directories += $parent
        $parent = [System.IO.Path]::GetDirectoryName($parent)
    }
}

if (-not $PSCmdlet.ShouldProcess($installRoot, 'Remove only files recorded by the Ultrapool Together installer')) {
    return
}
foreach ($target in ($targets | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}
Remove-Item -LiteralPath $manifestPath -Force
foreach ($directory in ($directories | Select-Object -Unique | Sort-Object Length -Descending)) {
    if ((Test-Path -LiteralPath $directory -PathType Container) -and
        -not (Get-ChildItem -LiteralPath $directory -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $directory -Force
    }
}
Write-Host 'Ultrapool Together was removed. The original game and all user saves are unchanged.'
if (Test-Path -LiteralPath $installRoot) {
    Write-Host "Files not owned by this installer were preserved at $installRoot"
}
