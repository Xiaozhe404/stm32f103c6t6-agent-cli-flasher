#include "framework.h"

#include <stdio.h>

static int s_cases;
static int s_failures;

void test_begin(const char *name)
{
    s_cases++;
    printf("[ RUN  ] %s\n", name);
}

void test_check(int condition, const char *expr, const char *file, int line)
{
    if (condition == 0) {
        s_failures++;
        printf("[ FAIL ] %s:%d  %s\n", file, line, expr);
    }
}

int test_summary(void)
{
    printf("[ DONE ] %d case(s), %d failure(s)\n", s_cases, s_failures);
    return (s_failures == 0) ? 0 : 1;
}
