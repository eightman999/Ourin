// Ourin YAYA-as-PLUGIN adapter. Apache-2.0; no third-party dictionary source.
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iconv.h>
#include <map>
#include <mutex>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <string>
#include <sstream>
#include <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <regex>
#include <set>

#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
extern "C" int32_t plugin_loadu(char*, size_t);
using json = nlohmann::json;
namespace fs = std::filesystem;
namespace {
constexpr size_t LIMIT = 4 * 1024 * 1024;
std::mutex guard;
std::string responseBuffer, pending;
pid_t child = -1;
pid_t ugmChild = -1;
int input = -1, output = -1;
fs::path resources;
json settings;
bool unavailable = false;
bool ownsGroup = true;
using Req = const unsigned char* (*)(const unsigned char*,size_t,size_t*);
using Load = int32_t (*)(char*,size_t);
using Unload = void (*)();
struct Backend { void *handle; Req request; Unload unload; };
std::map<std::string,Backend> backends;
std::string lower(std::string s) { for(auto &c:s)c=std::tolower(static_cast<unsigned char>(c));return s; }
std::string moduleKey(std::string s) {
 std::replace(s.begin(),s.end(),'\\','/');while(s.rfind("./",0)==0)s.erase(0,2);return lower(s);
}
std::string header(const std::string &wire,const std::string &key) {
 size_t at=wire.find("\r\n"); if(at==std::string::npos)return "";at+=2;
 while(at<wire.size()) {auto end=wire.find("\r\n",at);if(end==std::string::npos||end==at)break;
 auto colon=wire.find(':',at);if(colon<end&&lower(wire.substr(at,colon-at))==lower(key)){
 auto value=wire.substr(colon+1,end-colon-1);while(!value.empty()&&(value[0]==' '||value[0]=='\t'))value.erase(0,1);return value;}
 at=end+2;}return "";
}
std::string codec(std::string bytes,std::string from,std::string to) {
 auto canonical=[](std::string n){n=lower(n);return (n=="shift_jis"||n=="shift-jis"||n=="sjis")?"CP932":n;};
 from=canonical(from);to=canonical(to);if(from.empty())from="utf-8";if(to.empty())to="utf-8";
 if(from==to)return bytes;
 iconv_t cv=iconv_open(to.c_str(),from.c_str());if(cv==(iconv_t)-1)throw std::runtime_error("unsupported charset");
 std::string dest(bytes.size()*4+32,'\0');char *src=bytes.data(),*dst=dest.data();size_t left=bytes.size(),remain=dest.size();
 size_t result=iconv(cv,&src,&left,&dst,&remain);iconv_close(cv);
 if(result==(size_t)-1||left)throw std::runtime_error("charset conversion failed");dest.resize(dest.size()-remain);return dest;
}
fs::path inside(const fs::path &base,const std::string &relative) {
 fs::path rel(relative);if(rel.is_absolute())throw std::runtime_error("absolute package path");
 auto root=fs::weakly_canonical(base),path=fs::weakly_canonical(base/rel);
 auto suffix=path.lexically_relative(root);if(suffix.empty()||*suffix.begin()=="..")throw std::runtime_error("package path escapes resources");return path;
}
pid_t pollUGM() {
 pid_t state;do{state=waitpid(ugmChild,nullptr,WNOHANG);}while(state<0&&errno==EINTR);return state;
}
void stopUGM() {
 if(ugmChild<=0)return;
 pid_t already=pollUGM();if(already==ugmChild||(already<0&&errno==ECHILD)){ugmChild=-1;return;}
 kill(ugmChild,SIGTERM);
 for(int i=0;i<20;++i){pid_t done=pollUGM();if(done==ugmChild||(done<0&&errno==ECHILD)){ugmChild=-1;return;}usleep(50000);}
 kill(ugmChild,SIGKILL);while(waitpid(ugmChild,nullptr,0)<0&&errno==EINTR){}ugmChild=-1;
}
void stop() {
 stopUGM();
 if(child>0){kill(ownsGroup?-child:child,SIGKILL);while(waitpid(child,nullptr,0)<0&&errno==EINTR){}child=-1;}
 if(input>=0){close(input);input=-1;}if(output>=0){close(output);output=-1;}pending.clear();
 for(auto &[key,b]:backends){if(b.unload)b.unload();dlclose(b.handle);}backends.clear();
}
using Clock=std::chrono::steady_clock;
#include "bouyomi_backend.hpp"
void waitFD(int fd,short event,Clock::time_point deadline) {
 auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(deadline-Clock::now()).count();
 if(ms<=0)throw std::runtime_error("helper timeout");pollfd p{fd,event,0};int n;
 do{n=poll(&p,1,static_cast<int>(std::min<long long>(ms,1000)));}while(n<0&&errno==EINTR);
 if(n<0)throw std::runtime_error("helper pipe failed");
}
void send(const json &message,Clock::time_point deadline) {
 std::string wire=message.dump()+"\n";if(wire.size()>LIMIT)throw std::runtime_error("request too large");size_t at=0;
 while(at<wire.size()){waitFD(input,POLLOUT,deadline);auto n=write(input,wire.data()+at,wire.size()-at);
 if(n>0)at+=n;else if(n<0&&errno!=EAGAIN&&errno!=EINTR)throw std::runtime_error("helper write failed");}
}
json receive(Clock::time_point deadline) {
 while(true){auto end=pending.find('\n');if(end!=std::string::npos){auto line=pending.substr(0,end);pending.erase(0,end+1);return json::parse(line);}
 waitFD(output,POLLIN,deadline);char buf[4096];auto n=read(output,buf,sizeof buf);
 if(n==0)throw std::runtime_error("helper exited");if(n>0)pending.append(buf,n);else if(errno!=EAGAIN&&errno!=EINTR)throw std::runtime_error("helper read failed");
 if(pending.size()>LIMIT)throw std::runtime_error("helper response too large");}
}
bool startUGM(const json& params) {
 if(params.value("wait",false)||!params.value("arguments","").empty()||!settings.contains("ugm_http_helper"))return false;
 const auto root=inside(resources,settings.at("load").at("ghost_root").get<std::string>());
 std::string command=params.value("command","");std::replace(command.begin(),command.end(),'\\','/');
 // No shell parsing, quoting, extra flags, URL opening, or arbitrary executable map.
 if(command!="localweb/ugm_server.exe"&&command!=(root/"localweb/ugm_server.exe").string())return false;
 if(ugmChild>0){if(pollUGM()==0)return true;ugmChild=-1;}
 const auto helper=inside(resources,settings.at("ugm_http_helper").get<std::string>());
 int ready[2];if(pipe(ready))return false;
 fcntl(ready[0],F_SETFD,FD_CLOEXEC);fcntl(ready[1],F_SETFD,FD_CLOEXEC);
 posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
 posix_spawn_file_actions_adddup2(&actions,ready[1],STDOUT_FILENO);
 posix_spawn_file_actions_addopen(&actions,STDIN_FILENO,"/dev/null",O_RDONLY,0);
 posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0);
 std::string executable=helper.string(),directory=root.string(),parent=std::to_string(getpid());
 char* argv[]={executable.data(),directory.data(),parent.data(),nullptr};pid_t pid=-1;
 int error=posix_spawn(&pid,executable.c_str(),&actions,nullptr,argv,environ);
 posix_spawn_file_actions_destroy(&actions);close(ready[1]);
 if(error){close(ready[0]);return false;}ugmChild=pid;
 fcntl(ready[0],F_SETFL,O_NONBLOCK);
 std::string reply;const auto deadline=Clock::now()+std::chrono::seconds(3);
 while(Clock::now()<deadline&&reply.size()<100&&reply.find('\n')==std::string::npos){
  pollfd item{ready[0],POLLIN,0};int n=poll(&item,1,100);if(n<0&&errno==EINTR)continue;if(n<0)break;if(!n)continue;
  char buffer[100];auto count=read(ready[0],buffer,sizeof buffer);if(count>0)reply.append(buffer,count);else if(count==0)break;
 }
 close(ready[0]);
 if(reply.rfind("READY ",0)==0&&reply.back()=='\n'&&pollUGM()==0)return true;
 stopUGM();return false;
}
json callback(const json &message) {
 const auto denied=[](){unavailable=true;return json{{"ok",false},{"status",501},{"error","host operation unavailable in plugin adapter"}};};
 if(message.value("host_op","")=="execute") {
  if(bouyomi::enabled()) {
   try {if(bouyomi::execute(message.at("params")))return {{"ok",true},{"status",200},{"exit_code",0}};}catch(...){return denied();}
  }
  if(startUGM(message.at("params")))return {{"ok",true},{"status",200},{"exit_code",0}};
  return denied();
 }
 if(message.value("host_op","")!="plugin")return denied();
 auto op=message.at("params");auto params=op.at("params");std::string key=moduleKey(params.value("module",""));
 if(bouyomi::enabled()&&key=="proxy_ex.dll") {
  const auto operation=op.value("operation","");
  if(operation=="saori_load"||operation=="saori_unload")return {{"ok",true}};
  if(operation!="saori_request")return denied();
  try {return {{"ok",true},{"status",200},{"response",bouyomi::saori(params.value("request",""))}};}catch(...){return denied();}
 }
 auto configured=settings.value("saori_backends",json::object());if(!configured.contains(key))return denied();
 std::string operation=op.value("operation","");
 if(operation=="saori_unload") {auto it=backends.find(key);if(it!=backends.end()){if(it->second.unload)it->second.unload();dlclose(it->second.handle);backends.erase(it);}return {{"ok",true}};}
 if(!backends.count(key)) {
  auto path=inside(resources,configured.at(key).get<std::string>());void* handle=dlopen(path.c_str(),RTLD_NOW|RTLD_LOCAL);if(!handle)return denied();
  auto request=reinterpret_cast<Req>(dlsym(handle,"plugin_request"));if(!request)request=reinterpret_cast<Req>(dlsym(handle,"request"));
  auto load=reinterpret_cast<Load>(dlsym(handle,"plugin_loadu"));if(!load)load=reinterpret_cast<Load>(dlsym(handle,"loadu"));
  auto unload=reinterpret_cast<Unload>(dlsym(handle,"plugin_unload"));if(!unload)unload=reinterpret_cast<Unload>(dlsym(handle,"unload"));
  if(!request){dlclose(handle);return denied();}
  if(load){auto directory=path.parent_path().string()+"/";char* owned=strdup(directory.c_str());if(!load(owned,directory.size())){dlclose(handle);return denied();}}
  backends[key]={handle,request,unload};
 }
 if(operation=="saori_load")return {{"ok",true}};
 if(operation!="saori_request")return denied();
 auto wire=params.value("request","");size_t size=0;auto out=backends.at(key).request(reinterpret_cast<const unsigned char*>(wire.data()),wire.size(),&size);
 if(!out||size>LIMIT)return denied();std::string result(reinterpret_cast<const char*>(out),size);
 result=codec(result,header(result,"Charset"),"UTF-8");
 bool ok=result.rfind("SAORI/1.0 200",0)==0||result.rfind("SAORI/1.0 204",0)==0;
 if(!ok)unavailable=true;
 return {{"ok",ok},{"response",result},{"status",ok?200:501}};
}
json transact(const json &message,int seconds=20) {
 auto deadline=Clock::now()+std::chrono::seconds(seconds);send(message,deadline);
 for(int i=0;i<256;++i){auto result=receive(deadline);if(!result.contains("host_op"))return result;send(callback(result),deadline);}
 throw std::runtime_error("host callback limit exceeded");
}
void launch(const fs::path &helper,const fs::path &cwd) {
 int in[2],out[2];if(pipe(in))throw std::runtime_error("pipe failed");if(pipe(out)){close(in[0]);close(in[1]);throw std::runtime_error("pipe failed");}
 for(int fd:{in[0],in[1],out[0],out[1]})fcntl(fd,F_SETFD,FD_CLOEXEC);
 posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
 posix_spawn_file_actions_adddup2(&actions,in[0],STDIN_FILENO);posix_spawn_file_actions_adddup2(&actions,out[1],STDOUT_FILENO);
 posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0);
 posix_spawn_file_actions_addchdir_np(&actions,cwd.c_str());
 posix_spawnattr_t attr;posix_spawnattr_init(&attr);ownsGroup = !getenv("OURIN_CORPUS_PARENT_OWNS_GROUP") || std::string(getenv("OURIN_CORPUS_PARENT_OWNS_GROUP")) != "1";
 if(ownsGroup){posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attr,0);}
 std::string path=helper.string();char *argv[]={path.data(),nullptr};pid_t pid;
 int error=posix_spawn(&pid,path.c_str(),&actions,&attr,argv,environ);
 posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attr);close(in[0]);close(out[1]);
 if(error){close(in[1]);close(out[0]);throw std::runtime_error("spawn helper failed");}
 child=pid;input=in[1];output=out[0];fcntl(input,F_SETFL,O_NONBLOCK);fcntl(output,F_SETFL,O_NONBLOCK);
 int noSigPipe=1;fcntl(input,F_SETNOSIGPIPE,noSigPipe);
}
std::string failure(int code,const std::string &reason) {return "PLUGIN/2.0 "+std::to_string(code)+" "+reason+"\r\nCharset: UTF-8\r\n\r\n";}
}
extern "C" int32_t plugin_loadu(char *directory,size_t) {
 free(directory);std::lock_guard<std::mutex> lock(guard);stop();bouyomi::reset();unavailable=false;
 try {
  Dl_info info{};if(!dladdr(reinterpret_cast<void*>(&plugin_loadu),&info))return 0;
  resources=fs::path(info.dli_fname).parent_path().parent_path()/"Resources";
  std::ifstream file(resources/"adapter.json");file>>settings;
  if(bouyomi::enabled())bouyomi::configure();
  auto load=settings.at("load");load["host_execute"]=true;auto root=inside(resources,load.at("ghost_root").get<std::string>());load["ghost_root"]=root.string();
  load["save_file"]=inside(resources,load.at("save_file").get<std::string>()).string();
  for(auto &entry:load.at("dic_entries"))inside(root,entry.at("path").get<std::string>());
  launch(inside(resources,settings.value("helper","yaya_core")),root);
  auto result=transact(load,60);
  // The core permits partially parsed dictionaries for SHIORI compatibility.
  // A plugin package must not silently report load success with missing handlers.
  bool complete=result.contains("loaded_dics")&&result["loaded_dics"].is_array();
  for(const auto &entry:load.at("dic_entries")) {
   const auto expected=fs::weakly_canonical(root/entry.at("path").get<std::string>());
   bool found=false;
   if(complete)for(const auto &path:result["loaded_dics"])
    if(path.is_string()&&fs::weakly_canonical(path.get<std::string>())==expected){found=true;break;}
   if(!found){complete=false;break;}
  }
  if(!result.value("ok",false)||unavailable||!complete){fprintf(stderr,"[OurinYayaPlugin] load rejected: status=%d unavailable=%d\n",result.value("status",0),unavailable);stop();return 0;}return 1;
 } catch(const std::exception &error){fprintf(stderr,"[OurinYayaPlugin] load failed: %s\n",error.what());stop();return 0;}
}
extern "C" const unsigned char* plugin_request(const unsigned char *data,size_t length,size_t *outLength) {
 std::lock_guard<std::mutex> lock(guard);unavailable=false;
 try {
  if(child<=0)responseBuffer=failure(503,"Not Loaded");
  else if(length>LIMIT||(!data&&length))responseBuffer=failure(400,"Invalid Request");
  else {
   std::string wire(reinterpret_cast<const char*>(data),length);wire=codec(wire,header(wire,"Charset"),"UTF-8");
   bouyomi::grantRequestRoot(wire);
   auto result=transact({{"cmd","plugin_request"},{"wire",wire}});
   if(unavailable)responseBuffer=failure(501,"Host Capability Unavailable");
   else if(result.value("ok",false)&&result.contains("wire")) {
    auto raw=result.at("wire").get<std::string>();responseBuffer=codec(raw,"UTF-8",header(raw,"Charset"));
   } else responseBuffer=failure(result.value("status",502),"Framework Error");
  }
 } catch(...){responseBuffer=failure(502,"Helper Failure");stop();}
 if(outLength)*outLength=responseBuffer.size();return reinterpret_cast<const unsigned char*>(responseBuffer.data());
}
extern "C" void plugin_unload() {
 std::lock_guard<std::mutex> lock(guard);
 try{if(child>0)transact({{"cmd","unload"}},10);}catch(...){}stop();
}
