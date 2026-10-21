#if defined(__linux__)
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include "CHostPOSIX.h"

int native_host_open_directory(const char *path) {
    return open(path, O_PATH | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
}

int native_host_open_directory_at(int parent, const char *path) {
    return openat(parent, path, O_PATH | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
}
#endif
