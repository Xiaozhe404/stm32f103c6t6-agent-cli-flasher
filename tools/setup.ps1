# setup.ps1 - fetch the firmware package and verify the toolchain.
#
# Run once after cloning:
#   powershell -ExecutionPolicy Bypass -File tools/setup.ps1
#
# What it does:
#   1. Verifies armclang/armlink from the local MDK install.
#   2. Downloads STM32CubeF1 (CMSIS + HAL) into external/, because the CubeF1
#      repo keeps the HAL in git submodules that a plain tarball does not carry.
#   3. Prints the next command to run.
#
# Everything it downloads is git-ignored; nothing is written outside the repo.

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipDownload
)

. "$PSScriptRoot\env.ps1"

$cubeRoot = Join-Path $script:RepoRoot 'external\cubeF1\STM32CubeF1-master'
$marker   = Join-Path $cubeRoot 'Drivers\CMSIS\Device\ST\STM32F1xx\Include\stm32f1xx.h'
$halMarker = Join-Path $cubeRoot 'Drivers\STM32F1xx_HAL_Driver\Src\stm32f1xx_hal_uart.c'

Write-Step 'Checking Arm Compiler 6 (armclang/armlink)'
if (-not $script:ArmClangBin) {
    Write-Fail 'armclang not found. Install Keil MDK 5 (Arm Compiler 6) or set ARMCLANG_ROOT.'
    exit 1
}
$armlink = Join-Path $script:ArmClangBin 'armlink.exe'
if (-not (Test-Path -LiteralPath $armlink)) {
    Write-Fail "armlink.exe missing in $script:ArmClangBin"
    exit 1
}
Write-Ok $script:ArmClangBin

Write-Step 'Checking CMake and Ninja'
if (-not $script:CmakeExe) { Write-Fail 'cmake not found.'; exit 1 }
Write-Ok "cmake  $script:CmakeExe"
if (-not $script:NinjaExe) { Write-Warn 'ninja not found; CMake will fall back to another generator.' }
else { Write-Ok "ninja  $script:NinjaExe" }

if ($SkipDownload) {
    Write-Warn 'SkipDownload: firmware package not touched.'
} elseif ((Test-Path -LiteralPath $marker) -and (Test-Path -LiteralPath $halMarker) -and (-not $Force)) {
    Write-Ok 'STM32CubeF1 already present, skipping download.'
} else {
    Write-Step 'Downloading STM32CubeF1 (HAL + CMSIS)'
    $external = Join-Path $script:RepoRoot 'external'
    New-Item -ItemType Directory -Force -Path $external | Out-Null

    $jobs = @(
        @{ Url = 'https://codeload.github.com/STMicroelectronics/STM32CubeF1/tar.gz/refs/heads/master'; File = 'cubeF1.tar.gz' },
        @{ Url = 'https://codeload.github.com/STMicroelectronics/stm32f1xx_hal_driver/tar.gz/refs/heads/master'; File = 'hal.tar.gz' },
        @{ Url = 'https://codeload.github.com/STMicroelectronics/cmsis_device_f1/tar.gz/refs/heads/master'; File = 'cmsis.tar.gz' }
    )

    foreach ($job in $jobs) {
        $target = Join-Path $external $job.File
        if ((Test-Path -LiteralPath $target) -and (-not $Force)) {
            Write-Ok "$($job.File) cached"
            continue
        }
        Write-Step "GET $($job.Url)"
        & curl.exe -sS -L --max-time 600 -o $target $job.Url
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "download failed ($LASTEXITCODE). Check network access to codeload.github.com."
            exit 1
        }
    }

    Write-Step 'Extracting'
    $cubeTmp = Join-Path $external '_cube'
    if (Test-Path -LiteralPath $cubeTmp) { Remove-Item $cubeTmp -Recurse -Force }
    if (Test-Path -LiteralPath (Join-Path $external 'cubeF1')) { Remove-Item (Join-Path $external 'cubeF1') -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $cubeTmp | Out-Null
    tar -xzf (Join-Path $external 'cubeF1.tar.gz') -C $cubeTmp
    $cubeSrc = Get-ChildItem $cubeTmp -Directory | Select-Object -First 1
    $cubeDir = Join-Path $external 'cubeF1'
    New-Item -ItemType Directory -Force -Path $cubeDir | Out-Null
    Move-Item $cubeSrc.FullName (Join-Path $cubeDir 'STM32CubeF1-master')

    # CubeF1 references the HAL and CMSIS device as git submodules (empty dirs
    # in a tarball), so graft the two repositories in their place.
    $subTmp = Join-Path $external '_sub'
    if (Test-Path -LiteralPath $subTmp) { Remove-Item $subTmp -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $subTmp | Out-Null

    tar -xzf (Join-Path $external 'hal.tar.gz') -C $subTmp
    $halSrc = Get-ChildItem $subTmp -Directory | Select-Object -First 1
    $halDst = Join-Path $cubeRoot 'Drivers\STM32F1xx_HAL_Driver'
    if (Test-Path -LiteralPath $halDst) { Remove-Item $halDst -Recurse -Force }
    Move-Item $halSrc.FullName $halDst

    tar -xzf (Join-Path $external 'cmsis.tar.gz') -C $subTmp
    $cmsisSrc = Get-ChildItem $subTmp -Directory | Select-Object -First 1
    $cmsisDst = Join-Path $cubeRoot 'Drivers\CMSIS\Device\ST\STM32F1xx'
    if (Test-Path -LiteralPath $cmsisDst) { Remove-Item $cmsisDst -Recurse -Force }
    Move-Item $cmsisSrc.FullName $cmsisDst

    Remove-Item $cubeTmp, $subTmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $marker)) {
    Write-Fail "CMSIS device header still missing: $marker"
    exit 1
}
if (-not (Test-Path -LiteralPath $halMarker)) {
    Write-Fail "HAL sources still missing: $halMarker"
    exit 1
}
Write-Ok 'STM32CubeF1 ready'

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  powershell -ExecutionPolicy Bypass -File tools/build.ps1'
