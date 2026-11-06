# crashdump.ps1 - turn the on-target crash blackbox into a readable report.
#
# The firmware stores the fault frame in .noinit, resets, and prints it on the
# next boot as [FAULT] lines. This script pulls the newest record out of the
# UART log and maps PC/LR to symbols so an agent can point at a function.
#
#   tools\crashdump.ps1
#   tools\crashdump.ps1 -Log logs\uart.log -Config Release
#
# Exit code 0 even when no crash is found: "no crash" is not a script failure.

[CmdletBinding()]
param(
    [string]$Log = 'logs\uart.log',
    [ValidateSet('Debug', 'Release')][string]$Config = 'Debug',
    [string]$SymbolsFile = '',
    [string]$ElfFile = ''
)

. "$PSScriptRoot\env.ps1"

$flashStart = [uint32]0x08000000
$flashEnd   = [uint32]0x08008000   # STM32F103C6T6 = 32 KB

if (-not [System.IO.Path]::IsPathRooted($Log)) { $Log = Join-Path $script:RepoRoot $Log }
if (-not (Test-Path -LiteralPath $Log)) {
    Write-Fail "UART log not found: $Log"
    Write-Host 'Capture one first: tools\monitor.ps1 -Seconds 10' -ForegroundColor Yellow
    exit 1
}

$configDir = Get-ConfigDir $Config
if (-not $SymbolsFile) { $SymbolsFile = Join-Path $configDir 'firmware_symbols.txt' }
if (-not $ElfFile)     { $ElfFile     = Join-Path $configDir 'firmware.axf' }

$faultLines = @(Get-Content -LiteralPath $Log | Where-Object { $_ -match '\[FAULT\]' })
if ($faultLines.Count -eq 0) {
    Write-Warn 'No [FAULT] record in the log. The target has not crashed since the last flash.'
    exit 0
}

# Newest record: everything from the last "crash detected" marker onwards.
$startIndex = 0
for ($i = 0; $i -lt $faultLines.Count; $i++) {
    if ($faultLines[$i] -match 'crash detected') { $startIndex = $i }
}
$record = @($faultLines[$startIndex..($faultLines.Count - 1)])

function Get-SymbolTable {
    param([string]$TablePath)

    $table = @()
    if (-not (Test-Path -LiteralPath $TablePath)) { return $table }
    foreach ($textLine in Get-Content -LiteralPath $TablePath) {
        # "<index>  <name>  0xADDRESS  <attr>  <n>  <Code|Sect|Data|File>  ..."
        if ($textLine -match '^\s*\d+\s+(\S+)\s+0x([0-9a-fA-F]{8})\s+(\S+)\s+(\S+)\s+(\S+)') {
            $kind = $matches[5]
            if ($kind -eq 'Code' -or $kind -eq 'Sect') {
                $table += [pscustomobject]@{
                    Name    = $matches[1]
                    Address = [Convert]::ToUInt32($matches[2], 16)
                }
            }
        }
    }
    return $table
}

function Resolve-CodeSymbol {
    param($Table, [uint32]$Address)

    if ($Address -lt $flashStart -or $Address -ge $flashEnd) {
        return 'not a flash address'
    }
    $best = $null
    foreach ($sym in $Table) {
        if ($sym.Address -le $Address -and ($null -eq $best -or $sym.Address -gt $best.Address)) {
            $best = $sym
        }
    }
    if ($null -eq $best) { return 'no symbol below address' }
    return ("{0}+0x{1:x}" -f $best.Name, ($Address - $best.Address))
}

$symTable = @(Get-SymbolTable $SymbolsFile)

Write-Host ''
Write-Host '--- crash blackbox ---' -ForegroundColor Cyan
foreach ($line in $record) {
    $clean = $line -replace '^.*\[FAULT\]\s*', ''
    Write-Host "  $clean"
}

Write-Host ''
Write-Host '--- symbolication ---' -ForegroundColor Cyan

$pcLine = $record | Where-Object { $_ -match 'pc=(0x[0-9a-fA-F]+)' } | Select-Object -First 1
if ($pcLine -and $pcLine -match 'pc=(0x[0-9a-fA-F]+)') {
    $pc = [Convert]::ToUInt32($matches[1], 16)
    Write-Host ("  PC 0x{0:x8} -> {1}" -f $pc, (Resolve-CodeSymbol $symTable $pc))

    if ($script:GdbExe -and (Test-Path -LiteralPath $ElfFile)) {
        try {
            $gdbOut = & $script:GdbExe -batch -ex ("info line *0x{0:x8}" -f $pc) $ElfFile 2>&1 | Out-String
            if ($gdbOut -match 'Line (\d+) of "([^"]+)"') {
                Write-Host ("  source: {0}:{1}" -f $matches[2], $matches[1])
            }
        }
        catch { }
    }
}

$lrLine = $record | Where-Object { $_ -match 'lr=(0x[0-9a-fA-F]+)' } | Select-Object -First 1
if ($lrLine -and $lrLine -match 'lr=(0x[0-9a-fA-F]+)') {
    $lr = [Convert]::ToUInt32($matches[1], 16)
    Write-Host ("  LR 0x{0:x8} -> {1}" -f $lr, (Resolve-CodeSymbol $symTable $lr))
}

$causes = $record | Where-Object { $_ -match 'cause=' } |
          ForEach-Object { ($_ -split 'cause=')[1].Trim() }
if ($causes) {
    Write-Host ''
    Write-Host ("  causes: " + ($causes -join ', ')) -ForegroundColor Yellow
}
Write-Host ''
exit 0
