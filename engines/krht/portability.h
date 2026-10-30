// Local POSIX adapters for the original krht load/request/unload implementation.
#pragma once
#include <tcl.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>
using namespace std;
using BOOL = int32_t;
using HGLOBAL = void*;
#define __cdecl
#define GMEM_FIXED 0
inline void GlobalFree(void* value) { free(value); }
inline void* GlobalAlloc(int, size_t length) { return malloc(length); }
static Tcl_Interp* interp = nullptr;
static Tcl_Obj* cmd = nullptr;
static Tcl_Obj* arg = nullptr;
