/* Wrapper so MoonBit can call libc system(3) without a symbol clash. */
#include <stdlib.h>

int moonsight_system(const char *cmd) {
  return system(cmd);
}
