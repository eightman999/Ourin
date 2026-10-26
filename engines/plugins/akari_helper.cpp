// One Akari engine per process: isolate Swift globals, ObjC classes and failures.
#include <nlohmann/json.hpp>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <string>
#include <unistd.h>
using json=nlohmann::json;
constexpr size_t LIMIT=8*1024*1024;
using Load=int32_t(*)(void*,int32_t);
using Request=void*(*)(void*,int32_t*);
using Unload=int32_t(*)();
std::string hex(const std::string& s){static const char* d="0123456789abcdef";std::string r;for(unsigned char c:s){r+=d[c>>4];r+=d[c&15];}return r;}
std::string unhex(const std::string& s){if(s.size()%2||s.size()>LIMIT*2)throw std::runtime_error("wire limit");std::string r;for(size_t i=0;i<s.size();i+=2){auto d=[](char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;throw std::runtime_error("invalid hex");};r+=char(d(s[i])*16+d(s[i+1]));}return r;}
int main(){
 int protocol=dup(STDOUT_FILENO);if(protocol<0)return 1;fcntl(protocol,F_SETFD,FD_CLOEXEC);dup2(STDERR_FILENO,STDOUT_FILENO);
 void* library=nullptr;Request request=nullptr;Unload unload=nullptr;bool loaded=false;
 while(true){std::string line;char c;while(read(STDIN_FILENO,&c,1)==1&&c!='\n'){if(line.size()>=LIMIT*3)return 2;line+=c;}if(line.empty())break;
 json reply={{"ok",false}};bool finish=false;
 try{auto m=json::parse(line);auto cmd=m.value("cmd","");
 if(cmd=="load"&&!loaded){library=dlopen(m.at("library").get<std::string>().c_str(),RTLD_NOW|RTLD_LOCAL);
 if(library){auto start=reinterpret_cast<Load>(dlsym(library,"loadu"));request=reinterpret_cast<Request>(dlsym(library,"request"));unload=reinterpret_cast<Unload>(dlsym(library,"unload"));
 if(start&&request&&unload){auto path=m.at("root").get<std::string>()+"/";loaded=start(strdup(path.c_str()),static_cast<int32_t>(path.size()))!=0;reply["ok"]=loaded;}}}
 else if(cmd=="request"&&loaded){auto wire=unhex(m.at("wire").get<std::string>());auto end=wire.find("\r\n");auto first=wire.substr(0,end);
 if(first=="GET PLUGIN/2.0M"||first=="NOTIFY PLUGIN/2.0M")wire.erase(end-1,1);
 else if(first!="GET PLUGIN/2.0"&&first!="NOTIFY PLUGIN/2.0")throw std::runtime_error("protocol");
 auto input=malloc(wire.size());if(!input)throw std::bad_alloc();memcpy(input,wire.data(),wire.size());int32_t size=static_cast<int32_t>(wire.size());void* output=request(input,&size);
 if(output&&size>=0&&size<=LIMIT){std::string response(static_cast<char*>(output),size);if(response.rfind("PLUGIN/2.0 ",0)==0||response.rfind("PLUGIN/2.0M ",0)==0)reply={{"ok",true},{"wire",hex(response)}};}free(output);}
 else if(cmd=="unload"){reply["ok"]=!loaded||unload();loaded=false;finish=true;}
 }catch(...){reply={{"ok",false}};}
 auto out=reply.dump()+"\n";for(size_t at=0;at<out.size();){auto n=write(protocol,out.data()+at,out.size()-at);if(n<=0)return 3;at+=n;}if(finish)break;
 }
 // Process exit releases Swift runtime state; never unload a live Swift image.
 return 0;
}
