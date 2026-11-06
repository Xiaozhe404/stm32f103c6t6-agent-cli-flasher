#include "app.h"

#include <string.h>

#include "board.h"
#include "bsp_diag.h"
#include "bsp_log.h"
#include "stm32f1xx_hal.h"

#define APP_HEARTBEAT_MS  500U
#define APP_CMD_MAX        8U

/* Reset request sent by tools/monitor.ps1 -Reset. Going through the console
 * keeps the whole capture on one open handle: talking SWD while the virtual
 * COM port is open makes the ST-LINK stop delivering bytes. */
static const char k_reset_command[] = "@RST";

/* Set by SystemClock_Config() when the crystal failed and HSI was used. */
extern volatile uint8_t g_clock_fallback_hsi;

static uint32_t s_last_beat;
static uint32_t s_beat_count;
static char     s_cmd[APP_CMD_MAX];
static size_t   s_cmd_len;

static void console_poll(void)
{
    uint8_t rx;

    while (bsp_log_read_byte(&rx) != 0) {
        if (rx == '\r' || rx == '\n') {
            s_cmd_len = 0U;
            continue;
        }
        if (s_cmd_len >= sizeof(s_cmd)) {
            s_cmd_len = 0U;
            continue;
        }
        s_cmd[s_cmd_len++] = (char)rx;

        if (s_cmd_len == (sizeof(k_reset_command) - 1U) &&
            memcmp(s_cmd, k_reset_command, s_cmd_len) == 0) {
            bsp_log_printf("[BOOT] reset requested by console\r\n");
            bsp_log_flush();
            HAL_Delay(20U);          /* let the last bytes leave the shifter */
            NVIC_SystemReset();
        }
    }
}

void app_init(void)
{
    bsp_log_printf("\r\n");
    bsp_log_printf("[BOOT] board=%s core=%s\r\n", BOARD_MCU_NAME, BOARD_CORE);
    bsp_log_printf("[BOOT] sysclk=%lu apb1=%lu apb2=%lu\r\n",
                   (unsigned long)HAL_RCC_GetHCLKFreq(),
                   (unsigned long)HAL_RCC_GetPCLK1Freq(),
                   (unsigned long)HAL_RCC_GetPCLK2Freq());
    bsp_log_printf("[BOOT] reset=%s\r\n", bsp_diag_reset_cause());
    if (g_clock_fallback_hsi != 0U) {
        bsp_log_printf("[WARN] HSE start failed, running on internal HSI\r\n");
    }
    if (bsp_diag_stack_size() == 0U) {
        bsp_log_printf("[WARN] stack region missing, watermark disabled\r\n");
    }
    bsp_log_printf("[BOOT] ready\r\n");

    s_last_beat  = HAL_GetTick();
    s_beat_count = 0U;
}

void app_poll(void)
{
    uint32_t now;

    console_poll();

    now = HAL_GetTick();

    if ((now - s_last_beat) >= APP_HEARTBEAT_MS) {
        s_last_beat = now;
        s_beat_count++;
        BOARD_LED_TOGGLE();
        bsp_log_printf("[HB] n=%lu t=%lu dropped=%lu txerr=%lu stack=%lu/%lu\r\n",
                       (unsigned long)s_beat_count,
                       (unsigned long)now,
                       (unsigned long)bsp_log_dropped(),
                       (unsigned long)bsp_log_tx_errors(),
                       (unsigned long)bsp_diag_stack_used(),
                       (unsigned long)bsp_diag_stack_size());
    }
}
