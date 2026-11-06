#include "bsp_log.h"
#include "board.h"
#include "ringbuffer.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define LOG_QUEUE_SIZE     512U
#define LOG_CHUNK_SIZE      96U   /* max bytes pushed per flush call */
#define LOG_TX_TIMEOUT_MS   10U
#define LOG_LINE_SIZE      128

static uint8_t          s_storage[LOG_QUEUE_SIZE];
static ringbuffer_t     s_queue;
static UART_HandleTypeDef s_huart;
static uint8_t          s_ready;
static uint32_t         s_tx_errors;   /* HAL_UART_Transmit did not return OK */

void HAL_UART_MspInit(UART_HandleTypeDef *huart)
{
    GPIO_InitTypeDef gpio = {0};

    if (huart->Instance != BOARD_LOG_UART) {
        return;
    }

    /* board.h pins the console to USART1/PA9/PA10; update both files together. */
    __HAL_RCC_USART1_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();

    gpio.Pin   = BOARD_LOG_TX_PIN;
    gpio.Mode  = GPIO_MODE_AF_PP;
    gpio.Speed = GPIO_SPEED_FREQ_HIGH;
    HAL_GPIO_Init(BOARD_LOG_TX_PORT, &gpio);

    gpio.Pin  = BOARD_LOG_RX_PIN;
    gpio.Mode = GPIO_MODE_INPUT;
    gpio.Pull = GPIO_PULLUP;
    HAL_GPIO_Init(BOARD_LOG_RX_PORT, &gpio);
}

void bsp_log_init(void)
{
    s_ready = 0U;

    if (rb_init(&s_queue, s_storage, sizeof(s_storage)) != 0) {
        return;
    }

    s_huart.Instance          = BOARD_LOG_UART;
    s_huart.Init.BaudRate     = BOARD_LOG_BAUD;
    s_huart.Init.WordLength   = UART_WORDLENGTH_8B;
    s_huart.Init.StopBits     = UART_STOPBITS_1;
    s_huart.Init.Parity       = UART_PARITY_NONE;
    s_huart.Init.Mode         = UART_MODE_TX_RX;
    s_huart.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
    s_huart.Init.OverSampling = UART_OVERSAMPLING_16;

    if (HAL_UART_Init(&s_huart) == HAL_OK) {
        s_ready = 1U;
    }
}

size_t bsp_log_write(const char *data, size_t len)
{
    if (s_ready == 0U || data == NULL || len == 0U) {
        return 0U;
    }
    return rb_write(&s_queue, (const uint8_t *)data, len);
}

void bsp_log_flush(void)
{
    uint8_t chunk[LOG_CHUNK_SIZE];
    size_t  pending;

    if (s_ready == 0U) {
        return;
    }

    pending = rb_available(&s_queue);
    if (pending == 0U) {
        return;
    }
    if (pending > sizeof(chunk)) {
        pending = sizeof(chunk);
    }

    pending = rb_read(&s_queue, chunk, pending);
    if (pending > 0U) {
        /* A transmit that fails still releases the bytes, so without counting
         * the failures a dead console looks exactly like a working one. */
        if (HAL_UART_Transmit(&s_huart, chunk, (uint16_t)pending,
                              LOG_TX_TIMEOUT_MS) != HAL_OK) {
            s_tx_errors++;
        }
    }
}

uint32_t bsp_log_tx_errors(void)
{
    return s_tx_errors;
}

int bsp_log_read_byte(uint8_t *out)
{
    if (s_ready == 0U || out == NULL) {
        return 0;
    }
    /* Timeout 0: returns immediately when RX is empty, so the control loop
     * keeps its timing. */
    return (HAL_UART_Receive(&s_huart, out, 1U, 0U) == HAL_OK) ? 1 : 0;
}

int bsp_log_printf(const char *fmt, ...)
{
    char    line[LOG_LINE_SIZE];
    va_list args;
    int     length;

    if (s_ready == 0U || fmt == NULL) {
        return -1;
    }

    va_start(args, fmt);
    length = vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);

    if (length <= 0) {
        return length;
    }
    if ((size_t)length >= sizeof(line)) {
        length = (int)sizeof(line) - 1; /* truncated on purpose, still log it */
    }

    return (int)bsp_log_write(line, (size_t)length);
}

uint32_t bsp_log_dropped(void)
{
    return rb_dropped(&s_queue);
}
