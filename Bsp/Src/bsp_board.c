#include "bsp_board.h"

#include "board.h"
#include "stm32f1xx_hal.h"

void bsp_board_init(void)
{
    GPIO_InitTypeDef gpio = {0};

    /* Runs on the HSI clock right after reset, so no dependency on the PLL. */
    __HAL_RCC_GPIOC_CLK_ENABLE();

    gpio.Pin   = BOARD_LED_PIN;
    gpio.Mode  = GPIO_MODE_OUTPUT_PP;
    gpio.Pull  = GPIO_NOPULL;
    gpio.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(BOARD_LED_PORT, &gpio);

    BOARD_LED_OFF();
}
