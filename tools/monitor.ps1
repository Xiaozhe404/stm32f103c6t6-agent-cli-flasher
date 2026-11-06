# monitor.ps1 - capture the UART console into a file an agent can grep.
#
#   tools\monitor.ps1 -List
#   tools\monitor.ps1 -Seconds 15
#   tools\monitor.ps1 -Port COM5 -Expect '\[BOOT\] ready','\[HB\]' -Seconds 20
#   tools\monitor.ps1 -Reset -Seconds 10   # reset first, so [BOOT] is captured
#
# Exit code 0 = the capture window elapsed and every -Expect pattern matched.
# Without -Port the script picks the first real USB-serial adapter; Bluetooth
# virtual COM ports are ignored because they exist even with nothing plugged in.
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as
# ANSI, so non-ASCII characters in .ps1 files are a portability trap.

[CmdletBinding()]
param(
    [string]$Port,
    [int]$Baud = 115200,
    [int]$Seconds = 20,
    [string]$Log = '',
    [string[]]$Expect = @(),
    [switch]$List,
    [switch]$Quiet,
    [switch]$Raw,         # do not add a timestamp prefix per chunk
    [switch]$Reset        # reset the target after the port is open, so the
                          # boot sequence is captured instead of racing it
)

. "$PSScriptRoot\env.ps1"

function Get-SerialPortInfo {
    $result = @()
    $names = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    $infoById = @{}

    try {
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\((COM\d+)\)' } |
            ForEach-Object {
                $infoById[$matches[1]] = [pscustomobject]@{
                    Description  = $_.Name
                    Manufacturer = $_.Manufacturer
                }
            }
    }
    catch { }

    foreach ($name in $names) {
        $desc = ''
        $mfg = ''
        if ($infoById.ContainsKey($name)) {
            $desc = $infoById[$name].Description
            $mfg = $infoById[$name].Manufacturer
        }
        $result += [pscustomobject]@{ Port = $name; Description = $desc; Manufacturer = $mfg }
    }
    return $result
}

if ($List) {
    Get-SerialPortInfo | Format-Table -AutoSize
    exit 0
}

if (-not $Log) { $Log = Join-Path $script:LogDir 'uart.log' }
$logFull = $Log
if (-not [System.IO.Path]::IsPathRooted($logFull)) {
    $logFull = Join-Path $script:RepoRoot $logFull
}
$logDir = Split-Path -Parent $logFull
if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

if (-not $Port) {
    $allPorts = @(Get-SerialPortInfo)
    $candidates = @($allPorts | Where-Object { $_.Manufacturer -ne 'Microsoft' })
    if ($candidates.Count -eq 0) {
        Write-Fail 'No USB-serial adapter found (only Bluetooth/virtual ports are present).'
        Write-Host 'Plug in the USB-TTL adapter, then check with: tools\monitor.ps1 -List' -ForegroundColor Yellow
        $allPorts | Format-Table -AutoSize | Out-Host
        exit 1
    }
    $Port = $candidates[0].Port
    Write-Warn "No -Port given, using $Port ($($candidates[0].Description))"
}

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$serial.ReadTimeout = 250
$serial.WriteTimeout = 250
$serial.DtrEnable = $false
$serial.RtsEnable = $false

Write-Step "Listening on $Port @ $Baud (${Seconds}s) -> $logFull"

try {
    $serial.Open()
}
catch {
    Write-Fail "Cannot open $Port : $($_.Exception.Message)"
    exit 1
}

# A board that has been running since the last flash has already printed its
# [BOOT] lines and the ST-LINK VCP retains only a short backlog. Resetting here,
# after the port is open, makes the boot sequence part of the capture window.
if ($Reset) {
    # The ST-LINK virtual COM port stops delivering bytes as soon as the SWD
    # interface is used, so a debugger-driven reset makes the capture empty.
    # Ask the firmware to reset itself instead (app.c watches for "@RST").
    Write-Step 'Resetting target via console'
    try {
        $serial.DiscardInBuffer()
        $serial.Write("@RST`r`n")
    }
    catch {
        Write-Warn "-Reset failed: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 150
}

$deadline  = (Get-Date).AddSeconds($Seconds)
$collected = New-Object System.Text.StringBuilder
$pending   = @($Expect)
# A serial read can split a line anywhere, so a timestamp may only be added when
# the stream really is at the beginning of a line.
$atLineStart = $true

try {
    while ((Get-Date) -lt $deadline) {
        $chunk = ''
        try { $chunk = $serial.ReadExisting() } catch { $chunk = '' }

        if ($chunk.Length -gt 0) {
            [void]$collected.Append($chunk)

            if ($pending.Count -gt 0) {
                $stillMissing = @()
                $seen = $collected.ToString()
                foreach ($pattern in $pending) {
                    if ($seen -notmatch $pattern) { $stillMissing += $pattern }
                }
                $pending = $stillMissing
            }

            $text = $chunk
            if (-not $Raw) {
                $stamp = (Get-Date).ToString('HH:mm:ss.fff')
                $parts = $chunk -split "`n"
                for ($i = 0; $i -lt $parts.Length; $i++) {
                    if ($i -gt 0 -or $atLineStart) {
                        $parts[$i] = "$stamp|$($parts[$i])"
                    }
                }
                $text = $parts -join "`n"
                $atLineStart = $chunk.EndsWith("`n")
            }
            [System.IO.File]::AppendAllText(
                $logFull, $text, (New-Object System.Text.UTF8Encoding($false)))

            if (-not $Quiet) { Write-Host $chunk -NoNewline }
        }

        if ($Expect.Count -gt 0 -and $pending.Count -eq 0) { break }
        Start-Sleep -Milliseconds 40
    }
}
finally {
    try { $serial.Close() } catch { }
    $serial.Dispose()
}

Write-Host ''
$total = $collected.Length

if ($Expect.Count -gt 0) {
    if ($pending.Count -eq 0) {
        Write-Ok "All $($Expect.Count) expectation(s) matched ($total chars captured)"
        exit 0
    }
    Write-Fail "Missing expectation(s): $($pending -join ' | ')"
    exit 1
}

if ($total -eq 0) {
    Write-Warn 'No bytes received. Check TX wiring and baud rate.'
    exit 1
}
Write-Ok "$total chars captured"
exit 0
