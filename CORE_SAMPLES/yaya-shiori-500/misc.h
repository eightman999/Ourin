// 
// AYA version 5
//
// �G�p�֐�
// written by umeici. 2004
// 

#ifndef	MISCH
#define	MISCH

//----

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <vector>

#include "globaldef.h"

yaya::string_t::size_type Find_IgnoreDQ(const yaya::string_t &str, const yaya::char_t *findstr);
yaya::string_t::size_type Find_IgnoreDQ(const yaya::string_t &str, const yaya::string_t &findstr);

yaya::string_t::size_type find_last_str(const yaya::string_t &str, const yaya::char_t *findstr);
yaya::string_t::size_type find_last_str(const yaya::string_t &str, const yaya::string_t &findstr);

char	Split(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::char_t *sepstr);
char	Split(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::string_t &sepstr);
char	SplitOnly(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, yaya::char_t *sepstr);
char	Split_IgnoreDQ(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::char_t *sepstr);
char	Split_IgnoreDQ(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::string_t &sepstr);
size_t	SplitToMultiString(const yaya::string_t &str, std::vector<yaya::string_t> *array, const yaya::string_t &delimiter);

void	CutSpace(yaya::string_t &str);
void	CutStartSpace(yaya::string_t &str);
void	CutEndSpace(yaya::string_t &str);

void	CutDoubleQuote(yaya::string_t &str);
void	CutSingleQuote(yaya::string_t &str);
void	EscapingInsideDoubleDoubleQuote(yaya::string_t &str);
void	EscapingInsideDoubleSingleQuote(yaya::string_t &str);
void	UnescapeSpecialString(yaya::string_t &str);
void	AddDoubleQuote(yaya::string_t &str);
void	CutCrLf(yaya::string_t &str);

yaya::string_t	GetDateString(void);

yaya::time_t GetEpochTime();
struct tm EpochTimeToLocalTime(yaya::time_t tv);
yaya::time_t LocalTimeToEpochTime(struct tm &tm);

extern const yaya::string_t::size_type IsInDQ_notindq;
extern const yaya::string_t::size_type IsInDQ_runaway;
extern const yaya::string_t::size_type IsInDQ_npos;
yaya::string_t::size_type IsInDQ(const yaya::string_t &str, yaya::string_t::size_type startpoint, yaya::string_t::size_type checkpoint);

char	IsDoubleButNotIntString(const yaya::string_t &str);
char	IsIntString(const yaya::string_t &str);
char	IsIntBinString(const yaya::string_t &str, char header);
char	IsIntHexString(const yaya::string_t &str, char header);

char	IsLegalFunctionName(const yaya::string_t &str);
char	IsLegalVariableName(const yaya::string_t &str);
char	IsLegalStrLiteral(const yaya::string_t &str);
char	IsLegalPlainStrLiteral(const yaya::string_t &str);

bool	IsUnicodeAware(void);

void	EscapeString(yaya::string_t &wstr);
void	UnescapeString(yaya::string_t &wstr);

void	EncodeBase64(yaya::string_t &out,const char *in,size_t in_len);
void	DecodeBase64(std::string &out,const yaya::char_t *in,size_t in_len);
void	EncodeURL(yaya::string_t &out,const char *in,size_t in_len,bool isPlusPercent);
void	DecodeURL(std::string &out,const yaya::char_t *in,size_t in_len,bool isPlusPercent);

inline bool IsSpace(const yaya::char_t &c) {
#if !defined(POSIX) && !defined(__MINGW32__)
	return c == L' ' || c == L'\t' || c == L'�@';
#else
	return c == L' ' || c == L'\t' || c == L'\u3000';
#endif
}

//----

// �֐��Ăяo���̌��E���������邽�߂̃N���X

#define	CCALLLIMIT_CALLDEPTH_MAX	32		//�Ăяo�����E�f�t�H���g
#define	CCALLLIMIT_LOOP_MAX			10000	//���[�v�������E�f�t�H���g
class	CCallLimit
{
protected:
	size_t	depth;
	size_t	maxdepth;
	size_t maxloop;
	std::vector<yaya::string_t> stack;

public:
	CCallLimit(void) { depth = 0; maxdepth = CCALLLIMIT_CALLDEPTH_MAX; maxloop = CCALLLIMIT_LOOP_MAX; }

	void	SetMaxDepth(size_t value) { maxdepth = value; }
	size_t	GetMaxDepth(void) { return maxdepth; }

	void	SetMaxLoop(size_t value) { maxloop = value; }
	size_t	GetMaxLoop(void) { return maxloop; }

	void	InitCall(void) { depth = 0; stack.clear(); }

	char	AddCall(const yaya::string_t &str) {
		depth++;
		stack.emplace_back(str);
		if (maxdepth && depth > maxdepth)
			return 0;
		else
			return 1;
	}

	void	DeleteCall(void) {
		if ( depth ) {
			depth--;
			stack.erase(stack.end()-1);
		}
	}

	std::vector<yaya::string_t> &StackCall(void) {
		return stack;
	}

	int temp_unlock() {
		size_t aret=0;
		using std::swap;
		swap(aret, maxdepth);
		return aret;
	}
	void reset_lock(size_t lock) {
		using std::swap;
		swap(lock, maxdepth);
	}
};

//----

#endif
