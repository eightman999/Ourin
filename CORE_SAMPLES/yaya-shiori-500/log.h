// 
// AYA version 5
//
// ���M���O�p�N���X�@CLog
// written by umeici. 2004
// 

#ifndef	LOGGERH
#define	LOGGERH

//----

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <vector>
#include <deque>

#include "globaldef.h"
#include "manifest.h"
#include "timer.h"

#define	CLASSNAME_CHECKTOOL	"TamaWndClass"	/* �`�F�b�N�c�[���̃E�B���h�E�N���X�� */

//----

class	CLog
{
protected:
	yaya::string_t		path;		// ���O�t�@�C���̃p�X
	int			charset;	// �����R�[�h�Z�b�g
#if defined(WIN32)
	HWND		hWnd;		// �`�F�b�N�c�[����HWND
#endif
	void (*loghandler)(const yaya::char_t *str, int mode, int id);
	yaya::timer timer;

	size_t logmaxnum;

	char		enable;		// ���M���O�L���t���O
	char		open;		// ���M���O�J�n�t���O
	char		fileen;		// �t�@�C���ւ̃��M���O�L���t���O
	char		iolog;		// ���o�̓��M���O�L���t���O
	bool		locking;

	//���͂ł��̕����񂪂������烍�O�o�͂��Ȃ����X�g
	std::vector<yaya::string_t> iolog_filter_keyword;
	std::vector<yaya::string_t> iolog_filter_keyword_regex;

	//allowlist = 1 / denylist = 0
	char iolog_filter_mode;

	volatile char skip_next_log_output;//���̓��͌�ɏo�͂��}�����邽�߂̃t���O

	std::deque<yaya::string_t> error_log_history;

public:
	CLog(void)
	{
		charset = CHARSET_UTF8;
#if defined(WIN32)
		hWnd = NULL;
#endif
		enable = 1;
		open = 0;
		fileen = 1;
		iolog  = 1;
		skip_next_log_output=0;
		iolog_filter_mode = 0;
		loghandler = NULL;
		logmaxnum = 256;
		locking = 0;
	}

#if defined(POSIX)
	typedef void* HWND;
#endif
	void	Start(const yaya::string_t &p, int cs, HWND hw, char il);
	void	Termination(void);

	void	Write(const yaya::string_t &str, int mode = 0, int id = 0);
	void	Write(const yaya::char_t *str, int mode = 0, int id = 0);

	void	Message(int id, int mode = 0);
	void	Filename(const yaya::string_t &filename);

	void	Error(int mode, int id, const yaya::char_t *ref, const yaya::string_t &dicfilename, ptrdiff_t linecount);
	void	Error(int mode, int id, const yaya::string_t &ref, const yaya::string_t &dicfilename, ptrdiff_t linecount);
	void	Error(int mode, int id, const yaya::char_t *ref);
	void	Error(int mode, int id, const yaya::string_t &ref);
	void	Error(int mode, int id, const yaya::string_t &dicfilename, ptrdiff_t linecount);
	void	Error(int mode, int id);

	void	Io(char io, const yaya::char_t *str);
	void	Io(char io, const yaya::string_t &str);

	void	IoLib(char io, const yaya::string_t &str, const yaya::string_t &name);

	void	Call_loghandler(const yaya::string_t& str, int mode, int id=0);
	void	Call_loghandler(const yaya::char_t* str, int mode, int id=0);
	void	Set_loghandler(void(*loghandler_v)(const yaya::char_t* str, int mode, int id));

	void	SendLogToWnd(const yaya::char_t *str, int mode);

	void	AddIologFilterKeyword(const yaya::string_t &ignorestr);
	void	AddIologFilterKeywordRegex(const yaya::string_t &ignorestr);

	const std::vector<yaya::string_t>& GetIologFilterKeyword(void) { return iolog_filter_keyword; }
	const std::vector<yaya::string_t>& GetIologFilterKeywordRegex(void) { return iolog_filter_keyword_regex; }

	void	DeleteIologFilterKeyword(const yaya::string_t &ignorestr);
	void	DeleteIologFilterKeywordRegex(const yaya::string_t &ignorestr);

	void	ClearIologFilterKeyword();
	void	SetIologFilterMode(char mode);
	char	GetIologFilterMode(void) { return iolog_filter_mode; }

	std::deque<yaya::string_t> & GetErrorLogHistory(void);
	void AppendErrorLogHistoryToBegin(std::deque<yaya::string_t> &log);
#if CPP_STD_VER >= 2011
	void AppendErrorLogHistoryToBegin(std::deque<yaya::string_t>&&log);
#endif

	void SetMaxLogNum(size_t num);
	size_t GetMaxLogNum();

	void lock() { locking = 1; }
	void unlock() { locking = 0; }
protected:
#if defined(WIN32)
	HWND	GetCheckerWnd(void);
#endif

	void    AddErrorLogHistory(const yaya::string_t &err);
};

//----

#endif
