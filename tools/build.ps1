# build.ps1 - one command the AI (or you) can run to compile the firmware.
#
#   tools\build.ps1                      # CMake + armclang, Debug
#   tools\build.ps1 -Config Release      # -O2
#   tools\build.ps1 -Keil                # build the MDK-ARM project through UV4
#   tools\build.ps1 -Keil -Config Release
#   tools\build.ps1 -Clean               # throw the build tree away first
#
# Exit code 0 means the image linked. Compiler diagnostics are echoed in their
# native format (file:line: error: ...) so an agent can jump straight to them.

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Config = 'Debug',
    [switch]$Keil,
    [switch]$Clean,
    [switch]$NoLog
)

. "$PSScriptRoot\env.ps1"

Ensure-LogDir
$logPath = Join-Path $script:LogDir "build-$Config.log"

function Show-Diagnostics {
    param([string]$LogFile)

    if (-not (Test-Path -LiteralPath $LogFile)) { return }
    $lines = Get-Content -LiteralPath $LogFile
    $hits = $lines | Where-Object {
        $_ -match ':\s*error\s*:' -or
        $_ -match 'Error: L\d+' -or
        $_ -match '^\s*FAILED:'
    } | Select-Object -Unique | Select-Object -First 20

    if ($hits) {
        Write-Host ''
        Write-Host '--- diagnostics ---' -ForegroundColor Red
        $hits | ForEach-Object { Write-Host $_ }
    }
}

function Get-KeilFileNames {
    param([string]$ProjectFile)
    $xml = [xml](Get-Content -LiteralPath $ProjectFile -Raw)
    $names = @()
    foreach ($f in $xml.SelectNodes('//File/FilePath')) { $names += $f.InnerText }
    return $names
}

# The .uvprojx carries its own copy of the source list. If it drifts from
# CMakeLists.txt the Keil image silently differs from the CMake image, so
# refuse to build instead of shipping two different firmwares.
function Assert-KeilSourcesMatch {
    param([string]$ProjectFile)

    $cmake = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'CMakeLists.txt') -Raw
    $expected = @()
    foreach ($m in [regex]::Matches($cmake, '(?m)^\s+(App|Bsp|Core)/Src/([A-Za-z0-9_]+\.c)\s*$')) {
        $expected += "../$($m.Groups[1].Value)/Src/$($m.Groups[2].Value)"
    }
    foreach ($m in [regex]::Matches($cmake, '\$\{HAL_DIR\}/Src/([A-Za-z0-9_]+\.c)')) {
        $expected += "../external/cubeF1/STM32CubeF1/Drivers/STM32F1xx_HAL_Driver/Src/$($m.Groups[1].Value)"
    }
    foreach ($m in [regex]::Matches($cmake, '\$\{CMSIS_DEVICE_DIR\}/Source/Templates/([A-Za-z0-9_]+\.c)')) {
        $expected += "../external/cubeF1/STM32CubeF1/Drivers/CMSIS/Device/ST/STM32F1xx/Source/Templates/$($m.Groups[1].Value)"
    }
    foreach ($m in [regex]::Matches($cmake, '\$\{CMSIS_DEVICE_DIR\}/Source/Templates/arm/([A-Za-z0-9_]+\.s)')) {
        $expected += "../external/cubeF1/STM32CubeF1/Drivers/CMSIS/Device/ST/STM32F1xx/Source/Templates/arm/$($m.Groups[1].Value)"
    }

    $actual = Get-KeilFileNames $ProjectFile

    $missing = $expected | Where-Object { $actual -notcontains $_ }
    $extra = $actual | Where-Object { $expected -notcontains $_ -and $_ -like '../*' }

    if ($missing -or $extra) {
        Write-Fail 'MDK-ARM project is out of sync with CMakeLists.txt'
        foreach ($m in $missing) { Write-Host "  missing from .uvprojx: $m" -ForegroundColor Red }
        foreach ($e in $extra) { Write-Host "  not in CMakeLists.txt: $e" -ForegroundColor Yellow }
        Write-Host 'Add or remove the <File> entry in MDK-ARM\STM32F103C6T6.uvprojx.' -ForegroundColor Red
        return 1
    }
    return 0
}

function Build-WithKeil {
    if (-not $script:Uv4Exe) {
        Write-Fail 'UV4.exe not found. Install Keil MDK 5 or set UV4_PATH.'
        return 1
    }
    $mdkDir = Join-Path $script:RepoRoot 'MDK-ARM'
    $project = $null
    if (Test-Path -LiteralPath $mdkDir) {
        $project = Get-ChildItem -LiteralPath $mdkDir -Filter '*.uvprojx' -Recurse |
                   Select-Object -First 1
    }
    if (-not $project) {
        Write-Fail 'No MDK-ARM\*.uvprojx found. Run tools\setup.ps1 to install the Keil device pack, then restore the project file from git.'
        return 1
    }

    $syncRc = Assert-KeilSourcesMatch $project.FullName
    if ($syncRc -ne 0) { return $syncRc }

    Write-Step "UV4 build: $($project.Name)"
    $uvLog = Join-Path $script:LogDir "uv4-$Config.log"
    $uvArgs = @('-b', $project.FullName, '-j0', '-o', $uvLog)
    if ($Config -eq 'Release') { $uvArgs += '-t'; $uvArgs += 'Release' }

    $proc = Start-Process -FilePath $script:Uv4Exe -ArgumentList $uvArgs -Wait -PassThru -NoNewWindow
    $rc = $proc.ExitCode

    switch ($rc) {
        0 { Write-Ok 'Keil build succeeded (no warnings)' }
        1 { Write-Ok 'Keil build succeeded (with warnings)' }
        2 { Write-Fail 'Keil build finished with errors' }
        3 { Write-Fail 'Keil build hit a fatal error' }
        11 { Write-Fail 'UV4 could not open the project file' }
        13 { Write-Fail 'UV4 license problem' }
        default { Write-Fail "UV4 returned $rc" }
    }
    if (Test-Path -LiteralPath $uvLog) {
        Copy-Item -LiteralPath $uvLog -Destination $logPath -Force
        Show-Diagnostics $logPath
    }
    if ($rc -le 1) { return 0 }
    return 1
}

if ($Keil) {
    exit (Build-WithKeil)
}

if (-not $script:CmakeExe) {
    Write-Fail 'cmake not found. Run tools\setup.ps1 or install CMake.'
    exit 1
}

$configDir = Get-ConfigDir $Config
if ($Clean -and (Test-Path -LiteralPath $configDir)) {
    Write-Step "Removing $configDir"
    Remove-Item -LiteralPath $configDir -Recurse -Force
}

$configureArgs = @('--preset', $Config)
if ($script:NinjaExe) { $configureArgs += "-DCMAKE_MAKE_PROGRAM=$script:NinjaExe" }

if (-not (Test-Path -LiteralPath (Join-Path $configDir 'CMakeCache.txt'))) {
    Write-Step "Configuring ($Config)"
    $configureOutput = & $script:CmakeExe @configureArgs 2>&1
    if (-not $NoLog) { $configureOutput | Set-Content -LiteralPath $logPath -Encoding UTF8 }
    if ($LASTEXITCODE -ne 0) {
        $configureOutput | ForEach-Object { Write-Host $_ }
        Write-Fail 'CMake configure failed'
        exit 1
    }
}

Write-Step "Building ($Config)"
if ($NoLog) {
    & $script:CmakeExe --build --preset $Config
}
else {
    & $script:CmakeExe --build --preset $Config 2>&1 | Tee-Object -FilePath $logPath
}
$buildRc = $LASTEXITCODE

if ($buildRc -ne 0) {
    Show-Diagnostics $logPath
    Write-Fail "Build failed (exit $buildRc). Full log: $logPath"
    exit $buildRc
}

Write-Ok "Build succeeded"
$sizesFile = Join-Path $configDir 'firmware_sizes.txt'
if (Test-Path -LiteralPath $sizesFile) {
    $totals = Get-Content -LiteralPath $sizesFile |
              Where-Object { $_ -match 'ROM Totals for' } |
              Select-Object -First 1
    if ($totals) { Write-Host $totals.Trim() -ForegroundColor DarkGray }
}
exit 0
