# STM32F103C8T6 firmware — quick start

## First time

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup.ps1   # fetch CubeF1 + HAL, check toolchain
powershell -ExecutionPolicy Bypass -File tools\build.ps1   # compile + link
powershell -ExecutionPolicy Bypass -File tools\test.ps1    # host unit tests
```

`tools\setup.ps1` needs network access to `codeload.github.com`. Everything it
downloads goes to `external/`, which is git-ignored.

## Every day

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

## Wiring the console

USB-TTL adapter → Blue Pill, **crossed**:

```
adapter TX  -> PA10 (USART1_RX)
adapter RX  -> PA9  (USART1_TX)
adapter GND -> GND
(do not connect 3V3 if the board is powered from USB)
```

115200 8N1. `tools\monitor.ps1` finds the port automatically and skips Bluetooth
COM ports.

## Where the pieces are

| Directory | Contents |
|-----------|----------|
| `App/` | Application behaviour (AI-owned) |
| `Bsp/` | Console UART, crash blackbox, pin map |
| `Core/` | `main()`, clock tree, vector handlers |
| `tests/` | Host-side unit tests |
| `tools/` | build / flash / monitor / verify / crashdump / size |
| `cmake/` | armclang toolchain file, scatter file |
| `external/` | STM32CubeF1 + HAL (downloaded) |

Rules for agents and humans: [AGENTS.md](../AGENTS.md).
