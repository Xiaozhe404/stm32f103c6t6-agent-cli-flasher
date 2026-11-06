/* Cortex-M3 exception handlers that need real implementations.
 *
 * HardFault_Handler lives in Bsp/Src/bsp_fault.c - it must stay there so the
 * crash blackbox owns the whole fault path. Every other vector keeps the weak
 * default from startup_stm32f103x6.s.
 */
#include "stm32f1xx_hal.h"

void SysTick_Handler(void)
{
    HAL_IncTick();
}
