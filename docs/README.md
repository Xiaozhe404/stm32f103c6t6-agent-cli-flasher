# STM32F103C6T6 firmware

**English is the main document. 中文对照 starts at [中文对照](#中文对照).**

Part 1 explains what this project is and why it is built this way.
Part 2 is the operating manual.

---

## Part 1 — Introduction

### What this is

Bare-metal firmware for an **STM32F103C6T6** ("Blue Pill") on STM32Cube HAL,
arranged so an AI agent can change the code and then **prove the change on real
hardware by itself** — build, flash, read the serial console, symbolicate a
crash — with no human relaying results.

| Fact | Value |
|------|-------|
| MCU | STM32F103C6T6 — Cortex-M3, **32 KB flash / 10 KB RAM**, no FPU |
| Measured identity | `DBGMCU_IDCODE = 0x412` (low density), flash-size register `0x0020` |
| Clock | 72 MHz from the 8 MHz HSE (PLL x9); falls back to HSI/2 x16 = 64 MHz |
| Console | USART1, PA9 (TX) / PA10 (RX), **115200 8N1** |
| Status LED | PC13, **active low** |
| Probe | ST-LINK over SWD (PA13/PA14); this board has **no SWO pin** |

The part is a 32 KB / 10 KB device sold as a Blue Pill — **not** an F103C8T6.
The layout is deliberately the low-density one: an image built for it also runs
unchanged on a real C8T6, so it fails safe on either board.

### Why it exists

```
What an agent can do unaided          What it cannot
----------------------------------    ------------------------------------
read and write the code           ✓   see whether the code works     ✗
run a compiler                    ✓   flash a probe                  ✗
                                  ✗   read the serial console       ✗
```

Everything that lives behind a GUI, a probe or a cable is invisible. The six
layers below turn those into commands with exit codes.

| Layer | Problem it solves | Where it lives |
|-------|-------------------|----------------|
| 1. Tools are callable | Keil is a GUI; the agent cannot click it | `tools/env.ps1` resolves every binary once |
| 2. One-command build | "please click Build for me" | `CMakeLists.txt` + `cmake/armclang-toolchain.cmake` |
| 3. Flash and observe | compiling is not running | `tools/verify.ps1` chains build → flash → assert |
| 4. Project context | the agent re-guesses the chip every session | `AGENTS.md`, `.github/copilot-instructions.md`, 2 skills |
| 5. Testable logic | HAL code cannot be unit tested | `App/Src/ringbuffer.c` has no hardware dependency |
| 6. Guard rails | nobody notices a blown budget | `tools/size.ps1`, the `-Keil` drift check, `Bsp/Include/board.h` |

### Architecture

```
Core/     CubeMX-shaped entry layer: main(), clock tree, vector handlers.
App/      Application behaviour. Pure logic lives here so it can be unit tested.
Bsp/      Board specifics: console UART, crash blackbox, board.h pin map.
tests/    Host-side unit tests (gcc, no target needed).
cmake/    Toolchain file + scatter file.
tools/    The agent interface: build / flash / monitor / verify / crashdump.
MDK-ARM/  Keil project (Debug and Release targets).
external/ STM32CubeF1 + HAL. Git-ignored, recreated by tools/setup.ps1.
```

Boot sequence, in order:

```
HAL_Init -> bsp_board_init -> SystemClock_Config -> bsp_log_init
         -> bsp_fault_init -> app_init -> loop { app_poll(); bsp_log_flush(); }
```

`SystemClock_Config` writes `g_clock_fallback_hsi` when the crystal does not
start, so the reason for a slow board is visible in the log instead of guessed.

### Memory map

| Region | Address | Size | Notes |
|--------|---------|------|-------|
| Flash | `0x0800_0000` | 32 KB | `LR_IROM1` / `ER_IROM1` |
| RAM (RW + ZI) | `0x2000_0000` | 0x2300 | application data |
| Stack | `0x2000_2300` | 0x400 | own region, so the linker owns its bounds |
| Crash blackbox | `0x2000_2700` | 0x100 | `UNINIT`, survives `NVIC_SystemReset` |

The blackbox is why a crash can be diagnosed after the board has already
rebooted. It is declared through `#pragma clang section bss` so the section
stays ZI — armlink only skips initialization for ZI sections inside an UNINIT
region, and a `section()` attribute would silently zero the record on every boot.

### What the firmware tells you about itself

Every boot prints why it started and every heartbeat prints how close it is to a
stack overflow:

```
[BOOT] reset=PIN|SFT
[HB] n=1 t=500 dropped=0 txerr=0 stack=408/1024
```

| Field | Meaning |
|-------|---------|
| `reset=` | `RCC_CSR` flags: `POR`, `PIN`, `SFT`, `IWDG`, `WWDG`, `LPWR` |
| `txerr=` | `HAL_UART_Transmit` failures. Non-zero means the console is lying to you |
| `stack=` | high-water mark / total, measured by painting the unused stack at boot |

An independent watchdog (IWDG, ~2 s) is kicked once per main loop iteration, so
a firmware that spins forever resets and reports `reset=IWDG` instead of hanging
silently. It is frozen while a debugger holds the core, so breakpoints do not
turn into resets.

The console is also an input: sending `@RST` makes the firmware reset itself.
That is how `tools\monitor.ps1 -Reset` captures a boot sequence without touching
SWD (see "When it misbehaves").

### Two build tracks

| Track | Command | Purpose |
|-------|---------|---------|
| CMake + armclang | `tools\build.ps1` | the fast loop agents use |
| Keil MDK (UV4) | `tools\build.ps1 -Keil` | what actually ships |

Both drive **Arm Compiler 6**, the compiler Keil ships, so the two tracks cannot
diverge semantically. As of the last verification they produce **byte-identical
`.bin` images** in both configurations (SHA-256 compared):

| Config | CMake | Keil |
|--------|-------|------|
| Debug | 15,896 B | 15,896 B |
| Release | 13,496 B | 13,496 B |

### Verified state

| Item | Result |
|------|--------|
| Boot | reaches `main()` → `app_poll()`, no fault |
| Clock | `RCC_CFGR = 0x001D040A` → SWS=PLL, PLLSRC=HSE, PLLMUL=x9 = 72 MHz |
| Console | `[BOOT] board=STM32F103C6T6 … [BOOT] ready`, `[HB] … txerr=0` |
| Diagnostics | `[BOOT] reset=PIN\|SFT`, `[HB] … stack=408/1024` |
| Crash blackbox | forced `UDF` → record → reset → `[FAULT] count=1 cause=UFSR.UNDEFINSTR` |
| Symbolication | `PC 0x08002b40 -> bsp_fault_trigger_selftest+0x0` |
| Footprint | Debug 55.1% flash / 23.6% RAM; Release 47.7% / 23.6% |
| Dependencies | pinned to `STM32CubeF1 v1.8.7`, `stm32f1xx_hal_driver v1.1.10`, `cmsis_device_f1 v4.3.5`, each verified by SHA-256 |

### Known gaps

- Only the LED and the UART exist so far. The HAL opt-in procedure works (IWDG
  was added that way) but no real peripheral has been brought up yet.
- `Core/` is hand-written, not CubeMX output, so "regenerating from an `.ioc`"
  is untested.
- Unit tests cover `ringbuffer` only. Log formatting and fault-record decoding
  are still untested.
- No CI: every check is run locally.
- The reset-cause and watchdog behaviour is verified by reading RAM over SWD;
  the UART capture still depends on a healthy cable.

---

## Part 2 — Operations

### First time

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup.ps1   # fetch CubeF1 + HAL, check toolchain
powershell -ExecutionPolicy Bypass -File tools\build.ps1   # compile + link
powershell -ExecutionPolicy Bypass -File tools\test.ps1    # host unit tests
```

`tools\setup.ps1` needs network access to `codeload.github.com` and
`www.keil.com/pack`. The firmware package goes to `external/`, which is
git-ignored; the Keil device pack is installed into the MDK `PACK` directory.

### The two build tracks (commands)

| Command | What it builds |
|---------|----------------|
| `tools\build.ps1 [-Config Release]` | CMake + armclang → `build\<Config>\firmware.axf/.hex/.bin` |
| `tools\build.ps1 -Keil [-Config Release]` | `MDK-ARM\STM32F103C6T6.uvprojx` via UV4 → `MDK-ARM\Objects\<Config>\` |

Both drive **Arm Compiler 6**, so they agree. As of the last verification they
produce **byte-identical `.bin` images** in both configurations.

The Keil project is only a container: sources, defines, include paths and the
scatter file all point back at the same files CMake uses. `-Keil` cross-checks
the `.uvprojx` file list against `CMakeLists.txt` and refuses to build if they
have drifted, so a forgotten `<File>` entry cannot silently ship a different
firmware.

### Every day

```powershell
tools\build.ps1                     # CMake + armclang (the fast loop)
tools\build.ps1 -Keil               # the shipping MDK project, via UV4
tools\flash.ps1                     # ST-LINK download of build\Debug\firmware.hex
tools\monitor.ps1 -List             # which COM port is the USB-TTL adapter?
tools\monitor.ps1 -Seconds 20       # capture the console into logs\uart.log
tools\verify.ps1                    # build + flash + assert on UART markers
tools\crashdump.ps1                 # symbolicate the last HardFault
tools\size.ps1                      # flash/RAM budget check
```

### Wiring the console

USB-TTL adapter → Blue Pill, **crossed**:

```
adapter TX  -> PA10 (USART1_RX)
adapter RX  -> PA9  (USART1_TX)
adapter GND -> GND
(do not connect 3V3 if the board is powered from USB)
```

115200 8N1. `tools\monitor.ps1` finds the port automatically and skips Bluetooth
COM ports.

### When it misbehaves

| Symptom | Likely cause |
|---------|--------------|
| Console is silent but the board ran a moment ago | A memory read through STM32CubeProgrammer (`-c … -r32`) leaves the CPU **halted**. Run `STM32_Programmer_CLI -c port=SWD -rst -run`, or reflash. |
| Console goes silent right after any SWD access | The ST-LINK virtual COM port stops delivering bytes while the SWD interface is in use. Never capture and debug at the same time; unplug/replug the ST-LINK to recover. |
| `verify.ps1` sees heartbeats but no `[BOOT]` lines | The boot output happened before the port was open. `monitor.ps1 -Reset` sends `@RST` so the firmware resets itself with the port already open. |
| `Cannot convert value "-2" to type UInt32` | PowerShell 5.1 parses `0xFFFFFFFE` as Int32 `-2`. Mask with `x - (x -band 1)` instead of a hex literal. |
| Script behaves oddly after an edit | `tools/*.ps1` must stay **ASCII-only**; PowerShell 5.1 reads BOM-less scripts as ANSI and mangles non-ASCII. |
| Board resets every ~2 s | The watchdog is not being kicked: the main loop is stuck. Check `tools\crashdump.ps1` and the `[BOOT] reset=IWDG` line. |
| Board resets in a loop with no output | Read the blackbox: `tools\crashdump.ps1` names the faulting function. |

### Where the pieces are

| Directory | Contents |
|-----------|----------|
| `App/` | Application behaviour (AI-owned) |
| `Bsp/` | Console UART, crash blackbox, pin map |
| `Core/` | `main()`, clock tree, vector handlers |
| `tests/` | Host-side unit tests |
| `tools/` | build / flash / monitor / verify / crashdump / size |
| `cmake/` | armclang toolchain file, scatter file |
| `MDK-ARM/` | Keil project (`Debug` / `Release` targets) |
| `external/` | STM32CubeF1 + HAL (downloaded) |

Rules for agents and humans: [AGENTS.md](../AGENTS.md).

---

## 中文对照

### 这是什么

一块 **STM32F103C6T6**（Blue Pill）上的裸机固件，基于 STM32Cube HAL。它不是给代码补全用的素材库，而是一套**让 AI 改完代码后能自己证明改对了**的工程：编译 → 烧写 → 抓串口 → 断言 → 符号化崩溃，全部是命令，返回码即结论，不需要人在中间转述。

| 事实 | 取值 |
|------|------|
| 芯片 | STM32F103C6T6 —— Cortex-M3，**32 KB flash / 10 KB RAM**，无 FPU |
| 实测身份 | `DBGMCU_IDCODE = 0x412`（低密度），flash 容量寄存器 `0x0020` |
| 时钟 | 8 MHz 外部晶振 × 9 = 72 MHz；起振失败则降级 HSI/2 × 16 = 64 MHz |
| 控制台 | USART1，PA9（TX）/ PA10（RX），**115200 8N1** |
| 状态灯 | PC13，**低电平点亮** |
| 调试器 | ST-LINK over SWD（PA13/PA14）；本板**没有 SWO 引脚** |

这颗芯片是标着 Blue Pill 卖的 32 KB / 10 KB 器件，**不是** F103C8T6。内存布局故意按低密度做——按它编出来的固件在真正的 C8T6 上也能直接跑，两种板子都安全。

### 为什么要有它

AI 能读写代码、能跑编译器，但**看不见**板子。所有藏在 GUI、调试器、串口线后面的东西，对它都是不可见的。下面六层就是把那些变成带退出码的命令。

| 层 | 解决什么 | 落在哪 |
|---|---------|-------|
| 1 工具可调用 | Keil 是 GUI，AI 点不了 | `tools/env.ps1` 统一发现所有二进制 |
| 2 一条命令构建 | 不用"麻烦你点一下 Build" | `CMakeLists.txt` + `cmake/armclang-toolchain.cmake` |
| 3 烧写与观测 | 编译过不等于能跑 | `tools/verify.ps1` 串起 build → flash → 断言 |
| 4 项目上下文 | 别每次都重新猜芯片和引脚 | `AGENTS.md`、`.github/copilot-instructions.md`、2 个 Skill |
| 5 可测逻辑 | HAL 代码没法单测 | `App/Src/ringbuffer.c` 刻意零硬件依赖 |
| 6 护栏 | 没人会注意到预算爆了 | `tools/size.ps1`、`-Keil` 漂移检查、`Bsp/Include/board.h` |

### 架构

```
Core/     CubeMX 形状的入口层：main()、时钟树、中断向量
App/      应用行为；纯逻辑放这里，才能拿到主机上单测
Bsp/      板级细节：控制台串口、崩溃黑盒、board.h 引脚表
tests/    主机侧单测（gcc，不需要目标板）
cmake/    toolchain 文件 + 散布文件
tools/    AI 的接口：build / flash / monitor / verify / crashdump
MDK-ARM/  Keil 工程（Debug、Release 两个 target）
external/ STM32CubeF1 + HAL，被 git 忽略，由 setup.ps1 重建
```

启动顺序：

```
HAL_Init -> bsp_board_init -> SystemClock_Config -> bsp_log_init
         -> bsp_fault_init -> app_init -> loop { app_poll(); bsp_log_flush(); }
```

晶振不起振时 `SystemClock_Config` 会置 `g_clock_fallback_hsi`，所以板子变慢的原因是**打印出来的**，不用猜。

### 内存布局

| 区域 | 地址 | 大小 | 说明 |
|------|------|------|------|
| Flash | `0x0800_0000` | 32 KB | `LR_IROM1` / `ER_IROM1` |
| RAM（RW + ZI） | `0x2000_0000` | 0x2300 | 应用数据 |
| 栈 | `0x2000_2300` | 0x400 | 独立区域，边界由链接器给出 |
| 崩溃黑盒 | `0x2000_2700` | 0x100 | `UNINIT`，跨 `NVIC_SystemReset` 存活 |

黑盒是"板子已经重启过了还能查原因"的关键。它用 `#pragma clang section bss` 声明以保持 ZI 节——armlink 的 `UNINIT` 只对 ZI 节跳过初始化，用 `section()` 属性会变成 RW 节，每次启动都被拷一遍零，记录被悄悄擦掉。

### 双轨构建

| 轨 | 命令 | 用途 |
|---|------|------|
| CMake + armclang | `tools\build.ps1` | AI 用的快循环 |
| Keil MDK (UV4) | `tools\build.ps1 -Keil` | 真正出货的轨 |

两条轨都用 **Arm Compiler 6**（就是 Keil 自带的编译器），所以语义不会漂移。上次验证时两者产出的 `.bin` **字节级相同**（SHA-256 比对）：

| 配置 | CMake | Keil |
|------|-------|------|
| Debug | 15,896 B | 15,896 B |
| Release | 13,496 B | 13,496 B |

### 固件会告诉你什么

每次启动都说清"为什么启动"，每次心跳都说清"栈还剩多少"：

```
[BOOT] reset=PIN|SFT
[HB] n=1 t=500 dropped=0 txerr=0 stack=408/1024
```

| 字段 | 含义 |
|------|------|
| `reset=` | `RCC_CSR` 标志：`POR`、`PIN`、`SFT`、`IWDG`、`WWDG`、`LPWR` |
| `txerr=` | `HAL_UART_Transmit` 失败次数。非零说明串口在骗你 |
| `stack=` | 已用高水位 / 总量，靠启动时给空闲栈刷图案测得 |

独立看门狗（IWDG，约 2 秒）在主循环里喂一次，所以"死循环"不再表现为静默卡死，而是复位后报 `reset=IWDG`。调试器把核停住时看门狗会被冻结，断点不会变成复位。

串口也是输入通道：发 `@RST` 让固件自己复位——`tools\monitor.ps1 -Reset` 就是这么抓启动日志的，全程不碰 SWD（原因见"出问题时先看这里"）。

### 实测状态

| 项目 | 结果 |
|------|------|
| 启动 | 走到 `main()` → `app_poll()`，无异常 |
| 时钟 | `RCC_CFGR = 0x001D040A` → SWS=PLL、PLLSRC=HSE、PLLMUL=×9 = 72 MHz |
| 控制台 | `[BOOT] board=STM32F103C6T6 … [BOOT] ready`，`[HB] … txerr=0` |
| 诊断 | `[BOOT] reset=PIN\|SFT`，`[HB] … stack=408/1024` |
| 崩溃黑盒 | 主动 `UDF` → 记录 → 复位 → `[FAULT] count=1 cause=UFSR.UNDEFINSTR` |
| 符号化 | `PC 0x08002b40 -> bsp_fault_trigger_selftest+0x0` |
| 占用 | Debug 55.1% flash / 23.6% RAM；Release 47.7% / 23.6% |
| 依赖 | 钉在 `STM32CubeF1 v1.8.7`、`stm32f1xx_hal_driver v1.1.10`、`cmsis_device_f1 v4.3.5`，逐个 SHA-256 校验 |

### 已知边界

- 目前只有 LED 和串口。HAL opt-in 两步法已经走通（IWDG 就是这么加的），但还没有真实外设上过板。
- `Core/` 是手写的，不是 CubeMX 产物，"从 `.ioc` 重新生成"这条路未验证。
- 单测只覆盖 `ringbuffer`；日志格式化和崩溃记录解析还没测。
- 没有 CI，所有检查都在本地跑。
- 复位原因和看门狗是通过 SWD 读 RAM 验证的；串口抓取仍然依赖一根健康的线。

### 操作（对应英文 Part 2）

```powershell
# 首次
tools\setup.ps1                     # 校验工具链 + 拉 CubeF1/HAL + 装 Keil 器件包

# 日常
tools\build.ps1                     # CMake + armclang 快循环
tools\build.ps1 -Config Release
tools\build.ps1 -Keil               # 出货轨
tools\test.ps1                      # 主机单测
tools\size.ps1                      # 预算检查（flash>90% 或 RAM>70% 直接失败）
tools\flash.ps1                     # 只烧写
tools\monitor.ps1 -Reset -Seconds 20   # 先复位再抓，保证抓到 [BOOT]
tools\verify.ps1                    # 交付前必跑：build→flash→串口断言
tools\crashdump.ps1                 # 崩溃现场符号化
```

### 出问题时先看这里

| 现象 | 多半是 |
|------|-------|
| 串口突然没输出，但刚才还在跑 | 用 CubeProgrammer 读内存（`-c … -r32`）会把 CPU 停在 halt 状态。执行 `STM32_Programmer_CLI -c port=SWD -rst -run` 或重新烧写。 |
| 一用 SWD，串口就彻底没声音 | ST-LINK 的虚拟串口在 SWD 占用期间会停止送数据。不要边调试边抓日志；把 ST-LINK 的 USB 拔插一次即可恢复。 |
| `verify.ps1` 只看到心跳、没有 `[BOOT]` | 启动输出在串口打开之前就发完了。`monitor.ps1 -Reset` 会发 `@RST` 让固件在端口已打开的情况下自己复位。 |
| `Cannot convert value "-2" to type UInt32` | PowerShell 5.1 把 `0xFFFFFFFE` 当 Int32 `-2`。用 `x - (x -band 1)` 抹位，别用十六进制字面量。 |
| 改过脚本后行为古怪 | `tools/*.ps1` 必须保持**纯 ASCII**；PS 5.1 按 ANSI 读无 BOM 脚本，非 ASCII 会变乱码。 |
| 板子每 2 秒左右复位一次 | 看门狗没被喂：主循环卡住了。看 `[BOOT] reset=IWDG`，再用 `tools\crashdump.ps1`。 |
| 板子无限重启且无输出 | 跑 `tools\crashdump.ps1`，它会指出出错的函数。 |

给 AI 的完整规则见 [AGENTS.md](../AGENTS.md)。
