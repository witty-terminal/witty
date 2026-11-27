#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <windows.h>

static inline bool witty_pty_peek(HANDLE handle, uint32_t *available) {
    DWORD count = 0;
    bool ok = PeekNamedPipe(handle, NULL, 0, NULL, &count, NULL);
    *available = count;
    return ok;
}
