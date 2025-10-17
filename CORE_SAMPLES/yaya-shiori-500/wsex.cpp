// 
// AYA version 5
//
// stl::yaya::string_t��char*���Ɏg�����߂̊֐��Ȃ�
// written by umeici. 2004
// 

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif
#ifdef _MSC_VER
#if (_MSC_VER >= 1900)
#include <corecrt.h>
#endif
#endif // _MSC_AVR


#if defined(POSIX)
# include <iomanip>
# include <sstream>
#endif
#include <string>
#include <stdarg.h>
#include <string.h>

#include "ccct.h"
#if defined(POSIX)
# include "posix_utils.h"
#define wcsnicmp(s1, s2, n) wcsncasecmp(s1, s2, n)
#endif
#include "globaldef.h"
#include "manifest.h"
#include "misc.h"
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
*  �֐���  �F  yaya::ws_atoi / ws_atoll
*  �@�\�T�v�F  yaya::string_t��int�֕ϊ�
* -----------------------------------------------------------------------
*/
int	yaya::ws_atoi(const yaya::string_t &str, int base)
{
	if (!str.size())
		return 0;

	return wcstol(str.c_str(), NULL, base);
}

yaya::int_t yaya::ws_atoll(const yaya::string_t &str, int rdx_arg)
{
	yaya::int_t num = 0;
	yaya::int_t rdx = rdx_arg;
	
	if ( rdx < 2 ) { rdx = 2; }
	if ( rdx > 36 ) { rdx = 36; }

	const yaya::char_t *ptr = str.c_str();
	
	bool minus = false;
	if ( *ptr == L'-' ) {
		minus = true;
		ptr += 1;
	}
	else if ( *ptr == L'+' ) {
		ptr += 1;
	}
	else if ( wcsnicmp(ptr,L"0x",2) == 0 ) {
		ptr += 2;
		rdx = 16;
	}
	else if ( wcsnicmp(ptr,L"0b",2) == 0 ) {
		ptr += 2;
		rdx = 2;
	}

	while ( *ptr ) {
		yaya::int_t add = -1;

		if ( *ptr >= L'0' && *ptr <= L'9' ) {
			add = *ptr - L'0';
		}
		else if ( *ptr >= L'A' && *ptr <= L'Z' ) {
			add = *ptr - L'A' + 10;
		}
		else if ( *ptr >= L'a' && *ptr <= L'z' ) {
			add = *ptr - L'a' + 10;
		}

		if ( add < 0 || add > rdx ) {
			break;
		}
		num *= rdx;
		num += add;

		ptr += 1;
	}
	
	if ( minus ) {
		return 0-num;
	}
	else {
		return num;
	}
}

/* -----------------------------------------------------------------------
*  �֐���  �F  yaya::ws_atof
*  �@�\�T�v�F  yaya::string_t��double�֕ϊ�
* -----------------------------------------------------------------------
*/
double	yaya::ws_atof(const yaya::string_t &str)
{
	if (!str.size())
		return 0.0;

	return wcstod(str.c_str(), NULL);
}

/* -----------------------------------------------------------------------
*  �֐���  �F  yaya::ws_itoa
*  �@�\�T�v�F  int��yaya::string_t�֕ϊ�
* -----------------------------------------------------------------------
*/
yaya::string_t yaya::ws_itoa(int num, int rdx)
{
	return ws_lltoa(static_cast<yaya::int_t>(num), rdx);
}

yaya::string_t yaya::ws_lltoa(yaya::int_t num, int rdx)
{
	int idx;

	//                     123456789012345678901234567890123456789012345678901234567890123456 //64bitmax = 64chars + (+/-) = 65
	yaya::char_t buf[] = L"                                                                  ";
	int offset = (sizeof(buf) / sizeof(buf[0])) - 2;
	
	const yaya::char_t convchars[] = L"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
	
	if ( rdx < 2 ) { rdx = 2; }
	if ( rdx > 36 ) { rdx = 36; }
	
	bool minus = false;
	if ( num < 0 ) {
		minus = true;
		num = -num;
	}
	
	if ( num == 0 ) {
		buf[offset] = L'0';
		--offset;
	}
	else {
		while ( num ) {
			idx = num % rdx;
			buf[offset] = convchars[idx];
			num -= idx;
			num /= rdx;
			--offset;
		}
	}
	
	if ( minus ) {
		buf[offset] = '-';
		--offset;
	}
	
	return (buf + offset + 1);
}

/* -----------------------------------------------------------------------
*  �֐���  �F  yaya::ws_ftoa
*  �@�\�T�v�F  double��yaya::string_t�֕ϊ�
* -----------------------------------------------------------------------
*/
yaya::string_t	yaya::ws_ftoa(double num)
{
	yaya::char_t numtxt[128];
	yaya::snprintf(numtxt,64,L"%f",num);
	return numtxt;
}

/* -----------------------------------------------------------------------
*  �֐���  �F  yaya::ws_eraseend
*  �@�\�T�v�F  yaya::string_t�̏I�[����c�����
* -----------------------------------------------------------------------
*/
void	yaya::ws_eraseend(yaya::string_t &str,wchar_t c)
{
	if (!str.size())
		return;
	
	if (str[str.size() - 1] == c)
		str.erase(str.end() - 1);
}

/* -----------------------------------------------------------------------
*  �֐���  �F  yaya::ws_replace
*  �@�\�T�v�F  str����before�����ׂ�after�ɒu�����܂�
* -----------------------------------------------------------------------
*/
void	yaya::ws_replace(yaya::string_t &str, const wchar_t *before, const wchar_t *after, yaya::int_t count)
{
	if ( ! after ) { after = L""; }

	size_t sz_bef = wcslen(before);
	size_t sz_aft = wcslen(after);

	for(size_t rp_pos = 0; ; rp_pos += sz_aft) {
		rp_pos = str.find(before, rp_pos);
		if (rp_pos == yaya::string_t::npos)
			break;
		str.replace(rp_pos, sz_bef, after);
		if ( count > 0 ) {
			count -= 1;
			if ( count <= 0 ) { break; }
		}
	}
}

/* -----------------------------------------------------------------------
*  �֐���  �F  w_fopen
*  �@�\�T�v�F  UCS-2������̃t�@�C�����ŃI�[�v���ł���fopen
*
*  �⑫�@wchar_t*�𒼐ړn����_wfopen��Win9x�n���T�|�[�g�̂��ߎg���Ȃ��̂ł��B���O�B
* -----------------------------------------------------------------------
*/
#if defined(WIN32) || defined(_WIN32_WCE)
FILE	*yaya::w_fopen(const yaya::char_t *fname, const yaya::char_t *mode)
{
	FILE *fp;
	if ( IsUnicodeAware() ) {
		fp = _wfopen(fname,mode);
	}
	else {
		// �t�@�C�����ƃI�[�v�����[�h����MBCS�֕ϊ�
		char	*mfname = Ccct::Ucs2ToMbcs(fname, CHARSET_DEFAULT);
		if (mfname == NULL)
			return NULL;
		char	*mmode  = Ccct::Ucs2ToMbcs(mode,  CHARSET_DEFAULT);
		if (mmode == NULL) {
			free(mfname);
			mfname = NULL;
			return NULL;
		}
		// �I�[�v��
		fp = fopen(mfname, mmode);
		free(mfname);
		mfname = NULL;
		free(mmode);
		mmode = NULL;
	}
	
	return fp;
}
#else
FILE* yaya::w_fopen(const yaya::char_t* fname, const yaya::char_t* mode) {
	std::string s_fname = narrow(yaya::string_t(fname));
	std::string s_mode = narrow(yaya::string_t(mode));
	
    fix_filepath(s_fname);
	
    return fopen(s_fname.c_str(), s_mode.c_str());
}
#endif

/* -----------------------------------------------------------------------
*  �֐���  �F  write_utf8bom
*  �@�\�T�v�F  UTF-8 BOM����������
* -----------------------------------------------------------------------
*/
/*
void	write_utf8bom(FILE *fp)
{
fputc(0xef, fp);
fputc(0xbb, fp);
fputc(0xbf, fp);
}
*/

/* -----------------------------------------------------------------------
*  �֐���  �F  decode/encodecipher
*  �@�\�T�v�F  AYA�Í������ꂽ�����𕜍�����
*
*  �����̃r�b�g���]�Ƃ��������ł�
* -----------------------------------------------------------------------
*/
static int decodecipher(const int c)
{
	return (((c & 0x7) << 5) | ((c & 0xf8) >> 3)) ^ 0x5a;
}

static int encodecipher(const int c)
{
	return (((c^ 0x5a) << 3) & 0xF8) | (((c^ 0x5a) >> 5) & 0x7);
}

/* -----------------------------------------------------------------------
*  �֐���  �F  ws_fgets
*  �@�\�T�v�F  yaya::string_t�Ɏ��o����ȈՔ�fgets�A�Í�������UCS-2 BOM�폜���s�Ȃ�
* -----------------------------------------------------------------------
*/
int yaya::ws_fgets(std::string &buf, yaya::string_t &str, FILE *stream, int charset, int ayc, int lc, int cutspace)
{
	//ayc = 1 ������
	//lc = 1 BOM�폜
	//cutspace = 1 �擪�̋󔒍폜

	str.erase();
	buf.erase();
	int c = 1;
	
	if (ayc) {
		while (true) {
			c = fgetc(stream);
			if (c == EOF) {
				break;
			}
			c = decodecipher(c);
			buf += static_cast<char>(c);
			if (c == '\x0a') {
				// �s�̏I���
				break;
			}
		}
	}
	else {
		while (true) {
			c = fgetc(stream);
			if (c == EOF) {
				break;
			}
			buf += static_cast<char>(c);
			if (c == '\x0a') {
				// �s�̏I���
				break;
			}
		}
	}

	if ( lc == 1 && buf.length() >= 3 ) {
		if ( static_cast<unsigned char>(buf[0]) == 0xEFU &&
			 static_cast<unsigned char>(buf[1]) == 0xBBU &&
			 static_cast<unsigned char>(buf[2]) == 0xBFU ) { //UTF-8 bom
			buf.erase(0,3);
		}
	}
	
	if ( ! Ccct::MbcsToUcs2Buf(str, buf, charset) ) { return 0; }

	const wchar_t *cstr = str.c_str();
	if (cutspace) {
		while (IsSpace(*cstr)) { ++cstr; }
	}
	ptrdiff_t diff = cstr - str.c_str();
	if ( diff > 0 ) {
		str.erase(0,diff);
	}
	
	if (c == EOF && str.empty()) {
		return yaya::WS_EOF;
	}
	else {
		return str.size();
	}
}

/* -----------------------------------------------------------------------
*  �֐���  �F  ws_fputs
*  �@�\�T�v�F  yaya::string_t���������ފȈՔ�fputs�A�Í������s�Ȃ�
* -----------------------------------------------------------------------
*/
int yaya::ws_fputs(const yaya::char_t *str, FILE *stream, int charset, int ayc)
{
	//ayc = 1 ������
	char *str_result = Ccct::Ucs2ToMbcs(str, charset);
	if ( ! str_result ) { return 0; }

	int len = strlen(str_result);

	if (ayc) {
		char *resulttmp = str_result;
		while ( *resulttmp ) {
			*resulttmp = encodecipher(*resulttmp);
			++resulttmp;
		}
	}

	fwrite(str_result,1,len,stream);

	free(str_result);
	str_result = NULL;

	return len;
}

/* -----------------------------------------------------------------------
*  �֐���  �F  snprintf / format
*  �@�\�T�v�F  snprintf�݊�����
* -----------------------------------------------------------------------
*/
#if defined(__GNUC__)
// in g++ 12.2.0 (Debian 12.2.0-14)
//wsex.h:46:131: error: �eformat�f attribute argument 2 value �e3�f refers to parameter type �econst yaya::char_t*�f {aka �econst wchar_t*�f}
//int yaya::snprintf(yaya::char_t* buf, size_t count, const yaya::char_t* format, ...)__attribute__((format(printf, 3, 4)))
int yaya::snprintf(yaya::char_t* buf, size_t count, const yaya::char_t* format, ...)
#elif defined(_MSC_VER)
int yaya::snprintf(_Pre_notnull_ yaya::char_t *buf,size_t count, _Printf_format_string_ const yaya::char_t *format,...)
#else
int yaya::snprintf(yaya::char_t* buf, size_t count, const yaya::char_t* format, ...)
#endif
{
	va_list list;
	va_start( list, format );

	int result;

#ifdef _MSC_VER
#if _MSC_VER <= 1300
	//�W����݊�
	result = _vsnwprintf(buf,count,format,list);
#else
	result = vswprintf(buf,count*2,format,list);
#endif
#else
	result = vswprintf(buf,count*2,format,list);
#endif

	va_end (list);
	return result;
}
