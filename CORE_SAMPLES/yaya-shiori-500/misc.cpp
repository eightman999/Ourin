// 
// AYA version 5
//
// �G�p�֐�
// written by umeici. 2004
// 

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <ctime>
#include <string>
#include <vector>

#include "manifest.h"
#include "misc.h"
#if defined(POSIX) || defined(__MINGW32__)
# include "posix_utils.h"
#endif
#include "globaldef.h"
#include "wsex.h"
#include "function.h"
#include "sysfunc.h"

//////////DEBUG/////////////////////////
#ifdef _WINDOWS
#ifdef _DEBUG
#include <crtdbg.h>
#define new new( _NORMAL_BLOCK, __FILE__, __LINE__)
#endif
#endif
////////////////////////////////////////

/* -----------------------------------------------------------------------
 *  �֐���  �F  Split
 *  �@�\�T�v�F  ������𕪊����ė]���ȋ󔒂��폜���܂�
 *
 *  �Ԓl�@�@�F  0/1=���s/����
 * -----------------------------------------------------------------------
 */
char	Split(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::char_t *sepstr)
{
	yaya::string_t::size_type seppoint = str.find(sepstr);
	if (seppoint == yaya::string_t::npos) {
		dstr0 = str;
		dstr1.erase();
		return 0;
	}

	dstr0.assign(str, 0, seppoint);
	seppoint += ::wcslen(sepstr);
	dstr1.assign(str, seppoint, str.size() - seppoint);

	CutSpace(dstr0);
	CutSpace(dstr1);

	return 1;
}

//----

char	Split(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::string_t &sepstr)
{
	yaya::string_t::size_type seppoint = str.find(sepstr);
	if (seppoint == yaya::string_t::npos) {
		dstr0 = str;
		dstr1.erase();
		return 0;
	}

	dstr0.assign(str, 0, seppoint);
	seppoint += sepstr.size();
	dstr1.assign(str, seppoint, str.size() - seppoint);

	CutSpace(dstr0);
	CutSpace(dstr1);

	return 1;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  SplitOnly
 *  �@�\�T�v�F  ������𕪊����܂�
 *
 *  �Ԓl�@�@�F  0/1=���s/����
 * -----------------------------------------------------------------------
 */
char	SplitOnly(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::char_t *sepstr)
{
	yaya::string_t::size_type seppoint = str.find(sepstr);
	if (seppoint == yaya::string_t::npos) {
		dstr0 = str;
		dstr1.erase();
		return 0;
	}

	dstr0.assign(str, 0, seppoint);
	seppoint += ::wcslen(sepstr);
	dstr1.assign(str, seppoint, str.size() - seppoint);

	return 1;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  Find_IgnoreDQ
 *  �@�\�T�v�F  �_�u��/�V���O���N�H�[�g���𖳎����ĕ����������
 *
 *  �Ԓl�@�@�F  ��=���s   0�E��=����
 * -----------------------------------------------------------------------
 */
yaya::string_t::size_type Find_IgnoreDQ(const yaya::string_t &str, const yaya::char_t *findstr)
{
	yaya::string_t::size_type findpoint = 0;
	yaya::string_t::size_type nextdq = 0;

	while(true){
		findpoint = str.find(findstr, findpoint);
		if (findpoint == yaya::string_t::npos)
			return yaya::string_t::npos;

		nextdq = IsInDQ(str, nextdq, findpoint);
		if (nextdq >= IsInDQ_npos) {
			if (nextdq == IsInDQ_runaway) { //�N�I�[�g���I���Ȃ��܂܏I��
				return yaya::string_t::npos;
			}
			break; //�݂�����
		}
		else { //�N�I�[�g�����B�������Ď���
			findpoint = nextdq;
		}
	}

	return findpoint;
}

yaya::string_t::size_type Find_IgnoreDQ(const yaya::string_t &str, const yaya::string_t &findstr)
{
	return Find_IgnoreDQ(str,findstr.c_str());
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  find_last_str
 *  �@�\�T�v�F  ��ԍŌ�Ɍ�������������̈ʒu��Ԃ�
 *
 *  �Ԓl�@�@�F  npos=���s   0�E��=����
 * -----------------------------------------------------------------------
 */
yaya::string_t::size_type find_last_str(const yaya::string_t &str, const yaya::char_t *findstr)
{
	yaya::string_t::size_type it = yaya::string_t::npos;
	yaya::string_t::size_type found;

	while ( (found = str.find(findstr,it)) != yaya::string_t::npos ) {
		it = found;
	}

	return it;
}

yaya::string_t::size_type find_last_str(const yaya::string_t &str, const yaya::string_t &findstr)
{
	return find_last_str(str,findstr.c_str());
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  Split_IgnoreDQ
 *  �@�\�T�v�F  ������𕪊����ė]���ȋ󔒂��폜���܂�
 *  �@�@�@�@�@  �������_�u��/�V���O���N�H�[�g���ł͕������܂���
 *
 *  �Ԓl�@�@�F  0/1=���s/����
 * -----------------------------------------------------------------------
 */

char	Split_IgnoreDQ(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::char_t *sepstr)
{
	yaya::string_t::size_type seppoint = Find_IgnoreDQ(str,sepstr);
	if ( seppoint == yaya::string_t::npos ) {
		dstr0 = str;
		dstr1.erase();
		return 0;
	}

	dstr0.assign(str, 0, seppoint);
	seppoint += wcslen(sepstr);
	dstr1.assign(str, seppoint, str.size() - seppoint);

	CutSpace(dstr0);
	CutSpace(dstr1);

	return 1;
}

//----

char	Split_IgnoreDQ(const yaya::string_t &str, yaya::string_t &dstr0, yaya::string_t &dstr1, const yaya::string_t &sepstr)
{
	return Split_IgnoreDQ(str,dstr0,dstr1,sepstr.c_str());
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  SplitToMultiString
 *  �@�\�T�v�F  ������𕪊�����vector�Ɋi�[���܂�
 *
 *�@�Ԓl�@�@�F�@������(array.size())
 * -----------------------------------------------------------------------
 */
size_t	SplitToMultiString(const yaya::string_t &str, std::vector<yaya::string_t> *array, const yaya::string_t &delimiter)
{
	if (!str.size())
		return 0;

	const yaya::string_t::size_type dlmlen = delimiter.size();
	yaya::string_t::size_type beforepoint = 0,seppoint;
	size_t count = 1;

	for( ; ; ) {
		// �f���~�^�̔���
		seppoint = str.find(delimiter,beforepoint);
		if (seppoint == yaya::string_t::npos) {
			if ( array ) {
				array->emplace_back(yaya::string_t(str.begin()+beforepoint,str.end()));
			}
			break;
		}
		// ���o����vector�ւ̒ǉ�
		if ( array ) {
			array->emplace_back(yaya::string_t(str.begin()+beforepoint,str.begin()+seppoint));
		}
		// ���o���������폜
		beforepoint = seppoint + dlmlen;
		++count;
	}

	return count;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CutSpace
 *  �@�\�T�v�F  �^����ꂽ������̑O��ɔ��p�󔒂��^�u���������ꍇ�A���ׂč폜���܂�
 * -----------------------------------------------------------------------
 */
void	CutSpace(yaya::string_t &str)
{
	CutEndSpace(str);
	CutStartSpace(str);
}

void	CutStartSpace(yaya::string_t &str)
{
	int	len = str.size();
	// �O��
	int	erasenum = 0;
	for(int i = 0; i < len; i++) {
		if (IsSpace(str[i])) {
			erasenum++;
		}
		else {
			break;
		}
	}
	if (erasenum) {
		str.erase(0, erasenum);
	}
}

void	CutEndSpace(yaya::string_t &str)
{
	int	len = str.size();
	// ���
	int erasenum = 0;
	for(int i = len - 1; i >= 0; i--) {
		if (IsSpace(str[i])) {
			erasenum++;
		}
		else {
			break;
		}
	}
	if (erasenum) {
		str.erase(len - erasenum, erasenum);
	}
}


/* -----------------------------------------------------------------------
 *  �֐���  �F  UnescapeSpecialString
 *  �@�\�T�v�F  (�q�A�h�L�������g�d�l�p��)�L�Q�����G�X�P�[�v��߂��܂�
 *              CParser0::LoadDictionary1 ���Q�Ƃ��Ă�������
 * -----------------------------------------------------------------------
 */
void	UnescapeSpecialString(yaya::string_t &str)
{
	if ( str.size() <= 1 ) {
		return;
	}

	size_t len = str.size()-1; //1������O�܂�
	for ( size_t i = 0 ; i < len ; ++i ) {
		if ( str[i] == 0xFFFFU ) {
			if ( str[i+1] == 0x0001U ) {
				str[i]   = L'\r';
				str[i+1] = L'\n';
			}
			else if ( str[i+1] == 0x0002U ) {
				str.erase(i, 1);
				str[i] = L'"';
				len -= 1;
			}
			else if ( str[i+1] == 0x0003U ) {
				str.erase(i, 1);
				str[i] = L'\'';
				len -= 1;
			}
		}
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CutDoubleQuote
 *  �@�\�T�v�F  �^����ꂽ������̑O��Ƀ_�u���N�H�[�g���������ꍇ�폜���܂�
 * -----------------------------------------------------------------------
 */
void	CutDoubleQuote(yaya::string_t &str)
{
	size_t len = str.size();
	if (!len)
		return;
	// �O��
	if (str[0] == L'\"') {
		str.erase(0, 1);
		len--;
		if (!len)
			return;
	}
	// ���
	if (str[len - 1] == L'\"')
		str.erase(len - 1, 1);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CutSingleQuote
 *  �@�\�T�v�F  �^����ꂽ������̑O��ɃV���O���N�H�[�g���������ꍇ�폜���܂�
 * -----------------------------------------------------------------------
 */
void	CutSingleQuote(yaya::string_t &str)
{
	size_t len = str.size();
	if (!len)
		return;
	// �O��
	if (str[0] == L'\'') {
		str.erase(0, 1);
		len--;
		if (!len)
			return;
	}
	// ���
	if (str[len - 1] == L'\'')
		str.erase(len - 1, 1);
}

void EscapingInsideDoubleDoubleQuote(yaya::string_t &str) {
	yaya::ws_replace(str, L"\"\"", L"\"");
}
void EscapingInsideDoubleSingleQuote(yaya::string_t &str) {
	yaya::ws_replace(str, L"\'\'", L"\'");
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  AddDoubleQuote
 *  �@�\�T�v�F  �^����ꂽ��������_�u���N�H�[�g�ň݂͂܂�
 * -----------------------------------------------------------------------
 */
void	AddDoubleQuote(yaya::string_t &str)
{
	str = L"\"" + str + L"\"";
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CutCrLf
 *  �@�\�T�v�F  �^����ꂽ������̌�[�ɉ��s(CRLF)���������ꍇ�폜���܂�
 * -----------------------------------------------------------------------
 */
void	CutCrLf(yaya::string_t &str)
{
	yaya::ws_eraseend(str, L'\n');
	yaya::ws_eraseend(str, L'\r');
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  GetDateString
 *  �@�\�T�v�F  �N����/�����b�̕�������쐬���ĕԂ��܂�
 * -----------------------------------------------------------------------
 */

yaya::string_t GetDateString()
{
    char buf[128];
    time_t t = time(NULL);
    struct tm* tm = localtime(&t);
    strftime(buf, 127, "%Y/%m/%d %H:%M:%S", tm);

#if !defined(POSIX) && !defined(__MINGW32__)
	yaya::char_t wbuf[64];
	for ( size_t i = 0 ; i < 64 ; ++i ) {
		wbuf[i] = buf[i];
		if ( wbuf[i] == 0 ) { break; }
	}
	return wbuf;
#else
    return widen(std::string(buf));
#endif
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsInDQ
 *  �@�\�T�v�F  ��������̎w��ʒu���_�u��/�V���O���N�H�[�g�͈͓������`�F�b�N���܂�
 *
 *  �Ԓl�@�@�F  -1   = �_�u��/�V���O���N�H�[�g�̊O��
 *             !=-1 = �_�u��/�V���O���N�H�[�g�̓���
 *                -2  = �_�u��/�V���O���N�H�[�g�̓����̂܂܃e�L�X�g�I��
 *                >=0 = ���ɊO���ɂȂ�ʒu
 * -----------------------------------------------------------------------
 */
const yaya::string_t::size_type IsInDQ_notindq = static_cast<yaya::string_t::size_type>(-1);
const yaya::string_t::size_type IsInDQ_runaway = static_cast<yaya::string_t::size_type>(-2);
const yaya::string_t::size_type IsInDQ_npos    = static_cast<yaya::string_t::size_type>(-2);

yaya::string_t::size_type IsInDQ(const yaya::string_t &str, yaya::string_t::size_type startpoint, yaya::string_t::size_type checkpoint)
{
	bool dq    = false;
	bool quote = false;

	yaya::string_t::size_type len    = str.size();
	yaya::string_t::size_type found  = startpoint;

	while(true) {
		if (found >= len) {
			found = IsInDQ_runaway;
			break;
		}
		
		found = str.find_first_of(L"'\"",found);
		if (found == yaya::string_t::npos) {
			found = IsInDQ_runaway;
			break;
		}
		else {
			if (found >= checkpoint) {
				if ( (dq && str[found] == L'\"') || (quote && str[found] == L'\'') ) {
					found += 1;
					break;
				}
				if ( ! dq && ! quote ) {
					break;
				}
			}

			if (str[found] == L'\"') {
				if (!quote) {
					dq = !dq;
				}
			}
			else if (str[found] == L'\'') {
				if (!dq ) {
					quote = !quote;
				}
			}

			found += 1;
		}
	}

	if ( dq || quote ) {
		return found;
	}
	else {
		return IsInDQ_notindq;
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsDoubleButNotIntString
 *  �@�\�T�v�F  ������Int�������������l�Ƃ��Đ��������������܂�
 *  ���Ӂ@�@�F�@�����l��Double�Ƃ��Đ����Ȓl�Ȃ̂Ŏ�������IsIntString�Ƃ��킹�邱��
 *
 *  �Ԓl�@�@�F  0/1=�~/��
 * -----------------------------------------------------------------------
 */
char	IsDoubleButNotIntString(const yaya::string_t &str)
{
	int	len = str.size();
	if (!len)
		return 0;

	int	advance = (str[0] == L'-' || str[0] == L'+') ? 1 : 0;
	int i = advance;

	int	dotcount = 0;
	for( ; i < len; i++) {
//		if (!::iswdigit((int)str[i])) {
		if (str[i] < L'0' || str[i] > L'9') {
			if (str[i] == L'.') {
				dotcount++;
			}
			else {
				return 0;
			}
		}
	}

	return dotcount == 1 && (len-advance) > 0;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsIntString
 *  �@�\�T�v�F  ������10�i�������l�Ƃ��Đ��������������܂�
 *
 *  �Ԓl�@�@�F  0/1=�~/��
 * -----------------------------------------------------------------------
 */
char	IsIntString(const yaya::string_t &str)
{
	int	len = str.size();
	if (!len)
		return 0;

	int	advance = (str[0] == L'-' || str[0] == L'+') ? 1 : 0;
	int i = advance;

	//64bit
	//9223372036854775807
	if ( (len-i) > 19 ) { return 0; }

	for( ; i < len; i++) {
//		if (!::iswdigit((int)str[i]))
		if (str[i] < L'0' || str[i] > L'9') {
			return 0;
		}
	}

	if ( (len-advance) == 19 ) {
		if ( wcscmp(str.c_str(),L"9223372036854775807") > 0 ) {
			return 0; //Overflow
		}
	}

	return (len-advance) ? 1 : 0;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsIntBinString
 *  �@�\�T�v�F  ������2�i�������l�Ƃ��Đ��������������܂�
 *  �����@�@�F  header 0/1=�擪"0x"�Ȃ�/����
 *
 *  �Ԓl�@�@�F  0/1=�~/��
 * -----------------------------------------------------------------------
 */
char	IsIntBinString(const yaya::string_t &str, char header)
{
	int	len = str.size();
	if (!len)
		return 0;

	int	advance = (str[0] == L'-' || str[0] == L'+') ? 1 : 0;
	int i = advance;

	if (header) {
		if (::wcsncmp(PREFIX_BIN, str.c_str() + i,PREFIX_BASE_LEN))
			return 0;
		i += PREFIX_BASE_LEN;
	}

	//64bit
	if ( (len-i) > 64 ) { return 0; }
	
	for( ; i < len; i++) {
		yaya::char_t	j = str[i];
		if (j != L'0' && j != L'1')
			return 0;
	}

	return (len-advance) ? 1 : 0;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsIntHexString
 *  �@�\�T�v�F  ������16�i�������l�Ƃ��Đ��������������܂�
 *
 *  �Ԓl�@�@�F  0/1=�~/��
 * -----------------------------------------------------------------------
 */
char	IsIntHexString(const yaya::string_t &str, char header)
{
	int	len = str.size();
	if (!len)
		return 0;

	int	advance = (str[0] == L'-' || str[0] == L'+') ? 1 : 0;
	int i = advance;

	if (header) {
		if (::wcsncmp(PREFIX_HEX, str.c_str() + i,PREFIX_BASE_LEN))
			return 0;
		i += PREFIX_BASE_LEN;
	}

	//64bit
	//7fffffffffffffff
	if ( (len-i) > 16 ) { return 0; }

	for( ; i < len; i++) {
		yaya::char_t	j = str[i];
		if (j >= L'0' && j <= L'9')
			continue;
		else if (j >= L'a' && j <= L'f')
			continue;
		else if (j >= L'A' && j <= L'F')
			continue;

		return 0;
	}

	return (len-advance) ? 1 : 0;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsLegalFunctionName
 *  �@�\�T�v�F  �����񂪊֐����Ƃ��ēK�����𔻒肵�܂�
 *
 *  �Ԓl�@�@�F  0/��0=��/�~
 *
 *  �@�@�@�@�@  1/2/3/4/5/6=�󕶎���/���l�݂̂ō\��/�擪�����l��������"_"/�g���Ȃ��������܂�ł���
 *  �@�@�@�@�@  �@�V�X�e���֐��Ɠ���/���䕶�������͉��Z�q�Ɠ���
 * -----------------------------------------------------------------------
 */
char	IsLegalFunctionName(const yaya::string_t &str)
{
	int	len = str.size();
	if (!len)
		return 1;

	if (IsIntString(str))
		return 2;

//	if (::iswdigit(str[0]) || str[0] == L'_')
//	if ((str[0] >= L'0' && str[0] <= L'9') || str[0] == L'_') //�`�F�b�N����K�v�͂Ȃ�����
//		return 3;
	if (str[0] == L'_') //�����A���_�[�X�R�A�͏R��Ȃ��ƃ��[�J���ϐ��ƃJ�u��
		return 3;

	for(int i = 0; i < len; i++) {
		yaya::char_t	c = str[i];
		if ((c >= (yaya::char_t)0x0000 && c <= (yaya::char_t)0x0026) ||
			(c >= (yaya::char_t)0x0028 && c <= (yaya::char_t)0x002d) ||
			 c == (yaya::char_t)0x002f ||
			(c >= (yaya::char_t)0x003a && c <= (yaya::char_t)0x0040) ||
			 c == (yaya::char_t)0x005b ||
			(c >= (yaya::char_t)0x005d && c <= (yaya::char_t)0x005e) ||
			 c == (yaya::char_t)0x0060 ||
			(c >= (yaya::char_t)0x007b && c <= (yaya::char_t)0x007f))
			return 4;
	}

	ptrdiff_t sysidx = CSystemFunction::FindIndex(str);
	if( sysidx >= 0 ) { return 5; }

	for(size_t i= 0; i < FLOWCOM_NUM; i++) {
		if (str == flowcom[i]) {
			return 6;
		}
	}
	for(size_t i= 0; i < FORMULATAG_NUM; i++) {
//		if (str == formulatag[i])
		if (str.find(formulatag[i]) != yaya::string_t::npos) {
			return 6;
		}
	}

	return 0;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsLegalVariableName
 *  �@�\�T�v�F  �����񂪕ϐ����Ƃ��ēK�����𔻒肵�܂�
 *
 *  �Ԓl�@�@�F  0/1�`6/16��0=��(�O���[�o���ϐ�)/�~/��(���[�J���ϐ�)
 *
 *  �@�@�@�@�@  1/2/3/4/5/6=�󕶎���/���l�݂̂ō\��/�擪�����l/�g���Ȃ��������܂�ł���
 *  �@�@�@�@�@  �@�V�X�e���֐��Ɠ���/���䕶�������͉��Z�q�Ɠ���
 * -----------------------------------------------------------------------
 */
char	IsLegalVariableName(const yaya::string_t &str)
{
	int	len = str.size();
	if (!len)
		return 1;

	if (IsIntString(str))
		return 2;

//	if (::iswdigit((int)str[0]))
//	if (str[0] >= L'0' && str[0] <= L'9') //�`�F�b�N����K�v�͂Ȃ�����
//		return 3;

	for(int i = 0; i < len; i++) {
		yaya::char_t	c = str[i];
		if ((c >= (yaya::char_t)0x0000  && c <= (yaya::char_t)0x0026) ||
			(c >= (yaya::char_t)0x0028  && c <= (yaya::char_t)0x002d) ||
			 c == (yaya::char_t)0x002f ||
			(c >= (yaya::char_t)0x003a && c <= (yaya::char_t)0x0040) ||
			 c == (yaya::char_t)0x005b ||
			(c >= (yaya::char_t)0x005d && c <= (yaya::char_t)0x005e) ||
			 c == (yaya::char_t)0x0060 ||
			(c >= (yaya::char_t)0x007b && c <= (yaya::char_t)0x007f))
			return 4;
	}

	ptrdiff_t sysidx = CSystemFunction::FindIndex(str);
	if( sysidx >= 0 ) { return 5; }

	for(size_t i= 0; i < FLOWCOM_NUM; i++) {
		if (str == flowcom[i]) {
			return 6;
		}
	}
	for(size_t i= 0; i < FORMULATAG_NUM; i++) {
//		if (str == formulatag[i])
		if (str.find(formulatag[i]) != yaya::string_t::npos) {
			return 6;
		}
	}

	return (str[0] == L'_') ? 16 : 0;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsLegalStrLiteral
 *  �@�\�T�v�F  �_�u���N�H�[�g�ň͂܂�Ă���ׂ�������̐��������������܂�
 *
 *  �Ԓl�@�@�F  0/1/2/3=����/�_�u���N�H�[�g�����Ă��Ȃ�/
 *  �@�@�@�@�@  �@�_�u���N�H�[�g�ň͂܂�Ă��邪���̒��Ƀ_�u���N�H�[�g����܂���Ă���/
 *  �@�@�@�@�@  �@�_�u���N�H�[�g�ň͂܂�Ă��Ȃ�
 * -----------------------------------------------------------------------
 */
char	IsLegalStrLiteral(const yaya::string_t &str)
{
	int	len = str.size();
	if (!len)
		return 3;

	// �擪�̃_�u���N�H�[�g�`�F�b�N
	int	flg = (str[0] == L'\"') ? 1 : 0;
	// ��[�̃_�u���N�H�[�g�`�F�b�N
	if (len > 1)
		if (str[len - 1] == L'\"')
			flg += 2;
	// �����Ă���_�u���N�H�[�g�̒T��
	if(len > 2) {
		int lenm1 = len - 1;
		int i	  = 1;
		while(i < lenm1) {
			if(str[i] == L'\"') {
				if(str[i + 1] != L'\"') {
					flg = 4;
					break;
				}
				else
					i++;
			}
			i++;
		}
	}

	// ���ʂ�Ԃ��܂�
	switch(flg) {
	case 3:
		return 0;
	case 1:
	case 2:
	case 5:
	case 6:
		return 1;
	case 7:
		return 2;
	default:
		return 3;
	};
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsLegalPlainStrLiteral
 *  �@�\�T�v�F  �V���O���N�H�[�g�ň͂܂�Ă���ׂ�������̐��������������܂�
 *
 *  �Ԓl�@�@�F  0/1/2/3=����/�_�u���N�H�[�g�����Ă��Ȃ�/
 *  �@�@�@�@�@  �@�_�u���N�H�[�g�ň͂܂�Ă��邪���̒��Ƀ_�u���N�H�[�g����܂���Ă���/
 *  �@�@�@�@�@  �@�_�u���N�H�[�g�ň͂܂�Ă��Ȃ�
 * -----------------------------------------------------------------------
 */
char	IsLegalPlainStrLiteral(const yaya::string_t &str)
{
	int	len = str.size();
	if (!len)
		return 3;

	// �擪�̃V���O���N�H�[�g�`�F�b�N
	int	flg = (str[0] == L'\'') ? 1 : 0;
	// ��[�̃V���O���N�H�[�g�`�F�b�N
	if (len > 1)
		if (str[len - 1] == L'\'')
			flg += 2;
	// �����Ă���V���O���N�H�[�g�̒T��
	if (len > 2) {
		int	lenm1 = len - 1;
		int i	  = 1;
		while(i < lenm1) {
			if(str[i] == L'\'') {
				if(str[i + 1] != L'\'') {
					flg = 4;
					break;
				}
				else
					i++;
			}
			i++;
		}
	}

	// ���ʂ�Ԃ��܂�
	switch(flg) {
	case 3:
		return 0;
	case 1:
	case 2:
	case 5:
	case 6:
		return 1;
	case 7:
		return 2;
	default:
		return 3;
	};
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  IsUnicodeAware
 *  �@�\�T�v�F  Unicode�nAPI���g���邩�ǂ�����Ԃ��܂�
 *              POSIX�͏��true / Win9x/Me�̂�false
 * -----------------------------------------------------------------------
 */
#if defined(WIN32) || defined(_WIN32_WCE)
class IsUnicodeAwareHelper
{
public:
	bool isnt;

	IsUnicodeAwareHelper() {
		OSVERSIONINFO osVer;
		osVer.dwOSVersionInfoSize = sizeof(osVer);

		::GetVersionEx(&osVer);
		isnt = (osVer.dwPlatformId == VER_PLATFORM_WIN32_NT);
	}
};

bool	IsUnicodeAware(void)
{
	static IsUnicodeAwareHelper h;
	return h.isnt;
}
#else
bool	IsUnicodeAware(void)
{
	return true;
}
#endif

/* -----------------------------------------------------------------------
 *  �֐���  �F  GetEpochTime
 *  �@�\�T�v�F  64bit�Ή��� time() ����
 * -----------------------------------------------------------------------
 */
#if defined(WIN32) || defined(_WIN32_WCE)
static yaya::time_t FileTimeToEpochTime(FILETIME &ft)
{
	ULARGE_INTEGER ul;
	ul.LowPart = ft.dwLowDateTime;
	ul.HighPart = ft.dwHighDateTime;

	yaya::time_t tv = ul.QuadPart;
	tv -= LL_DEF(116444736000000000);
	tv /= LL_DEF(10000000);

	return tv;
}

static FILETIME EpochTimeToFileTime(yaya::time_t &tv)
{
	union {
		ULARGE_INTEGER ul;
		FILETIME ft;
	} tc;

	tc.ul.QuadPart = tv;
	tc.ul.QuadPart *= LL_DEF(10000000);
	tc.ul.QuadPart += LL_DEF(116444736000000000);

	return tc.ft;
}

static unsigned int month_to_day_table[] = {
	0,
	31,
	31+28,
	31+28+31,
	31+28+31+30,
	31+28+31+30+31,
	31+28+31+30+31+30,
	31+28+31+30+31+30+31,
	31+28+31+30+31+30+31+31,
	31+28+31+30+31+30+31+31+30,
	31+28+31+30+31+30+31+31+30+31,
	31+28+31+30+31+30+31+31+30+31+30,
};

static bool IsLeapYear(unsigned int year)
{
	if (year % 4 == 0) {
		if (year % 100 == 0) {
			if (year % 400 == 0) {
				return true;
			}
			else {
				return false;
			}
		}
		else {
			return true;
		}
	}
	else {
		return false;
	}
}

#endif

yaya::time_t GetEpochTime()
{
#if defined(WIN32) || defined(_WIN32_WCE)
	FILETIME ft;
	::GetSystemTimeAsFileTime(&ft);

	return FileTimeToEpochTime(ft);
#else
	time_t tv;
	time(&tv);
	return (yaya::time_t)tv;
#endif
}

struct tm EpochTimeToLocalTime(yaya::time_t tv)
{
#if defined(WIN32) || defined(_WIN32_WCE)
	FILETIME ft = EpochTimeToFileTime(tv);
	FILETIME lft;

	::FileTimeToLocalFileTime(&ft,&lft);

	SYSTEMTIME stime;
	::FileTimeToSystemTime(&lft,&stime);

	struct tm tmtime;
	tmtime.tm_sec = stime.wSecond;
	tmtime.tm_min = stime.wMinute;
	tmtime.tm_hour = stime.wHour;
	tmtime.tm_mday = stime.wDay;
	tmtime.tm_mon = stime.wMonth - 1; //struct tm 0-11 = SYSTEMTIME 1-12
	tmtime.tm_year = stime.wYear - 1900; //struct tm 100 = SYSTEMTIME 2000
	tmtime.tm_wday = stime.wDayOfWeek;
	tmtime.tm_yday = month_to_day_table[stime.wMonth-1] + stime.wDay;
	if ( IsLeapYear(stime.wYear) && stime.wMonth >= 3 ) { tmtime.tm_yday += 1; }

	TIME_ZONE_INFORMATION tzinfo;
	tmtime.tm_isdst = ::GetTimeZoneInformation(&tzinfo) == TIME_ZONE_ID_DAYLIGHT;

	return tmtime;
#else
	time_t tc = tv;
	return *localtime(&tc);
#endif
}

yaya::time_t LocalTimeToEpochTime(struct tm &tm)
{
#if defined(WIN32) || defined(_WIN32_WCE)
	__int64 t1 = tm.tm_year;

	if ( tm.tm_mon < 0 || tm.tm_mon > 11 ) { //1-12���O
		t1 += (tm.tm_mon / 12);

		tm.tm_mon %= 12;
		if ( tm.tm_mon < 0 ) {
			tm.tm_mon += 12;
			t1 -= 1;
		}
	}

	//t1 = �N
	static __int64 count_days[] = {
		0,
		31,
		31+28,
		31+28+31,
		31+28+31+30,
		31+28+31+30+31,
		31+28+31+30+31+30,
		31+28+31+30+31+30+31,
		31+28+31+30+31+30+31+31,
		31+28+31+30+31+30+31+31+30,
		31+28+31+30+31+30+31+31+30+31,
		31+28+31+30+31+30+31+31+30+31+30};

	__int64 t2 = count_days[tm.tm_mon] - 1;

	if ( !(t1 & 3) && (tm.tm_mon > 1) ) {
		t2 += 1;
	}

	__int64 t3 = (t1 - 70) * 365i64 + ((t1 - 1i64) >> 2) - 17i64;

	t3 += t2;
	t2 = tm.tm_mday;

	t1 = t3 + t2;

	//t1 = ��
	t2 = t1 * 24i64;
	t3 = tm.tm_hour;

	t1 = t2 + t3;

	//t1 = ��
	t2 = t1 * 60i64;
	t3 = tm.tm_min;

	t1 = t2 + t3;

	//t1 = ��
	t2 = t1 * 60i64;
	t3 = tm.tm_sec;

	t1 = t2 + t3;

	//t1 = �b(local EPOCH)
	
	FILETIME lft = EpochTimeToFileTime(t1);
	
	FILETIME ft;
	::LocalFileTimeToFileTime(&lft,&ft);

	return FileTimeToEpochTime(ft);
#else
	time_t gmt_local = mktime(&tm);

	time_t now;
	time(&now);
	struct tm* gmt_tm = gmtime(&now);
	time_t local_gmt = now - mktime(gmt_tm);

	return (yaya::time_t)(gmt_local + local_gmt);
#endif
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  EscapeString
 *  �@�\�T�v�F  �Z�[�u�t�@�C���ۑ��̍ۂɗL�Q�ȕ�����u�������܂�
 * -----------------------------------------------------------------------
 */

void	EscapeString(yaya::string_t &wstr)
{
	yaya::ws_replace(wstr, L"\"", ESC_DQ);

	for ( size_t i = 0 ; i < wstr.length() ; ++i ) {
		if ( wstr[i] <= END_OF_CTRL_CH ) {
			yaya::string_t replace_text(ESC_CTRL);
			replace_text += (yaya::char_t)(wstr[i] + CTRL_CH_START);

			wstr.replace(i,1,replace_text);
			i += replace_text.length() - 1; //�u����������������Ɉړ�
		}
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  UnescapeString
 *  �@�\�T�v�F  �Z�[�u�t�@�C���ǂݍ��݂̍ۂɗL�Q�ȕ�����߂��܂�
 * -----------------------------------------------------------------------
 */
void	UnescapeString(yaya::string_t &wstr)
{
	yaya::ws_replace(wstr, ESC_DQ, L"\"");

	yaya::string_t::size_type found = 0;
	const size_t len = ::wcslen(ESC_CTRL);
	yaya::char_t ch;
	yaya::char_t str[2] = L"x"; //�u�������p�_�~�[

	while(true) {
		found = wstr.find(ESC_CTRL,found);
		if ( found == yaya::string_t::npos ) {
			break;
		}

		ch = wstr[found + len];
		if ( ch > CTRL_CH_START && ch <= (CTRL_CH_START + END_OF_CTRL_CH) ) {
			str[0] = ch - CTRL_CH_START;
			wstr.replace(found,len + 1,str);
			found += 1;
		}
		else { //�͈͊O�������̂Ŗ���
			found += len;
		}
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  EncodeBase64
 * -----------------------------------------------------------------------
 */

void EncodeBase64(yaya::string_t &out,const char *in,size_t in_len)
{
	int len = in_len;
	const unsigned char* p = reinterpret_cast<const unsigned char*>(in);
	static const yaya::char_t table[] = L"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	
	while (len > 0)
	{
		// 1������ 1-6bit  xxxxxx--:--------:--------
		out.append(1,table[static_cast<int>(*p)>>2]);
		
		// 2������ 7-12bit ------xx:xxxx----:--------
		if ( len-1 > 0 )
			out.append(1,table[((static_cast<int>(*p) << 4)&0x30) | ((static_cast<int>(*(p+1)) >> 4)&0x0f)]);
		else
			out.append(1,table[((static_cast<int>(*p) << 4)&0x30) ]);
		
		--len;
		++p;
		
		// 3������ 13-18bit --------:----xxxx:xx------
		if ( len > 0 ) {
			if ( len-1 > 0 ) {
				out.append(1,table[((static_cast<int>(*p) << 2)&0x3C) | ((static_cast<int>(*(p+1)) >> 6)&0x03)]);
			}
			else {
				out.append(1,table[((static_cast<int>(*p) << 2)&0x3C) ]);
			}
			++p;
		}
		else {
			out.append(1,L'=');
		}
		
		// 4������ 19-24bit --------:--------:--xxxxxx
		out.append(1,(--len>0? table[static_cast<int>(*p) & 0x3F]: L'='));
		
		if(--len>0) p++;
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  DecodeBase64
 * -----------------------------------------------------------------------
 */

void DecodeBase64(std::string &out,const yaya::char_t *in,size_t in_len)
{
	static const unsigned char reverse_64[] = {
		//0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
		  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   // 0x00 - 0x0F
		  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,   // 0x10 - 0x1F
		  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 62,  0,  0,  0, 63,   // 0x20 - 0x2F
		 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,  0,  0,  0,  0,  0,  0,   // 0x30 - 0x3F
		  0,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,   // 0x40 - 0x4F
		 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,  0,  0,  0,  0,  0,   // 0x50 - 0x5F
		  0, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,   // 0x60 - 0x6F
		 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,  0,  0,  0,  0,  0    // 0x70 - 0x7F
	};

	const yaya::char_t* p = in;

	while (*p!='=')
	{
		//11111122:22223333:33444444
		if ( (*p=='\0') || (*(p+1)=='=') ) break;
		out.append(1,static_cast<unsigned char>((reverse_64[*p&0x7f] <<2) & 0xFC | (reverse_64[*(p+1)&0x7f] >>4) & 0x03));
		++p;

		if ( (*p=='\0') || (*(p+1)=='=') ) break;
		out.append(1,static_cast<unsigned char>((reverse_64[*p&0x7f] <<4) & 0xF0 | (reverse_64[*(p+1)&0x7f] >>2) & 0x0F));
		++p;

		if ( (*p=='\0') || (*(p+1)=='=') ) break;
		out.append(1,static_cast<unsigned char>((reverse_64[*p&0x7f] <<6) & 0xC0 | reverse_64[*(p+1)&0x7f] & 0x3f ));
		++p;

		if ( (*p=='\0') || (*(p+1)=='=') ) break;
		++p;
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  EncodeURL
 * -----------------------------------------------------------------------
 */

void EncodeURL(yaya::string_t &out,const char *in,size_t in_len,bool isPlusPercent)
{
	yaya::char_t chr[4] = L"%00";
	const unsigned char* p = reinterpret_cast<const unsigned char*>(in);

	for ( size_t i = 0 ; i < in_len ; ++i ) {
		int current = static_cast<unsigned char>(p[i]);
		if ( (current >= 'a' && current <= 'z') || (current >= 'A' && current <= 'Z') || (current >= '0' && current <= '9') || current == '.' || current == '_' || current == '-' ) {
			out.append(1,current);
		}
		else if ( (current == L' ') && isPlusPercent ) {
			out.append(1,L'+');
		}
		else {
			yaya::snprintf(chr+1,4,L"%02X",current);
			out.append(chr);
		}
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  DecodeURL
 * -----------------------------------------------------------------------
 */

void DecodeURL(std::string &out,const yaya::char_t *in,size_t in_len,bool isPlusPercent)
{
	char ch[3] = {0,0,0};

	for ( size_t pos = 0 ; pos < in_len ; ++pos ) {

		if ( in[pos] == L'%' && (in_len - pos) >= 3) {
			ch[0] = static_cast<char>(in[pos+1]);
			ch[1] = static_cast<char>(in[pos+2]);

			out.append(1,static_cast<char>(strtol(ch,NULL,16)));

			pos += 2;
		}
		else if ( isPlusPercent && in[pos] == L'+' ) {
			out.append(1,' ');
		}
		else {
			out.append(1,static_cast<char>(in[pos]));
		}
	}
}

