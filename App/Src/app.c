#include "app.h"

#include "board.h"
#include "bsp_log.h"
#include "stm32f1xx_hal.h"

#define APP_HEARTBEAT_MS  500U

/* Set by SystemClock_Config() when the crystal failed and HSI was used. */
extern volatile uint8_t g_clock_fallback_hsi;

static uint32_t s_last_beat;
static uint32_t s_beat_count;

void app_init(void)
{
    bsp_log_printf("\r\n");
    bsp_log_printf("[BOOT] board=%s core=%s\r\n", BOARD_MCU_NAME, BOARD_CORE);
    bsp_log_printf("[BOOT] sysclk=%lu apb1=%lu apb2=%lu\r\n",
                   (unsigned long)HAL_RCC_GetHCLKFreq(),
                   (unsigned long)HAL_RCC_GetPCLK1Freq(),
                   (unsigned long)HAL_RCC_GetPCLK2Freq());
    if (g_clock_fallback_hsi != 0U) {
        bsp_log_printf("[WARN] HSE start failed, running on internal HSI\r\n");
    }
    bsp_log_printf("[BOOT] ready\r\n");

    s_last_beat  = HAL_GetTick();
    s_beat_count = 0U;
}

void app_poll(void)
{
    uint32_t now = HAL_GetTick();

    if ((now - s_last_beat) >= APP_HEARTBEAT_MS) {
        s_last_beat = now;
        s_beat_count++;
        BOARD_LED_TOGGLE();
        bsp_log_printf("[HB] n=%lu t=%lu dropped=%lu\r\n",
                       (unsigned long)s_beat_count,
                       (unsigned long)now,
                       (unsigned long)bsp_log_dropped());
    }
}
