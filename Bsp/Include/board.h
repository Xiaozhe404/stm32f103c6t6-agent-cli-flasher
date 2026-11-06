/* Board constants for STM32F103C8T6 ("Blue Pill").
 *
 * Single source of truth for pin mapping, clocks and memory budget. If the
 * hardware changes, change it here - AGENTS.md tells the AI to read this file
 * instead of inventing pin numbers.
 */
#ifndef BOARD_H
#define BOARD_H

#ifdef __cplusplus
extern "C" {
#endif

#include "stm32f1xx_hal.h"

#define BOARD_MCU_NAME        "STM32F103C8T6"
#define BOARD_CORE            "Cortex-M3"

#define BOARD_HSE_HZ          8000000U
#define BOARD_SYSCLK_HZ       72000000U
#define BOARD_APB1_HZ         36000000U
#define BOARD_APB2_HZ         72000000U

#define BOARD_FLASH_BYTES     (64U * 1024U)
#define BOARD_RAM_BYTES       (20U * 1024U)

/* On-board LED: PC13, active low (LED lit when pin is driven low). */
#define BOARD_LED_PORT        GPIOC
#define BOARD_LED_PIN         GPIO_PIN_13
#define BOARD_LED_ON()        HAL_GPIO_WritePin(BOARD_LED_PORT, BOARD_LED_PIN, GPIO_PIN_RESET)
#define BOARD_LED_OFF()       HAL_GPIO_WritePin(BOARD_LED_PORT, BOARD_LED_PIN, GPIO_PIN_SET)
#define BOARD_LED_TOGGLE()    HAL_GPIO_TogglePin(BOARD_LED_PORT, BOARD_LED_PIN)

/* Debug console: USART1 on PA9 (TX) / PA10 (RX).
 * The Blue Pill has no SWO trace pin routed, so UART is the only log channel. */
#define BOARD_LOG_UART        USART1
#define BOARD_LOG_BAUD        115200U
#define BOARD_LOG_TX_PORT     GPIOA
#define BOARD_LOG_TX_PIN      GPIO_PIN_9
#define BOARD_LOG_RX_PORT     GPIOA
#define BOARD_LOG_RX_PIN      GPIO_PIN_10

/* SWD pins (PA13/PA14) must never be repurposed. */
#define BOARD_SWD_PORT        GPIOA
#define BOARD_SWDIO_PIN       GPIO_PIN_13
#define BOARD_SWCLK_PIN       GPIO_PIN_14

#ifdef __cplusplus
}
#endif

#endif /* BOARD_H */
