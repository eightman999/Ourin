// 
// AYA version 5
//
// �\�����/���ԃR�[�h�̐������s���N���X�@CParser0
// written by umeici. 2004
// 
// �\����͎���CBasis�����x����CParser0::Parse�����s����܂��B
// CParser0::ParseEmbedString��eval�n�̏����Ŏg�p����܂��B
//

#ifndef	PARSER0H
#define	PARSER0H

//----

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <vector>
#include "globaldef.h"
#include "selecter.h"

class	CDefine
{
public:
	yaya::string_t	before;
	yaya::string_t	after;
	yaya::string_t	dicfilename;
	yaya::string_t	dicfilename_fullpath;
public:
	CDefine(CAyaVM& vm, const yaya::string_t& bef, const yaya::string_t& aft, const yaya::string_t& df);

	CDefine(void) {}
	~CDefine(void) {}
};

//----

class CAyaVM;
class CStatement;
class CCell;
class CDic1;

class	CParser0
{
private:
	CAyaVM &vm;

	CParser0(void);

	std::vector<choicetype_t> m_defaultBlockChoicetypeStack;
	std::vector<size_t>  m_BlockhHeaderOfProcessingIndexStack;

public:
	CParser0(CAyaVM &vmr) : vm(vmr) {
		; //NOOP
	}
	char	Parse(int charset, const std::vector<CDic1>& dics);
	char	ParseEmbedString(yaya::string_t& str, CStatement &st, const yaya::string_t &dicfilename, ptrdiff_t linecount);

	int		DynamicLoadDictionary(const yaya::string_t& dicfilename, int charset);
	int		DynamicAppendRuntimeDictionary(const yaya::string_t& codes);
	int		DynamicUnloadDictionary(yaya::string_t dicfilename);
	int		DynamicUndefFunc(const yaya::string_t& funcname);

	//changed to public, for processglobaldefine
	void	ExecDefinePreProcess(yaya::string_t &str, const std::vector<CDefine>& defines);

protected:
	bool	ParseAfterLoad(const yaya::string_t &dicfilename);
	char	LoadDictionary1(const yaya::string_t& filename, std::vector<CDefine>& gdefines, int charset);
	char	GetPreProcess(yaya::string_t& str, std::vector<CDefine>& defines, std::vector<CDefine>& gdefines, const yaya::string_t& dicfilename,
			ptrdiff_t linecount);

	void	ExecInternalPreProcess(yaya::string_t &str,const yaya::string_t &file, ptrdiff_t line);

	char	IsCipheredDic(const yaya::string_t& filename);
	void	SeparateFactor(std::vector<yaya::string_t> &s, yaya::string_t &line);
	char	DefineFunctions(std::vector<yaya::string_t> &s, const yaya::string_t& dicfilename, ptrdiff_t linecount, size_t&depth, ptrdiff_t&targetfunction);
	ptrdiff_t MakeFunction(const yaya::string_t& name, choicetype_t chtype, const yaya::string_t& dicfilename, ptrdiff_t linecount);
	char	StoreInternalStatement(size_t targetfunc, yaya::string_t& str, size_t& depth, const yaya::string_t& dicfilename, ptrdiff_t linecount);
	char	MakeStatement(int type, size_t targetfunc, yaya::string_t &str, const yaya::string_t& dicfilename, ptrdiff_t linecount);
	char	StructWhen(yaya::string_t &str, std::vector<CCell> &cells, const yaya::string_t& dicfilename, ptrdiff_t linecount);
	char	StructFormula(yaya::string_t &str, std::vector<CCell> &cells, const yaya::string_t& dicfilename, ptrdiff_t linecount);
	void	StructFormulaCell(yaya::string_t &str, std::vector<CCell> &cells);

	char	AddSimpleIfBrace(const yaya::string_t &dicfilename);

	char	SetCellType(const yaya::string_t &dicfilename);
	char	SetCellType1(CCell& scell, char emb, const yaya::string_t& dicfilename, ptrdiff_t linecount);

	char	MakeCompleteFormula(const yaya::string_t &dicfilename);
	char	ParseEmbeddedFactor(const yaya::string_t& dicfilename);
	char	ParseEmbeddedFactor1(CStatement& st, const yaya::string_t& dicfilename);
	void	ConvertPlainString(const yaya::string_t& dicfilename);
	void	ConvertPlainString1(CStatement& st, const yaya::string_t& dicfilename);
	char	ConvertEmbedStringToFormula(yaya::string_t& str, const yaya::string_t& dicfilename, ptrdiff_t linecount);
	char	CheckDepthAndSerialize(const yaya::string_t& dicfilename);
	char	CheckDepth1(CStatement& st, const yaya::string_t& dicfilename);
	char	CheckDepthAndSerialize1(CStatement& st, const yaya::string_t& dicfilename);
	char	MakeCompleteConvertionWhenToIf(const yaya::string_t& dicfilename);

	char	IsDicFileAlreadyExist(yaya::string_t dicfilename);
};

//----

#endif
