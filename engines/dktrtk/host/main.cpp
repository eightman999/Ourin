#include "ported.cpp"
#include "encoding.hpp"
#include <iostream>
#include <stdexcept>
struct EndOfInput {};
static bool readLine(std::string &s) {
 s.clear();int c;
 while ((c=std::cin.get())!=EOF) {if(c=='\n'){if(!s.empty()&&s.back()=='\r')s.pop_back();return true;}s+=(char)c;if(s.size()>1048576)throw std::runtime_error("line limit");}
 if(!s.empty())throw EndOfInput{};return false;
}
int main(int argc, char** argv) {
 bool cp932=false;
 if (argc==3 && std::string(argv[1])=="--wire-charset" && std::string(argv[2])=="CP932") cp932=true;
 else if (argc!=1) { std::cerr<<"usage: dktrtk-host [--wire-charset CP932]\n"; return 2; }
 bool loaded=false;
 try {
  std::string line;
  if(!readLine(line))return 0;
  if(line.rfind("*L:",0)!=0)throw std::runtime_error("load control required");
  auto path=line.substr(3);
  if(cp932 && !OurinTranscode(path,"UTF-8","CP932")) throw std::runtime_error("invalid CP932 load path");
  auto p=malloc(path.size());memcpy(p,path.data(),path.size());
  if(!load(p,path.size()))throw std::runtime_error("script load failed");loaded=true;
  while(readLine(line)) {
   if(line=="*U:")break;
   if(line.rfind("*S:",0)!=0)throw std::runtime_error("sync required");
   std::cout<<line<<"\r\n"<<std::flush;
   std::string wire;
   do {if(!readLine(line))throw EndOfInput{};wire+=line+"\r\n";if(wire.size()>1048576)throw std::runtime_error("frame limit");}while(!line.empty());
   if(cp932 && (!OurinTranscode(wire,"UTF-8","CP932") || !OurinRewriteCharset(wire,"Shift_JIS","UTF-8")))
       throw std::runtime_error("invalid CP932 request or Charset");
   p=malloc(wire.size());memcpy(p,wire.data(),wire.size());long len=wire.size();
   p=request(p,&len);
   if(!p)throw std::runtime_error("script request failed");
   std::string response((char*)p,len-1);free(p);
   if(response.size()>1048576||response.size()<4||response.substr(response.size()-4)!="\r\n\r\n")throw std::runtime_error("malformed response");
   if(cp932 && (!OurinRewriteCharset(response,"UTF-8","Shift_JIS") || !OurinTranscode(response,"CP932","UTF-8")))
       throw std::runtime_error("response cannot be represented in CP932 or has incompatible Charset");
   std::cout.write(response.data(),response.size());std::cout.flush();
  }
  bool ok=unload();loaded=false;return ok?0:1;
 }catch(const EndOfInput &){if(loaded)return unload()?0:1;return 0;}
 catch(const std::exception &e){std::cerr<<e.what()<<"\n";if(loaded)unload();return 1;}
}
