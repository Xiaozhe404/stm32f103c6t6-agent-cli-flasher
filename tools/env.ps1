# Shared environment resolution for every tool in tools/.
# Dot-source it:  . "$PSScriptRoot\env.ps1"
#
# Everything here only *locates* things; nothing builds or flashes. Keeping the
# discovery in one place means an AI agent that hits a missing tool gets the
# same actionable message from every script.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Find-FirstPath {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match '[\*\?]') {
            $hit = Get-ChildItem -Path $candidate -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
        elseif (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Resolve-Tool {
    param([string[]]$Names, [string[]]$Paths)

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return (Find-FirstPath $Paths)
}

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "OK  $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "WARN $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "FAIL $Message" -ForegroundColor Red }

# --- MDK / Arm Compiler 6 --------------------------------------------------
$script:ArmClangRoot = Find-FirstPath @(
    $env:ARMCLANG_ROOT,
    'D:\Keil 5\ARM\ARMCLANG',
    'C:\Keil_v5\ARM\ARMCLANG',
    'C:\Program Files\Keil_v5\ARM\ARMCLANG'
)
$script:ArmClangBin = $null
if ($script:ArmClangRoot) { $script:ArmClangBin = Join-Path $script:ArmClangRoot 'bin' }

$script:Uv4Exe = Find-FirstPath @(
    $env:UV4_PATH,
    'D:\Keil 5\UV4\UV4.exe',
    'C:\Keil_v5\UV4\UV4.exe',
    'C:\Program Files\Keil_v5\UV4\UV4.exe'
)

# --- CMake / Ninja ---------------------------------------------------------
$script:CmakeExe = Resolve-Tool -Names @('cmake') -Paths @(
    "$env:LOCALAPPDATA\stm32cube\bundles\cmake\*\bin\cmake.exe",
    'C:\Program Files\CMake\bin\cmake.exe'
)
$script:NinjaExe = Resolve-Tool -Names @('ninja') -Paths @(
    "$env:LOCALAPPDATA\stm32cube\bundles\ninja\*\bin\ninja.exe",
    'C:\Program Files\Ninja\ninja.exe'
)

# --- ST-LINK tooling -------------------------------------------------------
# STM32_Programmer_CLI comes with STM32CubeProgrammer, also shipped inside the
# ST VS Code extension bundle. It is the only flasher we depend on.
$script:ProgrammerCli = Find-FirstPath @(
    $env:STM32_PROGRAMMER_CLI,
    'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
    "$env:LOCALAPPDATA\stm32cube\bundles\programmer\*\bin\STM32_Programmer_CLI.exe"
)

# Optional: used by crashdump.ps1 for addr2line quality symbolication.
$script:GdbExe = Find-FirstPath @(
    "$env:LOCALAPPDATA\stm32cube\bundles\gnu-gdb-for-stm32\*\bin\arm-none-eabi-gdb.exe",
    'C:\ST\STM32CubeIDE_*\STM32CubeIDE\plugins\*\tools\bin\arm-none-eabi-gdb.exe'
)

# --- Host compiler for unit tests -----------------------------------------
$script:HostGcc = Resolve-Tool -Names @('gcc') -Paths @(
    'D:\mingw64\bin\gcc.exe',
    'C:\msys64\mingw64\bin\gcc.exe',
    'C:\MinGW\bin\gcc.exe'
)

$script:BuildDir = Join-Path $script:RepoRoot 'build'
$script:LogDir   = Join-Path $script:RepoRoot 'logs'

function Ensure-LogDir {
    if (-not (Test-Path -LiteralPath $script:LogDir)) {
        New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    }
}

function Get-ConfigDir {
    param([string]$Config = 'Debug')
    return (Join-Path $script:BuildDir $Config)
}
