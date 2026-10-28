#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 1
#define HAS_PRINTF 1

typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef unsigned int   ee_u32;
typedef unsigned char  ee_u8;
typedef ee_u32         ee_ptr_int;
typedef size_t         ee_size_t;

#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD  MEM_STATIC
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0

typedef uint32_t CORE_TICKS;
#define TIMER_RES_DIVIDER 1
#define EE_TICKS_PER_SEC 100000000 // 100 MHz reference clock (10 ns)

#define COMPILER_VERSION "GCC 10.2.0 (RV32I)"
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS "-O2 -march=rv32i_zicsr_zicntr -mabi=ilp32"
#endif
#define MEM_LOCATION "On-Chip AHB RAM (0x80000000)"

int printf(const char *fmt, ...);
#define ee_printf printf

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#if (SEED_METHOD == SEED_VOLATILE)
  #define PERFORMANCE_RUN 1
#endif

#endif // CORE_PORTME_H
