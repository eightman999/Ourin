#include "windows.h"
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <dlfcn.h>
#include <fcntl.h>
#include <iconv.h>
#include <memory>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {
std::string convert(const void* input, size_t bytes, const char* from, const char* to) {
    iconv_t codec = iconv_open(to, from);
    if (codec == reinterpret_cast<iconv_t>(-1)) return {};
    std::string result(bytes * 4 + 32, '\0');
    char* source = const_cast<char*>(static_cast<const char*>(input));
    char* target = &result[0];
    size_t available = result.size();
    bool ok = iconv(codec, &source, &bytes, &target, &available) != static_cast<size_t>(-1) && bytes == 0;
    iconv_close(codec);
    if (!ok) return {};
    result.resize(result.size() - available);
    return result;
}
std::string filename(const wchar_t* path) {
    std::string result = convert(path, std::wcslen(path) * sizeof(wchar_t), "UTF-32LE", "UTF-8");
    for (char& byte : result) if (byte == '\\') byte = '/';
    return result;
}
struct ThreadState {
    std::mutex mutex;
    std::condition_variable complete;
    bool done = false;
};
struct Handle {
    int file = -1;
    std::shared_ptr<ThreadState> thread;
};
struct ThreadCall { ThreadEntry entry; void* argument; std::shared_ptr<ThreadState> state; };
void completed(void* pointer) {
    std::unique_ptr<ThreadCall> call(static_cast<ThreadCall*>(pointer));
    std::lock_guard<std::mutex> guard(call->state->mutex);
    call->state->done = true;
    call->state->complete.notify_all();
}
void* threadMain(void* pointer) {
    ThreadCall* call = static_cast<ThreadCall*>(pointer);
    pthread_cleanup_push(completed, pointer);
    call->entry(call->argument);
    pthread_cleanup_pop(1);
    return nullptr;
}
}

int MultiByteToWideChar(UINT cp, DWORD, const char* value, int size, wchar_t* out, int capacity) {
    if (!value || size <= 0) return 0;
    std::string result = convert(value, static_cast<size_t>(size), cp == CP_UTF8 ? "UTF-8" : "CP932", "UTF-32LE");
    size_t length = result.size() / sizeof(wchar_t);
    if (out) { if (capacity < 0 || static_cast<size_t>(capacity) < length) return 0; std::memcpy(out, result.data(), result.size()); }
    return static_cast<int>(length);
}
int WideCharToMultiByte(UINT cp, DWORD, const wchar_t* value, int size, char* out, int capacity, const char*, BOOL*) {
    if (!value || size <= 0) return 0;
    std::string result = convert(value, static_cast<size_t>(size) * sizeof(wchar_t), "UTF-32LE", cp == CP_UTF8 ? "UTF-8" : "CP932");
    if (out) { if (capacity < 0 || static_cast<size_t>(capacity) < result.size()) return 0; std::memcpy(out, result.data(), result.size()); }
    return static_cast<int>(result.size());
}
HANDLE CreateFileW(const wchar_t* path, DWORD access, DWORD, void*, DWORD disposition, DWORD, HANDLE) {
    int flags = access == GENERIC_READ ? O_RDONLY : O_WRONLY;
    if (disposition == CREATE_ALWAYS) flags |= O_CREAT | O_TRUNC;
    if (disposition == OPEN_ALWAYS) flags |= O_CREAT;
    if (access == FILE_APPEND_DATA) flags |= O_APPEND;
    int fd = open(filename(path).c_str(), flags | O_CLOEXEC, 0666);
    if (fd < 0) return INVALID_HANDLE_VALUE;
    Handle* handle = new Handle(); handle->file = fd; return handle;
}
BOOL GetFileSizeEx(HANDLE value, LARGE_INTEGER* size) {
    struct stat info; if (fstat(static_cast<Handle*>(value)->file, &info)) return FALSE;
    size->QuadPart = info.st_size; return TRUE;
}
BOOL ReadFile(HANDLE value, void* buffer, DWORD size, DWORD* received, void*) {
    ssize_t count; do { count = read(static_cast<Handle*>(value)->file, buffer, size); } while (count < 0 && errno == EINTR);
    if (count < 0) return FALSE; *received = static_cast<DWORD>(count); return TRUE;
}
BOOL WriteFile(HANDLE value, const void* buffer, DWORD size, DWORD* written, void*) {
    size_t offset = 0;
    while (offset < size) {
        ssize_t count = write(static_cast<Handle*>(value)->file, static_cast<const char*>(buffer) + offset, size - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return FALSE;
        offset += static_cast<size_t>(count);
    }
    *written = static_cast<DWORD>(offset); return TRUE;
}
DWORD SetFilePointer(HANDLE value, long distance, void*, DWORD origin) {
    return static_cast<DWORD>(lseek(static_cast<Handle*>(value)->file, distance, origin == FILE_END ? SEEK_END : SEEK_SET));
}
BOOL CloseHandle(HANDLE value) {
    if (!value || value == INVALID_HANDLE_VALUE) return FALSE;
    std::unique_ptr<Handle> handle(static_cast<Handle*>(value));
    if (handle->file >= 0) return close(handle->file) == 0;
    return TRUE;
}
DWORD GetFileAttributesW(const wchar_t* path) {
    struct stat info; if (stat(filename(path).c_str(), &info)) return INVALID_FILE_ATTRIBUTES;
    return S_ISDIR(info.st_mode) ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
}
BOOL GetFileAttributesExW(const wchar_t* path, int, WIN32_FILE_ATTRIBUTE_DATA* data) {
    struct stat info; if (stat(filename(path).c_str(), &info)) return FALSE;
    uint64_t stamp = static_cast<uint64_t>(info.st_mtimespec.tv_sec) * 10000000 + info.st_mtimespec.tv_nsec / 100;
    std::memset(data, 0, sizeof(*data));
    data->dwFileAttributes = S_ISDIR(info.st_mode) ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    data->ftLastWriteTime = {static_cast<DWORD>(stamp), static_cast<DWORD>(stamp >> 32)};
    data->nFileSizeLow = static_cast<DWORD>(info.st_size);
    data->nFileSizeHigh = static_cast<DWORD>(static_cast<uint64_t>(info.st_size) >> 32); return TRUE;
}
DWORD GetTickCount() { return static_cast<DWORD>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); }
DWORD GetCurrentProcessId() { return static_cast<DWORD>(getpid()); }
BOOL QueryPerformanceCounter(LARGE_INTEGER* value) { value->QuadPart = std::chrono::steady_clock::now().time_since_epoch().count(); return TRUE; }
void GetLocalTime(SYSTEMTIME* value) {
    time_t now = time(nullptr); struct tm local; localtime_r(&now, &local);
    *value = {static_cast<WORD>(local.tm_year + 1900), static_cast<WORD>(local.tm_mon + 1),
              static_cast<WORD>(local.tm_wday), static_cast<WORD>(local.tm_mday),
              static_cast<WORD>(local.tm_hour), static_cast<WORD>(local.tm_min), static_cast<WORD>(local.tm_sec), 0};
}
HMODULE LoadLibraryW(const wchar_t* path) {
    std::string name = filename(path);
    // POSIX SAORI implementations use malloc/free and C-long lengths.
    // The original PE file is never treated as executable macOS code.
    std::vector<std::string> candidates = {name};
    if (name.size() > 4 && name.substr(name.size() - 4) == ".dll") {
        std::string stem = name.substr(0, name.size() - 4);
        candidates = {stem + ".dylib", stem + ".so", name};
    }
    for (const std::string& candidate : candidates) {
        void* module = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE);
        if (module) return module;
    }
    errno = ENOEXEC; return nullptr;
}
void* GetProcAddress(HMODULE module, const char* name) { return dlsym(module, name); }
BOOL FreeLibrary(HMODULE module) { return module && dlclose(module) == 0; }
DWORD GetLastError() { return static_cast<DWORD>(errno); }
BOOL GetModuleHandleExW(DWORD, LPCWSTR address, HMODULE* result) {
    Dl_info info;
    if (!dladdr(reinterpret_cast<const void*>(address), &info) || !info.dli_fname) return FALSE;
    // An async SAORI may outlive unload. NODELETE prevents unmapping its caller
    // before pthread_exit has left this image. XPC still owns process lifetime.
    *result = dlopen(info.dli_fname, RTLD_LAZY | RTLD_LOCAL | RTLD_NODELETE); return *result != nullptr;
}
HANDLE CreateThread(void*, size_t, ThreadEntry entry, void* argument, DWORD, DWORD*) {
    std::unique_ptr<Handle> handle(new Handle()); handle->thread = std::make_shared<ThreadState>();
    std::unique_ptr<ThreadCall> call(new ThreadCall{entry, argument, handle->thread});
    pthread_attr_t options; pthread_attr_init(&options); pthread_attr_setdetachstate(&options, PTHREAD_CREATE_DETACHED);
    pthread_t thread; int result = pthread_create(&thread, &options, threadMain, call.get()); pthread_attr_destroy(&options);
    if (result) { errno = result; return nullptr; }
    call.release(); return handle.release();
}
DWORD WaitForSingleObject(HANDLE value, DWORD milliseconds) {
    Handle* handle = static_cast<Handle*>(value);
    if (!handle || !handle->thread) return WAIT_TIMEOUT;
    auto state = handle->thread; std::unique_lock<std::mutex> lock(state->mutex);
    return state->complete.wait_for(lock, std::chrono::milliseconds(milliseconds), [&] { return state->done; }) ? WAIT_OBJECT_0 : WAIT_TIMEOUT;
}
[[noreturn]] void FreeLibraryAndExitThread(HMODULE module, DWORD status) {
    FreeLibrary(module); pthread_exit(reinterpret_cast<void*>(static_cast<uintptr_t>(status)));
}
void Sleep(DWORD milliseconds) {
    struct timespec remaining = {static_cast<time_t>(milliseconds / 1000), static_cast<long>(milliseconds % 1000) * 1000000};
    while (nanosleep(&remaining, &remaining) && errno == EINTR) {}
}
size_t VirtualQuery(LPCVOID address, MEMORY_BASIC_INFORMATION* out, size_t size) {
    if (!out || size < sizeof(*out)) return 0;
    Dl_info info; if (!dladdr(address, &info)) return 0;
    out->AllocationBase = info.dli_fbase; return sizeof(*out);
}
DWORD GetModuleFileNameW(HMODULE base, wchar_t* out, DWORD capacity) {
    Dl_info info; if (!out || !capacity || !dladdr(base, &info) || !info.dli_fname) return 0;
    std::string bytes = convert(info.dli_fname, std::strlen(info.dli_fname), "UTF-8", "UTF-32LE");
    size_t count = bytes.size() / sizeof(wchar_t);
    if (count >= capacity) return capacity;
    std::memcpy(out, bytes.data(), bytes.size()); out[count] = 0; return static_cast<DWORD>(count);
}
