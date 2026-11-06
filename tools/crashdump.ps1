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
        # "<index>  <name>  0xADDRESS  <attr>  <n>  <Code|Sect|Data|File>  <..>  0xSIZE"
        $cols = $textLine.Trim() -split '\s+'
        if ($cols.Length -lt 6) { continue }
        if ($cols[2] -notmatch '^0x[0-9a-fA-F]{8}$') { continue }
        $kind = $cols[5]
        if ($kind -eq 'Code' -or $kind -eq 'Sect') {
            $size = [uint32]0
            $last = $cols[$cols.Length - 1]
            if ($last -match '^0x([0-9a-fA-F]+)$') {
                $size = [Convert]::ToUInt32($matches[1], 16)
            }
            # Code symbols carry the Thumb bit in bit 0; it is not part of the
            # address. (0xFFFFFFFE cannot be used as a [uint32] literal here -
            # PowerShell 5.1 parses that hex constant as Int32 -2.)
            $addr = [Convert]::ToUInt32($cols[2], 16)
            $addr = [uint32]($addr - ($addr -band 1))
            $table += [pscustomobject]@{
                Name    = $cols[1]
                Address = $addr
                Size    = $size
            }
        }
    }
    return $table
}

function Resolve-CodeSymbol {
    param($Table, [uint32]$Address)

    # Fault frames can hold PC/LR with the Thumb bit still set.
    $pc = [uint32]($Address - ($Address -band 1))

    if ($pc -lt $flashStart -or $pc -ge $flashEnd) {
        return 'not a flash address'
    }

    # Prefer the symbol whose size range contains the address. "Nearest below"
    # alone names the wrong function when the real one carries the Thumb bit
    # and therefore compares as numerically greater than the PC.
    foreach ($sym in $Table) {
        if ($sym.Size -gt 0 -and $pc -ge $sym.Address -and $pc -lt ($sym.Address + $sym.Size)) {
            return ("{0}+0x{1:x}" -f $sym.Name, ($pc - $sym.Address))
        }
    }

    $best = $null
    foreach ($sym in $Table) {
        if ($sym.Address -le $pc -and ($null -eq $best -or $sym.Address -gt $best.Address)) {
            $best = $sym
        }
    }
    if ($null -eq $best) { return 'no symbol below address' }
    return ("{0}+0x{1:x}" -f $best.Name, ($pc - $best.Address))
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
