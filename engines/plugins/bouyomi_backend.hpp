// Ourin's opt-in Bouyomi TCP port. Original dictionaries stay unmodified.
// Supports standard Bouyomi voices 0..8; no Windows/SAPI/process emulation.
#pragma once

namespace bouyomi {
struct Config { bool silentDefault=false; };
fs::path payloadRoot;
fs::path saveFile;
std::set<fs::path> grantedGhostRoots;

void reset() { payloadRoot.clear();saveFile.clear();grantedGhostRoots.clear(); }
bool enabled() { return settings.value("bouyomi_tcp_backend",false); }
std::string slashes(std::string value) { std::replace(value.begin(),value.end(),'\\','/');return value; }
void configure() {
 payloadRoot=inside(resources,settings.at("load").at("ghost_root").get<std::string>());
 saveFile=inside(resources,settings.at("load").at("save_file").get<std::string>());
}
void grantRequestRoot(const std::string& wire) {
 if(!enabled()||header(wire,"ID")!="OnMenuExec")return;
 const auto value=slashes(header(wire,"Reference4"));
 if(value.empty()||!fs::path(value).is_absolute())return;
 // Only paths furnished by the host's menu event, never a path invented by a dictionary.
 if(grantedGhostRoots.size()<256)grantedGhostRoots.insert(fs::weakly_canonical(value));
}
std::string readLimited(const fs::path& path) {
 if(!fs::is_regular_file(path)||fs::file_size(path)>1024*1024)throw std::runtime_error("invalid Bouyomi input file");
 std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("unreadable Bouyomi input");
 return std::string(std::istreambuf_iterator<char>(f),{});
}
Config config() {
 Config result;
 const auto path=inside(payloadRoot,"config.json");
 if(!fs::exists(path))return result;
 const auto value=json::parse(readLimited(path));
 if(!value.is_object())throw std::runtime_error("invalid Bouyomi config");
 for(auto key:{"NoVoiceByDefault","JapaneseOnly"})
  if(value.contains(key)&&!value[key].is_null()&&!value[key].is_boolean())throw std::runtime_error("invalid Bouyomi config flag");
 if(value.contains("NoVoiceByDefault")&&!value["NoVoiceByDefault"].is_null())result.silentDefault=value["NoVoiceByDefault"].get<bool>();
 if(value.contains("BouyomiChanPath")&&!value["BouyomiChanPath"].is_null()) {
  if(!value["BouyomiChanPath"].is_array())throw std::runtime_error("invalid engine paths");
  for(const auto& entry:value["BouyomiChanPath"])
   if(!entry.is_string()||!entry.get<std::string>().empty())throw std::runtime_error("Windows engine launch unsupported");
 }
 return result;
}
std::string md5(const std::string& text) {
 // MD5 is the upstream voice-setting key, not a security or integrity primitive.
 unsigned char bytes[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
 CC_MD5(text.data(),static_cast<CC_LONG>(text.size()),bytes);
#pragma clang diagnostic pop
 static const char hex[]="0123456789abcdef";std::string out;
 for(auto byte:bytes){out+=hex[byte>>4];out+=hex[byte&15];}return out;
}
std::string voiceList() {
 const auto cfg=config();
 std::string out=cfg.silentDefault?"0,読み上げなし":"0,棒読みちゃん上で指定(デフォルト)";
 const char* names[]={"女性1","女性2","男性1","男性2","中性","ロボット","機械1","機械2"};
 for(int i=0;i<8;++i)out+=std::string(1,'\1')+std::to_string(i+1)+","+names[i];
 return out;
}
std::string characterNames(const std::string& raw) {
 const auto root=fs::weakly_canonical(slashes(raw));
 if(!grantedGhostRoots.count(root))throw std::runtime_error("ghost root not furnished by host");
 const auto path=inside(root,"ghost/master/descript.txt");
 auto text=readLimited(path);
 if(text.rfind("\xef\xbb\xbf",0)==0)text.erase(0,3);
 std::string charset;std::istringstream rawLines(text);std::string rawLine;
 while(std::getline(rawLines,rawLine)) {
  auto comment=rawLine.find("//");if(comment!=std::string::npos)rawLine.resize(comment);
  auto comma=rawLine.find(',');if(comma==std::string::npos)continue;
  auto trim=[](std::string s){const auto first=s.find_first_not_of(" \t\r");if(first==std::string::npos)return std::string();const auto last=s.find_last_not_of(" \t\r");return s.substr(first,last-first+1);};
  if(lower(trim(rawLine.substr(0,comma)))=="charset")charset=lower(trim(rawLine.substr(comma+1)));
 }
 if(charset=="shift_jis"||charset=="shift-jis"||charset=="cp932")text=codec(text,"CP932","UTF-8");
 else if(charset.empty()) {try{(void)codec(text,"UTF-8","UTF-16LE");}catch(...){text=codec(text,"CP932","UTF-8");}}
 else if(charset=="utf-8"||charset=="utf8"){(void)codec(text,"UTF-8","UTF-16LE");}
 else throw std::runtime_error("unsupported descript charset");
 std::map<int,std::string> names;std::istringstream lines(text);std::string line;
 while(std::getline(lines,line)) {
  if(!line.empty()&&line.back()=='\r')line.pop_back();
  auto comma=line.find(',');if(comma==std::string::npos)continue;
  const auto key=line.substr(0,comma);int scope=-1;
  if(key=="sakura.name")scope=0;else if(key=="kero.name")scope=1;
  else if(std::regex_match(key,std::regex("char[0-9]{1,5}\\.name")))scope=std::stoi(key.substr(4,key.size()-9));
  if(scope>=0) {
   const auto name=line.substr(comma+1);
   for(const unsigned char c:name)if(c<32)throw std::runtime_error("control character in character name");
   names[scope]=name;
  }
 }
 std::string out;for(const auto& [scope,name]:names){if(!out.empty())out+='\1';out+=name;}
 return out;
}
std::string saori(const std::string& wire) {
 if(wire.rfind("GET Version SAORI/1.0\r\n",0)==0)return "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: Ourin Bouyomi TCP\r\n\r\n";
 if(wire.rfind("EXECUTE SAORI/1.0\r\n",0)!=0)throw std::runtime_error("invalid Bouyomi SAORI method");
 std::vector<std::string> args;
 std::set<std::string> keys;std::istringstream lines(wire);std::string line;
 std::map<int,std::string> arguments;
 while(std::getline(lines,line)) {
  if(!line.empty()&&line.back()=='\r')line.pop_back();
  if(line.empty())break;
  auto colon=line.find(':');if(colon==std::string::npos)continue;
  const auto key=lower(line.substr(0,colon));if(!keys.insert(key).second)throw std::runtime_error("duplicate SAORI header");
  if(key.rfind("argument",0)==0) {
   const auto number=key.substr(8);
   if(number.empty()||number.size()>2||number.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid SAORI argument");
   std::string value=line.substr(colon+1);if(!value.empty()&&value.front()==' ')value.erase(0,1);
   if(!arguments.emplace(std::stoi(number),value).second)throw std::runtime_error("duplicate argument index");
  }
 }
 for(const auto& [index,value]:arguments){if(index!=args.size())throw std::runtime_error("non-contiguous arguments");args.push_back(value);}
 std::string result;
 if(args.size()==2&&args[0]=="/charset"&&lower(args[1])=="utf-8")result="1";
 else if(args.size()>=2&&(slashes(args[0])=="core.exe"||slashes(args[0])=="./core.exe")) {
  if(args.size()==2&&args[1]=="-l")result=voiceList();
  else if(args.size()==3&&args[1]=="-hash")result=md5(args[2]);
  else if(args.size()==3&&args[1]=="-count")result=characterNames(args[2]);
  else throw std::runtime_error("unsupported Bouyomi proxy command");
 } else throw std::runtime_error("unsupported Bouyomi proxy command");
 if(result.find_first_of("\r\n")!=std::string::npos)throw std::runtime_error("invalid SAORI result characters");
 return "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: "+result+"\r\n\r\n";
}
struct Dialog {int scope;std::string text;};
std::vector<Dialog> dialogs(const std::string& script) {
 std::vector<Dialog> result;int scope=0;bool quick=false;std::string text;
 const auto flush=[&](){if(!text.empty()){result.push_back({scope,text});text.clear();}};
 for(size_t i=0;i<script.size();) {
  if(script[i]!='\\'){if(!quick)text+=script[i];++i;continue;}
  const size_t start=i++;
  if(i>=script.size()){if(!quick)text+='\\';break;}
  size_t prefix=i;while(i<script.size()&&script[i]=='_')++i;
  if(i>=script.size()){if(!quick)text+=script.substr(start);break;}
  const char command=script[i++];std::string bracket;
  if(i<script.size()&&script[i]=='[') {
   const size_t begin=++i;bool quoted=false;
   while(i<script.size()) {
    if(script[i]=='"'&&(i==begin||script[i-1]!='\\'))quoted=!quoted;
    if(script[i]==']'&&!quoted&&(i==begin||script[i-1]!='\\'))break;
    ++i;
   }
   if(i==script.size())throw std::runtime_error("unterminated Sakura Script command");
   bracket=script.substr(begin,i-begin);++i;
  }
  const bool underscored=prefix+1<i&&script[prefix]=='_';
  if(underscored&&command=='q'){quick=!quick;continue;}
  if(command=='!'&&(bracket=="quicksection,1"||bracket=="quicksection,true")){quick=true;continue;}
  if(command=='!'&&(bracket=="quicksection,0"||bracket=="quicksection,false")){quick=false;continue;}
  if(quick)continue;
  int next=-1;
  if(!underscored&&(command=='0'||command=='h'))next=0;
  else if(!underscored&&(command=='1'||command=='u'))next=1;
  else if(!underscored&&command=='p'&&!bracket.empty()&&bracket.size()<6&&bracket.find_first_not_of("0123456789")==std::string::npos)next=std::stoi(bracket);
  if(next>=0){flush();scope=next;}
  // Wait commands carry an unbracketed single digit.
  if(command=='w'&&i<script.size()&&script[i]>='1'&&script[i]<='9')++i;
 }
 flush();return result;
}
int voiceFor(const std::string& ghost,int scope) {
 const auto key=md5(ghost+std::to_string(scope))+".voice";
 const auto currentSave=inside(resources,settings.at("load").at("save_file").get<std::string>());
 if(!fs::exists(currentSave))return 0;
 const auto state=json::parse(readLimited(currentSave));
 if(!state.is_object())throw std::runtime_error("invalid Ourin state");
 if(!state.contains(key))return 0;
 const auto& value=state[key];std::string number;
 if(value.value("t","")=="i"&&value.contains("v")&&value["v"].is_number_integer())number=std::to_string(value["v"].get<int>());
 else if(value.value("t","")=="s"&&value.contains("v")&&value["v"].is_string())number=value["v"].get<std::string>();
 else throw std::runtime_error("invalid voice setting");
 if(number.size()!=1||number[0]<'0'||number[0]>'8')throw std::runtime_error("Windows SAPI voice unsupported");
 return number[0]-'0';
}
void sendTCP(const std::string& text,int voice,Clock::time_point deadline) {
 if(Clock::now()>=deadline)throw std::runtime_error("Bouyomi request deadline exceeded");
 int port=50001;
 if(const auto value=getenv("OURIN_BOUYOMI_PORT")) {
  const std::string input(value);
  if(input.empty()||input.size()>5||input.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid Bouyomi port");
  port=std::stoi(input);if(port<1||port>65535)throw std::runtime_error("invalid Bouyomi port");
 }
 const int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)throw std::runtime_error("socket failed");
 struct Close {int fd;~Close(){close(fd);}} closeSocket{fd};
 int yes=1;const int flags=fcntl(fd,F_GETFL,0);
 if(flags<0||setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof yes)||fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0)throw std::runtime_error("socket setup failed");
 sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 auto wait=[&](){auto left=std::chrono::duration_cast<std::chrono::milliseconds>(deadline-Clock::now()).count();pollfd item{fd,POLLOUT,0};if(left<=0||poll(&item,1,static_cast<int>(left))<=0||!(item.revents&POLLOUT))throw std::runtime_error("Bouyomi TCP timeout");};
 if(connect(fd,reinterpret_cast<sockaddr*>(&address),sizeof address)<0){if(errno!=EINPROGRESS)throw std::runtime_error("Bouyomi unavailable");wait();int error=0;socklen_t size=sizeof error;if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size)||error)throw std::runtime_error("Bouyomi unavailable");}
 std::string packet;const auto word=[&](unsigned value){packet+=static_cast<char>(value&255);packet+=static_cast<char>((value>>8)&255);};
 word(1);word(65535);word(65535);word(65535);word(voice);packet+='\0';
 for(int i=0;i<4;++i)packet+=static_cast<char>((text.size()>>(8*i))&255);packet+=text;
 size_t at=0;while(at<packet.size()){wait();const auto n=::send(fd,packet.data()+at,packet.size()-at,0);if(n<0&&(errno==EAGAIN||errno==EINTR))continue;if(n<=0)throw std::runtime_error("Bouyomi send failed");at+=n;}
}
bool execute(const json& params) {
 if(params.value("wait",false))return false;
 const auto command=slashes(params.value("command",""));
 if(command!="core.exe"&&command!=(payloadRoot/"core.exe").string())return false;
 const auto deadline=Clock::now()+std::chrono::seconds(2);
 const auto args=params.value("arguments","");const auto cfg=config();
 if(args=="-e")return true; // No configured engine executable: the upstream operation is empty.
 std::smatch match;
 if(!std::regex_match(args,match,std::regex("^-g \"([^\"\\r\\n]*)\" -v ([0-8]) \"([\\s\\S]*)\"$")))return false;
 const auto pieces=dialogs(match[3]);const auto ghost=match[1].str();
 std::vector<int> voices;
 for(const auto& piece:pieces) {
  if(Clock::now()>=deadline)throw std::runtime_error("Bouyomi request deadline exceeded");
  voices.push_back(voiceFor(ghost,piece.scope));
 }
 for(size_t i=0;i<pieces.size();++i){if(voices[i]==0&&cfg.silentDefault)continue;sendTCP(pieces[i].text,voices[i],deadline);}
 return true;
}
} // namespace bouyomi
