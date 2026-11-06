---
name: stm32-decode-hardfault
description: Diagnose a crash or silent reset on the STM32F103C8T6 target using the on-chip crash blackbox. Use when the board stops logging, resets itself, or a [FAULT] record appears on the UART.
---

# Decode a HardFault

The firmware captures the exception frame into a `.noinit` block, resets, and
prints it on the next boot. Nothing here needs a debugger attached.

## Steps

1. Capture the console: `powershell -ExecutionPolicy Bypass -File tools\monitor.ps1 -Seconds 30`
   The record appears right after reset as `[FAULT] crash detected count=N`.

2. Symbolicate: `powershell -ExecutionPolicy Bypass -File tools\crashdump.ps1`
   It prints the raw record, then maps PC and LR through
   `build\<Config>\firmware_symbols.txt` (and to file:line via gdb if installed).

3. Read the `cause=` lines:

   | Cause | Usual root cause in this codebase |
   |-------|-----------------------------------|
   | `UFSR.UNDEFINSTR` | Called through a wild function pointer, or executed data |
   | `UFSR.INVSTATE` | Branch to an address with the Thumb bit (bit 0) clear |
   | `UFSR.DIVBYZERO` | Division by zero (enabled trap) |
   | `UFSR.UNALIGNED` | Cast a byte buffer to a `uint32_t*` on Cortex-M3 |
   | `BFSR.PRECISERR` | Bad peripheral or RAM address; `bfar` holds it |
   | `BFSR.IMPRECISERR` | Write to an invalid peripheral address not yet flushed |
   | `BFSR.STKERR` | Stack overflow — check the 1 KB stack budget |
   | `HFSR.FORCED` | Any of the above escalated to HardFault |

4. Inspect `pc`/`lr`/`sp`:
   - `sp=0x20004F00` or lower than the first global → stack overflow.
   - `pc` inside `_memset_w`/`__scatterload` → corrupt data section, often a
     bad pointer write before `main()`.
   - `pc` near a HAL function with `bfar=0x4xxxxxxx` or similar → peripheral
     accessed before its clock was enabled with `__HAL_RCC_*_CLK_ENABLE()`.

5. Fix, then re-run `tools\verify.ps1`. Clear the record by power-cycling if you
   need a clean baseline (`count` increments on every fault).

## Prove the path works

Build with `-DCMAKE_C_FLAGS=-DBSP_FAULT_SELFTEST`, call
`bsp_fault_trigger_selftest()`, and confirm `UFSR.UNDEFINSTR` shows up. That is
the regression test for the blackbox itself.
