// This file is a part of Julia. License is MIT: https://julialang.org/license

#include "platform.h"

#ifndef JL_OPTIONS_H
#define JL_OPTIONS_H

// Options in here are NOT allowed to affect the jlapi, since that would require this header to be installed

// Build-time options for debugging, tweaking, and selecting alternative
// implementations of core features.

#define N_CALL_CACHE 4096

// object layout options ------------------------------------------------------

// The data for an array this size or below will be allocated within the
// Array object. If the array outgrows that space, it will be wasted.
#define ARRAY_INLINE_NBYTES (2048*sizeof(void*))

// Arrays at least this size will get larger alignment (JL_CACHE_BYTE_ALIGNMENT).
// Must be bigger than GC_MAX_SZCLASS.
#define ARRAY_CACHE_ALIGN_THRESHOLD 2048

// codegen options ------------------------------------------------------------

// (Experimental) Use MCJIT ELF, even where it's not the native format
//#define FORCE_ELF

// with KEEP_BODIES, we keep LLVM function bodies around for later debugging
// #define KEEP_BODIES

// delete julia IR for non-inlineable functions after they're codegen'd
#define JL_DELETE_NON_INLINEABLE 1

// GC options -----------------------------------------------------------------

// debugging options

// with MEMDEBUG, every object is allocated explicitly with malloc, and
// filled with 0xbb before being freed. this helps tools like valgrind
// catch invalid accesses.
// #define MEMDEBUG

// with MEMFENCE, the object pool headers are verified during sweep
// to help detect corruption due to fence-post write errors
// #define MEMFENCE


// GC_VERIFY force a full verification gc along with every quick gc to ensure no
// reachable memory is freed
#ifndef GC_VERIFY
#ifdef GC_DEBUG_ENV
#define GC_VERIFY
#else
// It is recommended to use the WITH_GC_VERIFY make option to turn on this
// option. Keep the document here before a better build system is ready.
// #define GC_VERIFY
#endif
#endif

// GC_ASSERT_PARENT_VALIDITY will check whether an object is valid when **pushing**
// it to the mark queue
// #define GC_ASSERT_PARENT_VALIDITY

// profiling options

// GC_FINAL_STATS prints total GC stats at exit
// #define GC_FINAL_STATS

// MEMPROFILE prints pool and large objects summary statistics after every GC
// #define MEMPROFILE

// GC_TIME prints time taken by each phase of GC
// #define GC_TIME

// pool allocator configuration options

// GC_SMALL_PAGE allocates objects in 4k pages
// #define GC_SMALL_PAGE


// method dispatch profiling --------------------------------------------------

// turn type inference on/off. this is for internal debugging only, and must be
// turned on for all practical purposes.
#define ENABLE_INFERENCE

// print all signatures type inference is invoked on
//#define TRACE_INFERENCE

// print all generic method dispatches (excludes inlined and specialized call
// sites). this generally prints too much output to be useful.
//#define JL_TRACE

// profile generic (not inlined or specialized) calls to each function
//#define JL_GF_PROFILE


// task options ---------------------------------------------------------------

// select whether to allow the COPY_STACKS stack switching implementation
#define COPY_STACKS
// select whether to use COPY_STACKS for new Tasks by default
//#define ALWAYS_COPY_STACKS

// When not using COPY_STACKS the task-system is less memory efficient so
// you probably want to choose a smaller default stack size (factor of 8-10)
#if !defined(JL_STACK_SIZE)
#if defined(_COMPILER_ASAN_ENABLED_) || defined(_COMPILER_MSAN_ENABLED_)
#define JL_STACK_SIZE (64*1024*1024)
#elif defined(_P64)
#define JL_STACK_SIZE (8*1024*1024)
#else
#define JL_STACK_SIZE (2*1024*1024)
#endif
#endif

// allow a suspended Task to restart on a different thread
#define MIGRATE_TASKS

// threading options ----------------------------------------------------------

// controls for when threads sleep
#define THREAD_SLEEP_THRESHOLD_NAME     "JULIA_THREAD_SLEEP_THRESHOLD"
#define DEFAULT_THREAD_SLEEP_THRESHOLD  100*1000 // nanoseconds (100us)

// defaults for # threads
#define NUM_THREADS_NAME                "JULIA_NUM_THREADS"
#ifndef JULIA_NUM_THREADS
#  define JULIA_NUM_THREADS 1
#endif

// threadpools specification
#define THREADPOOLS_NAME                "JULIA_THREADPOOLS"

// GC threads
#define NUM_GC_THREADS_NAME             "JULIA_NUM_GC_THREADS"

// heap size hint
#define HEAP_SIZE_HINT                  "JULIA_HEAP_SIZE_HINT"

// affinitization behavior
#define MACHINE_EXCLUSIVE_NAME          "JULIA_EXCLUSIVE"
#define DEFAULT_MACHINE_EXCLUSIVE       0

// sanitizer defaults ---------------------------------------------------------

// Automatically enable MEMDEBUG and KEEP_BODIES for the sanitizers
#if defined(_COMPILER_ASAN_ENABLED_)
// No MEMDEBUG for msan - we just poison allocated memory directly.
#define MEMDEBUG
#endif

#if defined(_COMPILER_ASAN_ENABLED_) || defined(_COMPILER_MSAN_ENABLED_)
#define KEEP_BODIES
#endif

// TSAN doesn't like COPY_STACKS
#if defined(_COMPILER_TSAN_ENABLED_) && defined(COPY_STACKS)
#undef COPY_STACKS
#endif

// Memory sanitizer needs TLS, which llvm only supports for the small memory model
#if defined(_COMPILER_MSAN_ENABLED_)
// todo: fix the llvm MemoryManager to work with small memory model
#endif

#endif
