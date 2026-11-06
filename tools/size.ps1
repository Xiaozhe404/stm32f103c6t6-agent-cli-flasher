# size.ps1 - budget guard for a 32 KB / 10 KB part.
#
#   tools\size.ps1
#   tools\size.ps1 -Config Release -FlashLimitPct 85 -RamLimitPct 60
#
# Exit code 1 when the image exceeds a budget, so CI (or an agent) can treat
# "the build still fits" as a pass/fail fact instead of a feeling.

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Config = 'Debug',
    [int]$FlashLimitPct = 90,
    [int]$RamLimitPct = 70
)

. "$PSScriptRoot\env.ps1"

$flashSize = 32KB
$ramSize   = 10KB

$configDir = Get-ConfigDir $Config
$sizesFile = Join-Path $configDir 'firmware_sizes.txt'
if (-not (Test-Path -LiteralPath $sizesFile)) {
    Write-Fail "size report not found: $sizesFile"
    Write-Host 'Build first: tools\build.ps1' -ForegroundColor Yellow
    exit 1
}

$code = 0; $ro = 0; $rw = 0; $zi = 0
$found = $false
foreach ($line in Get-Content -LiteralPath $sizesFile) {
    # The first data row is the image itself; later rows are "(incl. padding)"
    # and "ROM Totals" (which always reports ZI = 0). Take the image row only.
    if ((-not $found) -and
        $line -match '^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+' -and
        $line -notmatch 'ROM Totals') {
        $code = [int]$matches[1]
        $ro   = [int]$matches[3]
        $rw   = [int]$matches[4]
        $zi   = [int]$matches[5]
        $found = $true
    }
}

if (($code + $ro + $rw + $zi) -eq 0) {
    Write-Fail "could not parse totals from $sizesFile"
    exit 1
}

$flashUsed = $code + $ro + $rw
$ramUsed   = $rw + $zi
$flashPct  = [math]::Round(100.0 * $flashUsed / $flashSize, 1)
$ramPct    = [math]::Round(100.0 * $ramUsed / $ramSize, 1)

Write-Host ''
Write-Host "--- memory budget ($Config) ---" -ForegroundColor Cyan
Write-Host ("  flash {0,7} / {1,7} B  ({2,5}%)" -f $flashUsed, $flashSize, $flashPct)
Write-Host ("  ram   {0,7} / {1,7} B  ({2,5}%)" -f $ramUsed, $ramSize, $ramPct)
Write-Host ("  code={0} rodata={1} rw={2} zi={3}" -f $code, $ro, $rw, $zi) -ForegroundColor DarkGray
Write-Host ''

$failed = $false
if ($flashPct -gt $FlashLimitPct) {
    Write-Fail "flash over budget: $flashPct% > $FlashLimitPct%"
    $failed = $true
}
if ($ramPct -gt $RamLimitPct) {
    Write-Fail "ram over budget: $ramPct% > $RamLimitPct%"
    $failed = $true
}

if ($failed) { exit 1 }
Write-Ok 'within budget'
exit 0
