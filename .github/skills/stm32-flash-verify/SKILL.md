---
name: stm32-flash-verify
description: Build, flash and verify firmware on the STM32F103C6T6 board in this repo. Use after any firmware change to prove it compiles, fits, and still emits the expected UART boot/heartbeat markers.
---

# Flash and verify

Goal: turn "the code looks right" into "the board said so".

## Steps

1. Compile with the AI track:
   `powershell -ExecutionPolicy Bypass -File tools\build.ps1`
   Exit code must be 0. If it fails, read the `--- diagnostics ---` block: it
   prints `file:line: error:` entries that map straight to source.

2. Run the host tests when logic under `App/` changed:
   `powershell -ExecutionPolicy Bypass -File tools\test.ps1`

3. Check the memory budget on a 32 KB / 10 KB part:
   `powershell -ExecutionPolicy Bypass -File tools\size.ps1`
   Exits 1 above 90 % flash or 70 % RAM.

4. Flash and observe in one shot:
   `powershell -ExecutionPolicy Bypass -File tools\verify.ps1`
   It builds, programs through ST-LINK, then waits for `[BOOT] ready` and `[HB]`
   on USART1 and exits 0 only when both show up.

## Notes

- No COM port? `tools\monitor.ps1 -List`. The script auto-picks the first
  non-Bluetooth port, but pass `-Port COM5` explicitly when unsure.
- `verify.ps1 -NoFlash` is the CI-safe variant: build + size only.
- If flashing fails with "No STM32 target found", the SWD wiring or board power
  is the problem, not the firmware.
- Report the verification result with the actual exit codes. Never state that a
  change works based on the diff alone.
