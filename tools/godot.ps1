# Godot launcher shim. The editor binary is not on PATH, and the download
# folder is itself named ".exe", which makes the obvious path fail confusingly.
# Resolution order:
#   1. $env:GODOT_EXE           (explicit override)
#   2. the known Downloads path (console build - folder named .exe is correct)
#   3. Get-Command godot        (PATH, if it ever lands there)
#
# Usage:  powershell tools/godot.ps1 --headless --path . -s tools/check_cover_rules.gd
# All arguments are forwarded to Godot unchanged.

$tried = @()

$exe = $null
if ($env:GODOT_EXE) {
    if (Test-Path $env:GODOT_EXE) {
        $exe = $env:GODOT_EXE
    } else {
        $tried += "GODOT_EXE=$($env:GODOT_EXE) (set, but no file there)"
    }
} else {
    $tried += 'GODOT_EXE (not set)'
}

if (-not $exe) {
    $known = 'C:\Users\bhixe\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
    if (Test-Path $known) {
        $exe = $known
    } else {
        $tried += "$known (not found)"
    }
}

if (-not $exe) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) {
        $exe = $cmd.Source
    } else {
        $tried += "'godot' on PATH (not found)"
    }
}

if (-not $exe) {
    Write-Error ("tools/godot.ps1: no Godot binary found. Tried, in order:`n  " + ($tried -join "`n  ") + "`nSet `$env:GODOT_EXE to the console executable and retry.")
    exit 1
}

& $exe @args
exit $LASTEXITCODE
