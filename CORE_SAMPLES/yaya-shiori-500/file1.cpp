// 
// AYA version 5
//
// 1�̃t�@�C���������N���X�@CFile1
// written by umeici. 2004
// 

#if defined(WIN32) || defined(_WIN32_WCE)
#  include "stdafx.h"
#endif

#include <string.h>

#include "ccct.h"
#include "file.h"
#include "manifest.h"
#include "globaldef.h"
#include "wsex.h"
#include "misc.h"

//////////DEBUG/////////////////////////
#ifdef _WINDOWS
#ifdef _DEBUG
#include <crtdbg.h>
#define new new( _NORMAL_BLOCK, __FILE__, __LINE__)
#endif
#endif
////////////////////////////////////////

#ifdef POSIX
#define wcsicmp wcscasecmp
#endif

#ifdef INT64_IS_NOT_STD
extern "C" {
__int64 __cdecl _ftelli64(FILE *);
int __cdecl _fseeki64(FILE *, __int64, int);
}
#endif

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::Open
 *  �@�\�T�v�F  �t�@�C�����I�[�v�����܂�
 *
 *  �Ԓl�@�@�F�@0/1=���s/����(���Ƀ��[�h����Ă���܂�)
 * -----------------------------------------------------------------------
 */
int	CFile1::Open(void)
{
	if (fp != NULL)
		return 1;

	fp = yaya::w_fopen(name.c_str(), (wchar_t *)mode.c_str());

	if ( ! fp ) {
		size = 0;
		return 0;
	}

#ifdef POSIX
	yaya::int_t cur = ftello(fp);
	fseeko(fp, 0, SEEK_SET);
	yaya::int_t start = ftello(fp);
	fseeko(fp, 0, SEEK_END);
	yaya::int_t end = ftello(fp);
	fseeko(fp, cur, SEEK_SET);
#else
	yaya::int_t cur = _ftelli64(fp);
	_fseeki64(fp,0,SEEK_SET);
	yaya::int_t start = _ftelli64(fp);
	_fseeki64(fp,0,SEEK_END);
	yaya::int_t end = _ftelli64(fp);
	_fseeki64(fp,cur,SEEK_SET);
#endif

	size = end-start;
	
	return 1;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::Close
 *  �@�\�T�v�F  �t�@�C�����N���[�Y���܂�
 *
 *  �Ԓl�@�@�F�@1/2=����/���[�h����Ă��Ȃ��A�������͊���unload����Ă���
 * -----------------------------------------------------------------------
 */
int	CFile1::Close(void)
{
	if (fp) {
		fclose(fp);
		fp = NULL;
		return 1;
	}
	else {
		return 2;
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::Write
 *  �@�\�T�v�F  �t�@�C���ɕ�������������݂܂�
 *
 *  �Ԓl�@�@�F�@0/1=���s/����
 * -----------------------------------------------------------------------
 */
int	CFile1::Write(const yaya::string_t &istr)
{
	if (fp == NULL)
		return 0;

	// ��������}���`�o�C�g�����R�[�h�ɕϊ�
	char	*t_istr = Ccct::Ucs2ToMbcs(istr, charset);
	if (t_istr == NULL)
		return 0;

	long	len = (long)strlen(t_istr);

	// ��������
	fwrite(t_istr, sizeof(char), len, fp);
	free(t_istr);
	t_istr = NULL;

	return 1;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::WriteBin
 *  �@�\�T�v�F  �t�@�C���Ƀo�C�i���f�[�^���������݂܂�
 *
 *  �Ԓl�@�@�F�@0/1=���s/����
 * -----------------------------------------------------------------------
 */
int	CFile1::WriteBin(const yaya::string_t &istr, const yaya::char_t alt)
{
	if (fp == NULL)
		return 0;

	size_t len = istr.size();

	unsigned char *t_istr = reinterpret_cast<unsigned char*>(malloc(len+1));
	t_istr[len] = 0; //�O�̂��߃[���I�[�i����Ȃ��j
	
	//alt��0�ɒu�������f�[�^�\�z
	for ( size_t i = 0 ; i < len ; ++i ) {
		if ( istr[i] == alt ) {
			t_istr[i] = 0;
		}
		else {
			t_istr[i] = static_cast<unsigned char>(istr[i]);
		}
	}

	// ��������
	size_t write = fwrite(t_istr, sizeof(unsigned char), len, fp);
	free(t_istr);
	t_istr = NULL;

	return write;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::WriteDecode
 *  �@�\�T�v�F  �t�@�C���Ƀo�C�i���f�[�^���f�R�[�h���Ȃ��珑�����݂܂�
 *
 *  �Ԓl�@�@�F�@0/1=���s/����
 * -----------------------------------------------------------------------
 */
int	CFile1::WriteDecode(const yaya::string_t &istr, const yaya::string_t &type)
{
	if (fp == NULL)
		return 0;

	std::string out;

	if ( wcsicmp(type.c_str(),L"base64") == 0 ) {
		DecodeBase64(out,istr.c_str(),istr.length());
	}
	else if ( wcsicmp(type.c_str(),L"form") == 0 ) {
		DecodeURL(out,istr.c_str(),istr.length(),true);
	}
	else {
		DecodeURL(out,istr.c_str(),istr.length(),false);
	}

	// ��������
	size_t write = fwrite(out.c_str(), sizeof(unsigned char), out.length(), fp);

	return write;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::Read
 *  �@�\�T�v�F  �t�@�C�����當�����1�s�ǂݎ��܂�
 *
 *  �Ԓl�@�@�F�@-1/0/1=EOF/���s/����
 * -----------------------------------------------------------------------
 */
int	CFile1::Read(yaya::string_t &ostr)
{
	ostr.erase();

	if (fp == NULL)
		return 0;

	std::string buf;
	buf.reserve(1000);

	if (yaya::ws_fgets(buf, ostr, fp, charset, 0, bomcheck, false) == yaya::WS_EOF)
		return -1;

	bomcheck++;

	return 1;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::ReadBin
 *  �@�\�T�v�F  �t�@�C������o�C�i���f�[�^��ǂݎ��܂�
 *
 *  �Ԓl�@�@�F�@-1/0/1=EOF/���s/����
 * -----------------------------------------------------------------------
 */
int	CFile1::ReadBin(yaya::string_t &ostr, size_t len, yaya::char_t alt)
{
	ostr.erase();

	if (fp == NULL)
		return 0;

	if(len<1){ //0=�f�t�H���g�T�C�Y�w��
		len = (size_t)size;
	}

	char f_buffer[1024];
	size_t read = 0;

	while ( true ) {
		size_t lenread = len - read;
		if ( lenread > sizeof(f_buffer) ) {
			lenread = sizeof(f_buffer);
		}

		size_t done = fread(f_buffer,1,lenread,fp);
		if ( ! done ) {
			break;
		}

		for ( size_t i = 0 ; i < done ; ++i ) {
			if ( f_buffer[i] == 0 ) {
				ostr.append(1,alt);
			}
			else {
				ostr.append(1,static_cast<yaya::char_t>(static_cast<unsigned char>(f_buffer[i])));
			}
		}

		read += done;
		if ( done < lenread ) { break; }
	}

	return read;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::ReadEncode
 *  �@�\�T�v�F  �t�@�C������o�C�i���f�[�^���G���R�[�h���ēǂݎ��܂�
 *
 *  �Ԓl�@�@�F�@-1/0/1=EOF/���s/����
 * -----------------------------------------------------------------------
 */
int	CFile1::ReadEncode(yaya::string_t &ostr, size_t len, const yaya::string_t &type)
{
	ostr.erase();

	if (fp == NULL)
		return 0;

	if(len<1){ //0=�f�t�H���g�T�C�Y�w��
		len = (size_t)size;
	}

	char f_buffer[3*3*3*3*3*3*3]; //3�̔{���ɂ��邱�� base64�΍�
	size_t read = 0;

	yaya::string_t s;
	int enc_type = 0;
	if ( wcsicmp(type.c_str(),L"base64") == 0 ) {
		enc_type = 1;
	}
	else if ( wcsicmp(type.c_str(),L"form") == 0 ) {
		enc_type = 2;
	}

	while ( true ) {
		size_t lenread = len - read;
		if ( lenread > sizeof(f_buffer) ) {
			lenread = sizeof(f_buffer);
		}

		size_t done = fread(f_buffer,1,lenread,fp);
		if ( ! done ) {
			break;
		}

		s.erase();
		if ( enc_type == 1 ) { //b64
			EncodeBase64(s,f_buffer,done);
		}
		else if ( enc_type == 2 ) { //form
			EncodeURL(s,f_buffer,done,true);
		}
		else {
			EncodeURL(s,f_buffer,done,false);
		}
		ostr += s;

		read += done;
		if ( done < lenread ) { break; }
	}

	return read;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::FSeek
 *  �@�\�T�v�F  C���C�u����fseek����
 *  �Ԓl�@�@�F�@0/1=���s/����
 * -----------------------------------------------------------------------
 */
yaya::int_t CFile1::FSeek(yaya::int_t offset,int origin){
	if (fp == NULL)
		return 0;

#ifdef POSIX
	yaya::int_t result = fseeko(fp, offset, origin);
#else
	yaya::int_t result=::_fseeki64(fp,offset,origin);
#endif

	if(result!=0){
		return 0;
	}else{
		return 1;
	}
}


/* -----------------------------------------------------------------------
 *  �֐���  �F  CFile1::FTell
 *  �@�\�T�v�F  C���C�u����ftell����
 *  �Ԓl�@�@�F�@-1/���̑�=���s/�����iftell�̌��ʁj
 * -----------------------------------------------------------------------
 */
yaya::int_t CFile1::FTell(){
	if (fp == NULL)
		return -1;

#ifdef POSIX
	yaya::int_t result = ftello(fp);
#else
	yaya::int_t result=::_ftelli64(fp);
#endif

	if(result<0){
		return -1;
	}else{
		return result;
	}
}

