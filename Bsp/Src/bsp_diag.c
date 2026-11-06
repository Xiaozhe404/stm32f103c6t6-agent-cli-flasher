#include "bsp_diag.h"

#include <string.h>

#include "stm32f1xx_hal.h"

/* Provided by the STACKS region in cmake/stm32f103c6tx.sct and by the vendor
 * startup file. Both bounds come from the linker, so the watermark can never
 * disagree with the real stack.
 *
 * Image$$STACKS$$Limit equals Base here: armlink reports the end of the
 * *initialized* part of a region, and a stack is UNINIT. The top is therefore
 * taken from vector table entry 0, which is __initial_sp by construction. */
extern uint32_t Image$$STACKS$$Base[];
extern uint32_t __Vectors[];

#define STACK_PAINT       0xA5A5A5A5U
#define STACK_PAINT_MARGIN 128U   /* bytes above the probe left unpainted */
#define STACK_SANE_MIN     256U   /* reject a region we clearly mis-measured */
#define STACK_SANE_MAX    8192U

/* LSI 40 kHz / 64 = 625 Hz; 1250 counts is a 2 s window. */
#define IWDG_PRESCALER     IWDG_PRESCALER_64
#define IWDG_RELOAD        1249U

static IWDG_HandleTypeDef s_iwdg;
static uint8_t  s_iwdg_running;
static char     s_reset_cause[24];
static uint32_t s_stack_base;
static uint32_t s_stack_top;
static uint32_t s_stack_mark;   /* base of the still-painted area, 0 = disabled */

static void append_cause(const char *token)
{
    size_t len = strlen(s_reset_cause);

    if (len != 0U) {
        if (len + 1U >= sizeof(s_reset_cause)) { return; }
        s_reset_cause[len++] = '|';
        s_reset_cause[len] = '\0';
    }
    strncat(s_reset_cause, token, sizeof(s_reset_cause) - len - 1U);
}

static void capture_reset_cause(void)
{
    uint32_t csr = RCC->CSR;

    s_reset_cause[0] = '\0';

    if ((csr & RCC_CSR_PORRSTF)  != 0U) { append_cause("POR"); }
    if ((csr & RCC_CSR_PINRSTF)  != 0U) { append_cause("PIN"); }
    if ((csr & RCC_CSR_SFTRSTF)  != 0U) { append_cause("SFT"); }
    if ((csr & RCC_CSR_IWDGRSTF) != 0U) { append_cause("IWDG"); }
    if ((csr & RCC_CSR_WWDGRSTF) != 0U) { append_cause("WWDG"); }
    if ((csr & RCC_CSR_LPWRRSTF) != 0U) { append_cause("LPWR"); }
    if (s_reset_cause[0] == '\0')       { append_cause("NONE"); }

    /* Clear the flags so the next boot reports its own cause, not this one. */
    RCC->CSR |= RCC_CSR_RMVF;
}

static void paint_stack(void)
{
    uint32_t base = (uint32_t)(uintptr_t)Image$$STACKS$$Base;
    uint32_t top  = __Vectors[0];
    uint32_t probe;
    uint32_t from;
    uint32_t primask;
    uint32_t *p;

    s_stack_base = base;
    s_stack_top  = top;
    s_stack_mark = 0U;

    if (top <= base ||
        (top - base) < STACK_SANE_MIN ||
        (top - base) > STACK_SANE_MAX) {
        return;                     /* region missing or not what we expect */
    }

    probe = (uint32_t)(uintptr_t)&base;
    from  = probe - STACK_PAINT_MARGIN;
    if (from <= base) { return; }   /* already deep in the stack */
    if (from > top)   { return; }

    /* An interrupt frame would land inside the range being painted. */
    primask = __get_PRIMASK();
    __disable_irq();
    for (p = (uint32_t *)base; p < (uint32_t *)from; p++) {
        *p = STACK_PAINT;
    }
    __set_PRIMASK(primask);

    s_stack_mark = base;
}

static void start_watchdog(void)
{
    s_iwdg.Instance          = IWDG;
    s_iwdg.Init.Prescaler    = IWDG_PRESCALER;
    s_iwdg.Init.Reload       = IWDG_RELOAD;

    if (HAL_IWDG_Init(&s_iwdg) != HAL_OK) {
        return;                     /* no watchdog is better than a wrong one */
    }
    s_iwdg_running = 1U;

    /* Stop the counter while the core is halted by a debugger, otherwise every
     * breakpoint longer than two seconds turns into a reset. */
    DBGMCU->CR |= DBGMCU_CR_DBG_IWDG_STOP;
}

void bsp_diag_init(void)
{
    capture_reset_cause();
    paint_stack();
    start_watchdog();
}

const char *bsp_diag_reset_cause(void)
{
    return s_reset_cause;
}

uint32_t bsp_diag_stack_size(void)
{
    return (s_stack_top > s_stack_base) ? (s_stack_top - s_stack_base) : 0U;
}

uint32_t bsp_diag_stack_used(void)
{
    uint32_t a = s_stack_mark;

    if (a == 0U) { return 0U; }
    while (a < s_stack_top && *(volatile uint32_t *)a == STACK_PAINT) {
        a += 4U;
    }
    return s_stack_top - a;
}

void bsp_diag_kick(void)
{
    if (s_iwdg_running != 0U) {
        (void)HAL_IWDG_Refresh(&s_iwdg);
    }
}
