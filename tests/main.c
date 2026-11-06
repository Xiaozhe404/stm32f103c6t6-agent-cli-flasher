/* Test entry point. Add one line per new suite. */
#include "framework.h"

void run_ringbuffer_tests(void);

int main(void)
{
    run_ringbuffer_tests();
    return test_summary();
}
