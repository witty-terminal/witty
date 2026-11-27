#ifndef WITTY_BENCHMARK_SHIMS_H
#define WITTY_BENCHMARK_SHIMS_H

#include <stdint.h>
#include <wchar.h>

#ifndef _WIN32
static inline int witty_benchmark_wcwidth(uint32_t cp) {
    return wcwidth((wchar_t)cp);
}
#endif

static inline void witty_benchmark_do_not_optimize_u64(uint64_t value) {
#if defined(__clang__) || defined(__GNUC__)
    __asm__ __volatile__("" : : "r,m"(value) : "memory");
#else
    volatile uint64_t sink = value;
    (void)sink;
#endif
}

static inline void witty_benchmark_do_not_optimize_ptr(const void *value) {
#if defined(__clang__) || defined(__GNUC__)
    __asm__ __volatile__("" : : "r,m"(value) : "memory");
#else
    volatile const void *sink = value;
    (void)sink;
#endif
}

#endif
