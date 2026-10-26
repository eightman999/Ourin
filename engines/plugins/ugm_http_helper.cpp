// Ourin UGM static-file helper. Apache-2.0. No third-party source or payload.
// Replaces only the explicitly configured localweb/ugm_server.exe operation.
#include <arpa/inet.h>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <poll.h>
#include <regex>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
namespace fs = std::filesystem;
namespace {
volatile sig_atomic_t stopping = 0;
void stopSignal(int) { stopping = 1; }
struct FD { int value; explicit FD(int v=-1):value(v){} ~FD(){if(value>=0)close(value);} FD(const FD&)=delete; };
bool sendAll(int fd, const std::string& data) {
 size_t at=0; while(at<data.size()) {auto n=send(fd,data.data()+at,data.size()-at,0);if(n<0&&errno==EINTR)continue;if(n<=0)return false;at+=n;}return true;
}
void reply(int fd,int status,const std::string& reason,const std::string& body="",bool head=false,const std::string& type="text/plain; charset=utf-8") {
 std::string header="HTTP/1.1 "+std::to_string(status)+" "+reason+"\r\nConnection: close\r\nContent-Type: "+type+"\r\nContent-Length: "+std::to_string(body.size())+"\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\n\r\n";
 if(sendAll(fd,header)&&!head)sendAll(fd,body);
}
std::string lowercase(std::string s) {for(char& c:s)if(c>='A'&&c<='Z')c+=32;return s;}
std::string trim(std::string s) {const auto a=s.find_first_not_of(" \t\r"),b=s.find_last_not_of(" \t\r");return a==std::string::npos?"":s.substr(a,b-a+1);}
bool decodePath(const std::string& target,std::string& path) {
 if(target.empty()||target.front()!='/')return false;
 auto query=target.find('?');const auto raw=target.substr(0,query);path.clear();
 const auto hex=[](char c)->int{if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;};
 for(size_t i=0;i<raw.size();++i) {unsigned char c=raw[i];if(c=='%'){if(i+2>=raw.size())return false;int a=hex(raw[i+1]),b=hex(raw[i+2]);if(a<0||b<0)return false;c=a*16+b;i+=2;}if(c<32||c==127||c=='\\')return false;path+=static_cast<char>(c);}
 return true;
}
std::string mime(const std::string& path) {
 const auto ext=lowercase(fs::path(path).extension().string());
 static const std::map<std::string,std::string> types={{".html","text/html; charset=utf-8"},{".js","text/javascript; charset=utf-8"},{".css","text/css; charset=utf-8"},{".json","application/json; charset=utf-8"},{".png","image/png"},{".jpg","image/jpeg"},{".jpeg","image/jpeg"},{".gif","image/gif"},{".webp","image/webp"},{".ico","image/x-icon"},{".svg","image/svg+xml"},{".txt","text/plain; charset=utf-8"}};
 auto found=types.find(ext);return found==types.end()?"application/octet-stream":found->second;
}
// openat + O_NOFOLLOW on every component prevents both traversal and symlink races.
int openFile(int root,const std::string& path) {
 int current=dup(root);if(current<0)return -1;
 const auto relative=path.substr(1);size_t start=0;
 while(start<relative.size()) {
  const auto end=relative.find('/',start);const auto part=relative.substr(start,end==std::string::npos?std::string::npos:end-start);
  if(part.empty()||part=="."||part=="..") {close(current);return -1;}
  const bool last=end==std::string::npos;
  int next=openat(current,part.c_str(),O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC|(last?0:O_DIRECTORY));close(current);if(next<0)return -1;current=next;
  if(last)return current;start=end+1;
 }
 close(current);return -1;
}
void serve(int client,int root,int port) {
 timeval timeout{2,0};setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout);
 const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
 std::string request;
 while(request.find("\r\n\r\n")==std::string::npos) {
  if(stopping||std::chrono::steady_clock::now()>deadline)return;
  pollfd item{client,POLLIN,0};int ready=poll(&item,1,100);if(ready<0&&errno==EINTR)continue;if(ready<0)return;if(!ready)continue;
  char buffer[2048];auto n=recv(client,buffer,sizeof buffer,0);if(n<=0)return;request.append(buffer,n);if(request.size()>16384){reply(client,431,"Request Header Fields Too Large");return;}
 }
 auto first=request.find("\r\n"),space=request.find(' '),second=request.find(' ',space+1);
 if(space>=first||second>=first){reply(client,400,"Bad Request");return;}
 const auto method=request.substr(0,space),target=request.substr(space+1,second-space-1),version=request.substr(second+1,first-second-1);
 if(method!="GET"&&method!="HEAD"){reply(client,405,"Method Not Allowed");return;}
 if(version!="HTTP/1.1"&&version!="HTTP/1.0"){reply(client,400,"Bad Request");return;}
 std::map<std::string,std::string> headers;
 for(size_t at=first+2;;) {auto end=request.find("\r\n",at);if(end==at)break;auto colon=request.find(':',at);if(colon>=end){reply(client,400,"Bad Request");return;}auto key=lowercase(request.substr(at,colon-at));if(headers.count(key)){reply(client,400,"Bad Request");return;}headers[key]=trim(request.substr(colon+1,end-colon-1));at=end+2;}
 const std::string local="localhost:"+std::to_string(port),numeric="127.0.0.1:"+std::to_string(port);
 const auto host=lowercase(headers["host"]);
 if(host!=local&&host!=numeric){reply(client,403,"Forbidden");return;}
 if(headers.count("origin")&&headers["origin"]!="http://"+host){reply(client,403,"Forbidden");return;}
 std::string path;if(!decodePath(target,path)){reply(client,400,"Bad Request");return;}
 if(path.back()=='/')path+="index.html";
 FD file(openFile(root,path));struct stat stat{};
 if(file.value<0||fstat(file.value,&stat)||!S_ISREG(stat.st_mode)){reply(client,404,"Not Found");return;}
 if(stat.st_size<0||stat.st_size>32*1024*1024){reply(client,413,"Content Too Large");return;}
 std::string data;data.reserve(static_cast<size_t>(stat.st_size));char chunk[32768];
 for(;;){auto n=read(file.value,chunk,sizeof chunk);if(n<0&&errno==EINTR)continue;if(n<0){reply(client,500,"Read Error");return;}if(!n)break;data.append(chunk,n);if(data.size()>32*1024*1024){reply(client,413,"Content Too Large");return;}}
 reply(client,200,"OK",data,method=="HEAD",mime(path));
}
int run(const fs::path& payload,pid_t parent) {
 if(parent<=1||getppid()!=parent)return 2;
 const fs::path local=payload/"localweb",root=local/"html";
 if(fs::weakly_canonical(root)!=fs::absolute(root).lexically_normal())return 2;
 FD rootFD(open(root.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC));if(rootFD.value<0)return 2;
 int port=8000;std::ifstream config(payload/"ugm_config.txt");std::string line;std::regex setting("localhost_number,\\s*([0-9]+)\\s*");std::smatch match;
 while(std::getline(config,line)) {
  line=trim(line);if(!std::regex_match(line,match,setting))continue;
  try{const auto value=std::stoll(match[1]);port=(value>=1024&&value<=65535&&value!=9801&&value!=9821)?static_cast<int>(value):8000;}catch(...){port=8000;}
 }
 FD server(socket(AF_INET,SOCK_STREAM,0));if(server.value<0)return 3;
 fcntl(server.value,F_SETFD,FD_CLOEXEC);int reuse=1;setsockopt(server.value,SOL_SOCKET,SO_REUSEADDR,&reuse,sizeof reuse);
 sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 if(bind(server.value,reinterpret_cast<sockaddr*>(&address),sizeof address)||listen(server.value,8))return 3;
 const auto running=local/"running.signal",shutdown=local/"shutdown.signal";
 // A stale shutdown request is a startup failure, never a READY-then-exit success.
 std::error_code shutdownError;if(fs::exists(shutdown,shutdownError)||shutdownError)return 5;
 FD marker(open(running.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600));if(marker.value<0)return 4;
 struct stat own{};fstat(marker.value,&own);
 std::printf("READY %d\n",port);std::fflush(stdout);
 while(!stopping&&getppid()==parent&&kill(parent,0)==0) {
  std::error_code ec;if(fs::exists(shutdown,ec))break;
  pollfd item{server.value,POLLIN,0};int n=poll(&item,1,100);if(n<0&&errno==EINTR)continue;if(n<0)break;if(n>0){FD client(accept(server.value,nullptr,nullptr));if(client.value>=0)serve(client.value,rootFD.value,port);}
 }
 struct stat current{};if(lstat(running.c_str(),&current)==0&&current.st_dev==own.st_dev&&current.st_ino==own.st_ino)unlink(running.c_str());
 return 0;
}
}
int main(int argc,char** argv) {
 if(argc!=3)return 2;
 signal(SIGTERM,stopSignal);signal(SIGINT,stopSignal);signal(SIGPIPE,SIG_IGN);
 try {size_t count=0;long parent=std::stol(argv[2],&count);if(count!=std::strlen(argv[2]))return 2;return run(fs::path(argv[1]),static_cast<pid_t>(parent));}catch(...){return 2;}
}
