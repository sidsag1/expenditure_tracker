# Works around a Windows-only Flutter/Dart bug that breaks `flutter test`
# whenever any dependency ships a native-assets build hook (e.g. sqlite3,
# pulled in transitively by sqflite_common_ffi).
#
# Root cause: if the Flutter SDK lives under a path containing a space, the
# native-assets pre-build step's hooks_runner re-joins the executable path
# and argument list into a single string for cmd.exe without quoting the
# executable path. cmd.exe then truncates the command at the space:
#
#   'E:\External' is not recognized as an internal or external command,
#   operable program or batch file.
#
# The bug lives in a precompiled snapshot bundled with the Dart SDK
# (dartdev_aot.dart.snapshot), not in pub-cache source, so it can't be
# patched from a project. Moving the SDK is the real fix; this script is a
# non-destructive alternative that creates a directory junction at a
# space-free path and points PATH/FLUTTER_ROOT at it.
#
# The native-assets prebuild runs for the whole project, so this affects
# EVERY test file, not just the DB-backed ones -- without it `flutter test`
# fails before a single test executes.
#
# Usage:
#   .\scripts\setup-windows-flutter-sdk.ps1              # persist (run once, ever)
#   . .\scripts\setup-windows-flutter-sdk.ps1            # persist + fix this shell too
#   .\scripts\setup-windows-flutter-sdk.ps1 -SessionOnly # don't touch stored env vars
#   .\scripts\setup-windows-flutter-sdk.ps1 -Revert      # undo the stored env changes
#
# Persisting writes User-scope PATH/FLUTTER_ROOT, so new terminals, VS Code
# and CI runners on this machine pick it up with no per-session step. The
# real SDK stays on PATH behind the junction, so deleting the junction
# degrades back to today's behaviour instead of breaking `flutter`.
#
# Safe to re-run: junction creation and the PATH entry are both idempotent.

[CmdletBinding()]
param(
    [switch]$SessionOnly,
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'

$junctionPath = 'C:\flutter_sdk'
$junctionBin = "$junctionPath\bin"

function Get-UserPathEntries {
    $raw = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ([string]::IsNullOrEmpty($raw)) { return @() }
    return @($raw -split ';' | Where-Object { $_ -ne '' })
}

if ($Revert) {
    $entries = Get-UserPathEntries | Where-Object { $_ -ne $junctionBin }
    [Environment]::SetEnvironmentVariable('PATH', ($entries -join ';'), 'User')
    if ([Environment]::GetEnvironmentVariable('FLUTTER_ROOT', 'User') -eq $junctionPath) {
        [Environment]::SetEnvironmentVariable('FLUTTER_ROOT', $null, 'User')
    }
    Write-Output "Removed $junctionBin from the User PATH and cleared FLUTTER_ROOT."
    Write-Output "The junction at $junctionPath was left in place; remove it with: Remove-Item $junctionPath"
    return
}

$realFlutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $realFlutterCmd) {
    throw 'flutter is not on PATH. Add the real Flutter SDK to PATH first, then re-run this script.'
}
$sdkRoot = Split-Path (Split-Path $realFlutterCmd.Source)

# Already resolving through the junction (i.e. this has been run before):
# recover the real target so re-running is a no-op rather than a junction
# pointing at itself.
if ($sdkRoot -eq $junctionPath) {
    $existing = Get-Item $junctionPath -ErrorAction SilentlyContinue
    if ($existing -and $existing.Target) { $sdkRoot = @($existing.Target)[0] }
}

if ($sdkRoot -notmatch ' ') {
    Write-Output "Flutter SDK path '$sdkRoot' has no space; the junction workaround isn't needed."
    return
}

if (-not (Test-Path $junctionPath)) {
    New-Item -ItemType Junction -Path $junctionPath -Target $sdkRoot | Out-Null
    Write-Output "Created junction $junctionPath -> $sdkRoot"
} else {
    Write-Output "Junction already exists: $junctionPath"
}

if (-not $SessionOnly) {
    $entries = Get-UserPathEntries
    if ($entries -notcontains $junctionBin) {
        [Environment]::SetEnvironmentVariable('PATH', (@($junctionBin) + $entries) -join ';', 'User')
        Write-Output "Prepended $junctionBin to the User PATH (persistent)."
    } else {
        Write-Output "User PATH already contains $junctionBin."
    }
    [Environment]::SetEnvironmentVariable('FLUTTER_ROOT', $junctionPath, 'User')
    Write-Output "Set User FLUTTER_ROOT=$junctionPath (persistent)."
    Write-Output 'Open a new terminal for the change to take effect (already-running shells keep their old environment).'
}

# Also fix the current process when dot-sourced, so the shell that ran this
# doesn't have to be restarted.
$env:PATH = "$junctionBin;" + $env:PATH
$env:FLUTTER_ROOT = $junctionPath
