#ifndef WITTY_POSIX_POLL_H
#define WITTY_POSIX_POLL_H

#include <poll.h>

static inline int witty_posix_poll(struct pollfd *fds, unsigned int count, int timeout) {
    return poll(fds, count, timeout);
}

#endif
