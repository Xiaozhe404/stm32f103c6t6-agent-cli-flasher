/* Board bring-up that must happen before anything else.
 *
 * Kept separate from the application so the LED works even if the clock tree or
 * the console fails to start - Error_Handler() blinks it.
 */
#ifndef BSP_BOARD_H
#define BSP_BOARD_H

void bsp_board_init(void);

#endif /* BSP_BOARD_H */
