[CmdletBinding()]
param(
    [string]$GamePath,
    [ValidateRange(1, 30)]
    [int]$GuestDelaySeconds = 3
)

$ErrorActionPreference = 'Stop'
$runtimeFiles = @('game.exe', 'libgodotsteam.windows.template_release.x86_64.dll', 'steam_api64.dll')
$roles = @('host', 'guest')

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

if (-not $GamePath) { $GamePath = Find-Ultrapool }
$gameRoot = [System.IO.Path]::GetFullPath($GamePath)
if (Test-Path -LiteralPath $gameRoot -PathType Leaf) { $gameRoot = Split-Path -Parent $gameRoot }
foreach ($name in $runtimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $gameRoot $name) -PathType Leaf)) {
        throw "Missing Ultrapool runtime file: $name"
    }
}
foreach ($name in @('mod\main.gd', 'tests\local_session_probe.gd')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {
        throw "Missing $name. Run this harness from a complete source checkout."
    }
}

if (Get-Process -Name game -ErrorAction SilentlyContinue) {
    throw 'Close Ultrapool and Ultrapool Together before starting the local session harness.'
}

$mutex = [System.Threading.Mutex]::new($false, 'Local\UltrapoolTogetherLocalSession')
$locked = $false
$processes = @()
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another local session harness is already running.' }

    $sessionRoot = Join-Path $PSScriptRoot '.local\local-session'
    $sourceRoot = $PSScriptRoot.Replace('\', '/')
    New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null

    foreach ($role in $roles) {
        $runtimeRoot = Join-Path $sessionRoot $role
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
        foreach ($name in $runtimeFiles) {
            $source = Join-Path $gameRoot $name
            $target = Join-Path $runtimeRoot $name
            $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHash) {
                Copy-Item -LiteralPath $source -Destination $target -Force
            }
        }
        $profileName = "UltrapoolTogetherLocalSession$role"
        $override = @"
[application]
config/name="Ultrapool Together Local Session ($role)"
config/use_custom_user_dir=true
config/custom_user_dir_name="$profileName"
run/max_fps=60

[display]
window/size/window_width_override=1280
window/size/window_height_override=720

[steam]
initialization/initialize_on_startup=false

[autoload]
UltrapoolTogether="*$sourceRoot/mod/main.gd"
LocalSessionProbe="*$sourceRoot/tests/local_session_probe.gd"
"@
        [System.IO.File]::WriteAllText((Join-Path $runtimeRoot 'override.cfg'), $override, [System.Text.UTF8Encoding]::new($false))
        '4195110' | Set-Content -LiteralPath (Join-Path $runtimeRoot 'steam_appid.txt') -Encoding ASCII
    }

    $commonArgs = '--windowed --resolution 1280x720 --rendering-method gl_compatibility --disable-vsync --'
    $hostRuntime = Join-Path $sessionRoot 'host'
    $guestRuntime = Join-Path $sessionRoot 'guest'
    $hostProcess = Start-Process -FilePath (Join-Path $hostRuntime 'game.exe') -WorkingDirectory $hostRuntime -ArgumentList ($commonArgs + ' --host') -PassThru
    $null = $hostProcess.Handle
    $processes += $hostProcess
    Write-Host "Started local session host (PID $($hostProcess.Id))."
    Write-Host "Waiting $GuestDelaySeconds second(s) before starting guest..."
    Start-Sleep -Seconds $GuestDelaySeconds
    if ($hostProcess.HasExited) {
        throw "Host process exited early with code $($hostProcess.ExitCode). Check the host window or AppData\UltrapoolTogetherLocalSessionhost."
    }
    $guestProcess = Start-Process -FilePath (Join-Path $guestRuntime 'game.exe') -WorkingDirectory $guestRuntime -ArgumentList ($commonArgs + ' --guest') -PassThru
    $null = $guestProcess.Handle
    $processes += $guestProcess
    Write-Host "Started local session guest (PID $($guestProcess.Id))."
    Write-Host ""
    Write-Host "Two windowed processes are running over LAN loopback (UDP 24817)."
    Write-Host "Isolated saves: UltrapoolTogetherLocalSessionhost / UltrapoolTogetherLocalSessionguest"
    Write-Host "Runtimes: $sessionRoot\host and $sessionRoot\guest"
    Write-Host "Close both game windows when finished. This script does not stop them."
} catch {
    foreach ($process in $processes) {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    throw
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}