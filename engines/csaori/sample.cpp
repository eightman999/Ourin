// Self-authored SHIORI subclass. Parsing and wire generation belong to CSAORI.
#include "csaori_base.h"
#include <codecvt>
#include <locale>
#include <cstring>
#include <fstream>
#include <memory>
#include <unistd.h>
class ShioriExample : public CSAORIBase {
public:
    const string_t& s_saori_version() const override { static string_t v=L"SHIORI/3.0"; return v; }
    const string_t& s_saori_def() const override { static string_t v=L" SHIORI/"; return v; }
    const string_t& s_saori_argument() const override { static string_t v=L"Reference"; return v; }
    const string_t& s_saori_value() const override { static string_t v=L"Reference"; return v; }
    const string_t& s_saori_result() const override { static string_t v=L"Value"; return v; }
    bool load() override { return true; }
    bool unload() override { return true; }
    void exec(const CSAORIInput& in, CSAORIOutput& out) override {
        out.result_code=SAORIRESULT_NO_CONTENT;
        if (in.cmd!=L"GET") return;
        if (in.id==L"version") out.result=L"0.1";
        else if (in.id==L"name") out.result=L"CSAORI SHIORI development example";
        else if (in.id==L"OnBoot") out.result=L"\\0\\s[0]桜鈴、こんにちは。\\e";
        else if (in.id==L"OnEcho" && !in.args.empty()) out.result=in.args[0];
        else if (in.id==L"OnSparse" && in.args.size()>2) out.result=in.args[2];
        if (!out.result.empty()) out.result_code=SAORIRESULT_OK;
    }
};
static ShioriExample instance;
static std::string directory;
static bool loaded=false;
static std::string respond(const std::string& wire) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> codec;
    CSAORIInput in(instance);
    CSAORIOutput out(instance);
    in.codepage=out.codepage=CP_UTF8;
    out.result_code=SAORIRESULT_BAD_REQUEST;
    out.opts[L"Sender"]=L"csaori-example";
    try {
        if (in.parseString(codec.from_bytes(wire)) && (in.cmd==L"GET" || in.cmd==L"NOTIFY")) instance.exec(in,out);
    } catch (...) { out.result_code=SAORIRESULT_BAD_REQUEST; }
    return codec.to_bytes(out.toString());
}
extern "C" int32_t load(void* input, long length) {
    std::unique_ptr<void, decltype(&free)> owned(input,free);
    if (!input || length<=0 || length>1048576) return 0;
    directory.assign(static_cast<const char*>(input),length);
    std::ofstream marker(directory+"loaded.pid"); marker<<getpid();
    loaded=marker.good() && instance.load();
    return loaded ? 1 : 0;
}
extern "C" int32_t unload() {
    if (!loaded) return 1;
    bool ok=instance.unload();
    std::ofstream marker(directory+"unloaded.marker"); marker<<"unloaded";
    loaded=false;
    return ok && marker.good() ? 1 : 0;
}
extern "C" void* request(void* input, long* length) {
    std::unique_ptr<void, decltype(&free)> owned(input,free);
    if (!loaded || !input || !length || *length<0 || *length>1048576) return nullptr;
    try {
        std::string output=respond(std::string(static_cast<const char*>(input),*length));
        void* result=malloc(output.size()+1);
        if (!result) return nullptr;
        memcpy(result,output.c_str(),output.size()+1);
        *length=static_cast<long>(output.size());
        return result;
    } catch (...) { return nullptr; }
}
