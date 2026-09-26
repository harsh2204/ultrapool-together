[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GamePath,
    [string]$Destination,
    [string]$UserDataRoot = [Environment]::GetFolderPath('ApplicationData')
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

function Get-ProgressImport {
    $profileRoot = Get-FullDirectory $UserDataRoot
    $steamProfile = Join-Path $profileRoot 'Godot\app_userdata\Ultrapool'
    $modProfile = Join-Path $profileRoot 'UltrapoolTogether'
    $importMarker = Join-Path $modProfile 'ultrapool-together-progress-import.json'
    Assert-PlainPath $steamProfile
    Assert-PlainPath $modProfile
    Assert-PlainPath $importMarker
    if (Test-Path -LiteralPath $importMarker) { return $null }

    $sourceSave = Join-Path $steamProfile 'save.tres'
    if (-not (Test-Path -LiteralPath $sourceSave -PathType Leaf)) {
        Write-Host 'No Steam progression save found; existing mod progress is unchanged.'
        return $null
    }
    foreach ($name in @('save.tres', 'save.bak.tres')) {
        Assert-PlainPath (Join-Path $steamProfile $name)
        Assert-PlainPath (Join-Path $modProfile $name)
    }
    $saveHeader = Get-Content -LiteralPath $sourceSave -TotalCount 1
    if (-not $saveHeader -or $saveHeader -notmatch '^\[gd_resource\b' -or $saveHeader -notmatch 'script_class="SaveData"') {
        throw 'The Steam progression save is empty or unrecognized. Existing saves were not changed.'
    }
    $backupRoot = Join-Path $modProfile 'save-import-backups'
    Assert-PlainPath $backupRoot
    return @{
        source = $sourceSave
        profile = $modProfile
        marker = $importMarker
        backup_root = $backupRoot
    }
}

function Import-Progress($Plan) {
    if ($null -eq $Plan) { return }
    $importId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N')
    $backupPath = Join-Path $Plan.backup_root $importId
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    foreach ($name in @('save.tres', 'save.bak.tres')) {
        $existing = Join-Path $Plan.profile $name
        if (Test-Path -LiteralPath $existing -PathType Leaf) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $backupPath $name)
        }
    }
    $sourceHash = (Get-FileHash -LiteralPath $Plan.source -Algorithm SHA256).Hash
    # Seed both native recovery files from the same imported progress.
    foreach ($name in @('save.bak.tres', 'save.tres')) {
        $target = Join-Path $Plan.profile $name
        $staged = Join-Path $Plan.profile ($name + '.' + $importId + '.tmp')
        Copy-Item -LiteralPath $Plan.source -Destination $staged
        if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $sourceHash) {
            throw 'The source save changed during import. Close Ultrapool and rerun Install.cmd.'
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            [System.IO.File]::Replace($staged, $target, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [System.IO.File]::Move($staged, $target)
        }
    }
    $record = [ordered]@{
        schema = 1
        imported_at = [DateTime]::UtcNow.ToString('o')
        source = $Plan.source
        source_sha256 = $sourceHash
        previous_mod_progress = $backupPath
    }
    $record | ConvertTo-Json | Set-Content -LiteralPath $Plan.marker -Encoding UTF8
    Write-Host 'Imported Steam progression once. Future mod updates will preserve this profile.'
    Write-Host "Previous mod progression backup: $backupPath"
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

$runningGames = @(Get-Process -Name game -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq (Join-Path $gameRoot 'game.exe') -or $_.Path -eq (Join-Path $installRoot 'game.exe')
})
if ($runningGames.Count -gt 0) {
    throw 'Close Ultrapool and Ultrapool Together before installing or importing progress.'
}
$progressImport = Get-ProgressImport

$manifestPath = Join-Path $installRoot $manifestName
Assert-PlainPath $manifestPath
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
    if ($previous.files -isnot [array]) {
        throw 'The installation marker contains an invalid owned-file list.'
    }
    $previousFiles = @($previous.files)
    $validatedPreviousFiles = @()
    # Validate every old path before any write; retired files will be deleted.
    foreach ($relative in $previousFiles) {
        if ($relative -isnot [string] -or [string]::IsNullOrWhiteSpace($relative) -or
            [System.IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or
            $relative -match '(^|[\\/])\.{1,2}([\\/]|$)' -or
            $relative -match '[. ]([\\/]|$)' -or $relative -eq $manifestName) {
            throw 'The installation marker contains an invalid owned file path.'
        }
        $target = [System.IO.Path]::GetFullPath((Join-Path $installRoot $relative))
        if (-not $target.StartsWith($installRoot + '\', $comparison)) {
            throw "The installation marker contains a path outside the mod directory: $relative"
        }
        Assert-PlainPath $target
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "An expected installed file is now a directory; leaving it unchanged: $target"
        }
        $validatedPreviousFiles += $target.Substring($installRoot.Length + 1)
    }
    $previousFiles = @($validatedPreviousFiles | Select-Object -Unique)
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

$installAction = 'Install Ultrapool Together using local copies of the game files'
if ($null -ne $progressImport) { $installAction += ' and import Steam progression once with a backup of existing mod progress' }
if (-not $PSCmdlet.ShouldProcess($installRoot, $installAction)) {
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
Import-Progress $progressImport
# Retain the union in the in-progress manifest until cleanup succeeds, so a
# partial update can be retried or uninstalled without forgetting owned files.
foreach ($relative in $previousFiles) {
    if ($relative -in $ownedFiles) { continue }
    $target = Join-Path $installRoot $relative
    Assert-PlainPath $target
    if (Test-Path -LiteralPath $target -PathType Container) {
        throw "An expected installed file is now a directory; leaving it unchanged: $target"
    }
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}
$manifest.files = @($ownedFiles | Select-Object -Unique)
$manifest.state = 'installed'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Installed Ultrapool Together to $installRoot"
Write-Host "Launch it with: $(Join-Path $installRoot 'Launch.cmd')"
Write-Host 'Your original Steam game and solo runs are unchanged. Mod saves use a separate UltrapoolTogether user folder.'
