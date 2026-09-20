[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GamePath,
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$modId = 'UltrapoolTogether'
$manifestName = 'ultrapool-together-install.json'
$runtimeFiles = @('game.exe', 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll')

function Find-Ultrapool {
    $steamRoots = @(
        (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($steamRoot in $steamRoots) {
        $libraries = @($steamRoot)
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile -PathType Leaf) {
            $libraryText = Get-Content -LiteralPath $libraryFile -Raw
            $libraries += [regex]::Matches($libraryText, '"path"\s+"([^"]+)"') | ForEach-Object {
                $_.Groups[1].Value.Replace('\\', '\')
            }
        }

        foreach ($library in ($libraries | Select-Object -Unique)) {
            $appManifest = Join-Path $library 'steamapps\appmanifest_4195110.acf'
            if (-not (Test-Path -LiteralPath $appManifest -PathType Leaf)) { continue }
            $appText = Get-Content -LiteralPath $appManifest -Raw
            $installMatch = [regex]::Match($appText, '"installdir"\s+"([^"]+)"')
            if (-not $installMatch.Success) { continue }
            $candidate = Join-Path $library ('steamapps\common\' + $installMatch.Groups[1].Value)
            if (Test-Path -LiteralPath (Join-Path $candidate 'game.exe') -PathType Leaf) {
                return $candidate
            }
        }
    }
    throw 'Ultrapool was not found in Steam. Run Install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Ultrapool".'
}

function Get-FullDirectory([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-PlainPath([string]$Path) {
    $current = $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Symbolic links and junctions are not supported for installation paths: $current"
            }
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
}

if (-not $GamePath) { $GamePath = Find-Ultrapool }
if (Test-Path -LiteralPath $GamePath -PathType Leaf) {
    $GamePath = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($GamePath))
}
$gameRoot = Get-FullDirectory $GamePath
foreach ($name in $runtimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $gameRoot $name) -PathType Leaf)) {
        throw "Missing Ultrapool game file: $(Join-Path $gameRoot $name)"
    }
}

$sourceRoot = Get-FullDirectory $PSScriptRoot
$sourceMod = Join-Path $sourceRoot 'mod'
foreach ($name in @('mod\main.gd', 'Launch.cmd', 'Uninstall.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $name) -PathType Leaf)) {
        throw "The package file $name is missing. Extract the complete Ultrapool Together package before installing."
    }
}
if (-not $Destination) { $Destination = Join-Path $gameRoot $modId }
$installRoot = Get-FullDirectory $Destination
$comparison = [System.StringComparison]::OrdinalIgnoreCase
if ($installRoot -eq [System.IO.Path]::GetPathRoot($installRoot).TrimEnd('\', '/') -or
    $installRoot -eq $gameRoot -or $installRoot -eq $sourceRoot -or
    $gameRoot.StartsWith($installRoot + '\', $comparison) -or
    $sourceRoot.StartsWith($installRoot + '\', $comparison)) {
    throw 'The destination must be a dedicated mod directory, separate from the game and package roots.'
}
Assert-PlainPath $installRoot

$manifestPath = Join-Path $installRoot $manifestName
$previousFiles = @()
if (Test-Path -LiteralPath $installRoot) {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "The destination already exists without an Ultrapool Together installation marker: $installRoot"
    }
    $previous = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($previous.mod_id -ne $modId -or $previous.schema -ne 1 -or
        (Get-FullDirectory $previous.install_root) -ne $installRoot) {
        throw 'The existing installation marker does not match this destination.'
    }
    $previousFiles = @($previous.files)
}

$modFiles = @(Get-ChildItem -LiteralPath $sourceMod -File -Recurse)
$ownedFiles = @($runtimeFiles) + @('override.cfg', 'steam_appid.txt', 'Launch.cmd', 'Uninstall.ps1')
foreach ($file in $modFiles) {
    if ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "The mod package contains a symbolic link: $($file.FullName)"
    }
    $ownedFiles += $file.FullName.Substring($sourceRoot.Length + 1)
}
foreach ($relative in $ownedFiles) {
    $target = Join-Path $installRoot $relative
    Assert-PlainPath $target
    if ((Test-Path -LiteralPath $target) -and $relative -notin $previousFiles) {
        throw "Installation would replace an unowned file: $target"
    }
}

if (-not $PSCmdlet.ShouldProcess($installRoot, 'Install Ultrapool Together using local copies of the game files')) {
    return
}

$installedFiles = @($previousFiles + $ownedFiles | Select-Object -Unique)
$manifest = [ordered]@{
    schema = 1
    mod_id = $modId
    install_root = $installRoot
    game_root = $gameRoot
    installed_at = [DateTime]::UtcNow.ToString('o')
    state = 'installing'
    source_exe_sha256 = (Get-FileHash -LiteralPath (Join-Path $gameRoot 'game.exe') -Algorithm SHA256).Hash
    supported_game_version = '0.15.7'
    supported_steam_build = '25298901'
    files = $installedFiles
}
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
foreach ($name in $runtimeFiles) {
    Copy-Item -LiteralPath (Join-Path $gameRoot $name) -Destination (Join-Path $installRoot $name) -Force
}
foreach ($file in $modFiles) {
    $target = Join-Path $installRoot $file.FullName.Substring($sourceRoot.Length + 1)
    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'Launch.cmd') -Destination (Join-Path $installRoot 'Launch.cmd') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'Uninstall.ps1') -Destination (Join-Path $installRoot 'Uninstall.ps1') -Force

$autoloadPath = (Join-Path $installRoot 'mod\main.gd').Replace('\', '/')
$override = @"
[application]
config/name="Ultrapool Together"
config/use_custom_user_dir=true
config/custom_user_dir_name="UltrapoolTogether"

[autoload]
UltrapoolTogether="*$autoloadPath"
"@
[System.IO.File]::WriteAllText((Join-Path $installRoot 'override.cfg'), $override, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $installRoot 'steam_appid.txt'), "4195110`n", [System.Text.Encoding]::ASCII)
$manifest.state = 'installed'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Installed Ultrapool Together to $installRoot"
Write-Host "Launch it with: $(Join-Path $installRoot 'Launch.cmd')"
Write-Host 'Your original Steam game files are unchanged. Mod saves use a separate UltrapoolTogether user folder.'
