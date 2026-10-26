// Ourin-owned KOTORI native module adapters. No ghost files are rewritten.
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <iconv.h>
#include <poll.h>
#include <random>
#include <cmath>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <ApplicationServices/ApplicationServices.h>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
int luaopen_luachild(lua_State*);
int ourin_luaopen_utf8(lua_State*);
int luaopen_socket_core(lua_State*);
int luaopen_lpeg(lua_State*);
int lc_dir(lua_State*);
int lc_dirent(lua_State*);
}
extern "C" const char* ourin_luachild_cwd(lua_State* L) {
    lua_getfield(L, LUA_REGISTRYINDEX, "ourin.kagari.cwd");
    const char* path = lua_tostring(L, -1);
    lua_pop(L, 1);
    return path;
}
namespace {
std::string absolutePath(lua_State* L, const char* path) {
    if (*path == '/') return path;
    const char* root = ourin_luachild_cwd(L);
    return std::string(root ? root : "") + "/" + path;
}
void resolveArgument(lua_State* L, int index) {
    if (lua_type(L, index) == LUA_TSTRING) {
        const auto path = absolutePath(L, lua_tostring(L, index));
        lua_pushlstring(L, path.data(), path.size()); lua_replace(L, index);
    }
}
int rootedDir(lua_State* L) { resolveArgument(L, 1); return lc_dir(L); }
int rootedDirent(lua_State* L) { resolveArgument(L, 1); return lc_dirent(L); }
int virtualCurrentDirectory(lua_State* L) { lua_pushstring(L, ourin_luachild_cwd(L)); return 1; }
int virtualChdir(lua_State* L) {
    const auto path = absolutePath(L, luaL_checkstring(L, 1));
    struct stat state;
    if (stat(path.c_str(), &state) != 0 || !S_ISDIR(state.st_mode)) {
        lua_pushnil(L); lua_pushliteral(L, "directory unavailable"); return 2;
    }
    lua_pushlstring(L, path.data(), path.size()); lua_setfield(L, LUA_REGISTRYINDEX, "ourin.kagari.cwd");
    lua_pushboolean(L, true); return 1;
}
int openLuachild(lua_State* L) {
    luaopen_luachild(L);
    for (const auto& field : std::vector<std::pair<const char*, lua_CFunction>>{
        {"dir", rootedDir}, {"dirent", rootedDirent}, {"currentdir", virtualCurrentDirectory}, {"chdir", virtualChdir}}) {
        lua_pushcfunction(L, field.second); lua_setfield(L, -2, field.first);
    }
    return 1;
}
int rootedFileCall(lua_State* L) {
    const int count = lua_gettop(L);
    resolveArgument(L, 1);
    lua_pushvalue(L, lua_upvalueindex(1)); lua_insert(L, 1);
    lua_call(L, count, LUA_MULTRET);
    return lua_gettop(L);
}
void wrapFileFunction(lua_State* L, const char* table, const char* name) {
    if (table) lua_getglobal(L, table); else lua_pushglobaltable(L);
    lua_getfield(L, -1, name);
    lua_pushcclosure(L, rootedFileCall, 1); lua_setfield(L, -2, name); lua_pop(L, 1);
}
constexpr size_t maxBuffer = 64 * 1024 * 1024;
int fileDescriptor(lua_State* L) {
    auto* file = static_cast<luaL_Stream*>(luaL_checkudata(L, 1, LUA_FILEHANDLE));
    if (!file->f || !file->closef) luaL_error(L, "closed file");
    return fileno(file->f);
}
int readable(lua_State* L) {
    pollfd file{fileDescriptor(L), POLLIN, 0};
    const int result = poll(&file, 1, 0);
    lua_pushboolean(L, result > 0 && (file.revents & (POLLIN | POLLHUP)));
    return 1;
}
int blocking(lua_State* L) {
    const int fd = fileDescriptor(L), flags = fcntl(fd, F_GETFL);
    const bool enabled = lua_toboolean(L, 2);
    lua_pushboolean(L, flags >= 0 && fcntl(fd, F_SETFL, enabled ? flags & ~O_NONBLOCK : flags | O_NONBLOCK) == 0);
    return 1;
}
int openFH(lua_State* L) {
    lua_newtable(L);
    lua_pushcfunction(L, readable); lua_setfield(L, -2, "readable");
    lua_pushcfunction(L, blocking); lua_setfield(L, -2, "blocking");
    return 1;
}
// The original clipboard module takes an HWND and CP932 text. The HWND is
// ignored on macOS; importing the module never reads or changes the clipboard.
int clipboardSet(lua_State* L) {
    const int index = lua_gettop(L) >= 2 ? 2 : 1;
    size_t length = 0;
    const char* bytes = luaL_checklstring(L, index, &length);
    CFStringRef text = CFStringCreateWithBytes(kCFAllocatorDefault,
        reinterpret_cast<const UInt8*>(bytes), length, kCFStringEncodingDOSJapanese, false);
    if (!text) { lua_pushboolean(L, false); return 1; }
    CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, text, kCFStringEncodingUTF8, 0);
    CFRelease(text);
    PasteboardRef board = nullptr;
    OSStatus status = data ? PasteboardCreate(kPasteboardClipboard, &board) : paramErr;
    if (status == noErr) status = PasteboardClear(board);
    if (status == noErr) status = PasteboardPutItemFlavor(board, reinterpret_cast<PasteboardItemID>(1), CFSTR("public.utf8-plain-text"), data, 0);
    if (board) CFRelease(board);
    if (data) CFRelease(data);
    lua_pushboolean(L, status == noErr); return 1;
}
int openClipboard(lua_State* L) {
    lua_newtable(L);
    lua_pushcfunction(L, clipboardSet); lua_setfield(L, -2, "set");
    return 1;
}
// KOTORI's Lua wrapper divides the callable result by 2^32. Preserve that
// uint32 contract; seeds reproduce a stream within this implementation.
struct Random { std::mt19937 engine; explicit Random(uint32_t seed): engine(seed) {} };
Random* randomState(lua_State* L) { return static_cast<Random*>(luaL_checkudata(L, 1, "Ourin.Kagari.random")); }
int randomNext(lua_State* L) { lua_pushinteger(L, randomState(L)->engine()); return 1; }
int randomGC(lua_State* L) { randomState(L)->~Random(); return 0; }
int randomUniform(lua_State* L) {
    auto* state = randomState(L);
    double limit = luaL_checknumber(L, 2);
    luaL_argcheck(L, std::isfinite(limit) && limit > 0, 2, "positive finite bound required");
    lua_pushnumber(L, std::uniform_real_distribution<double>(0, limit)(state->engine)); return 1;
}
int randomNormal(lua_State* L) {
    auto* state = randomState(L);
    double mean = luaL_checknumber(L, 2), deviation = luaL_checknumber(L, 3);
    luaL_argcheck(L, std::isfinite(mean), 2, "finite mean required");
    luaL_argcheck(L, std::isfinite(deviation) && deviation > 0, 3, "positive finite deviation required");
    lua_pushnumber(L, std::normal_distribution<double>(mean, deviation)(state->engine)); return 1;
}
int newRandom(lua_State* L) {
    auto seed = static_cast<uint32_t>(luaL_optinteger(L, 1, 5489));
    new(lua_newuserdatauv(L, sizeof(Random), 0)) Random(seed);
    luaL_setmetatable(L, "Ourin.Kagari.random"); return 1;
}
int openRandom(lua_State* L) {
    if (luaL_newmetatable(L, "Ourin.Kagari.random")) {
        for (const auto& field : std::vector<std::pair<const char*, lua_CFunction>>{
            {"__gc", randomGC}, {"__call", randomNext}, {"uniform", randomUniform}, {"normal_distribution", randomNormal}}) {
            lua_pushcfunction(L, field.second); lua_setfield(L, -2, field.first);
        }
        lua_pushvalue(L, -1); lua_setfield(L, -2, "__index");
    }
    lua_pop(L, 1); lua_pushcfunction(L, newRandom); return 1;
}
struct Converter { iconv_t descriptor; };
int closeConverter(lua_State* L) {
    auto* converter = static_cast<Converter*>(luaL_checkudata(L, 1, "Ourin.Kagari.iconv"));
    if (converter->descriptor != reinterpret_cast<iconv_t>(-1)) iconv_close(converter->descriptor);
    converter->descriptor = reinterpret_cast<iconv_t>(-1);
    return 0;
}
int convert(lua_State* L) {
    auto* converter = static_cast<Converter*>(luaL_checkudata(L, 1, "Ourin.Kagari.iconv"));
    size_t left = 0;
    const char* original = luaL_checklstring(L, 2, &left);
    if (converter->descriptor == reinterpret_cast<iconv_t>(-1) || left > maxBuffer) {
        lua_pushnil(L); lua_pushinteger(L, 3); return 2;
    }
    std::vector<char> output(left * 2 + 32);
    if (output.size() > maxBuffer) output.resize(maxBuffer);
    char* input = const_cast<char*>(original);
    char* destination = output.data();
    size_t remaining = output.size();
    iconv(converter->descriptor, nullptr, nullptr, nullptr, nullptr);
    while (true) {
        const size_t result = iconv(converter->descriptor, &input, &left, &destination, &remaining);
        if (result != static_cast<size_t>(-1)) break;
        if (errno != E2BIG || output.size() >= maxBuffer) {
            lua_pushnil(L); lua_pushinteger(L, errno == EINVAL ? 1 : errno == EILSEQ ? 2 : 3); return 2;
        }
        const size_t used = output.size() - remaining;
        output.resize(std::min(maxBuffer, output.size() * 2));
        destination = output.data() + used; remaining = output.size() - used;
    }
    lua_pushlstring(L, output.data(), output.size() - remaining);
    lua_pushnil(L);
    return 2;
}
int newConverter(lua_State* L) {
    const char* to = luaL_checkstring(L, 1);
    const char* from = luaL_checkstring(L, 2);
    iconv_t descriptor = iconv_open(to, from);
    if (descriptor == reinterpret_cast<iconv_t>(-1)) { lua_pushnil(L); return 1; }
    auto* converter = static_cast<Converter*>(lua_newuserdatauv(L, sizeof(Converter), 0));
    converter->descriptor = descriptor;
    luaL_setmetatable(L, "Ourin.Kagari.iconv");
    return 1;
}
int openIconv(lua_State* L) {
    if (luaL_newmetatable(L, "Ourin.Kagari.iconv")) {
        lua_pushcfunction(L, closeConverter); lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, convert); lua_setfield(L, -2, "iconv");
        lua_pushvalue(L, -1); lua_setfield(L, -2, "__index");
    }
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushcfunction(L, newConverter); lua_setfield(L, -2, "new");
    return 1;
}
struct Saori {
    void* handle = nullptr;
    int (*load)(char*, long) = nullptr;
    int (*unload)() = nullptr;
    char* (*request)(char*, long*) = nullptr;
    bool loaded = false;
};
int unloadSaori(lua_State* L) {
    auto* module = static_cast<Saori*>(luaL_checkudata(L, 1, "Ourin.Kagari.saori"));
    bool success = true;
    if (module->loaded && module->unload) success = module->unload() != 0;
    module->loaded = false;
    lua_pushboolean(L, success); return 1;
}
int gcSaori(lua_State* L) {
    auto* module = static_cast<Saori*>(luaL_checkudata(L, 1, "Ourin.Kagari.saori"));
    if (module->loaded && module->unload) module->unload();
    if (module->handle) dlclose(module->handle);
    module->~Saori(); return 0;
}
int loadSaori(lua_State* L) {
    auto* module = static_cast<Saori*>(luaL_checkudata(L, 1, "Ourin.Kagari.saori"));
    size_t length = 0;
    const char* directory = luaL_checklstring(L, 2, &length);
    if (!module->handle || !module->load || !module->request) { lua_pushboolean(L, false); return 1; }
    char* copy = static_cast<char*>(malloc(length + 1));
    if (!copy) return luaL_error(L, "allocation failed");
    memcpy(copy, directory, length + 1);
    module->loaded = module->load(copy, static_cast<long>(length)) != 0;
    lua_pushboolean(L, module->loaded); return 1;
}
int requestSaori(lua_State* L) {
    auto* module = static_cast<Saori*>(luaL_checkudata(L, 1, "Ourin.Kagari.saori"));
    size_t length = 0;
    const char* wire = luaL_checklstring(L, 2, &length);
    if (!module->loaded || !module->request || length > maxBuffer) {
        lua_pushliteral(L, "SAORI/1.0 503 Service Unavailable\r\n\r\n"); return 1;
    }
    char* copy = static_cast<char*>(malloc(length + 1));
    if (!copy) return luaL_error(L, "allocation failed");
    memcpy(copy, wire, length + 1);
    long count = static_cast<long>(length);
    char* response = module->request(copy, &count);
    if (!response || count < 0 || static_cast<size_t>(count) > maxBuffer) {
        free(response); lua_pushliteral(L, "SAORI/1.0 500 Internal Server Error\r\n\r\n"); return 1;
    }
    lua_pushlstring(L, response, static_cast<size_t>(count)); free(response); return 1;
}
int newSaori(lua_State* L) {
    std::string path = absolutePath(L, luaL_checkstring(L, 1));
    auto* module = new(lua_newuserdatauv(L, sizeof(Saori), 0)) Saori();
    // KOTORI declares DLL paths on all platforms. Try matching native siblings,
    // never dlopen the Windows binary or invent success for an absent SAORI.
    std::vector<std::string> candidates;
    const auto dot = path.rfind('.');
    const std::string base = dot == std::string::npos ? path : path.substr(0, dot);
    candidates.push_back(base + ".dylib"); candidates.push_back(base + ".so");
    for (const auto& candidate : candidates) {
        module->handle = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (module->handle) break;
    }
    if (module->handle) {
        module->load = reinterpret_cast<decltype(module->load)>(dlsym(module->handle, "loadu"));
        if (!module->load) module->load = reinterpret_cast<decltype(module->load)>(dlsym(module->handle, "load"));
        module->unload = reinterpret_cast<decltype(module->unload)>(dlsym(module->handle, "unload"));
        module->request = reinterpret_cast<decltype(module->request)>(dlsym(module->handle, "request"));
    }
    luaL_setmetatable(L, "Ourin.Kagari.saori"); return 1;
}
int openSaori(lua_State* L) {
    if (luaL_newmetatable(L, "Ourin.Kagari.saori")) {
        lua_pushcfunction(L, gcSaori); lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, loadSaori); lua_setfield(L, -2, "load");
        lua_pushcfunction(L, unloadSaori); lua_setfield(L, -2, "unload");
        lua_pushcfunction(L, requestSaori); lua_setfield(L, -2, "request");
        lua_pushvalue(L, -1); lua_setfield(L, -2, "__index");
    }
    lua_pop(L, 1); lua_pushcfunction(L, newSaori); return 1;
}
}
extern "C" void ourin_kagari_preload_modules(lua_State* L, const char* root) {
    lua_pushstring(L, root); lua_setfield(L, LUA_REGISTRYINDEX, "ourin.kagari.cwd");
    wrapFileFunction(L, "io", "open"); wrapFileFunction(L, "io", "lines");
    wrapFileFunction(L, nullptr, "loadfile"); wrapFileFunction(L, nullptr, "dofile");
    lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");
    for (const auto& module : std::vector<std::pair<const char*, lua_CFunction>>{
        {"luachild", openLuachild}, {"lua-utf8", ourin_luaopen_utf8},
        {"socket.core", luaopen_socket_core}, {"lpeg", luaopen_lpeg},
        {"clipboard", openClipboard}, {"rand.native", openRandom}, {"fh", openFH}, {"iconv", openIconv}, {"saori_universal.native", openSaori}}) {
        lua_pushcfunction(L, module.second); lua_setfield(L, -2, module.first);
    }
    lua_pop(L, 2);
}
