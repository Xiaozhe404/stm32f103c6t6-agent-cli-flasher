#include "bsp_fault.h"
#include "bsp_log.h"

#include "stm32f1xx.h"

#define FAULT_MAGIC  0x4641554CU   /* 'FAUL' */

typedef struct {
    uint32_t magic;
    uint32_t count;
    uint32_t r0;
    uint32_t r1;
    uint32_t r2;
    uint32_t r3;
    uint32_t r12;
    uint32_t lr;
    uint32_t pc;
    uint32_t xpsr;
    uint32_t exc_return;
    uint32_t cfsr;
    uint32_t hfsr;
    uint32_t mmfar;
    uint32_t bfar;
    uint32_t sp;
} fault_record_t;

/* Lives in the UNINIT scatter region: never zeroed by the C startup, so it
 * survives NVIC_SystemReset(). See cmake/stm32f103c6tx.sct.
 *
 * The section has to be ZI (SHT_NOBITS). armlink only skips initialization for
 * ZI output sections inside an UNINIT region; a section() attribute would make
 * armclang emit an RW section whose all-zero contents get copied from flash on
 * every boot, silently wiping the record. */
#pragma clang section bss = ".noinit"
static fault_record_t s_record __attribute__((used));
#pragma clang section bss = ""

static const char *const k_mmfsr[8] = {
    "IACCVIOL", "DACCVIOL", "", "MUNSTKERR", "MSTKERR", "MLSPERR", "", "MMARVALID"
};

static const char *const k_bfsr[8] = {
    "IBUSERR", "PRECISERR", "IMPRECISERR", "UNSTKERR", "STKERR", "LSPERR", "", "BFARVALID"
};

static const char *const k_ufsr[16] = {
    "UNDEFINSTR", "INVSTATE", "INVPC", "NOCP", "", "", "", "",
    "UNALIGNED", "DIVBYZERO", "", "", "", "", "", ""
};

static void report_bits(const char *group, uint32_t value, uint32_t shift,
                        const char *const *names, uint32_t count)
{
    uint32_t bit;

    for (bit = 0U; bit < count; bit++) {
        if (((value >> (shift + bit)) & 1U) != 0U && names[bit][0] != '\0') {
            bsp_log_printf("[FAULT] cause=%s.%s\r\n", group, names[bit]);
        }
    }
}

static void fault_report(const fault_record_t *r)
{
    bsp_log_printf("[FAULT] crash detected count=%lu\r\n", (unsigned long)r->count);
    bsp_log_printf("[FAULT] pc=0x%08lx lr=0x%08lx xpsr=0x%08lx exc_return=0x%08lx\r\n",
                   (unsigned long)r->pc, (unsigned long)r->lr,
                   (unsigned long)r->xpsr, (unsigned long)r->exc_return);
    bsp_log_printf("[FAULT] cfsr=0x%08lx hfsr=0x%08lx mmfar=0x%08lx bfar=0x%08lx\r\n",
                   (unsigned long)r->cfsr, (unsigned long)r->hfsr,
                   (unsigned long)r->mmfar, (unsigned long)r->bfar);
    bsp_log_printf("[FAULT] r0=0x%08lx r1=0x%08lx r2=0x%08lx r3=0x%08lx r12=0x%08lx\r\n",
                   (unsigned long)r->r0, (unsigned long)r->r1, (unsigned long)r->r2,
                   (unsigned long)r->r3, (unsigned long)r->r12);
    bsp_log_printf("[FAULT] sp=0x%08lx\r\n", (unsigned long)r->sp);

    report_bits("MMFSR", r->cfsr, 0U, k_mmfsr, 8U);
    report_bits("BFSR", r->cfsr, 8U, k_bfsr, 8U);
    report_bits("UFSR", r->cfsr, 16U, k_ufsr, 16U);

    if ((r->hfsr & (1UL << 1)) != 0U) {
        bsp_log_printf("[FAULT] cause=HFSR.VECTTBL\r\n");
    }
    if ((r->hfsr & (1UL << 30)) != 0U) {
        bsp_log_printf("[FAULT] cause=HFSR.FORCED\r\n");
    }
}

void bsp_fault_init(void)
{
    if (s_record.magic != FAULT_MAGIC) {
        s_record.count = 0U;
        return;
    }

    fault_report(&s_record);
    s_record.magic = 0U;   /* report once */
}

void bsp_fault_handler_c(uint32_t *frame, uint32_t exc_return)
{
    s_record.count++;
    s_record.magic      = FAULT_MAGIC;
    s_record.r0         = frame[0];
    s_record.r1         = frame[1];
    s_record.r2         = frame[2];
    s_record.r3         = frame[3];
    s_record.r12        = frame[4];
    s_record.lr         = frame[5];
    s_record.pc         = frame[6];
    s_record.xpsr       = frame[7];
    s_record.exc_return = exc_return;
    s_record.cfsr       = SCB->CFSR;
    s_record.hfsr       = SCB->HFSR;
    s_record.mmfar      = SCB->MMFAR;
    s_record.bfar       = SCB->BFAR;
    s_record.sp         = (uint32_t)(uintptr_t)frame;

    NVIC_SystemReset();
}

/* Verify the blackbox end to end by faulting on purpose. */
#ifdef BSP_FAULT_SELFTEST
void bsp_fault_trigger_selftest(void)
{
    __builtin_trap();   /* emits UDF -> UsageFault -> HardFault */
}
#endif

__attribute__((naked)) void HardFault_Handler(void)
{
    __asm volatile(
        "tst   lr, #4              \n"
        "ite   eq                  \n"
        "mrseq r0, msp             \n"
        "mrsne r0, psp             \n"
        "mov   r1, lr              \n"
        "b.w   bsp_fault_handler_c \n"
    );
}
