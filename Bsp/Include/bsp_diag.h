/* Boot diagnostics: why did we start, how much stack is left, and the watchdog
 * that turns a silent hang into a visible reset.
 *
 * The crash blackbox in bsp_fault.c only catches exceptions. A firmware that
 * spins in a while(1), or blocks forever on a peripheral flag, raises nothing -
 * it just stops. The IWDG is what makes that visible: the board resets and the
 * next boot reports reset=IWDG.
 */
#ifndef BSP_DIAG_H
#define BSP_DIAG_H

#include <stdint.h>

/* Call once, before anything that can block. Captures the reset cause from
 * RCC_CSR (and clears it), paints the unused stack, and starts the IWDG. */
void bsp_diag_init(void);

/* Human readable reset cause: "POR", "PIN|POR", "IWDG", "SFT", "NONE", ... */
const char *bsp_diag_reset_cause(void);

/* Bytes of stack that have been touched since boot, and total stack size.
 * Both are 0 when the linker did not provide the STACKS region. */
uint32_t bsp_diag_stack_used(void);
uint32_t bsp_diag_stack_size(void);

/* Feed the watchdog. Call once per main loop iteration. */
void bsp_diag_kick(void);

#endif /* BSP_DIAG_H */
