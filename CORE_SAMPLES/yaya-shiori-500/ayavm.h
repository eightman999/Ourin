// 
// AYA version 5
//
// AYA��1�C���X�^���X��ێ�����N���XAYAVM
// written by the Maintenance Shop/C.Ponapalt 2006
// 
// CAyaVM������������ƕ�����AYA��1�̃v���Z�X/�X���b�h/���W���[�����ő��点�邱�Ƃ��ł��܂��B
// 

#ifndef AYAVM_H
#define AYAVM_H

#include <vector>
#include <map>
#include <memory>
#include "log.h"
#include "mt19937ar.h"
#include "globaldef.h"

class CBasis;
class CFunction;
class CFunctionDef;
class CCallLimit;
class CSystemFunction;
class CGlobalVariable;
class CFile;
class CLib;
class CParser0;
class CParser1;
class CDefine;
class CAyaVM;

class CAyaVM
{
private:
	std_shared_ptr<CBasis>					m_basis;

	std_shared_ptr<CFunctionDef>	m_function_parse;
	std_shared_ptr<CFunctionDef>	m_function_exec;
	std_shared_ptr<CFunctionDef>	m_function_destruct;
	
	std_shared_ptr< std::vector<CDefine> >	m_gdefines;

	std_shared_ptr<CCallLimit>				m_call_limit;
	std_shared_ptr<CSystemFunction>			m_sysfunction;
	std_shared_ptr<CGlobalVariable>			m_variable;

	std_shared_ptr<CFile>					m_files;
	std_shared_ptr<CLib>						m_libs;

	std_shared_ptr<CParser0>					m_parser0;
	std_shared_ptr<CParser1>					m_parser1;

	CLog	m_logger;

	MersenneTwister64 rs_sysfunc64;
	MersenneTwister64 rs_internal64;

public:
	CAyaVM();
	CAyaVM(CAyaVM &vm);
	virtual ~CAyaVM() {}

	CAyaVM* get_a_deep_copy();

	void load(void);
	void unload(void);

	void request_before(void);
	void request_after(void);

	void func_parse_to_exec(void);
	void func_parse_destruct(void);
	void func_parse_new(void);

	size_t genrand_uint(size_t n);

	yaya::int_t genrand_sysfunc_ll(yaya::int_t n);

	void genrand_sysfunc_srand_ll(yaya::int_t n);
	void genrand_sysfunc_srand_array(const std::uint64_t a[],const int n);

	// �吧��
	CBasis&					basis();

	// �֐�/�V�X�e���֐�/�O���[�o���ϐ�
	CFunctionDef&	function_parse(); //�p�[�X�p
	CFunctionDef&	function_exec(); //���s�p

	std::vector<CDefine>&	gdefines();

	CCallLimit&				call_limit();
	CSystemFunction&		sysfunction();
	CGlobalVariable&		variable();

	// �t�@�C���ƊO�����C�u����
	CFile&					files();
	CLib&					libs();

	// ���K�[
	inline CLog& logger() {
		return m_logger;
	}

	// �p�[�T
	CParser0&				parser0();
	CParser1&				parser1();
};

#endif //AYAVM_H


