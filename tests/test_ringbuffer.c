#include "framework.h"
#include "ringbuffer.h"

#include <string.h>

static uint8_t g_storage[8];

static void init_default(ringbuffer_t *rb)
{
    (void)memset(&g_storage[0], 0, sizeof(g_storage));
    TEST_ASSERT_EQ(0, rb_init(rb, g_storage, sizeof(g_storage)));
}

static void starts_empty(void)
{
    ringbuffer_t rb;
    init_default(&rb);
    TEST_ASSERT_EQ(0, rb_available(&rb));
    TEST_ASSERT_EQ(7, rb_free_space(&rb));   /* one slot stays reserved */
}

static void rejects_bad_init(void)
{
    ringbuffer_t rb;
    TEST_ASSERT(rb_init(&rb, g_storage, 1) != 0);
    TEST_ASSERT(rb_init(&rb, NULL, sizeof(g_storage)) != 0);
    TEST_ASSERT(rb_init(NULL, g_storage, sizeof(g_storage)) != 0);
}

static void keeps_fifo_order(void)
{
    ringbuffer_t rb;
    uint8_t out[8] = {0};
    init_default(&rb);

    TEST_ASSERT_EQ(3, rb_write(&rb, (const uint8_t *)"abc", 3));
    TEST_ASSERT_EQ(3, rb_available(&rb));
    TEST_ASSERT_EQ(3, rb_read(&rb, out, sizeof(out)));
    TEST_ASSERT_EQ(0, memcmp(out, "abc", 3));
    TEST_ASSERT_EQ(0, rb_available(&rb));
}

static void wraps_around(void)
{
    ringbuffer_t rb;
    uint8_t out[8] = {0};
    init_default(&rb);

    TEST_ASSERT_EQ(5, rb_write(&rb, (const uint8_t *)"12345", 5));
    TEST_ASSERT_EQ(5, rb_read(&rb, out, 5));

    /* Now head/tail are near the end; this write must wrap. */
    TEST_ASSERT_EQ(4, rb_write(&rb, (const uint8_t *)"wxyz", 4));
    TEST_ASSERT_EQ(4, rb_read(&rb, out, sizeof(out)));
    TEST_ASSERT_EQ(0, memcmp(out, "wxyz", 4));
}

static void reports_overflow(void)
{
    ringbuffer_t rb;
    init_default(&rb);

    /* Capacity 8 keeps 7 usable bytes. */
    TEST_ASSERT_EQ(7, rb_write(&rb, (const uint8_t *)"1234567", 7));
    TEST_ASSERT_EQ(0, rb_write(&rb, (const uint8_t *)"89", 2));
    TEST_ASSERT_EQ(2, rb_dropped(&rb));
    TEST_ASSERT_EQ(0, rb_free_space(&rb));
}

static void partial_read_keeps_rest(void)
{
    ringbuffer_t rb;
    uint8_t out[8] = {0};
    init_default(&rb);

    TEST_ASSERT_EQ(4, rb_write(&rb, (const uint8_t *)"abcd", 4));
    TEST_ASSERT_EQ(2, rb_read(&rb, out, 2));
    TEST_ASSERT_EQ(0, memcmp(out, "ab", 2));
    TEST_ASSERT_EQ(2, rb_available(&rb));

    TEST_ASSERT_EQ(2, rb_read(&rb, out, sizeof(out)));
    TEST_ASSERT_EQ(0, memcmp(out, "cd", 2));
}

static void reset_clears_counters(void)
{
    ringbuffer_t rb;
    init_default(&rb);

    TEST_ASSERT_EQ(4, rb_write(&rb, (const uint8_t *)"abcd", 4));
    rb_reset(&rb);
    TEST_ASSERT_EQ(0, rb_available(&rb));
    TEST_ASSERT_EQ(7, rb_free_space(&rb));
}

void run_ringbuffer_tests(void)
{
    TEST_CASE(starts_empty);
    TEST_CASE(rejects_bad_init);
    TEST_CASE(keeps_fifo_order);
    TEST_CASE(wraps_around);
    TEST_CASE(reports_overflow);
    TEST_CASE(partial_read_keeps_rest);
    TEST_CASE(reset_clears_counters);
}
