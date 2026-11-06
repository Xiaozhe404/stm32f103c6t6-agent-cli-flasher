# setup.ps1 - fetch the firmware package and verify the toolchain.
#
# Run once after cloning:
#   powershell -ExecutionPolicy Bypass -File tools/setup.ps1
#
# What it does:
#   1. Verifies armclang/armlink from the local MDK install.
#   2. Installs the Keil STM32F1xx device pack if the MDK-ARM track needs it.
#   3. Downloads STM32CubeF1 (CMSIS + HAL) into external/, because the CubeF1
#      repo keeps the HAL in git submodules that a plain tarball does not carry.
#   4. Prints the next command to run.
#
# Everything it downloads is git-ignored. The only thing written outside the
# repo is the device pack, which goes into the Keil PACK directory.

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipDownload
)

. "$PSScriptRoot\env.ps1"

$cubeRoot = Join-Path $script:RepoRoot 'external\cubeF1\STM32CubeF1'
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

# --- Keil device pack: needed by the MDK-ARM track only --------------------
# tools/build.ps1 (CMake) does not need it; tools/build.ps1 -Keil does, because
# UV4 resolves the device, its memory map and the flash algorithm from the pack.
Write-Step 'Checking Keil device pack (Keil.STM32F1xx_DFP)'
$dfpVersion  = '2.4.1'
$packRoot   = $env:KEIL_PACK_ROOT
if (-not $packRoot -and $script:ArmClangRoot) {
    $packRoot = Join-Path (Split-Path -Parent $script:ArmClangRoot) 'PACK'
}
$dfpDir  = $null
$dfpPdsc = $null
if ($packRoot) {
    $dfpDir  = Join-Path $packRoot "Keil\STM32F1xx_DFP\$dfpVersion"
    $dfpPdsc = Join-Path $dfpDir 'Keil.STM32F1xx_DFP.pdsc'
}

if ($dfpPdsc -and (Test-Path -LiteralPath $dfpPdsc) -and (-not $Force)) {
    Write-Ok "STM32F1 device pack $dfpVersion"
}
elseif ($SkipDownload) {
    Write-Warn 'SkipDownload: device pack not installed; tools/build.ps1 -Keil will fail.'
}
elseif (-not $packRoot) {
    Write-Warn 'Keil PACK root not found; set KEIL_PACK_ROOT to install the device pack.'
}
else {
    $packFile = Join-Path $script:RepoRoot "external\packs\Keil.STM32F1xx_DFP.$dfpVersion.pack"
    if (-not (Test-Path -LiteralPath $packFile)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $packFile) | Out-Null
        $url = "https://www.keil.com/pack/Keil.STM32F1xx_DFP.$dfpVersion.pack"
        Write-Step "GET $url"
        & curl.exe -sS -L --max-time 900 -o $packFile $url
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "device pack download failed ($LASTEXITCODE). Check network access to keil.com."
            exit 1
        }
    }
    Write-Step "Installing into $dfpDir"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $dfpDir) { Remove-Item -LiteralPath $dfpDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dfpDir | Out-Null
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($packFile, $dfpDir)
    }
    catch {
        Write-Fail "could not extract the pack into $dfpDir. Run this script as administrator."
        exit 1
    }
    if (-not (Test-Path -LiteralPath $dfpPdsc)) {
        Write-Fail "pack installed but $dfpPdsc is missing."
        exit 1
    }
    Write-Ok "STM32F1 device pack $dfpVersion"
}

if ($SkipDownload) {
    Write-Warn 'SkipDownload: firmware package not touched.'
} elseif ((Test-Path -LiteralPath $marker) -and (Test-Path -LiteralPath $halMarker) -and (-not $Force)) {
    Write-Ok 'STM32CubeF1 already present, skipping download.'
} else {
    # Pinned to release tags, each with a checksum. Tracking a branch would let
    # the same repository produce a different firmware tomorrow, which would
    # quietly invalidate every "the two tracks are byte-identical" claim.
    $packages = @(
        @{ Name = 'STM32CubeF1'
           Tag  = 'v1.8.7'
           Sha  = '3f1b2948ba485671a81b0f25132b77c09bf5209146d4d731ef0cf70ecd74aab3'
           Url  = 'https://codeload.github.com/STMicroelectronics/STM32CubeF1/tar.gz/refs/tags/v1.8.7' },
        @{ Name = 'stm32f1xx_hal_driver'
           Tag  = 'v1.1.10'
           Sha  = 'dac985f582b763e8a54aee8329fc7cc86e5690d4ed97f48f7bb7a89eb23f94ca'
           Url  = 'https://codeload.github.com/STMicroelectronics/stm32f1xx_hal_driver/tar.gz/refs/tags/v1.1.10' },
        @{ Name = 'cmsis_device_f1'
           Tag  = 'v4.3.5'
           Sha  = '2994ffe58af1f819928f11840359565e0293e91dfb840661da77c2e02de24ca3'
           Url  = 'https://codeload.github.com/STMicroelectronics/cmsis_device_f1/tar.gz/refs/tags/v4.3.5' }
    )

    $external  = Join-Path $script:RepoRoot 'external'
    $downloads = Join-Path $external 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null

    foreach ($pkg in $packages) {
        $file = Join-Path $downloads "$($pkg.Name)-$($pkg.Tag).tar.gz"
        $have = Test-Path -LiteralPath $file
        if ($have) {
            $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
            if ($actual -ne $pkg.Sha) {
                Write-Warn "$($pkg.Name): cached archive does not match the pinned checksum, fetching again"
                $have = $false
            }
        }
        if (-not $have) {
            Write-Step "GET $($pkg.Name) $($pkg.Tag)"
            & curl.exe -sS -L --max-time 900 -o $file $pkg.Url
            if ($LASTEXITCODE -ne 0) {
                Write-Fail "download failed ($LASTEXITCODE). Check network access to codeload.github.com."
                exit 1
            }
            $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
        }
        if ($actual -ne $pkg.Sha) {
            Write-Fail "$($pkg.Name): SHA256 mismatch. expected $($pkg.Sha), got $actual"
            exit 1
        }
        Write-Ok "$($pkg.Name) $($pkg.Tag) checksum verified"
    }

    Write-Step 'Extracting'
    $stage = Join-Path $external '_stage'
    if (Test-Path -LiteralPath $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    $cubeF1Dir = Join-Path $external 'cubeF1'
    if (Test-Path -LiteralPath $cubeF1Dir) { Remove-Item $cubeF1Dir -Recurse -Force }

    function Expand-Package {
        param([string]$Name, [string]$Tag, [string]$Destination)
        $work = Join-Path $stage $Name
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        tar -xzf (Join-Path $downloads "$Name-$Tag.tar.gz") -C $work
        $top = Get-ChildItem $work -Directory | Select-Object -First 1
        if (-not $top) {
            Write-Fail "${Name}: archive looked empty"
            exit 1
        }
        if (Test-Path -LiteralPath $Destination) { Remove-Item $Destination -Recurse -Force }
        $parent = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Move-Item $top.FullName $Destination
        Remove-Item $work -Recurse -Force
    }

    # The release tree keeps the HAL and the CMSIS device headers as git
    # submodules, which a tarball leaves empty, so graft the two repositories
    # into the places the build expects. The destination names carry no version
    # so that a version bump does not ripple through CMakeLists and the Keil
    # project; the version is recorded in external/versions.json instead.
    Expand-Package 'STM32CubeF1'         'v1.8.7'  (Join-Path $cubeF1Dir 'STM32CubeF1')
    Expand-Package 'stm32f1xx_hal_driver' 'v1.1.10' (Join-Path $cubeRoot 'Drivers\STM32F1xx_HAL_Driver')
    Expand-Package 'cmsis_device_f1'      'v4.3.5'  (Join-Path $cubeRoot 'Drivers\CMSIS\Device\ST\STM32F1xx')

    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

    $manifest = [ordered]@{
        generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        packages  = @($packages | ForEach-Object {
            [ordered]@{ name = $_.Name; tag = $_.Tag; sha256 = $_.Sha; url = $_.Url }
        })
    }
    $manifest | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $external 'versions.json') -Encoding UTF8
    Write-Ok 'wrote external/versions.json'
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
