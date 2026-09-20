$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testParent = Join-Path $repoRoot '.local\installer-tests'
$testRoot = Join-Path $testParent ([Guid]::NewGuid().ToString('N'))
$package = Join-Path $testRoot 'package [test]'
$game = Join-Path $testRoot 'game [test]'
$installed = Join-Path $game 'UltrapoolTogether'

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Expect-Failure([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert $failed $Message
}

try {
    New-Item -ItemType Directory -Path (Join-Path $package 'mod'), $game -Force | Out-Null
    foreach ($name in @('Install.ps1', 'Uninstall.ps1', 'Launch.cmd')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination (Join-Path $package $name)
    }
    foreach ($name in @('game.exe', 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll')) {
        Set-Content -LiteralPath (Join-Path $game $name) -Value "fixture for $name"
    }
    Set-Content -LiteralPath (Join-Path $package 'mod\main.gd') -Value 'extends Node'
    $originalHash = (Get-FileHash -LiteralPath (Join-Path $game 'game.exe')).Hash

    & (Join-Path $package 'Install.ps1') -GamePath $game -WhatIf
    Assert (-not (Test-Path -LiteralPath $installed)) 'Install -WhatIf wrote files.'

    & (Join-Path $package 'Install.ps1') -GamePath (Join-Path $game 'game.exe')
    $markerPath = Join-Path $installed 'ultrapool-together-install.json'
    $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    Assert ($marker.source_exe_sha256 -eq $originalHash) 'The source executable hash was not recorded.'
    $config = Get-Content -LiteralPath (Join-Path $installed 'override.cfg') -Raw
    Assert ($config.Contains('config/use_custom_user_dir=true')) 'Custom save directory is disabled.'
    Assert ($config.Contains((Join-Path $installed 'mod\main.gd').Replace('\', '/'))) 'Autoload path is incorrect.'
    Assert ((Get-Content -LiteralPath (Join-Path $installed 'steam_appid.txt') -Raw).Trim() -eq '4195110') 'Steam App ID is incorrect.'

    Set-Content -LiteralPath (Join-Path $installed 'my-notes.txt') -Value 'preserve this'
    Set-Content -LiteralPath (Join-Path $package 'mod\main.gd') -Value 'extends Node # updated'
    & (Join-Path $package 'Install.ps1') -GamePath $game
    Assert ((Get-Content -LiteralPath (Join-Path $installed 'mod\main.gd') -Raw).Contains('updated')) 'Updating did not copy the new mod.'
    Assert (Test-Path -LiteralPath (Join-Path $installed 'my-notes.txt')) 'Updating deleted an unowned file.'

    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $game } 'The original game directory was accepted as the destination.'
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $testRoot } 'A parent of the original game directory was accepted as the destination.'
    $unmarked = Join-Path $testRoot 'unmarked'
    New-Item -ItemType Directory -Path $unmarked | Out-Null
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $unmarked } 'An unmarked existing directory was accepted.'

    Set-Content -LiteralPath (Join-Path $package 'mod\collision.gd') -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $installed 'mod\collision.gd') -Value 'unowned'
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game } 'An unowned installed file was overwritten.'
    Assert ((Get-Content -LiteralPath (Join-Path $installed 'mod\collision.gd') -Raw).Trim() -eq 'unowned') 'The collision check changed a file.'

    & (Join-Path $package 'Uninstall.ps1') -Destination $installed -WhatIf
    Assert (Test-Path -LiteralPath (Join-Path $installed 'game.exe')) 'Uninstall -WhatIf removed files.'
    $validMarker = Get-Content -LiteralPath $markerPath -Raw
    $unsafeMarker = $validMarker | ConvertFrom-Json
    $unsafeMarker.files += '..\game.exe'
    $unsafeMarker | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath
    Expect-Failure { & (Join-Path $package 'Uninstall.ps1') -Destination $installed } 'Uninstall accepted a file outside its directory.'
    Assert (Test-Path -LiteralPath (Join-Path $installed 'game.exe')) 'An invalid uninstall partially removed installed files.'
    Set-Content -LiteralPath $markerPath -Value $validMarker

    & (Join-Path $package 'Uninstall.ps1') -Destination $installed
    Assert (-not (Test-Path -LiteralPath (Join-Path $installed 'game.exe'))) 'Uninstall left an owned file.'
    Assert (Test-Path -LiteralPath (Join-Path $installed 'my-notes.txt')) 'Uninstall deleted an unowned file.'
    Assert (Test-Path -LiteralPath (Join-Path $installed 'mod\collision.gd')) 'Uninstall deleted an unowned nested file.'
    Assert ((Get-FileHash -LiteralPath (Join-Path $game 'game.exe')).Hash -eq $originalHash) 'The original executable changed.'

    $customInstall = Join-Path $testRoot 'custom-destination'
    & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $customInstall
    & (Join-Path $package 'Uninstall.ps1') -Destination $customInstall
    Assert (-not (Test-Path -LiteralPath $customInstall)) 'An empty installation directory was not removed.'
    Write-Output 'Installer smoke tests passed: dry runs, installation, update, destination guards, unowned files, path traversal, and uninstall.'
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTestParent = [System.IO.Path]::GetFullPath($testParent).TrimEnd('\') + '\'
    if (-not $resolvedTestRoot.StartsWith($resolvedTestParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test cleanup path escaped the test workspace.'
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
