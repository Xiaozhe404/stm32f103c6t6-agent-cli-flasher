# verify.ps1 - the feedback loop that makes AI changes trustworthy.
#
#   tools\verify.ps1                     # build -> flash -> observe -> assert
#   tools\verify.ps1 -NoFlash            # only prove it compiles/links
#   tools\verify.ps1 -Port COM5 -Seconds 15
#
# Exit code 0 means: the image built, the device accepted it, and the expected
# runtime markers showed up on the UART. This is the command an agent should run
# after touching firmware code and before claiming the task is done.

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Config = 'Debug',
    [string]$Port,
    [int]$Seconds = 20,
    [string[]]$Expect = @(),
    [switch]$NoFlash,
    [switch]$NoBuild
)

. "$PSScriptRoot\env.ps1"

$script:results = @()

function Add-Result {
    param([string]$Step, [bool]$Ok, [string]$Detail)
    $script:results += [pscustomobject]@{ Step = $Step; Result = $Ok; Detail = $Detail }
}

function Show-Summary {
    Write-Host ''
    Write-Host '--- verify summary ---' -ForegroundColor Cyan
    foreach ($r in $script:results) {
        $label = 'FAIL'
        $color = 'Red'
        if ($r.Result) { $label = 'PASS'; $color = 'Green' }
        Write-Host ("  {0,-5} {1,-8} {2}" -f $label, $r.Step, $r.Detail) -ForegroundColor $color
    }
    Write-Host ''
}

if (-not $Expect -or $Expect.Count -eq 0) {
    $Expect = @('\[BOOT\] board=', '\[BOOT\] ready', '\[HB\]')
}

if ($NoBuild) {
    Add-Result 'build' $true 'skipped'
}
else {
    Write-Step 'Step 1/3  build'
    & (Join-Path $PSScriptRoot 'build.ps1') -Config $Config
    $rc = $LASTEXITCODE
    Add-Result 'build' ($rc -eq 0) "exit $rc"
    if ($rc -ne 0) {
        Show-Summary
        exit 1
    }
}

if ($NoFlash) {
    Add-Result 'flash' $true 'skipped'
    Add-Result 'observe' $true 'skipped'
    Show-Summary
    exit 0
}

Write-Step 'Step 2/3  flash'
& (Join-Path $PSScriptRoot 'flash.ps1') -Config $Config
$flashRc = $LASTEXITCODE
Add-Result 'flash' ($flashRc -eq 0) "exit $flashRc"
if ($flashRc -ne 0) {
    Add-Result 'observe' $false 'not attempted'
    Show-Summary
    exit 1
}

Write-Step 'Step 3/3  observe'
$monitorArgs = @{
    Seconds = $Seconds
    Expect  = $Expect
    Log     = "logs/verify-$Config.log"
}
if ($Port) { $monitorArgs['Port'] = $Port }
& (Join-Path $PSScriptRoot 'monitor.ps1') @monitorArgs
$monitorRc = $LASTEXITCODE
Add-Result 'observe' ($monitorRc -eq 0) "exit $monitorRc"

$allOk = $true
foreach ($r in $script:results) { if (-not $r.Result) { $allOk = $false } }

Show-Summary
if ($allOk) { exit 0 } else { exit 1 }
