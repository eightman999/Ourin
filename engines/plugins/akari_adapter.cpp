// Ourin Akari PLUGIN adapter. Each Swift engine runs in its own helper process.
#include <nlohmann/json.hpp>
#include <chrono>
#include <cerrno>
#include <cstdlib>
#include <dlfcn.h>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
extern "C" int32_t plugin_loadu(char*, size_t);
namespace fs=std::filesystem;
using json=nlohmann::json;
namespace {
constexpr size_t LIMIT=8*1024*1024;
using Clock=std::chrono::steady_clock;
std::mutex gate;
std::string pending, result;
int input=-1, output=-1;
pid_t child=-1;
bool ownsGroup=true;
fs::path inside(const fs::path& root,const std::string& value) {
 if(fs::path(value).is_absolute())throw std::runtime_error("absolute resource path");
 auto base=fs::canonical(root),path=fs::canonical(root/value),relative=path.lexically_relative(base);
 if(relative.empty()||*relative.begin()=="..")throw std::runtime_error("resource escape");return path;
}
void stop() {
 if(child>0){kill(ownsGroup?-child:child,SIGKILL);while(waitpid(child,nullptr,0)<0&&errno==EINTR){}child=-1;}
 if(input>=0)close(input);if(output>=0)close(output);input=output=-1;pending.clear();
}
void waitFD(int fd,short events,Clock::time_point deadline) {
 auto left=std::chrono::duration_cast<std::chrono::milliseconds>(deadline-Clock::now()).count();
 if(left<=0)throw std::runtime_error("helper timeout");
 pollfd p{fd,events,0};int n=poll(&p,1,static_cast<int>(std::min<long long>(left,1000)));
 if(n<0&&errno!=EINTR)throw std::runtime_error("helper pipe error");
}
json exchange(const json& message,int seconds=20) {
 auto deadline=Clock::now()+std::chrono::seconds(seconds);auto wire=message.dump()+"\n";
 if(wire.size()>LIMIT*3)throw std::runtime_error("oversize request");
 for(size_t at=0;at<wire.size();){waitFD(input,POLLOUT,deadline);auto n=write(input,wire.data()+at,wire.size()-at);
 if(n>0)at+=n;else if(n<0&&errno!=EINTR&&errno!=EAGAIN)throw std::runtime_error("helper write failed");}
 while(true){auto end=pending.find('\n');if(end!=std::string::npos){auto line=pending.substr(0,end);pending.erase(0,end+1);return json::parse(line);}
 waitFD(output,POLLIN,deadline);char buf[4096];auto n=read(output,buf,sizeof buf);
 if(n==0)throw std::runtime_error("helper exited");if(n>0)pending.append(buf,n);else if(errno!=EINTR&&errno!=EAGAIN)throw std::runtime_error("helper read failed");
 if(pending.size()>LIMIT*3)throw std::runtime_error("oversize response");}
}
void launch(const fs::path& helper,const fs::path& cwd) {
 int in[2],out[2];if(pipe(in))throw std::runtime_error("pipe failed");if(pipe(out)){close(in[0]);close(in[1]);throw std::runtime_error("pipe failed");}
 for(int fd:{in[0],in[1],out[0],out[1]})fcntl(fd,F_SETFD,FD_CLOEXEC);
 posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
 posix_spawn_file_actions_adddup2(&actions,in[0],STDIN_FILENO);posix_spawn_file_actions_adddup2(&actions,out[1],STDOUT_FILENO);
 posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0);
 posix_spawn_file_actions_addchdir_np(&actions,cwd.c_str());
 auto path=helper.string();char *argv[]={path.data(),nullptr};pid_t pid;
 posix_spawnattr_t attributes;posix_spawnattr_init(&attributes);
 ownsGroup=!getenv("OURIN_CORPUS_PARENT_OWNS_GROUP")||std::string(getenv("OURIN_CORPUS_PARENT_OWNS_GROUP"))!="1";
 if(ownsGroup){posix_spawnattr_setflags(&attributes,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attributes,0);}
 int error=posix_spawn(&pid,path.c_str(),&actions,&attributes,argv,environ);
 posix_spawnattr_destroy(&attributes);posix_spawn_file_actions_destroy(&actions);close(in[0]);close(out[1]);
 if(error){close(in[1]);close(out[0]);throw std::runtime_error("spawn failed");}
 child=pid;input=in[1];output=out[0];fcntl(input,F_SETFL,O_NONBLOCK);fcntl(output,F_SETFL,O_NONBLOCK);fcntl(input,F_SETNOSIGPIPE,1);
}
std::string hex(const unsigned char* p,size_t n){static const char* digits="0123456789abcdef";std::string s;s.reserve(n*2);for(size_t i=0;i<n;++i){s+=digits[p[i]>>4];s+=digits[p[i]&15];}return s;}
std::string unhex(const std::string& s){if(s.size()%2||s.size()>LIMIT*2)throw std::runtime_error("invalid wire");std::string r;for(size_t i=0;i<s.size();i+=2){auto digit=[](char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;throw std::runtime_error("invalid hex");};r+=char(digit(s[i])*16+digit(s[i+1]));}return r;}
}
extern "C" int32_t plugin_loadu(char* owned,size_t) {
 free(owned);std::lock_guard<std::mutex> lock(gate);stop();
 try {Dl_info info{};if(!dladdr(reinterpret_cast<void*>(&plugin_loadu),&info))return 0;
 auto root=fs::canonical(fs::path(info.dli_fname).parent_path()/"../Resources");
 if(fs::file_size(root/"adapter.json")>1024*1024)return 0;
 std::ifstream file(root/"adapter.json");auto config=json::parse(file);if(config.value("engine","")!="akari")return 0;
 auto payload=inside(root,config.value("payload","payload"));auto library=inside(root,config.value("engine_library","libakari.dylib"));
 launch(inside(root,"akari_helper"),payload);
 if(exchange({{"cmd","load"},{"root",payload.string()},{"library",library.string()}},60).value("ok",false))return 1;
 }catch(...){}stop();return 0;
}
extern "C" const unsigned char* plugin_request(const unsigned char* data,size_t size,size_t* length) {
 std::lock_guard<std::mutex> lock(gate);if(!length)return nullptr;*length=0;
 if(child<=0||!data||!size||size>LIMIT)return nullptr;
 try {auto reply=exchange({{"cmd","request"},{"wire",hex(data,size)}});if(!reply.value("ok",false))return nullptr;
 result=unhex(reply.at("wire").get<std::string>());*length=result.size();return reinterpret_cast<const unsigned char*>(result.data());
 }catch(...){stop();return nullptr;}
}
extern "C" void plugin_unload() {
 std::lock_guard<std::mutex> lock(gate);try{if(child>0)exchange({{"cmd","unload"}},10);}catch(...){}stop();result.clear();
}
