// Types needed to compile CSAORI's protocol declarations on POSIX.
#pragma once
#include <cstdint>
#include <cwchar>
#include <cstdlib>
#define __declspec(x)
#define __cdecl
#define APIENTRY
using BOOL = int32_t;
using HGLOBAL = void*;
using HANDLE = void*;
using HINSTANCE = void*;
using LPVOID = void*;
using DWORD = uint32_t;
using UINT = unsigned int;
using CRITICAL_SECTION = int; // Only an unused declaration in excluded Win32 utilities.
constexpr unsigned int CP_OEMCP = 65001;
#define _wcsnicmp wcsncasecmp
#define wcsicmp wcscasecmp
inline int _wtoi(const wchar_t* text) { return static_cast<int>(wcstol(text,nullptr,10)); }
