// Explicit local TTS replacement for the original CeVIO/AIVOICE helper ABI.
// This does not emulate product voices or launch arbitrary Windows executables.
#pragma once

namespace localtts {
constexpr size_t WIRE_LIMIT = 65536;
std::string product, session;
fs::path payloadRoot;
bool attempted = false;
bool enabled() { return settings.contains("local_tts_backend"); }
std::string slashes(std::string s) { std::replace(s.begin(),s.end(),'\\','/');return s; }
void configure() {
 product=settings.at("local_tts_backend").get<std::string>();
 if((product!="cevio"&&product!="aivoice")||settings.value("bouyomi_tcp_backend",false)||settings.contains("ugm_http_helper")||!settings.value("saori_backends",json::object()).empty())throw std::runtime_error("invalid local TTS backend combination");
 payloadRoot=inside(resources,settings.at("load").at("ghost_root").get<std::string>());
 unsigned char random[16];arc4random_buf(random,sizeof random);session.clear();
 static const char hex[]="0123456789abcdef";
 for(unsigned char byte:random){session+=hex[byte>>4];session+=hex[byte&15];}
 attempted=false;
}
std::string rpc(const std::string& action,const std::string& argument="") {
 const auto deadline=Clock::now()+std::chrono::seconds(2);
 int port=50731;
 if(const char* raw=getenv("OURIN_LOCAL_TTS_PORT")) {
  const std::string value(raw);
  if(value.empty()||value.size()>5||value.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid local TTS port");
  port=std::stoi(value);if(port<1||port>65535)throw std::runtime_error("invalid local TTS port");
 }
 std::string wire=json{{"product",product},{"session",session},{"action",action},{"argument",argument}}.dump()+"\n";
 if(wire.size()>WIRE_LIMIT)throw std::runtime_error("local TTS request too large");
 const int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)throw std::runtime_error("local TTS socket failed");
 struct Close {int fd;~Close(){close(fd);}} closeSocket{fd};
 const int flags=fcntl(fd,F_GETFL,0);int yes=1;
 if(flags<0||setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof yes)||fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0)throw std::runtime_error("local TTS socket setup failed");
 auto wait=[&](short events) {
  for(;;) {
   const auto left=std::chrono::duration_cast<std::chrono::milliseconds>(deadline-Clock::now()).count();
   if(left<=0)throw std::runtime_error("local TTS timeout");
   pollfd item{fd,events,0};const int status=poll(&item,1,static_cast<int>(left));
   if(status<0&&errno==EINTR)continue;
   if(status<=0||!(item.revents&(events|POLLHUP)))throw std::runtime_error("local TTS socket unavailable");
   return;
  }
 };
 sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 if(connect(fd,reinterpret_cast<sockaddr*>(&address),sizeof address)<0) {
  if(errno!=EINPROGRESS)throw std::runtime_error("local TTS service unavailable");
  wait(POLLOUT);int error=0;socklen_t length=sizeof error;
  if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&length)||error)throw std::runtime_error("local TTS service unavailable");
 }
 size_t at=0;
 while(at<wire.size()) {
  wait(POLLOUT);auto count=::send(fd,wire.data()+at,wire.size()-at,0);
  if(count<0&&(errno==EINTR||errno==EAGAIN))continue;
  if(count<=0)throw std::runtime_error("local TTS send failed");at+=count;
 }
 std::string reply;
 for(;;) {
  wait(POLLIN);char buffer[4096];auto count=recv(fd,buffer,sizeof buffer,0);
  if(count<0&&(errno==EINTR||errno==EAGAIN))continue;
  if(count<=0)throw std::runtime_error("local TTS service closed without response");
  reply.append(buffer,count);if(reply.size()>WIRE_LIMIT)throw std::runtime_error("local TTS response too large");
  auto end=reply.find('\n');if(end==std::string::npos)continue;
  if(end+1!=reply.size())throw std::runtime_error("extra local TTS response data");
  const auto response=json::parse(reply.substr(0,end));
  if(!response.is_object()||!response.contains("ok")||!response.at("ok").is_boolean()||!response.at("ok").get<bool>()||!response.contains("result")||!response.at("result").is_string())throw std::runtime_error("local TTS operation rejected");
  const auto result=response.at("result").get<std::string>();
  for(unsigned char byte:result)if(byte<32||byte==127)throw std::runtime_error("control character in local TTS result");
  return result;
 }
}
void stopSession() {
 if(attempted&&!session.empty())try{(void)rpc("stop");}catch(...){}
 attempted=false;session.clear();product.clear();payloadRoot.clear();
}
bool execute(const json& params) {
 if(params.value("wait",false)||!params.value("arguments","").empty())return false;
 const auto raw=slashes(params.value("command",""));
 for(const auto& component:fs::path(raw))if(component=="..")return false;
 const auto command=fs::path(raw).lexically_normal().string();
 const auto relative=std::string("dll/")+(product=="cevio"?"myserver.exe":"server.exe");
 if(command!=relative&&command!=(payloadRoot/relative).string())return false;
 attempted=true;(void)rpc("start");return true;
}
std::vector<std::string> arguments(const std::string& wire) {
 if(wire.size()>WIRE_LIMIT||wire.find('\0')!=std::string::npos)throw std::runtime_error("invalid local TTS SAORI wire");
 std::istringstream lines(wire);std::string line;std::getline(lines,line);
 std::set<std::string> keys;std::map<int,std::string> values;
 while(std::getline(lines,line)) {
  if(line.empty()||line.back()!='\r')throw std::runtime_error("invalid SAORI line ending");
  line.pop_back();if(line.empty())break;
  const auto colon=line.find(':');if(colon==std::string::npos)throw std::runtime_error("invalid SAORI header");
  const auto key=lower(line.substr(0,colon));if(!keys.insert(key).second)throw std::runtime_error("duplicate SAORI header");
  std::string value=line.substr(colon+1);if(!value.empty()&&value.front()==' ')value.erase(0,1);
  if(key.rfind("argument",0)!=0)continue;
  const auto suffix=key.substr(8);
  if(suffix.empty()||suffix.size()>2||suffix.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid SAORI argument index");
  if(!values.emplace(std::stoi(suffix),value).second)throw std::runtime_error("duplicate SAORI argument");
 }
 std::vector<std::string> result;
 for(const auto& [index,value]:values){if(index!=result.size())throw std::runtime_error("noncontiguous SAORI arguments");result.push_back(value);}
 return result;
}
std::string saori(const std::string& wire) {
 const std::string prefix="SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: ";
 if(wire.rfind("GET Version SAORI/1.0\r\n",0)==0)return prefix+"Ourin Irodori Local TTS\r\n\r\n";
 if(wire.rfind("EXECUTE SAORI/1.0\r\n",0)!=0)throw std::runtime_error("invalid local TTS SAORI method");
 const auto args=arguments(wire);std::string result;
 if(args.size()==2&&args[0]=="/charset"&&(lower(args[1])=="utf-8"||lower(args[1])=="sjis")) {
  // The original flag selected Windows process stdout decoding. Our host IPC
  // carries Unicode strings and always returns explicitly tagged UTF-8.
  return "SAORI/1.0 204 No Content\r\nCharset: UTF-8\r\n\r\n";
 } else if(args.size()==1&&moduleKey(args[0])==(product=="cevio"?"checkcevio.exe":"check.exe")) {
  result=rpc("check");if(result!="True"&&result!="False")throw std::runtime_error("invalid local TTS check response");
 } else if(args.size()==2&&moduleKey(args[0])=="client.exe") {
  result=rpc("client",args[1]);
 } else throw std::runtime_error("unsupported local TTS proxy command");
 return prefix+result+"\r\n\r\n";
}
} // namespace localtts
