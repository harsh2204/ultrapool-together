$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testParent = Join-Path $repoRoot '.local\installer-tests'
$testRoot = Join-Path $testParent ([Guid]::NewGuid().ToString('N'))
$package = Join-Path $testRoot 'package [test]'
$game = Join-Path $testRoot 'game [test]'
$installed = Join-Path $game 'UltrapoolTogether'
$userDataRoot = Join-Path $testRoot 'user data [test]'
$steamProfile = Join-Path $userDataRoot 'Godot\app_userdata\Ultrapool'
$modProfile = Join-Path $userDataRoot 'UltrapoolTogether'
$importMarkerName = 'ultrapool-together-progress-import.json'
$junctions = @()

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Expect-Failure([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert $failed $Message
}

function Write-SaveFixture([string]$Path, [string]$Tag) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value @(
        '[gd_resource type="Resource" script_class="SaveData" load_steps=2 format=3]',
        "; fixture: $Tag"
    )
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Message) {
    Assert ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected) $Message
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
    Write-SaveFixture (Join-Path $steamProfile 'save.tres') 'Steam progression'
    Write-SaveFixture (Join-Path $steamProfile 'save.bak.tres') 'older Steam recovery save'
    $steamHash = (Get-FileHash -LiteralPath (Join-Path $steamProfile 'save.tres')).Hash
    $steamBackupHash = (Get-FileHash -LiteralPath (Join-Path $steamProfile 'save.bak.tres')).Hash
    foreach ($name in @('run_data.tres', 'daily_data.tres')) {
        Set-Content -LiteralPath (Join-Path $steamProfile $name) -Value "Steam $name"
    }

    & (Join-Path $package 'Install.ps1') -GamePath $game -UserDataRoot $userDataRoot -WhatIf
    Assert (-not (Test-Path -LiteralPath $installed)) 'Install -WhatIf wrote files.'
    Assert (-not (Test-Path -LiteralPath $modProfile)) 'Install -WhatIf created a save directory.'

    & (Join-Path $package 'Install.ps1') -GamePath (Join-Path $game 'game.exe') -UserDataRoot $userDataRoot
    $markerPath = Join-Path $installed 'ultrapool-together-install.json'
    $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    Assert ($marker.source_exe_sha256 -eq $originalHash) 'The source executable hash was not recorded.'
    $config = Get-Content -LiteralPath (Join-Path $installed 'override.cfg') -Raw
    Assert ($config.Contains('config/use_custom_user_dir=true')) 'Custom save directory is disabled.'
    Assert ($config.Contains((Join-Path $installed 'mod\main.gd').Replace('\', '/'))) 'Autoload path is incorrect.'
    Assert ((Get-Content -LiteralPath (Join-Path $installed 'steam_appid.txt') -Raw).Trim() -eq '4195110') 'Steam App ID is incorrect.'
    foreach ($name in @('save.tres', 'save.bak.tres')) {
        Assert-Hash (Join-Path $modProfile $name) $steamHash 'Initial import did not seed both saves from Steam primary progress.'
    }
    Assert-Hash (Join-Path $steamProfile 'save.tres') $steamHash 'Import changed Steam primary progress.'
    Assert-Hash (Join-Path $steamProfile 'save.bak.tres') $steamBackupHash 'Import changed the Steam recovery save.'
    foreach ($name in @('run_data.tres', 'daily_data.tres')) {
        Assert (-not (Test-Path -LiteralPath (Join-Path $modProfile $name))) 'Import copied an active run or daily file.'
        Assert ((Get-Content -LiteralPath (Join-Path $steamProfile $name) -Raw).Trim() -eq "Steam $name") 'Import changed a Steam run or daily file.'
        Set-Content -LiteralPath (Join-Path $modProfile $name) -Value "mod $name"
    }
    $importMarkerPath = Join-Path $modProfile $importMarkerName
    $importMarker = Get-Content -LiteralPath $importMarkerPath -Raw | ConvertFrom-Json
    Assert ($importMarker.schema -eq 1 -and $importMarker.source_sha256 -eq $steamHash) 'The import record does not identify the copied progress.'
    $importMarkerHash = (Get-FileHash -LiteralPath $importMarkerPath).Hash
    Write-SaveFixture (Join-Path $modProfile 'save.tres') 'new mod progression'
    $modHash = (Get-FileHash -LiteralPath (Join-Path $modProfile 'save.tres')).Hash

    Set-Content -LiteralPath (Join-Path $installed 'my-notes.txt') -Value 'preserve this'
    Set-Content -LiteralPath (Join-Path $package 'mod\main.gd') -Value 'extends Node # updated'
    & (Join-Path $package 'Install.ps1') -GamePath $game -UserDataRoot $userDataRoot
    Assert ((Get-Content -LiteralPath (Join-Path $installed 'mod\main.gd') -Raw).Contains('updated')) 'Updating did not copy the new mod.'
    Assert (Test-Path -LiteralPath (Join-Path $installed 'my-notes.txt')) 'Updating deleted an unowned file.'
    Assert-Hash (Join-Path $modProfile 'save.tres') $modHash 'Updating replaced subsequent mod progression.'
    Assert-Hash (Join-Path $modProfile 'save.bak.tres') $steamHash 'Updating replaced the mod recovery save.'
    Assert-Hash $importMarkerPath $importMarkerHash 'Updating rewrote the one-time import record.'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $modProfile 'save-import-backups') -Directory).Count -eq 1) 'Updating imported progress again.'
    foreach ($name in @('run_data.tres', 'daily_data.tres')) {
        Assert ((Get-Content -LiteralPath (Join-Path $modProfile $name) -Raw).Trim() -eq "mod $name") 'Updating changed a mod run or daily file.'
    }

    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $game -UserDataRoot $userDataRoot } 'The original game directory was accepted as the destination.'
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $testRoot -UserDataRoot $userDataRoot } 'A parent of the original game directory was accepted as the destination.'
    $unmarked = Join-Path $testRoot 'unmarked'
    New-Item -ItemType Directory -Path $unmarked | Out-Null
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $unmarked -UserDataRoot $userDataRoot } 'An unmarked existing directory was accepted.'

    Set-Content -LiteralPath (Join-Path $package 'mod\collision.gd') -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $installed 'mod\collision.gd') -Value 'unowned'
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -UserDataRoot $userDataRoot } 'An unowned installed file was overwritten.'
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
    Assert-Hash (Join-Path $modProfile 'save.tres') $modHash 'Uninstall removed or changed mod progress.'
    Assert-Hash $importMarkerPath $importMarkerHash 'Uninstall removed the one-time import record.'

    $customInstall = Join-Path $testRoot 'custom-destination'
    & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $customInstall -UserDataRoot $userDataRoot
    & (Join-Path $package 'Uninstall.ps1') -Destination $customInstall
    Assert (-not (Test-Path -LiteralPath $customInstall)) 'An empty installation directory was not removed.'

    $existingUserData = Join-Path $testRoot 'existing progress'
    $existingSteam = Join-Path $existingUserData 'Godot\app_userdata\Ultrapool'
    $existingMod = Join-Path $existingUserData 'UltrapoolTogether'
    $existingInstall = Join-Path $testRoot 'existing-progress-install'
    Write-SaveFixture (Join-Path $existingSteam 'save.tres') 'Steam primary without backup'
    $existingSteamHash = (Get-FileHash -LiteralPath (Join-Path $existingSteam 'save.tres')).Hash
    $previousHashes = @{}
    foreach ($name in @('save.tres', 'save.bak.tres')) {
        Write-SaveFixture (Join-Path $existingMod $name) "previous mod $name"
        $previousHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $existingMod $name)).Hash
    }
    Set-Content -LiteralPath (Join-Path $existingMod 'run_data.tres') -Value 'existing mod run'
    & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $existingInstall -UserDataRoot $existingUserData -WhatIf
    Assert (-not (Test-Path -LiteralPath (Join-Path $existingMod 'save-import-backups'))) 'Dry run created a progress backup.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $existingMod $importMarkerName))) 'Dry run marked progress as imported.'
    foreach ($name in $previousHashes.Keys) {
        Assert-Hash (Join-Path $existingMod $name) $previousHashes[$name] 'Dry run changed existing mod progress.'
    }
    & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $existingInstall -UserDataRoot $existingUserData
    $existingRecord = Get-Content -LiteralPath (Join-Path $existingMod $importMarkerName) -Raw | ConvertFrom-Json
    $backupPath = $existingRecord.previous_mod_progress
    Assert ((Split-Path -Parent $backupPath) -eq (Join-Path $existingMod 'save-import-backups')) 'Progress backup escaped its profile.'
    Assert ((Split-Path -Leaf $backupPath) -match '^\d{8}T\d{6}Z-[a-f0-9]{32}$') 'Progress backup lacks a timestamp and unique identifier.'
    foreach ($name in $previousHashes.Keys) {
        Assert-Hash (Join-Path $backupPath $name) $previousHashes[$name] 'An existing mod save was not backed up byte for byte.'
        Assert-Hash (Join-Path $existingMod $name) $existingSteamHash 'Import without a source backup did not seed both mod saves.'
    }
    Assert ((Get-Content -LiteralPath (Join-Path $existingMod 'run_data.tres') -Raw).Trim() -eq 'existing mod run') 'Import overwrote the active mod run.'
    Assert-Hash (Join-Path $existingSteam 'save.tres') $existingSteamHash 'Import changed the source save.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $existingSteam 'save.bak.tres'))) 'Import created a backup in the Steam profile.'

    $missingUserData = Join-Path $testRoot 'missing progress'
    $missingInstall = Join-Path $testRoot 'missing-progress-install'
    $missingMod = Join-Path $missingUserData 'UltrapoolTogether'
    & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $missingInstall -UserDataRoot $missingUserData
    Assert (Test-Path -LiteralPath (Join-Path $missingInstall 'game.exe')) 'Missing Steam progress prevented installation.'
    Assert (-not (Test-Path -LiteralPath $missingMod)) 'Missing Steam progress created a profile or completion marker.'
    $lateSave = Join-Path $missingUserData 'Godot\app_userdata\Ultrapool\save.tres'
    Write-SaveFixture $lateSave 'Steam progress created after installation'
    & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $missingInstall -UserDataRoot $missingUserData
    Assert-Hash (Join-Path $missingMod 'save.tres') (Get-FileHash -LiteralPath $lateSave).Hash 'An earlier missing save permanently prevented import.'

    $invalidUserData = Join-Path $testRoot 'invalid progress'
    $invalidSave = Join-Path $invalidUserData 'Godot\app_userdata\Ultrapool\save.tres'
    $invalidMod = Join-Path $invalidUserData 'UltrapoolTogether'
    $invalidInstall = Join-Path $testRoot 'invalid-progress-install'
    Write-SaveFixture $invalidSave 'invalid header below'
    Set-Content -LiteralPath $invalidSave -Value 'not a SaveData resource'
    Write-SaveFixture (Join-Path $invalidMod 'save.tres') 'preserve after invalid import'
    $invalidModHash = (Get-FileHash -LiteralPath (Join-Path $invalidMod 'save.tres')).Hash
    Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $invalidInstall -UserDataRoot $invalidUserData } 'An invalid Steam save was accepted.'
    Assert (-not (Test-Path -LiteralPath $invalidInstall)) 'Invalid progress caused a partial installation.'
    Assert-Hash (Join-Path $invalidMod 'save.tres') $invalidModHash 'Invalid Steam progress replaced existing mod progress.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $invalidMod $importMarkerName))) 'Invalid progress was marked imported.'

    foreach ($linkedProfile in @('Godot\app_userdata\Ultrapool', 'UltrapoolTogether', 'UltrapoolTogether\save-import-backups')) {
        $junctionRoot = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
        $junctionTarget = Join-Path $junctionRoot 'target'
        $junctionUserData = Join-Path $junctionRoot 'user-data'
        $junctionInstall = Join-Path $junctionRoot 'install'
        $junctionPath = Join-Path $junctionUserData $linkedProfile
        Assert ([System.IO.Path]::GetFullPath($junctionTarget).StartsWith([System.IO.Path]::GetFullPath($testRoot) + '\', [System.StringComparison]::OrdinalIgnoreCase)) 'Junction target escaped the test workspace.'
        Write-SaveFixture (Join-Path $junctionTarget 'save.tres') 'junction target must remain unchanged'
        $junctionHash = (Get-FileHash -LiteralPath (Join-Path $junctionTarget 'save.tres')).Hash
        New-Item -ItemType Directory -Path (Split-Path -Parent $junctionPath) -Force | Out-Null
        New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
        $junctions += $junctionPath
        if ($linkedProfile -ne 'Godot\app_userdata\Ultrapool') {
            Write-SaveFixture (Join-Path $junctionUserData 'Godot\app_userdata\Ultrapool\save.tres') 'source for junction guard'
        }
        Expect-Failure { & (Join-Path $package 'Install.ps1') -GamePath $game -Destination $junctionInstall -UserDataRoot $junctionUserData } 'A profile junction was accepted.'
        Assert (-not (Test-Path -LiteralPath $junctionInstall)) 'A profile junction caused a partial installation.'
        Assert-Hash (Join-Path $junctionTarget 'save.tres') $junctionHash 'Import wrote through a profile junction.'
        Assert (@(Get-ChildItem -LiteralPath $junctionTarget -Force).Count -eq 1) 'Import added files through a profile junction.'
    }
    Write-Output 'Installer smoke tests passed: dry runs, one-time progress import, existing-save backups, missing/invalid saves, junction guards, updates, ownership, and uninstall.'
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTestParent = [System.IO.Path]::GetFullPath($testParent).TrimEnd('\') + '\'
    if (-not $resolvedTestRoot.StartsWith($resolvedTestParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test cleanup path escaped the test workspace.'
    }
    foreach ($junction in $junctions) {
        $resolvedJunction = [System.IO.Path]::GetFullPath($junction)
        if (-not $resolvedJunction.StartsWith($resolvedTestRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Junction cleanup path escaped the test workspace.'
        }
        $junctionTarget = [System.IO.Path]::GetFullPath(@((Get-Item -LiteralPath $resolvedJunction -Force).Target)[0])
        if (-not $junctionTarget.StartsWith($resolvedTestRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Junction cleanup target escaped the test workspace.'
        }
        [System.IO.Directory]::Delete($resolvedJunction)
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
