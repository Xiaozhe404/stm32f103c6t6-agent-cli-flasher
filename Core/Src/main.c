/* Entry point and clock tree.
 *
 * Shape matches what STM32CubeMX generates for an MDK-ARM project, so a .ioc
 * regeneration only replaces the two USER CODE blocks at the bottom.
 *
 * Clock plan (F103C6T6):
 *   HSE 8 MHz x PLL9 = 72 MHz SYSCLK, AHB /1, APB1 /2 (36 MHz), APB2 /1 (72 MHz)
 *   Fallback when the crystal does not start:
 *   HSI 8 MHz /2 x PLL16 = 64 MHz SYSCLK, same bus dividers.
 */
#include "stm32f1xx_hal.h"

#include "app.h"
#include "board.h"
#include "bsp_board.h"
#include "bsp_fault.h"
#include "bsp_log.h"

volatile uint8_t g_clock_fallback_hsi = 0U;

static void SystemClock_Config(void);
static void Error_Handler(void);

int main(void)
{
    HAL_Init();
    bsp_board_init();   /* LED first: it is the only sign of life if clocks fail */
    SystemClock_Config();

    bsp_log_init();
    bsp_fault_init();   /* prints a crash record left by the previous boot */

    app_init();

    for (;;) {
        app_poll();
        bsp_log_flush();
    }
}

static void SystemClock_Config(void)
{
    RCC_OscInitTypeDef osc = {0};
    RCC_ClkInitTypeDef clk = {0};

    osc.OscillatorType  = RCC_OSCILLATORTYPE_HSE;
    osc.HSEState        = RCC_HSE_ON;
    osc.HSEPredivValue  = RCC_HSE_PREDIV_DIV1;
    osc.HSIState        = RCC_HSI_ON;
    osc.PLL.PLLState    = RCC_PLL_ON;
    osc.PLL.PLLSource   = RCC_PLLSOURCE_HSE;
    osc.PLL.PLLMUL      = RCC_PLL_MUL9;

    if (HAL_RCC_OscConfig(&osc) != HAL_OK) {
        /* Dead crystal / clone board: keep the MCU alive on the internal RC
         * so the log still reaches the engineer (and the AI). */
        g_clock_fallback_hsi = 1U;

        osc.OscillatorType = RCC_OSCILLATORTYPE_HSI;
        osc.HSEState       = RCC_HSE_OFF;
        osc.PLL.PLLSource  = RCC_PLLSOURCE_HSI_DIV2;
        osc.PLL.PLLMUL     = RCC_PLL_MUL16;

        if (HAL_RCC_OscConfig(&osc) != HAL_OK) {
            Error_Handler();
        }
    }

    clk.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK |
                         RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
    clk.AHBCLKDivider  = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV2;
    clk.APB2CLKDivider = RCC_HCLK_DIV1;

    if (HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_2) != HAL_OK) {
        Error_Handler();
    }
}

static void Error_Handler(void)
{
    __disable_irq();
    for (;;) {
        BOARD_LED_TOGGLE();
        for (volatile uint32_t i = 0U; i < 400000U; i++) {
            __NOP();
        }
    }
}
