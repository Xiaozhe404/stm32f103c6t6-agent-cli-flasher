# flash.ps1 - program the target through ST-LINK, no Keil GUI involved.
#
#   tools\flash.ps1                  # flash build\Debug\firmware.hex
#   tools\flash.ps1 -Config Release
#   tools\flash.ps1 -File path\to.bin -Address 0x08000000
#   tools\flash.ps1 -Erase           # full chip erase before programming
#   tools\flash.ps1 -NoReset         # leave the core halted after download
#
# Exit code 0 means the programmer verified the image on the device.

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Config = 'Debug',
    [string]$File,
    [string]$Address = '0x08000000',
    [switch]$Erase,
    [switch]$NoReset,
    [switch]$Run,
    [switch]$UnderReset   # connect-under-reset; needs the NRST wire attached
)

. "$PSScriptRoot\env.ps1"

if (-not $script:ProgrammerCli) {
    Write-Fail 'STM32_Programmer_CLI.exe not found.'
    Write-Host 'Install STM32CubeProgrammer, or point STM32_PROGRAMMER_CLI at the executable.' -ForegroundColor Yellow
    exit 1
}

if (-not $File) {
    $configDir = Get-ConfigDir $Config
    $File = Join-Path $configDir 'firmware.hex'
}
if (-not (Test-Path -LiteralPath $File)) {
    Write-Fail "image not found: $File"
    Write-Host 'Build first: tools\build.ps1' -ForegroundColor Yellow
    exit 1
}

$isBinary = ([System.IO.Path]::GetExtension($File)).ToLower() -eq '.bin'

# Normal SWD connect only needs SWDIO/SWCLK/GND/3V3, which is what a typical
# Blue Pill + ST-LINK V2 hookup provides. Connect-under-reset additionally needs
# the NRST wire, hence opt-in.
$cliArgs = @('-c', 'port=SWD')
if ($UnderReset) { $cliArgs += 'mode=UR' }
if ($Erase) { $cliArgs += @('-e', 'all') }
if ($isBinary) { $cliArgs += @('-w', $File, $Address) } else { $cliArgs += @('-w', $File) }
$cliArgs += @('-v')
if (-not $NoReset) { $cliArgs += '-rst' }
if ($Run) { $cliArgs += '-run' }

Write-Step "Programming $File"
$output = & $script:ProgrammerCli @cliArgs 2>&1 | Out-String
Write-Host $output.TrimEnd()

$ok = ($output -match 'Download verified successfully') -or
      ($output -match 'File download complete') -or
      ($output -match 'Verification\s*:\s*OK')
$noError = -not ($output -match 'Error:|FAILED|No STM32 target found')

if ($LASTEXITCODE -eq 0 -and $ok -and $noError) {
    Write-Ok 'Target programmed and verified'
    exit 0
}

Write-Fail "Programming failed (exit $LASTEXITCODE)"
if ($output -match 'No debug probe detected') {
    Write-Host 'Hint: no ST-LINK found. Check the USB cable and run: STM32_Programmer_CLI.exe -l' -ForegroundColor Yellow
}
if ($output -match 'No STM32 target found') {
    Write-Host 'Hint: check SWD wiring (SWDIO/SWCLK/GND/3V3) and that the board is powered. Try -UnderReset.' -ForegroundColor Yellow
}
if ($output -match 'Error while attempting to connect|mode=UR') {
    Write-Host 'Hint: connect-under-reset needs the NRST wire; drop -UnderReset for a 4-wire hookup.' -ForegroundColor Yellow
}
exit 1
