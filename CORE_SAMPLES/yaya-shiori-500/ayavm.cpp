// 
// AYA version 5
//
// AYA��1�C���X�^���X��ێ�����N���XAYAVM
// written by the Maintenance Shop/C.Ponapalt 2006
// 

#ifdef _MSC_VER
#pragma warning( disable : 4786 ) //�u�f�o�b�O�����ł̎��ʎq�؎̂āv
#pragma warning( disable : 4503 ) //�u�������ꂽ���O�̒��������E���z���܂����B���O�͐؂�̂Ă��܂��B�v
#endif

#include "ayavm.h"

#include "basis.h"
#include "file.h"
#include "function.h"
#include "lib.h"
#include "misc.h"
#include "parser0.h"
#include "parser1.h"
#include "sysfunc.h"

//#include "babel/babel.h"

#ifdef POSIX
#include <sys/time.h>
#else
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

//////////DEBUG/////////////////////////
#ifdef _WINDOWS
#ifdef _DEBUG
#include <crtdbg.h>
#define new new( _NORMAL_BLOCK, __FILE__, __LINE__)
#endif
#endif
////////////////////////////////////////

/*-----------------------------------------------
	�R���X�g���N�^
-----------------------------------------------*/

CAyaVM::CAyaVM()
{
	memset(&rs_sysfunc64,  0, sizeof(rs_sysfunc64));
	memset(&rs_internal64, 0, sizeof(rs_internal64));
}

/*-----------------------------------------------
	�R�s�[�R���X�g���N�^
	shared_ptr���f�B�[�v�R�s�[����_�ɒ���
-----------------------------------------------*/

CAyaVM::CAyaVM(CAyaVM &ovm)
{
	#define copy_new(name) yaya::shared_ptr_deep_copy(ovm.name,name);
	copy_new(m_basis);
	copy_new(m_function_exec);
	copy_new(m_gdefines);
	copy_new(m_call_limit);
	copy_new(m_sysfunction);
	copy_new(m_variable);
	copy_new(m_files);
	copy_new(m_libs);
	copy_new(m_parser0);
	copy_new(m_parser1);
	#undef copy_new

	m_logger = ovm.m_logger;
	rs_sysfunc64 = ovm.rs_sysfunc64;
	rs_internal64 = ovm.rs_internal64;
}

CAyaVM* CAyaVM::get_a_deep_copy()
{
	CAyaVM *nvm = new CAyaVM(*this);
	return nvm;
}

/*-----------------------------------------------
	������
	�قڗ����������p
-----------------------------------------------*/
void CAyaVM::load(void)
{
	unsigned int dwSeed;

	//babel::init_babel();

#ifdef POSIX
	struct timeval tv;
	gettimeofday(&tv,NULL);
	dwSeed = tv.tv_usec;
#else
	dwSeed = ::GetTickCount();
#endif

	init_genrand64(rs_internal64, dwSeed);
	init_genrand64(rs_sysfunc64, dwSeed);
}

/*-----------------------------------------------
	�I��
-----------------------------------------------*/
void CAyaVM::unload(void)
{
}

/*-----------------------------------------------
	request
-----------------------------------------------*/
void CAyaVM::request_before(void)
{
}

void CAyaVM::request_after(void)
{
	m_function_destruct.reset();
}

/*-----------------------------------------------
	�p�[�X�p
-----------------------------------------------*/
CFunctionDef& CAyaVM::function_parse()
{
	if ( m_function_parse.get() ) {
		return *m_function_parse.get();
	}
	function_exec();
	m_function_parse = m_function_exec;
	return *m_function_parse.get();
}

/*-----------------------------------------------
	����func����
-----------------------------------------------*/
void CAyaVM::func_parse_to_exec(void)
{
	m_function_destruct = m_function_exec;
	m_function_exec = m_function_parse;
}

void CAyaVM::func_parse_destruct(void)
{
	m_function_parse.reset();
	m_function_parse = m_function_exec;
}

void CAyaVM::func_parse_new(void)
{
	yaya::shared_ptr_deep_copy(m_function_exec,m_function_parse);

	m_function_parse->deep_copy_func(*m_function_exec);
}

/*-----------------------------------------------
	��������
-----------------------------------------------*/
size_t CAyaVM::genrand_uint(size_t n)
{
	return genrand64_int63(rs_internal64) % n;
}

yaya::int_t CAyaVM::genrand_sysfunc_ll(yaya::int_t n)
{
	return genrand64_int63(rs_sysfunc64) % n;
}

void CAyaVM::genrand_sysfunc_srand_ll(yaya::int_t n)
{
	init_genrand64(rs_sysfunc64,n);
}

void CAyaVM::genrand_sysfunc_srand_array(const std::uint64_t a[],const int n)
{
	init_by_array64(rs_sysfunc64,a,n);
}

// ������ƂЂǂ��n�b�N�ł����c�c

#define FACTORY_DEFINE_THIS(classt,deft) \
	classt & CAyaVM:: deft () { \
		if( m_ ## deft .get() == NULL ) { \
			m_##deft = std_make_shared<classt >(classt(*this)); \
		} \
		return *(m_ ## deft .get()); \
	} 

#define FACTORY_DEFINE_PLAIN(classt,deft) \
	classt & CAyaVM:: deft () { \
		if( m_ ## deft .get() == NULL ) { \
			m_##deft = std_make_shared<classt >(); \
		} \
		return *(m_ ## deft .get()); \
	} 


FACTORY_DEFINE_PLAIN(std::vector<CDefine>,gdefines)

FACTORY_DEFINE_THIS(CBasis,basis)

FACTORY_DEFINE_PLAIN(CFunctionDef,function_exec)
FACTORY_DEFINE_PLAIN(CCallLimit,call_limit)
FACTORY_DEFINE_THIS(CSystemFunction,sysfunction)
FACTORY_DEFINE_THIS(CGlobalVariable,variable)

FACTORY_DEFINE_PLAIN(CFile,files)
FACTORY_DEFINE_THIS(CLib,libs)

FACTORY_DEFINE_THIS(CParser0,parser0)
FACTORY_DEFINE_THIS(CParser1,parser1)



