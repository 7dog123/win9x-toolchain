/*
 * stdarg.h
 *
 * Provides facilities for stepping through a list of function arguments of
 * an unknown number and type.
 *
 * Adapted from mingw-runtime-1.2 (2001) to the mingwrt-5.0.2 era by the
 * Win9x toolchain: GCC 6 ships only a `#include_next <stdarg.h>`
 * forwarding stub (which needs a real stdarg.h later in the include
 * search path) and mingwrt 5.0.2 provides none, so the sysroot installs
 * a self-contained one.  Definitions are expressed with the compiler's
 * __builtin_va_* builtins so they stay valid for the target's va_list
 * ABI.  The __need___va_list protocol used by mingwrt's stdio.h is
 * honored: in that mode only __gnuc_va_list is defined, _STDARG_H_ is
 * left undefined and va_list / va_* stay out of the way.
 *
 * This file is part of the Mingw32 package.  This source code is offered
 * for use in the public domain; you may use, modify or distribute it
 * freely.
 *
 * $Date: 2001/11/29 04:26:33 $
 */

#if !defined(_STDARG_H_) || defined(__need___va_list)

#include <_mingw.h>

/*
 * Don't do any of this stuff for the resource compiler.
 */
#ifndef RC_INVOKED

#ifdef __need___va_list

/* We're only being asked for the va_list carrier, e.g. by mingwrt's
 * stdio.h.  Expose __gnuc_va_list only; leave _STDARG_H_ undefined so
 * va_list and the va_* macros stay out of the way (ANSI C says stdio.h
 * must not define va_list). */
#undef __need___va_list

#ifndef __GNUC_VA_LIST
#define __GNUC_VA_LIST
typedef __builtin_va_list __gnuc_va_list;
#endif

#else /* __need___va_list */

#define _STDARG_H_

/* I was told that Win NT likes this. */
#ifndef _VA_LIST_DEFINED
#define _VA_LIST_DEFINED
#endif

#ifndef _VA_LIST
#define _VA_LIST
typedef __builtin_va_list va_list;
#endif

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap)         __builtin_va_end(ap)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)

#if !defined(__STRICT_ANSI__) || (__STDC_VERSION__ + 0 >= 199901L) || \
    (__cplusplus + 0 >= 201103L)
#define va_copy(dest, src) __builtin_va_copy(dest, src)
#endif
#define __va_copy(dest, src) __builtin_va_copy(dest, src)

#endif /* __need___va_list */

#endif /* Not RC_INVOKED */

#endif /* !_STDARG_H_ || __need___va_list */