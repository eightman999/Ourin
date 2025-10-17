// 
// AYA version 5
//
// written by umeici. 2004
// 

#if defined(WIN32) || defined(_WIN32_WCE)
#include "stdafx.h"
#include <io.h>
#include <fcntl.h>
#endif

#include <vector>
#include <ctime>
#include <locale>
#include <clocale>
#include <locale>
#include <stdio.h>

#include "aya5.h"
#include "basis.h"
#include "ayavm.h"
#include "ccct.h"
#include "manifest.h"
#include "messages.h"
#include "misc.h"

class CAyaVMWrapper;

static std::vector<CAyaVMWrapper*> vm;
static yaya::string_t modulename;
static std::vector<void (*)(const yaya::char_t *str, int mode, int id)> loghandler_list;
static size_t id_now=0;
static long logsend_hwnd = 0;

#if defined(WIN32)
void*  g_hModule = NULL;
#endif

//////////DEBUG/////////////////////////
#ifdef _WINDOWS
#ifdef _DEBUG
#include <crtdbg.h>
#define new new( _NORMAL_BLOCK, __FILE__, __LINE__)
#endif
#endif
////////////////////////////////////////

class CAyaVMWrapper {
private:
	CAyaVM *vm;

public:
	CAyaVMWrapper(const yaya::string_t &path, yaya::global_t h, long len, bool is_utf8) {
		vm = new CAyaVM();

		if (logsend_hwnd != 0) {
			SetLogRcvWnd(logsend_hwnd);
			logsend_hwnd = 0;
		}

		vm->logger().Set_loghandler(loghandler_list[id_now]);

		vm->basis().SetModuleName(modulename,L"",L"normal");

		vm->load();

		vm->basis().SetPath(h, len, is_utf8);
		vm->basis().Configure();

		if ( vm->basis().IsSuppress() ) {
			vm->logger().Message(10,E_E);

			CAyaVM *vme = new CAyaVM();

			vme->logger().Set_loghandler(loghandler_list[id_now]);

			vme->basis().SetModuleName(modulename,L"_emerg",L"emergency");

			vme->load();

			vme->basis().SetPath(h, len, is_utf8);
			vme->basis().Configure();

			vme->logger().Message(11,E_E);

			if( ! vme->basis().IsSuppress() ) {
				vme->logger().AppendErrorLogHistoryToBegin(std_move(vm->logger().GetErrorLogHistory())); //�G���[���O�������p��

				std::swap(vm, vme);
			}
			delete vme;
		}
		vm->basis().ExecuteLoad();
	}
	virtual ~CAyaVMWrapper() {
		vm->basis().Termination();

		vm->unload();

		delete vm;
	}

	void Set_loghandler(void (*loghandler)(const yaya::char_t *str, int mode, int id)){
		vm->logger().Set_loghandler(loghandler);
	}

	bool IsSuppress(void) {
		if ( ! vm ) { return true; }
		return vm->basis().IsSuppress() != 0;
	}
	bool IsEmergency(void) {
		if( ! vm ) { return false; }
		return !wcscmp(vm->basis().GetModeName(),L"emergency");
	}

	yaya::global_t ExecuteRequest(yaya::global_t h, long *len, bool is_debug)
	{
		if ( ! vm ) { return NULL; }
		
		vm->request_before();

		yaya::global_t r = vm->basis().ExecuteRequest(h,len,is_debug);

		vm->request_after();

		return r;
	}

	void SetLogRcvWnd(long hwnd)
	{
		if ( ! vm ) { return; }
#if defined(WIN32)
		vm->basis().SetLogRcvWnd(hwnd);
#endif
	}

};

class CAyaVMPrepare {
public:
	CAyaVMPrepare(void) {
		vm.clear();
		vm.emplace_back(nullptr); //0��VM��load�ȂǏ]���֐��Ŏg���W��
	}
	~CAyaVMPrepare(void) {
		size_t n = vm.size();
		for ( size_t i = 0 ; i < n ; ++i ) {
			if ( vm[i] ) {
				delete vm[i];
			}
		}
	}
};

static CAyaVMPrepare prepare; //����̓R���X�g���N�^�E�f�X�g���N�^�쓮�p

/* -----------------------------------------------------------------------
 *  DllMain
 * -----------------------------------------------------------------------
 */
#if defined(WIN32)

static void AYA_InitModule(HMODULE hModule)
{
#ifdef _DEBUG
	int tmpFlag = _CrtSetDbgFlag( _CRTDBG_REPORT_FLAG );
	tmpFlag |= _CRTDBG_LEAK_CHECK_DF | _CRTDBG_ALLOC_MEM_DF;
	tmpFlag &= ~_CRTDBG_CHECK_CRT_DF;
	_CrtSetDbgFlag( tmpFlag );
#endif

	g_hModule = hModule;

	if ( IsUnicodeAware() ) {
		wchar_t path[MAX_PATH] = L"";
		::GetModuleFileNameW(hModule, path, sizeof(path) / sizeof(path[0]));
		
		wchar_t drive[_MAX_DRIVE], dir[_MAX_DIR], fname[_MAX_FNAME], ext[_MAX_EXT];
		_wsplitpath(path, drive, dir, fname, ext);

		modulename = fname;
	}
	else {
		char path[MAX_PATH] = "";
		::GetModuleFileNameA(hModule, path, sizeof(path));
		
		char drive[_MAX_DRIVE], dir[_MAX_DIR], fname[_MAX_FNAME], ext[_MAX_EXT];
		_splitpath(path, drive, dir, fname, ext);

		std::string	mbmodulename = fname;

		Ccct::MbcsToUcs2Buf(modulename, mbmodulename, CHARSET_DEFAULT);
	}

	Ccct::sys_setlocale(LC_ALL);
}

#endif //win32

#if !defined(AYA_MAKE_EXE)
#if defined(WIN32)

extern "C" BOOL APIENTRY DllMain(HMODULE hModule, DWORD  ul_reason_for_call, LPVOID /*lpReserved*/)
{
	// ���W���[���̎�t�@�C�������擾
	// NT�n�ł͂����Ȃ�UNICODE�Ŏ擾�ł��邪�A9x�n���l������MBCS�Ŏ擾���Ă���UCS-2�֕ϊ�
	if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
		AYA_InitModule(hModule);
	}

	return TRUE;
}

#endif //win32
#endif //aya_make_exe

inline void enlarge_loghandler_list(size_t size){
	loghandler_list.reserve(size);
	while(loghandler_list.size()<size)
		loghandler_list.emplace_back(nullptr);
}

/* -----------------------------------------------------------------------
 *  load
 * -----------------------------------------------------------------------
 */
extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB loadu(yaya::global_t h, long len)
{
	if ( vm[0] ) { delete vm[0]; }

	id_now=0;
	enlarge_loghandler_list(1);
	vm[0] = new CAyaVMWrapper(modulename,h,len,true);

#if defined(WIN32) || defined(_WIN32_WCE)
	::GlobalFree(h);
#elif defined(POSIX)
    free(h);
#endif

    return 1;
}

extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB load(yaya::global_t h, long len)
{
	if ( vm[0] ) { return 1; } //loadu�œǂݍ��܂ꂽ��ēx�Ăяo���ꂽ�Ɖ���

	id_now=0;
	enlarge_loghandler_list(1);
	vm[0] = new CAyaVMWrapper(modulename,h,len,false);

#if defined(WIN32) || defined(_WIN32_WCE)
	::GlobalFree(h);
#elif defined(POSIX)
    free(h);
#endif

    return 1;
}

extern "C" DLLEXPORT long FUNCATTRIB multi_loadu(yaya::global_t h, long len)
{
	long id = 0;
	
	long n = (long)vm.size();
	for ( long i = 1 ; i < n ; ++i ) { //1���� 0�Ԃ͏]���p
		if ( vm[i] == NULL ) {
			id = i;
		}
	}

	if ( id <= 0 ) {
		vm.emplace_back(nullptr);
		id = (long)vm.size() - 1;
	}

	enlarge_loghandler_list(id+1);
	id_now=id;
	vm[id] = new CAyaVMWrapper(modulename,h,len,true);

#if defined(WIN32) || defined(_WIN32_WCE)
	::GlobalFree(h);
#elif defined(POSIX)
    free(h);
#endif

	return id;
}

extern "C" DLLEXPORT long FUNCATTRIB multi_load(yaya::global_t h, long len)
{
	long id = 0;
	
	long n = (long)vm.size();
	for ( long i = 1 ; i < n ; ++i ) { //1���� 0�Ԃ͏]���p
		if ( vm[i] == NULL ) {
			id = i;
		}
	}

	if ( id <= 0 ) {
		vm.emplace_back(nullptr);
		id = (long)vm.size() - 1;
	}

	enlarge_loghandler_list(id+1);
	id_now=id;
	vm[id] = new CAyaVMWrapper(modulename,h,len,false);

#if defined(WIN32) || defined(_WIN32_WCE)
	::GlobalFree(h);
#elif defined(POSIX)
    free(h);
#endif

	return id;
}

/* -----------------------------------------------------------------------
 *  unload
 * -----------------------------------------------------------------------
 */
extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB unload()
{
	if ( vm[0] ) {
		delete vm[0];
		vm[0] = NULL;
	}

    return 1;
}

extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB multi_unload(long id)
{
	if ( id <= 0 || id > (long)vm.size() || vm[id] == NULL ) { //1���� 0�Ԃ͏]���p
		return 0;
	}

	delete vm[id];
	vm[id] = NULL;

	return 1;
}

/* -----------------------------------------------------------------------
 *  request
 * -----------------------------------------------------------------------
 */
extern "C" DLLEXPORT yaya::global_t FUNCATTRIB request(yaya::global_t h, long *len)
{
	if ( vm[0] ) {
		return vm[0]->ExecuteRequest(h, len, false);
	}
	else {
		return NULL;
	}
}

extern "C" DLLEXPORT yaya::global_t FUNCATTRIB multi_request(long id, yaya::global_t h, long *len)
{
	if ( id <= 0 || id > (long)vm.size() || vm[id] == NULL ) { //1���� 0�Ԃ͏]���p
		return 0;
	}

	if ( vm[id] ) {
		return vm[id]->ExecuteRequest(h, len, false);
	}
	else {
		return NULL;
	}
}

/* -----------------------------------------------------------------------
 *  CI_check_failed
 * -----------------------------------------------------------------------
 */
 extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB CI_check_failed(void)
{
	if( vm[0] ) {
		return vm[0]->IsSuppress()||vm[0]->IsEmergency();
	}
	else {
		return 0;
	}
}

extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB multi_CI_check_failed(long id)//?
{
	if( id <= 0 || id > (long)vm.size() || vm[id] == NULL ) { //1���� 0�Ԃ͏]���p
		return 0;
	}

	if( vm[id] ) {
		return vm[id]->IsSuppress()||vm[id]->IsEmergency();
	}
	else {
		return 0;
	}
}

/* -----------------------------------------------------------------------
 *  Set_loghandler
 * -----------------------------------------------------------------------
 */
 extern "C" DLLEXPORT void FUNCATTRIB Set_loghandler(void (*loghandler)(const yaya::char_t *str, int mode, int id))
{
	if(loghandler_list.size()<1)
		loghandler_list.emplace_back(nullptr);
	loghandler_list[0]=loghandler;
	if( vm[0] ) {
		vm[0]->Set_loghandler(loghandler);
	}
	else {
		loghandler_list.reserve(1);
	}
}

extern "C" DLLEXPORT void FUNCATTRIB multi_Set_loghandler(long id,void (*loghandler)(const yaya::char_t *str, int mode, int id))//?
{
	if( id <= 0 || id > (long)vm.size() || vm[id] == NULL ) { //1���� 0�Ԃ͏]���p
		return;
	}

	enlarge_loghandler_list(id+1);
	loghandler_list[id]=loghandler;
	if( vm[id] ) {
		vm[id]->Set_loghandler(loghandler);
	}
}
 
/* -----------------------------------------------------------------------
 *  logsend�iAYA�ŗL�@�`�F�b�N�c�[������g�p�j
 * -----------------------------------------------------------------------
 */
#if !defined(AYA_MAKE_EXE)
#if defined(WIN32)
extern "C" DLLEXPORT BOOL_TYPE FUNCATTRIB logsend(long hwnd)
{
	if ( vm[0] ) {
		vm[0]->SetLogRcvWnd(hwnd);
	}
	else if ( vm.size() >= 2 && vm[1] ) {
		vm[1]->SetLogRcvWnd(hwnd);
	}
	else {
		logsend_hwnd = hwnd;
	}

	return TRUE;
}
#endif //win32
#endif //aya_make_exe


/* -----------------------------------------------------------------------
 *  main (���s�t�@�C���ł̂�)
 * -----------------------------------------------------------------------
 */

#if defined(AYA_MAKE_EXE)

int main( int argc, char *argv[ ], char *envp[ ] )
{
	AYA_InitModule(NULL);

	std::string bufstr;

	_setmode( _fileno( stdin ), _O_BINARY );
	_setmode( _fileno( stdout ), _O_BINARY );

	while ( 1 ) {
		bufstr.erase();

		while ( 1 ) {
			char buf[2];
			fread(buf,1,1,stdin);
			bufstr += static_cast<char>(buf[0]);

			if ( bufstr.size() >= 2 ) {
				if ( strcmp(bufstr.c_str() + bufstr.size() - 2,"\r\n") == 0 ) { //���s���o
					break;
				}
			}
		}

		const char* bufptr = bufstr.c_str();

		if ( strncmp(bufptr,"load:",5) == 0 ) {
			bufptr += 5;
			long size = atoi(bufptr);
			if ( size > 0 ) {
				char *read_ptr = (char*)::GlobalAlloc(GMEM_FIXED,size+1);
				fread(read_ptr,1,size,stdin);
				read_ptr[size] = 0;

				char *p = strstr(read_ptr,"\r\n");
				if ( p ) { *p = 0; size -= 2; }
				
				load(read_ptr,size);
			}

			const char* result = "load:5\r\n1\r\n\r\n";
			fwrite(result,1,strlen(result),stdout);
			fflush(stdout);
		}
		else if ( strncmp(bufptr,"unload:",7) == 0 ) {
			bufptr += 7;
			long size = atoi(bufptr);
			if ( size > 0 ) {
				char *read_ptr = (char*)malloc(size);
				fread(read_ptr,1,size,stdin);
				free(read_ptr); //�f�[�^�܂Ƃ߂Ĕj��
			}

			unload();

			const char* result = "unload:5\r\n1\r\n\r\n";
			fwrite(result,1,strlen(result),stdout);
			fflush(stdout);
			break;
		}
		else if ( (strncmp(bufptr,"request:",8) == 0) ) {
			bufptr += 8;
			
			long size = atoi(bufptr);
			if ( size > 0 ) {
				char *read_ptr = (char*)::GlobalAlloc(GMEM_FIXED,size+1);
				fread(read_ptr,1,size,stdin);
				read_ptr[size] = 0;
				
				yaya::global_t res = request(read_ptr,&size);

				char write_header[64];
				sprintf(write_header,"request:%d\r\n",size);
				fwrite(write_header,1,strlen(write_header),stdout);

				fwrite(res,1,size,stdout);
				fflush(stdout);

				::GlobalFree(res);
			}
			else {
				const char* w = "request:0\r\n";
				fwrite(w,1,strlen(w),stdout);
			}
		}
	}

	return 0;
}

#endif //aya_make_exe
