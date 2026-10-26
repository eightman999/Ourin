// Compile the upstream POSIX interface in this translation unit so its existing
// parser stays authoritative. Our additions enforce load failure and save/unload.
#define aosora_load upstream_aosora_load
#define aosora_unload upstream_aosora_unload
#include "dllmain.cpp"
#undef aosora_load
#undef aosora_unload

extern "C" long aosora_load(char *path, long len) {
    // Upstream TextSystem/Debugger are process singletons. Additional instances
    // require a separate XPC process; don't let a failed second load destroy one.
    if (!path || len <= 0 || !shioriInstance.empty()) {
        free(path);
        return 0;
    }
    long id = upstream_aosora_load(path, len);
    if (id > 0 && shioriInstance.at(id)->HasBootError()) {
        upstream_aosora_unload(id);
        return 0;
    }
    return id;
}

extern "C" int aosora_unload(long id) {
    auto found = shioriInstance.find(id);
    if (found == shioriInstance.end()) return 0;
    found->second->Unload();
    return upstream_aosora_unload(id);
}
