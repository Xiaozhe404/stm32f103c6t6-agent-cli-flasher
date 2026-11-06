/* Minimal host-side test framework.
 *
 * Why not Unity / CMock: this project has to stay buildable with nothing but a
 * host GCC, and the whole framework is 20 lines. Swap it out later if the test
 * suite grows; the macros are named so the change stays mechanical.
 */
#ifndef TEST_FRAMEWORK_H
#define TEST_FRAMEWORK_H

void test_begin(const char *name);
void test_check(int condition, const char *expr, const char *file, int line);
int  test_summary(void);

#define TEST_ASSERT(cond)     test_check((cond) ? 1 : 0, #cond, __FILE__, __LINE__)
#define TEST_ASSERT_EQ(a, b)  test_check(((a) == (b)) ? 1 : 0, #a " == " #b, __FILE__, __LINE__)
#define TEST_CASE(fn)         do { test_begin(#fn); fn(); } while (0)

#endif /* TEST_FRAMEWORK_H */
