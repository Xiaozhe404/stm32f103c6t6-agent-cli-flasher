/* Debug console: buffered, non-blocking UART logging.
 *
 * The Blue Pill does not break out SWO, so every observation an AI agent can
 * make about the running target comes through here. Three rules follow:
 *   1. Logging must never block the control loop for long -> data is queued in
 *      a ring buffer and pushed out by bsp_log_flush().
 *   2. Formatting must avoid float (%f) - it drags in ~6 KB of code on a 32 KB
 *      part. Log integers and scale them yourself.
 *   3. Lines are machine parsable ("[HB] t=..." ) so tools/verify.ps1 can
 *      assert on them.
 */
#ifndef BSP_LOG_H
#define BSP_LOG_H

#include <stddef.h>
#include <stdint.h>

void   bsp_log_init(void);

/* Queue raw bytes. Returns bytes accepted (0 when the queue is full). */
size_t bsp_log_write(const char *data, size_t len);

/* Push queued bytes to the UART. Call it from the main loop. */
void   bsp_log_flush(void);

/* Queue a formatted line (max 128 bytes, no float support). */
int    bsp_log_printf(const char *fmt, ...);

/* Bytes lost because the queue was full - a sanity metric for timing bugs. */
uint32_t bsp_log_dropped(void);

#endif /* BSP_LOG_H */
