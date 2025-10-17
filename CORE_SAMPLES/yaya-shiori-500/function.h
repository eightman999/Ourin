// 
// AYA version 5
//
// �֐��������N���X�@CFunction/CStatement
// written by umeici. 2004
// 
// CFunction���֐��ACStatement���֐����̃X�e�[�g�����g�ł��B
// CStatement�͒l�̕ێ��݂̂ŁA����̓C���X�^���X������CFunction�ōs���܂��B
//

#ifndef	FUNCTIONH
#define	FUNCTIONH

//----

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <vector>
#include <memory>

#include "cell.h"
#include "selecter.h"
#include "globaldef.h"
#include "variable.h"
#include "value.h"

class CAyaVM;
class CCell;
class CSerial;
class CSelecter;

class	CStatement
{
public:
	int				type;			// �X�e�[�g�����g�̎��
	ptrdiff_t		jumpto;			// ��ѐ�s�ԍ� break/continue/return/if/elseif/else/for/foreach�Ŏg�p���܂�
									// �Y���P�ʏI�[��"}"�̈ʒu���i�[����Ă��܂�
	ptrdiff_t linecount;			// �����t�@�C�����̍s�ԍ�

	mutable std_shared_ptr < CDuplEvInfo >	dupl_block;		// pool:{ //...
	mutable bool						ismutiarea;

private:
	mutable std_shared_ptr<std::vector<CCell> >		m_cell;				// �����̍��̌Q�@
	mutable std_shared_ptr<std::vector<CSerial> >	m_serial;			// �����̉��Z����

public:
	CStatement(int t, ptrdiff_t l, std_shared_ptr<CDuplEvInfo> dupl = std_shared_ptr<CDuplEvInfo>() )
	{
		type = t;
		linecount = l;
		jumpto = 0;
		dupl_block=dupl;
		ismutiarea = false;
	}
	CStatement(void) {
		type = ST_NOP;
		linecount = 0;
		jumpto = 0;
		dupl_block.reset();
		ismutiarea = false;
	}
	~CStatement(void) {}

	void deep_copy(CStatement &from) {
		yaya::shared_ptr_deep_copy(from.m_cell,this->m_cell);
		yaya::shared_ptr_deep_copy(from.m_serial,this->m_serial);
	}

	//////////////////////////////////////////////
	std::vector<CCell>::size_type cell_size(void) const {
		if ( ! m_cell.get() ) {
			return 0;
		}
		else {
			return m_cell->size();
		}
	}
	const std::vector<CCell>& cell(void) const {
		if ( ! m_cell.get() ) {
			m_cell=std_make_shared<std::vector<CCell> >();
		}
		return *m_cell;
	}
	std::vector<CCell>& cell(void) {
		if ( ! m_cell.get() ) { 
			m_cell=std_make_shared<std::vector<CCell> >();
		}
		return *m_cell;
	}
	//////////////////////////////////////////////
	std::vector<CSerial>::size_type serial_size(void) const {
		if ( ! m_serial.get() ) {
			return 0;
		}
		else {
			return m_serial->size();
		}
	}
	const std::vector<CSerial>& serial(void) const {
		if ( ! m_serial.get() ) {
			m_serial=std_make_shared<std::vector<CSerial> >();
		}
		return *m_serial;
	}
	std::vector<CSerial>& serial(void) {
		if ( ! m_serial.get() ) {
			m_serial=std_make_shared<std::vector<CSerial> >();
		}
		return *m_serial;
	}
	//////////////////////////////////////////////
	void cell_cleanup(void) const {
		const std::vector<CCell>& c = cell();

		for ( size_t i = 0 ; i < c.size() ; ++i ) {
			c[i].tmpdata_cleanup();
		}
	}
};

//----

class	CFunction
{
private:
	CAyaVM *pvm;
	
public:
	yaya::string_t				name;			// ���O
	yaya::string_t::size_type	namelen;		// ���O�̒���
	std::vector<CStatement>		statement;		// ���ߌS
	yaya::string_t				dicfilename;	// �Ή����鎫���t�@�C����
	yaya::string_t				dicfilename_fullpath;

protected:
	size_t					statelenm1;		// statement�̒���-1�i1�������Ă���̂͏I�[��"}"���������Ȃ����߂ł��j
	size_t					linecount;		// ��`���ꂽ�s

private:
	CFunction(void);

public:
	CFunction(CAyaVM& vmr, const yaya::string_t& n, const yaya::string_t& df, int lc);

	~CFunction(void) {}

	void    deep_copy_statement(CFunction &from);

	class ExecutionResult {
	public:
		CSelecter PossibleResults;

		ExecutionResult(CAyaVM* pvm) :PossibleResults(pvm, NULL, BRACE_DEFAULT) {}
		ExecutionResult(CSelecter& a) :PossibleResults(a) {}

		virtual ~ExecutionResult() { }
		
		CValue Output() { return PossibleResults.Output(); }
		size_t OutputNum() { return PossibleResults.OutputNum(); }
		
		operator CValue() { return Output(); }
	};

	void	CompleteSetting(void);
	ExecutionResult	Execute();
	ExecutionResult	Execute(const CValue& arg);
	ExecutionResult	Execute(const CValue &arg, CLocalVariable &lvar);
private:
	void Execute_SEHhelper(ExecutionResult& aret, CLocalVariable& lvar, int& exitcode);
	void Execute_SEHbody(ExecutionResult& retas, CLocalVariable& lvar, int& exitcode);
public:
	const CValue& GetFormulaAnswer(CLocalVariable &lvar, CStatement &st);

	int     ReindexUserFunctions(void);

	const yaya::string_t&	GetFileName() const {return dicfilename;}
	size_t	GetLineNumBegin() const { return linecount;}
	size_t	GetLineNumEnd() const   { return statement.empty() ? 0 : statement.back().linecount;}

protected:
	
	class ExecutionInBraceResult : public ExecutionResult {
	public:
		size_t linenum;

		ExecutionInBraceResult(CSelecter& a, size_t b) : ExecutionResult(a), linenum(b) {}
		virtual ~ExecutionInBraceResult() { }
	};

	ExecutionInBraceResult	ExecuteInBrace(size_t line, CLocalVariable& lvar, yaya::int_t type, int& exitcode, std::vector<CVecValue>* UpperLvCandidatePool, bool inpool);

	void	Foreach(CLocalVariable& lvar, CSelecter& output, size_t line, int& exitcode, std::vector<CVecValue>* UpperLvCandidatePool, bool inpool);

	const	CValue& GetValueRefForCalc(CCell &cell, CStatement &st, CLocalVariable &lvar);
	
	void	SolveEmbedCell(CCell &cell, CStatement &st, CLocalVariable &lvar);

	char	Comma(CValue &answer, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	char	CommaAdd(CValue &answer, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	char	Subst(int type, CValue &answer, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	char	SubstToArray(CCell &vcell, CCell &ocell, CValue &answer, CStatement &st, CLocalVariable &lvar);
	char	Array(CCell &anscell, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	bool	_in_(const CValue &src, const CValue &dst);
	bool	not_in_(const CValue &src, const CValue &dst);
	char	ExecFunctionWithArgs(CValue &answer, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	char	ExecSystemFunctionWithArgs(CCell& cell, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	void	ExecHistoryP1(size_t start_index, CCell& cell, const CValue &arg, CStatement &st);
	void	ExecHistoryP2(CCell &cell, CStatement &st);
	char	Feedback(CCell &anscell, std::vector<size_t> &sid, CStatement &st, CLocalVariable &lvar);
	void	EncodeArrayOrder(CCell &vcell, const CValue &order, CLocalVariable &lvar, CValue &result);
	void	FeedLineToTail(size_t&line);
};

//----

class CFunctionDef
{
private:
	yaya::indexmap map;

public:
	std::vector<CFunction> func;
	
	ptrdiff_t GetFunctionIndexFromName(const yaya::string_t& name);
	void AddFunctionIndex(const yaya::string_t& name,size_t index);
	void ClearFunctionIndex(void);
	void RebuildFunctionMap(void);
	void deep_copy_func(CFunctionDef &from);
};

//----

#endif
