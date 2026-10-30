// Ourin macOS port: the small Win32 surface used by pinned nashi SHIORI.
// This is a POSIX adaptation, not a Windows DLL execution layer.
#pragma once
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

using UINT = unsigned int;
using DWORD = uint32_t;
using WORD = uint16_t;
using BOOL = int;
using HANDLE = void*;
using HGLOBAL = void*;
using HMODULE = void*;
using LPCWSTR = const wchar_t*;
using LPCVOID = const void*;
using CRITICAL_SECTION = std::recursive_mutex;
union LARGE_INTEGER { struct { uint32_t LowPart; int32_t HighPart; }; int64_t QuadPart; };
struct SYSTEMTIME { WORD wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds; };
struct FILETIME { DWORD dwLowDateTime, dwHighDateTime; };
struct WIN32_FILE_ATTRIBUTE_DATA {
    DWORD dwFileAttributes; FILETIME ftCreationTime, ftLastAccessTime, ftLastWriteTime;
    DWORD nFileSizeHigh, nFileSizeLow;
};
struct MEMORY_BASIC_INFORMATION { void* AllocationBase; };
#define __cdecl
#define __declspec(attribute)
#define WINAPI
#define TRUE 1
#define FALSE 0
#define CP_UTF8 65001
// POSIX module load paths are UTF-8; explicit source/wire CP932 remains 932.
#define CP_ACP 65001
#define GENERIC_READ 0x80000000u
#define GENERIC_WRITE 0x40000000u
#define FILE_APPEND_DATA 4
#define FILE_SHARE_READ 1
#define OPEN_EXISTING 3
#define OPEN_ALWAYS 4
#define CREATE_ALWAYS 2
#define FILE_ATTRIBUTE_NORMAL 0x80
#define FILE_ATTRIBUTE_DIRECTORY 0x10
#define INVALID_FILE_ATTRIBUTES 0xffffffffu
#define INVALID_HANDLE_VALUE reinterpret_cast<HANDLE>(static_cast<intptr_t>(-1))
#define FILE_END 2
#define GMEM_FIXED 0
#define GetFileExInfoStandard 0
#define WAIT_OBJECT_0 0
#define WAIT_TIMEOUT 258
#define GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS 4
#define MAX_PATH 4096

template <size_t N, typename... Args>
int sprintf_s(char (&buffer)[N], const char* format, Args... args) {
    return std::snprintf(buffer, N, format, args...);
}
template <size_t N>
int strcpy_s(char (&buffer)[N], const char* source) {
    size_t length = std::strlen(source);
    if (length >= N) { buffer[0] = '\0'; return 34; }
    std::memcpy(buffer, source, length + 1); return 0;
}

int MultiByteToWideChar(UINT, DWORD, const char*, int, wchar_t*, int);
int WideCharToMultiByte(UINT, DWORD, const wchar_t*, int, char*, int, const char*, BOOL*);
HANDLE CreateFileW(const wchar_t*, DWORD, DWORD, void*, DWORD, DWORD, HANDLE);
BOOL GetFileSizeEx(HANDLE, LARGE_INTEGER*);
BOOL ReadFile(HANDLE, void*, DWORD, DWORD*, void*);
BOOL WriteFile(HANDLE, const void*, DWORD, DWORD*, void*);
DWORD SetFilePointer(HANDLE, long, void*, DWORD);
BOOL CloseHandle(HANDLE);
DWORD GetFileAttributesW(const wchar_t*);
BOOL GetFileAttributesExW(const wchar_t*, int, WIN32_FILE_ATTRIBUTE_DATA*);
DWORD GetTickCount();
DWORD GetCurrentProcessId();
BOOL QueryPerformanceCounter(LARGE_INTEGER*);
void GetLocalTime(SYSTEMTIME*);
inline HGLOBAL GlobalAlloc(UINT, size_t length) { return std::malloc(length); }
inline HGLOBAL GlobalFree(HGLOBAL value) { std::free(value); return nullptr; }
inline void InitializeCriticalSection(CRITICAL_SECTION*) {}
inline void DeleteCriticalSection(CRITICAL_SECTION*) {}
inline void EnterCriticalSection(CRITICAL_SECTION* lock) { lock->lock(); }
inline void LeaveCriticalSection(CRITICAL_SECTION* lock) { lock->unlock(); }
inline long InterlockedIncrement(long* value) { return __sync_add_and_fetch(value, 1); }
inline long InterlockedDecrement(long* value) { return __sync_sub_and_fetch(value, 1); }
HMODULE LoadLibraryW(const wchar_t*);
void* GetProcAddress(HMODULE, const char*);
BOOL FreeLibrary(HMODULE);
DWORD GetLastError();
BOOL GetModuleHandleExW(DWORD, LPCWSTR, HMODULE*);
using ThreadEntry = DWORD (*)(void*);
HANDLE CreateThread(void*, size_t, ThreadEntry, void*, DWORD, DWORD*);
DWORD WaitForSingleObject(HANDLE, DWORD);
[[noreturn]] void FreeLibraryAndExitThread(HMODULE, DWORD);
void Sleep(DWORD);
size_t VirtualQuery(LPCVOID, MEMORY_BASIC_INFORMATION*, size_t);
DWORD GetModuleFileNameW(HMODULE, wchar_t*, DWORD);
