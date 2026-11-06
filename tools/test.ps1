# test.ps1 - host-side unit tests for hardware-free logic.
#
#   tools\test.ps1
#
# Compiles tests/*.c together with the portable modules they cover using the
# host GCC, then runs them. Anything that talks to a peripheral cannot live
# here; that is what tools\verify.ps1 (build + flash + UART) is for.

[CmdletBinding()]
param(
    [switch]$ShowCommand
)

. "$PSScriptRoot\env.ps1"

if (-not $script:HostGcc) {
    Write-Fail 'host gcc not found. Install MinGW-w64 or add gcc to PATH.'
    exit 1
}

$hostDir = Join-Path $script:BuildDir 'host'
if (-not (Test-Path -LiteralPath $hostDir)) {
    New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
}

$tests = Get-ChildItem (Join-Path $script:RepoRoot 'tests') -Filter '*.c' |
         Select-Object -ExpandProperty FullName
if (-not $tests -or $tests.Count -eq 0) {
    Write-Warn 'No tests/*.c found.'
    exit 0
}

$exe = Join-Path $hostDir 'unit_tests.exe'
$includeApp = Join-Path $script:RepoRoot 'App\Include'
$includeTests = Join-Path $script:RepoRoot 'tests'

Write-Step "Compiling $($tests.Count) test file(s) with $script:HostGcc"
$compileArgs = @(
    '-std=c99', '-Wall', '-Wextra', '-Werror', '-O1', '-g',
    "-I$includeApp", "-I$includeTests",
    (Join-Path $script:RepoRoot 'App\Src\ringbuffer.c')
) + $tests + @('-o', $exe)

if ($ShowCommand) { Write-Host "$script:HostGcc $($compileArgs -join ' ')" -ForegroundColor DarkGray }
& $script:HostGcc @compileArgs
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'host build failed'
    exit 1
}

Write-Step 'Running unit tests'
& $exe
$rc = $LASTEXITCODE
if ($rc -eq 0) { Write-Ok 'unit tests passed' } else { Write-Fail "unit tests failed (exit $rc)" }
exit $rc
