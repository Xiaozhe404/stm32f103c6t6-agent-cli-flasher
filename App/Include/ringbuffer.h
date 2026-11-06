/* Fixed-capacity byte ring buffer.
 *
 * Deliberately hardware free: this file must stay compilable by a host
 * compiler so tests/ can exercise it without a board (see tools/test.ps1).
 */
#ifndef RINGBUFFER_H
#define RINGBUFFER_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t *buf;
    size_t   size;    /* capacity in bytes, at least 2 */
    size_t   head;    /* next write index */
    size_t   tail;    /* next read index */
    uint32_t dropped; /* bytes rejected because the buffer was full */
} ringbuffer_t;

/* Returns 0 on success, -1 if size < 2 or storage is NULL. */
int  rb_init(ringbuffer_t *rb, uint8_t *storage, size_t size);

/* Returns the number of bytes actually stored (may be less than len). */
size_t rb_write(ringbuffer_t *rb, const uint8_t *data, size_t len);

/* Returns the number of bytes copied into out. */
size_t rb_read(ringbuffer_t *rb, uint8_t *out, size_t len);

size_t rb_available(const ringbuffer_t *rb);
size_t rb_free_space(const ringbuffer_t *rb);
uint32_t rb_dropped(const ringbuffer_t *rb);
void rb_reset(ringbuffer_t *rb);

#endif /* RINGBUFFER_H */
