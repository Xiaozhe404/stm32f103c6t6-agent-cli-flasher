/* Crash blackbox.
 *
 * A HardFault on this part is otherwise a silent hang. The handler stores the
 * exception frame plus the fault status registers into a .noinit RAM block,
 * resets the MCU, and the next boot prints the record over UART. That single
 * feature is what lets an AI agent answer "where did my change crash?" without
 * a debugger attached.
 */
#ifndef BSP_FAULT_H
#define BSP_FAULT_H

#include <stdint.h>

/* Call once at boot, after bsp_log_init(): prints and clears any old record. */
void bsp_fault_init(void);

/* Called from the HardFault_Handler assembly stub with the exception frame
 * and the EXC_RETURN value (r1) that tells which stack was in use. */
void bsp_fault_handler_c(uint32_t *frame, uint32_t exc_return);

/* Set BSP_FAULT_SELFTEST to prove the blackbox path end to end. */
#ifdef BSP_FAULT_SELFTEST
void bsp_fault_trigger_selftest(void);
#endif

#endif /* BSP_FAULT_H */
