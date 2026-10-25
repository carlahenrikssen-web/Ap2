#ifndef COMPAT_EXTRA_H
#define COMPAT_EXTRA_H
#include <stdint.h>
#include <stdlib.h>
static __inline int setenv(const char *name, const char *val, int overwrite) {
    (void)overwrite;
    return _putenv_s(name, val);
}
#endif
