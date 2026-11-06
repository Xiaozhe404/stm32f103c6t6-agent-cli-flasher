# Copilot instructions

Full rules: [AGENTS.md](../AGENTS.md). The short version:

## Non-negotiables
- **STM32F103C6T6**: 32 KB flash, 10 KB RAM, Cortex-M3, no FPU. `tools\size.ps1` is the budget gate.
- **Verify before claiming success.** `tools\build.ps1` then `tools\test.ps1` then
  `tools\size.ps1`; with hardware attached also `tools\verify.ps1`.
- **Never edit** `external/`, startup `.s` files, or `cmake/stm32f103c6tx.sct`
  without being asked. Edit `MDK-ARM/*.uvprojx` only together with `CMakeLists.txt`.
- **No `%f` printf, no malloc, no blocking in ISRs.**

## Where code goes
| Change | File |
|--------|------|
| Application behaviour | `App/Src/*.c` + `App/Include/*.h` |
| Board/console/crash support | `Bsp/Src/*.c` |
| Startup wiring, clock tree | `Core/Src/main.c` |
| Pin/clock constants | `Bsp/Include/board.h` |
| New HAL peripheral | `Core/Include/stm32f1xx_hal_conf.h` + `HAL_SOURCES` in `CMakeLists.txt` |

## Observation channel
There is no SWO pin. USART1 @115200 on PA9/PA10 is the only window into the
running target. Machine-readable log tags: `[BOOT]`, `[HB]`, `[WARN]`, `[FAULT]`.
Crash records survive reset via `.noinit`; read them with `tools\crashdump.ps1`.

## Two build tracks, one compiler
`tools\build.ps1` (CMake + armclang) is the fast loop. `tools\build.ps1 -Keil`
builds the shipping MDK project through UV4. Both use Arm Compiler 6 and
currently emit byte-identical images — a disagreement between them is a defect,
not a workaround.

Adding a source file means touching **both** `CMakeLists.txt` and the matching
`<Group>` in `MDK-ARM\STM32F103C6T6.uvprojx`; `-Keil` fails the build if they
disagree. Same for compiler options: `Cads/MiscControls` in the `.uvprojx` must
stay equal to `target_compile_options` in `CMakeLists.txt`.
