#include "ringbuffer.h"

int rb_init(ringbuffer_t *rb, uint8_t *storage, size_t size)
{
    if (rb == NULL || storage == NULL || size < 2U) {
        return -1;
    }
    rb->buf     = storage;
    rb->size    = size;
    rb->head    = 0U;
    rb->tail    = 0U;
    rb->dropped = 0U;
    return 0;
}

size_t rb_write(ringbuffer_t *rb, const uint8_t *data, size_t len)
{
    size_t written = 0U;

    if (rb == NULL || data == NULL) {
        return 0U;
    }

    while (written < len) {
        size_t next = rb->head + 1U;
        if (next >= rb->size) {
            next = 0U;
        }
        if (next == rb->tail) {
            /* Full: account for every byte we could not store. */
            rb->dropped += (uint32_t)(len - written);
            break;
        }
        rb->buf[rb->head] = data[written];
        rb->head = next;
        written++;
    }
    return written;
}

size_t rb_read(ringbuffer_t *rb, uint8_t *out, size_t len)
{
    size_t read = 0U;

    if (rb == NULL || out == NULL) {
        return 0U;
    }

    while (read < len && rb->tail != rb->head) {
        out[read] = rb->buf[rb->tail];
        rb->tail++;
        if (rb->tail >= rb->size) {
            rb->tail = 0U;
        }
        read++;
    }
    return read;
}

size_t rb_available(const ringbuffer_t *rb)
{
    if (rb == NULL) {
        return 0U;
    }
    if (rb->head >= rb->tail) {
        return rb->head - rb->tail;
    }
    return rb->size - rb->tail + rb->head;
}

size_t rb_free_space(const ringbuffer_t *rb)
{
    if (rb == NULL) {
        return 0U;
    }
    /* One slot is always kept empty to tell full from empty. */
    return (rb->size - 1U) - rb_available(rb);
}

uint32_t rb_dropped(const ringbuffer_t *rb)
{
    return (rb == NULL) ? 0U : rb->dropped;
}

void rb_reset(ringbuffer_t *rb)
{
    if (rb != NULL) {
        rb->head = 0U;
        rb->tail = 0U;
    }
}
