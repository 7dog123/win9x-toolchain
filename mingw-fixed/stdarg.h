/*
 * Self-contained <stdarg.h> for the Win9x cross sysroot.
 *
 * CC (GCC 6) only ships a forwarding stub (gcc/include/stdarg.h does
 * `#include_next <stdarg.h>`) that needs a real stdarg.h later in the
 * include search path. Mingwrt 5.0.2 provides none, and w32api compiles
 * its import-lib C stubs with -nostdinc, so the sysroot needs its own.
 * Implemented purely in terms of the compiler builtins, so it does not
 * depend on the target va_list ABI, and honors the __need___va_list
 * protocol used by mingwrt's stdio.h.
 */
#ifndef _STDARG_H
#ifndef __need___va_list
#define _STDARG_H
#endif
#undef __need___va_list

#ifndef __GNUC_VA_LIST
#define __GNUC_VA_LIST
typedef __builtin_va_list __gnuc_va_list;
#endif

#ifdef _STDARG_H
typedef __builtin_va_list va_list;

#define va_start(ap, param) __builtin_va_start(ap, param)
#define va_end(ap)          __builtin_va_end(ap)
#define va_arg(ap, type)    __builtin_va_arg(ap, type)

#if !defined(__STRICT_ANSI__) || (__STDC_VERSION__ + 0 >= 199901L) || \
    (__cplusplus + 0 >= 201103L)
#define va_copy(dest, src) __builtin_va_copy(dest, src)
#endif
#define __va_copy(dest, src) __builtin_va_copy(dest, src)

#endif /* _STDARG_H */
#endif /* _STDARG_H */