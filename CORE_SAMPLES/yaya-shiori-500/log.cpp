//
// AYA version 5
//
// ���M���O�p�N���X�@CLog
// written by umeici. 2004
// 

#include <algorithm>

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include "deelx.h"

#include "ccct.h"
#include "log.h"
#include "manifest.h"
#include "messages.h"
#include "misc.h"
#if defined(POSIX)
# include "posix_utils.h"
#endif
#include "globaldef.h"
#include "timer.h"
#include "wsex.h"

//////////DEBUG/////////////////////////
#ifdef _WINDOWS
#ifdef _DEBUG
#include <crtdbg.h>
#define new new( _NORMAL_BLOCK, __FILE__, __LINE__)
#endif
#endif
////////////////////////////////////////

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Start
 *  �@�\�T�v�F  ���M���O���J�n���܂�
 * -----------------------------------------------------------------------
 */
void	CLog::Start(const yaya::string_t &p, int cs, HWND hw, char il)
{
	iolog   = il;

	if( open ) {
		if(path != p || charset != cs
#ifdef _WINDOWS
                || hw != hWnd
#endif
                ) {
			Termination();
		}
		else {
			if ( ! iolog ) {
				Termination();
			}
			return;
		}
	}

	path    = p;
	charset = cs;
	
	if( hw || loghandler) { //hw�����遁�ʂ���̌Ăяo���Ȃ̂ŋ���ON�A�t�@�C������
		path.erase();
	}
	else if ( ! il ) {
		enable = 0;
		return;
	}

#if defined(WIN32)
	// ����hWnd��NULL�Ȃ�N�����̃`�F�b�N�c�[����T���Ď擾����
	hWnd    = hw != NULL ? hw : GetCheckerWnd();
#endif

#if defined(POSIX)
	fix_filepath(path);
#endif

	// ���M���O�L��/�����̔���
	if ( path.size() ) {
		fileen = 1;
		enable = 1;
	}
	else {
		fileen = 0;
		enable = 1;
		if( 
			loghandler == NULL
#if defined(WIN32)
			&&hWnd == NULL
#endif
		) {
			enable = 0;
			return;
		}
	}

	timer.restart();

	// ������쐬
	yaya::string_t	str = yayamsg::GetTextFromTable(E_J,0);
	str += GetDateString();
	str += L"\n\n";

#ifdef _WINDOWS
	// �t�@�C���֏�������
	if (fileen) {
		char	*tmpstr = Ccct::Ucs2ToMbcs(str, charset);
		if (tmpstr != NULL) {
			FILE	*fp = yaya::w_fopen(path.c_str(), L"w");
			if (fp != NULL) {
/*				if (charset == CHARSET_UTF8)
					write_utf8bom(fp);*/
				fputs(tmpstr,fp);
				fclose(fp);
			}
			free(tmpstr);
		}
	}
#endif
	open = 1;

	// �`�F�b�N�c�[���֑��o�@�ŏ��ɕ����R�[�h��ݒ肵�Ă��當����𑗏o
	if(charset == CHARSET_SJIS)
		Call_loghandler(L"", E_SJIS);
	else if(charset == CHARSET_UTF8)
		Call_loghandler(L"", E_UTF8);
	else	// CHARSET_DEFAULT
		Call_loghandler(L"", E_DEFAULT);

	Call_loghandler(str, E_I);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Termination
 *  �@�\�T�v�F  ���M���O���I�����܂�
 * -----------------------------------------------------------------------
 */
void	CLog::Termination(void)
{
	if (!enable)
		return;

	Message(1);

	yaya::string_t	str = GetDateString();
	str += L"\n\n";

	Write(str);

	open = 0;

	Call_loghandler(L"", E_END);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Write
 *  �@�\�T�v�F  ���O�ɕ�������������݂܂�
 * -----------------------------------------------------------------------
 */
void	CLog::Write(const yaya::char_t *str, int mode, int id)
{
	if (!enable)
		return;
	if (str == NULL)
		return;
	if (!wcslen(str))
		return;

	// �����񒆂�\r�͏���
	yaya::string_t	cstr = str;
	size_t	len = cstr.size();
	for(size_t i = 0; i < len; ) {
		if(cstr[i] == L'\r') {
			cstr.erase(i, 1);
			len--;
			continue;
		}
		i++;
	}

#ifdef _WINDOWS
	// �t�@�C���֏�������
	if (fileen) {
		if (! path.empty()) {
			char	*tmpstr = Ccct::Ucs2ToMbcs(cstr, charset);
			if (tmpstr != NULL) {
				FILE	*fp = yaya::w_fopen(path.c_str(), L"a");
				if (fp != NULL) {
					fputs(tmpstr, fp);
					fclose(fp);
				}
				free(tmpstr);
			}
		}
	}
#endif

	// �`�F�b�N�c�[���֑��o
	Call_loghandler(cstr, mode, id);
}

//----

void	CLog::Write(const yaya::string_t &str, int mode, int id)
{
	Write(str.c_str(), mode, id);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Filename
 *  �@�\�T�v�F  ����̃t�H�[�}�b�g�Ńt�@�C���������O�ɋL�^���܂�
 * -----------------------------------------------------------------------
 */
void	CLog::Filename(const yaya::string_t &filename)
{
	yaya::string_t	str =  L"- ";
	str += filename;
	str += L"\n";
	Write(str);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Message
 *  �@�\�T�v�F  id�Ŏw�肳�ꂽ����̃��b�Z�[�W�����O�ɏ������݂܂�
 * -----------------------------------------------------------------------
 */
void	CLog::Message(int id, int mode)
{
	Write(yayamsg::GetTextFromTable(E_J,id), mode, id);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Error
 *  �@�\�T�v�F  ���O��mode��id�Ŏw�肳�ꂽ�G���[��������������݂܂�
 *
 *  �����@�@�F�@ref         �t�����
 *  �@�@�@�@�@  dicfilename �G���[���N�������ӏ����܂ގ����t�@�C���̖��O
 *  �@�@�@�@�@  linecount   �G���[���N�������s�ԍ�
 *
 *  �@�@�@�@�@  ref��dicfilename��NULL�Alinecount��-1�Ƃ��邱�ƂŁA������
 *  �@�@�@�@�@  ��\���ɂł��܂�
 * -----------------------------------------------------------------------
 */
void	CLog::Error(int mode, int id, const yaya::char_t *ref, const yaya::string_t &dicfilename, ptrdiff_t linecount)
{
	if (locking)
		return;
	// ���O�ɏ������ݕ�������쐬�i�����t�@�C�����ƍs�ԍ��j
	yaya::string_t	logstr;

	if (dicfilename.empty())
		logstr = L"-(-) : ";
	else {
		logstr = dicfilename + L'(';
		if(linecount == -1)
			logstr += L"-) : ";
		else {
			logstr += yaya::ws_lltoa(linecount);
			logstr += L") : ";
		}
	}
	// ���O�ɏ������ݕ�������쐬�i�{���j
	{
		logstr += yayamsg::GetTextFromTable(mode,id);
	}
	// ���O�ɏ������ݕ�������쐬�i�t�����j
	if (ref != NULL) {
		logstr += L" : ";
		logstr += ref;
	}

	// �O�̈׉��s�R�[�h�������Ă���
	for(yaya::string_t::iterator it = logstr.begin(); it != logstr.end(); it++){
		if ( *it == '\r' || *it == '\n' ) {
			*it = ' ';
		}
	}

	AddErrorLogHistory(logstr);

	// ��������
	if (!enable)
		return;

	logstr += L'\n';
	Write(logstr, mode, id);
}

//----

void	CLog::Error(int mode, int id, const yaya::string_t& ref, const yaya::string_t& dicfilename, ptrdiff_t linecount)
{
	Error(mode, id, (yaya::char_t *)ref.c_str(), dicfilename, linecount);
}

//----

void	CLog::Error(int mode, int id, const yaya::char_t *ref)
{
        Error(mode, id, ref, yaya::string_t(), -1);
}

//----

void	CLog::Error(int mode, int id, const yaya::string_t& ref)
{
        Error(mode, id, (yaya::char_t *)ref.c_str(), yaya::string_t(), -1);
}

//----

void	CLog::Error(int mode, int id, const yaya::string_t& dicfilename, ptrdiff_t linecount)
{
	Error(mode, id, (yaya::char_t *)NULL, dicfilename, linecount);
}

//----

void	CLog::Error(int mode, int id)
{
        Error(mode, id, (yaya::char_t *)NULL, yaya::string_t(), -1);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::Io
 *  �@�\�T�v�F  ���o�͕�����Ǝ��s���Ԃ����O�ɋL�^���܂�
 *  �����@�@�F  io 0/1=�J�n��/�I����
 * -----------------------------------------------------------------------
 */
void	CLog::Io(char io, const yaya::char_t *str)
{
	if (!enable || !iolog)
		return;

	if(!io) {
		//ignoreiolog�@�\�B
		if ( iolog_filter_keyword.size() > 0 || iolog_filter_keyword_regex.size() > 0 ) {
			yaya::string_t cstr=str;

			bool found = false;

			std::vector<yaya::string_t>::iterator it;

			for(it = iolog_filter_keyword.begin(); it != iolog_filter_keyword.end(); it++){
				if(cstr.find(*it) != yaya::string_t::npos){
					found = true;
					break;
				}
			}

			if ( ! found ) {
				for(it = iolog_filter_keyword_regex.begin(); it != iolog_filter_keyword_regex.end(); it++){
					CRegexpT<yaya::char_t> regex(it->c_str(),MULTILINE | EXTENDED);

					MatchResult result = regex.Match(cstr.c_str());
					if ( result.IsMatched() ) {
						found = true;
						break;
					}
				}
			}

			if ( iolog_filter_mode == 0 ) { //denylist
				if ( found ) {
					skip_next_log_output = 1;
					return;
				}
			}
			else { //allowlist
				if ( ! found ) {
					skip_next_log_output = 1;
					return;
				}
			}
		}

		Write(L"// request\n");
		Write(str);
		Write(L"\n");

        timer.restart();
	}
	else {
		//���O�}��
		if(skip_next_log_output){
			skip_next_log_output=0;
			return;
		}

		int elapsed_time = timer.elapsed();
		yaya::string_t t_str = L"// response (Execution time : " + yaya::ws_itoa(elapsed_time) + L"[ms])\n";

		Write(t_str);
		Write(str);
		Write(L"\n");
	}
}

void	CLog::Io(char io, const yaya::string_t &str)
{
	Io(io,str.c_str());
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::IoLib
 *  �@�\�T�v�F  �O�����C�u�������o�͕�����Ǝ��s���Ԃ����O�ɋL�^���܂�
 *  �����@�@�F  io 0/1=�J�n��/�I����
 * -----------------------------------------------------------------------
 */
void	CLog::IoLib(char io, const yaya::string_t &str, const yaya::string_t &name)
{
	if (!enable || !iolog)
		return;

	static	yaya::timer		timer;

	if (!io) {
		Write(L"// request to library\n// name : ");
		Write(name + L"\n");
		Write(str + L"\n");

		timer.restart();
	}
	else {
		int elapsed_time = timer.elapsed();
		yaya::string_t t_str = L"// response (Execution time : " + yaya::ws_itoa(elapsed_time) + L"[ms])\n";

		Write(t_str);
		Write(str + L"\n");
	}
}

void	CLog::Call_loghandler(const yaya::string_t &str, int mode, int id)
{
	Call_loghandler((yaya::char_t *)str.c_str(), mode, id);
}
void	CLog::Call_loghandler(const yaya::char_t *str, int mode, int id){
	if (loghandler)
		loghandler(str,mode,id);
	else
	#if defined(WIN32)
		SendLogToWnd(str,mode);
	#else
		return;
	#endif
}
void	CLog::Set_loghandler(void (*loghandler_v)(const yaya::char_t *str, int mode, int id)){
	loghandler=loghandler_v;
	if(loghandler)
		enable = 1;
}
/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::SendLogToWnd
 *  �@�\�T�v�F  �`�F�b�N�c�[���ɐ��䃁�b�Z�[�W����у��O�������WM_COPYDATA�ő��M���܂�
 * -----------------------------------------------------------------------
 */
#if defined(WIN32)
void	CLog::SendLogToWnd(const yaya::char_t *str, int mode)
{
	if (hWnd == NULL)
		return;

	COPYDATASTRUCT cds;
	cds.dwData = mode;
	cds.cbData = (wcslen(str) + 1)*sizeof(yaya::char_t);
	cds.lpData = (LPVOID)str;

	DWORD res_dword = 0;
	::SendMessageTimeout(hWnd, WM_COPYDATA, (WPARAM)NULL, (LPARAM)&cds, SMTO_ABORTIFHUNG|SMTO_BLOCK, 5000, &res_dword);
}
#endif

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::GetCheckerWnd
 *  �@�\�T�v�F  �`�F�b�N�c�[����hWnd���擾���܂���
 * -----------------------------------------------------------------------
 */
#if defined(WIN32)
HWND	CLog::GetCheckerWnd(void)
{
	return FindWindowA(CLASSNAME_CHECKTOOL, NULL);
}
#endif

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::AddIologFilterKeyword / KeywordRegex
 *  �@�\�T�v�F  IO���O�̖������镶���񃊃X�g��ǉ����܂�
 * -----------------------------------------------------------------------
 */
void	CLog::AddIologFilterKeyword(const yaya::string_t &ignorestr){
	std::vector<yaya::string_t>::iterator it = std::find(iolog_filter_keyword.begin(), iolog_filter_keyword.end(), ignorestr);

	if ( it == iolog_filter_keyword.end() ){
		iolog_filter_keyword.emplace_back(ignorestr);
	}
}

void	CLog::AddIologFilterKeywordRegex(const yaya::string_t &ignorestr){
	std::vector<yaya::string_t>::iterator it = std::find(iolog_filter_keyword_regex.begin(), iolog_filter_keyword_regex.end(), ignorestr);

	if ( it == iolog_filter_keyword_regex.end() ){
		iolog_filter_keyword_regex.emplace_back(ignorestr);
	}
}


/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::DeleteIologFilterKeyword / KeywordRegex
 *  �@�\�T�v�F  IO���O�̖������镶���񃊃X�g���폜���܂�
 * -----------------------------------------------------------------------
 */
void	CLog::DeleteIologFilterKeyword(const yaya::string_t &ignorestr){
	std::vector<yaya::string_t>::iterator it = std::find(iolog_filter_keyword.begin(), iolog_filter_keyword.end(), ignorestr);

	if ( it != iolog_filter_keyword.end() ){
		iolog_filter_keyword.erase(it);
	}
}

void	CLog::DeleteIologFilterKeywordRegex(const yaya::string_t &ignorestr){
	std::vector<yaya::string_t>::iterator it = std::find(iolog_filter_keyword_regex.begin(), iolog_filter_keyword_regex.end(), ignorestr);

	if ( it != iolog_filter_keyword_regex.end() ){
		iolog_filter_keyword_regex.erase(it);
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::ClearIologFilterKeyword
 *  �@�\�T�v�F  IO���O�̖������镶���񃊃X�g���N���A���܂�
 * -----------------------------------------------------------------------
 */
void	CLog::ClearIologFilterKeyword(){
	iolog_filter_keyword.clear();
	iolog_filter_keyword_regex.clear();
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::SetIologFilterMode
 *  �@�\�T�v�F  IO���O�̃t�B���^���[�h(�z���C�g���X�g=1/�u���b�N���X�g=0)
 * -----------------------------------------------------------------------
 */
void CLog::SetIologFilterMode(char mode)
{
	iolog_filter_mode = mode;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::AddErrorLogHistory
 *  �@�\�T�v�F  �����G���[���O�����ɒǉ����܂�
 * -----------------------------------------------------------------------
 */
void    CLog::AddErrorLogHistory(const yaya::string_t &err) {
	if(logmaxnum && error_log_history.size() >= logmaxnum) {
		error_log_history.pop_back();
	}
	error_log_history.push_front(err);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::GetErrorLogHistory
 *  �@�\�T�v�F  �����G���[���O������Ԃ��܂�
 * -----------------------------------------------------------------------
 */
std::deque<yaya::string_t> & CLog::GetErrorLogHistory(void) {
	return error_log_history;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CLog::AppendErrorLogHistoryToBegin
 *  �@�\�T�v�F  �����G���[���O�����𒼐ڐݒ肵�܂�
 * -----------------------------------------------------------------------
 */
void CLog::AppendErrorLogHistoryToBegin(std::deque<yaya::string_t> &log) {
	if(error_log_history.size())
		error_log_history.insert(error_log_history.begin(),log.begin(),log.end());
	else
		error_log_history=log;
}

#if CPP_STD_VER >= 2011
void CLog::AppendErrorLogHistoryToBegin(std::deque<yaya::string_t> &&log) {
	if(error_log_history.size())
		error_log_history.insert(error_log_history.begin(),log.begin(),log.end());
	else
		error_log_history=log;
}
#endif

void CLog::SetMaxLogNum(size_t num)
{
	logmaxnum = num;
}

size_t CLog::GetMaxLogNum()
{
	return logmaxnum;
}
