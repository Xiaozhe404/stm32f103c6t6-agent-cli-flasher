/* Application layer - the part of the firmware AI agents own.
 *
 * Rule of thumb: Core/ holds startup wiring, App/ holds behaviour, Bsp/ holds
 * board specifics. Nothing here may touch registers directly; go through HAL or
 * through a Bsp driver.
 */
#ifndef APP_H
#define APP_H

void app_init(void);
void app_poll(void);

#endif /* APP_H */
