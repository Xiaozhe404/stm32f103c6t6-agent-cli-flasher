# Pin map — STM32F103C8T6 (Blue Pill)

Authoritative C definitions live in [board.h](../Bsp/Include/board.h). Change
both together, or nothing.

## Reserved / fixed

| Pin | Function | Notes |
|-----|----------|-------|
| PA13 | SWDIO | Never repurpose — it is the flashing interface |
| PA14 | SWCLK | Never repurpose |
| PA9 | USART1_TX (console) | 115200 8N1 |
| PA10 | USART1_RX (console) | Reserved even when unused |
| PC13 | LED | **Active low** — `RESET` = lit |
| PD0 / PD1 | HSE 8 MHz crystal | Blue Pill on-board crystal |
| NRST | Reset | |
| BOOT0 | Boot select | Low = run from flash |

## JTAG pins that double as GPIO

| Pin | Default | To use as GPIO |
|-----|---------|----------------|
| PB3 | JTDO | `__HAL_AFIO_REMAP_SWJ_NOJTAG()` + AFIO clock |
| PB4 | NJTRST | same |
| PA15 | JTDI | same |

Do not disable SWD on PA13/PA14 — that would leave no way to reflash.

## Free pins

PA0–PA8, PA11, PA12, PB0–PB2, PB5–PB15, PC14, PC15, and PA15/PB3/PB4 after the
remap above. PC14/PC15 are wired to the low-speed oscillator pads on some
boards; check the schematic before using them.

## Memory map

| Region | Start | Size |
|--------|-------|------|
| Flash | `0x0800_0000` | 64 KB |
| SRAM (RW + ZI + stack) | `0x2000_0000` | 20 KB minus blackbox |
| Crash blackbox (UNINIT) | `0x2000_4F00` | 256 B |
