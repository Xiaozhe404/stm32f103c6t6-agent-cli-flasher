# STM32F103C6T6 — an AI-operable firmware skeleton

Bare-metal STM32 firmware arranged so an AI agent can change the code and then
**prove the change on real hardware**: build → flash → read the serial console →
symbolicate a crash, all from the command line, exit code is the verdict.

| | |
|---|---|
| MCU | STM32F103C6T6 — Cortex-M3, 32 KB flash / 10 KB RAM, no FPU |
| Compiler | Arm Compiler 6, one source tree, two build tracks (CMake and Keil MDK) |
| Console | USART1 on PA9/PA10 @ 115200 — the only observation channel (no SWO pin) |
| Status | verified on hardware; the CMake and Keil images are byte-identical |

## Quick start

```powershell
tools\setup.ps1     # toolchain check + STM32CubeF1/HAL + Keil device pack
tools\build.ps1     # compile and link
tools\verify.ps1    # build -> flash -> assert on the UART markers
```

## Read next

| Document | For |
|----------|-----|
| [docs/README.md](docs/README.md) | project introduction and operating manual (English, with 中文对照) |
| [AGENTS.md](AGENTS.md) | the rules an AI agent must follow before touching code |
| [docs/pinmap.md](docs/pinmap.md) | pin, clock and memory facts |

---

**中文**：这是一套"AI 改完代码能自己证明改对了"的 STM32 裸机固件骨架——编译、烧写、抓串口、符号化崩溃全部在命令行里完成，返回码即结论。完整介绍与操作手册见 [docs/README.md](docs/README.md)，给 AI 的规则见 [AGENTS.md](AGENTS.md)。
