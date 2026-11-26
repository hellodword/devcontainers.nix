/*
 * Workaround for gVisor devpts returning EIO on blocking PTY master reads
 * while numReplicas == 0, before a forked Nix builder opens /dev/pts/<N>.
 *
 * Upstream issue: https://github.com/google/gvisor/issues/13738
 * Upstream fix:   https://github.com/google/gvisor/pull/17244
 *
 * Retire this shim once target hosts run pkgs.gvisor >= 20261130.0.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_TRACKED_FDS 4096
#define FIRST_READ_RETRY_NS 5000000000ULL

static int (*real_posix_openpt)(int flags);
static ssize_t (*real_read)(int fd, void *buf, size_t count);
static int (*real_close)(int fd);
static atomic_uint_least64_t first_byte_deadline_ns[MAX_TRACKED_FDS];

static uint64_t monotonic_ns(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
    return 1;
  }
  return ((uint64_t)ts.tv_sec * 1000000000ULL) + (uint64_t)ts.tv_nsec;
}

static void strip_self_from_ld_preload(void) {
  const char *preload = getenv("LD_PRELOAD");
  if (preload == NULL || preload[0] == '\0') {
    return;
  }
  if (strcmp(preload, SHIM_SO_PATH) == 0) {
    unsetenv("LD_PRELOAD");
    return;
  }
  size_t len = strlen(preload);
  char *copy = malloc(len + 1);
  char *rebuilt = malloc(len + 1);
  if (copy == NULL || rebuilt == NULL) {
    free(copy);
    free(rebuilt);
    return;
  }
  memcpy(copy, preload, len + 1);
  rebuilt[0] = '\0';
  char *saveptr = NULL;
  for (char *tok = strtok_r(copy, ": ", &saveptr); tok != NULL;
       tok = strtok_r(NULL, ": ", &saveptr)) {
    if (strcmp(tok, SHIM_SO_PATH) == 0) {
      continue;
    }
    if (rebuilt[0] != '\0') {
      strcat(rebuilt, ":");
    }
    strcat(rebuilt, tok);
  }
  if (rebuilt[0] == '\0') {
    unsetenv("LD_PRELOAD");
  } else {
    setenv("LD_PRELOAD", rebuilt, 1);
  }
  free(copy);
  free(rebuilt);
}

__attribute__((constructor)) static void init_shim(void) {
  real_posix_openpt = dlsym(RTLD_NEXT, "posix_openpt");
  real_read = dlsym(RTLD_NEXT, "read");
  real_close = dlsym(RTLD_NEXT, "close");
  strip_self_from_ld_preload();
}

int posix_openpt(int flags) {
  if (real_posix_openpt == NULL) {
    real_posix_openpt = dlsym(RTLD_NEXT, "posix_openpt");
  }
  int fd = real_posix_openpt(flags);
  if (fd >= 0 && fd < MAX_TRACKED_FDS) {
    atomic_store_explicit(
        &first_byte_deadline_ns[fd],
        monotonic_ns() + FIRST_READ_RETRY_NS,
        memory_order_relaxed);
  }
  return fd;
}

int close(int fd) {
  if (real_close == NULL) {
    real_close = dlsym(RTLD_NEXT, "close");
  }
  if (fd >= 0 && fd < MAX_TRACKED_FDS) {
    atomic_store_explicit(&first_byte_deadline_ns[fd], 0, memory_order_relaxed);
  }
  return real_close(fd);
}

ssize_t read(int fd, void *buf, size_t count) {
  if (real_read == NULL) {
    real_read = dlsym(RTLD_NEXT, "read");
  }
  if (fd < 0 || fd >= MAX_TRACKED_FDS) {
    return real_read(fd, buf, count);
  }
  uint64_t deadline =
      atomic_load_explicit(&first_byte_deadline_ns[fd], memory_order_relaxed);
  if (deadline == 0) {
    return real_read(fd, buf, count);
  }
  for (;;) {
    ssize_t n = real_read(fd, buf, count);
    if (n > 0) {
      atomic_store_explicit(
          &first_byte_deadline_ns[fd], 0, memory_order_relaxed);
      return n;
    }
    if (n == -1 && errno == EIO) {
      if (monotonic_ns() < deadline) {
        struct timespec req = {.tv_sec = 0, .tv_nsec = 1000000L};
        nanosleep(&req, NULL);
        continue;
      }
      atomic_store_explicit(
          &first_byte_deadline_ns[fd], 0, memory_order_relaxed);
      errno = EIO;
      return -1;
    }
    return n;
  }
}
