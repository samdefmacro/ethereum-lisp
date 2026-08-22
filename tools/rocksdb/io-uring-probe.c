#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <liburing.h>

int main(void) {
  struct io_uring ring;
  unsigned int flags = IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_DEFER_TASKRUN;
  int result = io_uring_queue_init(256, &ring, flags);
  int compatibility_retry = 0;

  if (result == -EINVAL) {
    compatibility_retry = 1;
    result = io_uring_queue_init(256, &ring, 0);
  }
  if (result != 0) {
    fprintf(stderr, "io_uring queue-depth 256 unavailable: %s\n",
            strerror(-result));
    return 1;
  }
  io_uring_queue_exit(&ring);
  printf("io_uring-ready queue-depth=256 compatibility-retry=%s\n",
         compatibility_retry ? "true" : "false");
  return 0;
}
