[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$OutputPath,
    [ValidateRange(30, 300)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
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
            $libraries += [regex]::Matches((Get-Content -LiteralPath $libraryFile -Raw), '"path"\s+"([^"]+)"') | ForEach-Object {
                $_.Groups[1].Value.Replace('\\', '\')
            }
        }
        foreach ($library in ($libraries | Select-Object -Unique)) {
            $manifest = Join-Path $library 'steamapps\appmanifest_4195110.acf'
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
            $install = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"installdir"\s+"([^"]+)"')
            if (-not $install.Success) { continue }
            $candidate = Join-Path $library ('steamapps\common\' + $install.Groups[1].Value)
            if (Test-Path -LiteralPath (Join-Path $candidate 'game.exe') -PathType Leaf) { return $candidate }
        }
    }
    throw 'Ultrapool was not found in Steam. Supply -GamePath with the installed game folder.'
}

function Get-ProgressHashes {
    $profileRoot = [Environment]::GetFolderPath('ApplicationData')
    $hashes = [ordered]@{}
    foreach ($profile in @('Godot\app_userdata\Ultrapool', 'UltrapoolTogether')) {
        $path = Join-Path $profileRoot $profile
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        foreach ($save in (Get-ChildItem -LiteralPath $path -Filter '*.tres' -File | Sort-Object Name)) {
            $hashes[$save.FullName] = (Get-FileHash -LiteralPath $save.FullName -Algorithm SHA256).Hash
        }
    }
    return $hashes
}

if (-not $GamePath) { $GamePath = Find-Ultrapool }
$gameRoot = [System.IO.Path]::GetFullPath($GamePath)
if (Test-Path -LiteralPath $gameRoot -PathType Leaf) { $gameRoot = Split-Path -Parent $gameRoot }
foreach ($name in $runtimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $gameRoot $name) -PathType Leaf)) {
        throw "Missing Ultrapool runtime file: $name"
    }
}
$fixtureFiles = @(
    'mod\main.gd', 'tests\render_bootstrap.gd', 'tests\render_talo.gd', 'tests\render_settings.gd',
    'tests\render_ui_fixtures.gd', 'tests\spectator_fixtures.gd', 'tests\round_flow_fixtures.gd', 'tests\render_probe.gd', 'tests\render_gallery.html',
    'tests\team_vote_probe.gd', 'tests\lobby_probe.gd', 'tests\router_probe.gd', 'tests\controller_probe.gd', 'tests\snapshot_probe.gd',
    'tests\multiplayer_balls_probe.gd', 'tests\bounty_probe.gd'
)
foreach ($name in $fixtureFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {
        throw "Missing $name. Run this harness from a complete source checkout."
    }
}

$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot ('.local\screenshots\' + $runId) }
$outputRoot = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $outputRoot) { throw 'OutputPath must be a new directory so earlier captures are preserved.' }
$runtimeRoot = Join-Path $PSScriptRoot '.local\screenshot-runtime'
$profileName = 'UltrapoolTogetherRenderTest-' + $runId
$mutex = [System.Threading.Mutex]::new($false, 'Local\UltrapoolTogetherScreenshots')
$locked = $false
$process = $null
$report = $null
$failure = $null

try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another screenshot harness is running.' }
    if (Get-Process -Name game -ErrorAction SilentlyContinue) {
        throw 'Close Ultrapool and Ultrapool Together before capturing screenshots.'
    }
    $saveHashes = Get-ProgressHashes
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $outputRoot | Out-Null
    $sourceHashes = [ordered]@{}
    foreach ($name in $runtimeFiles) {
        $source = Join-Path $gameRoot $name
        $target = Join-Path $runtimeRoot $name
        $sourceHashes[$name] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHashes[$name]) {
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
    $sourceRoot = $PSScriptRoot.Replace('\', '/')
    $override = @"
[application]
config/name="Ultrapool Together Render Test"
config/use_custom_user_dir=true
config/custom_user_dir_name="$profileName"
run/max_fps=30

[display]
window/size/window_width_override=1280
window/size/window_height_override=720

[steam]
initialization/initialize_on_startup=false

[autoload]
Log="*$sourceRoot/tests/render_bootstrap.gd"
Talo="*$sourceRoot/tests/render_talo.gd"
SettingsManager="*$sourceRoot/tests/render_settings.gd"
UltrapoolTogether="*$sourceRoot/mod/main.gd"
RenderProbe="*$sourceRoot/tests/render_probe.gd"
"@
    [System.IO.File]::WriteAllText((Join-Path $runtimeRoot 'override.cfg'), $override, [System.Text.UTF8Encoding]::new($false))
    '4195110' | Set-Content -LiteralPath (Join-Path $runtimeRoot 'steam_appid.txt') -Encoding ASCII
    $stdout = Join-Path $outputRoot 'stdout.log'
    $stderr = Join-Path $outputRoot 'stderr.log'
    $report = [ordered]@{
        started_at = [DateTime]::UtcNow.ToString('o')
        status = 'running'
        renderer = 'gl_compatibility'
        resolution = '1280x720'
        max_fps = 30
        timeout_seconds = $TimeoutSeconds
        isolated_profile = Join-Path ([Environment]::GetFolderPath('ApplicationData')) $profileName
        source_sha256 = $sourceHashes
        save_sha256_before = $saveHashes
        process_id = $null
        exit_code = $null
        timed_out = $false
        process_stopped = $false
        probe_passed = $false
        script_errors = @()
        saves_unchanged = $false
        game_files_unchanged = $false
    }
    $arguments = '--windowed --resolution 1280x720 --rendering-method gl_compatibility --max-fps 30 --disable-vsync -- --output "' + $outputRoot + '"'
    $process = Start-Process -FilePath (Join-Path $runtimeRoot 'game.exe') -WorkingDirectory $runtimeRoot -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $null = $process.Handle
    $report.process_id = $process.Id
    Write-Host "Capturing screenshots with one game process (PID $($process.Id))."
    Write-Host "Output: $outputRoot"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $process.WaitForExit(500)) {
        $report.script_errors = @(Get-Content -LiteralPath $stderr | Where-Object {
            $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|RENDER_PROBE_FAIL'
        } | ForEach-Object { $_.ToString() })
        if ($report.script_errors.Count -gt 0) {
            throw 'The render probe reported a script error. Inspect stderr.log in the output directory.'
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            $report.timed_out = $true
            throw "Capture exceeded its $TimeoutSeconds second watchdog."
        }
    }
    $process.WaitForExit()
    $report.exit_code = $process.ExitCode
    $log = @(Get-Content -LiteralPath $stdout, $stderr)
    $report.probe_passed = [bool]($log -match '^RENDER_PROBE_PASS\b')
    $report.script_errors = @($log | Where-Object { $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|RENDER_PROBE_FAIL' } | ForEach-Object { $_.ToString() })
    if ($process.ExitCode -ne 0 -or -not $report.probe_passed -or $report.script_errors.Count -gt 0) {
        throw 'The render probe failed. Inspect stdout.log and stderr.log in the output directory.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $outputRoot 'index.html') -PathType Leaf)) {
        throw 'The render probe did not produce its screenshot gallery.'
    }
} catch {
    $failure = $_
} finally {
    if ($null -ne $process) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
        if ($null -ne $report) { $report.process_stopped = $process.HasExited }
        $process.Dispose()
    }
    if ($null -ne $report) {
        $report.saves_unchanged = (Get-ProgressHashes | ConvertTo-Json -Compress) -eq ($saveHashes | ConvertTo-Json -Compress)
        $report.game_files_unchanged = $true
        foreach ($name in $runtimeFiles) {
            if ((Get-FileHash -LiteralPath (Join-Path $gameRoot $name) -Algorithm SHA256).Hash -ne $sourceHashes[$name]) {
                $report.game_files_unchanged = $false
            }
        }
        if (-not $report.saves_unchanged -or -not $report.game_files_unchanged) {
            $failure = 'A game file or normal save changed during capture. See runner.json.'
        }
        $report.status = if ($null -eq $failure) { 'passed' } else { 'failed' }
        $report.finished_at = [DateTime]::UtcNow.ToString('o')
        if ($null -ne $failure) { $report.error = [string]$failure }
        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputRoot 'runner.json') -Encoding UTF8
    }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

if ($null -ne $failure) { throw $failure }
Write-Host "Render checks passed. Open $(Join-Path $outputRoot 'index.html')"
