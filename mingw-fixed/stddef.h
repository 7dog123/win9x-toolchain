/*
 * Self-contained <stddef.h> for the Win9x cross sysroot.
 *
 * CC (GCC 6) only ships a forwarding stub (gcc/include/stddef.h does
 * `#include_next <stddef.h>`) that needs a real stddef.h later in the
 * include search path. Mingwrt 5.0.2 provides none, and w32api compiles
 * its import-lib C stubs with -nostdinc, so the sysroot needs its own.
 * Built on the compiler's __PTRDIFF_TYPE__/__SIZE_TYPE__ macros and
 * honoring the _WCHAR_T_DEFINED/_WCHAR_T_ guards used by w32api's
 * winnt.h (which defines wchar_t itself).
 */
#ifndef _STDDEF_H
#define _STDDEF_H

#if defined(__need_ptrdiff_t) || defined(_STDDEF_H)
#ifndef _PTRDIFF_T_DEFINED
#define _PTRDIFF_T_DEFINED
#ifndef _PTRDIFF_T_
#define _PTRDIFF_T_
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#endif
#endif
#endif

#if defined(__need_size_t) || defined(_STDDEF_H)
#ifndef _SIZE_T_DEFINED
#define _SIZE_T_DEFINED
#ifndef _SIZE_T_
#define _SIZE_T_
typedef __SIZE_TYPE__ size_t;
#endif
#endif
#endif

#if defined(__need_wchar_t) || defined(_STDDEF_H)
#ifndef _WCHAR_T_DEFINED
#define _WCHAR_T_DEFINED
#ifndef _WCHAR_T_
#define _WCHAR_T_
#ifndef __cplusplus
typedef unsigned short wchar_t;
#endif
#endif
#endif
#endif

#undef __need_size_t
#undef __need_ptrdiff_t
#undef __need_wchar_t

#ifdef _STDDEF_H
#ifdef __cplusplus
#define NULL __null
#else
#define NULL ((void *)0)
#endif

#define offsetof(type, member) __builtin_offsetof(type, member)
#endif /* _STDDEF_H */

#endif /* _STDDEF_H */