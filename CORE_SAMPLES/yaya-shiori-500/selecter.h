// 
// AYA version 5
//
// �o�͂̑I�����s�Ȃ��N���X�@CSelecter/CDuplEvInfo
// written by umeici. 2004
// 
// CSelecter�͏o�͂̑I�����s�Ȃ��܂��B
// CDuplEvInfo�͏d��������s�Ȃ��܂��B
//

#ifndef	SELECTERH
#define	SELECTERH

//----

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <vector>

#include "cell.h"
#include "value.h"
#include "variable.h"

//There's no reason to define it in enum anymore.
typedef unsigned int choicetype_t;

//alternative definitions for constexpr
static const choicetype_t CHOICETYPE_RANDOM_FLAG       = 0x0001U;
static const choicetype_t CHOICETYPE_SEQUENTIAL_FLAG   = 0x0002U;
static const choicetype_t CHOICETYPE_NONOVERLAP_FLAG   = 0x0004U;
static const choicetype_t CHOICETYPE_ARRAY_FLAG        = 0x0008U;
static const choicetype_t CHOICETYPE_PICKONE_FLAG      = 0x0100U;
static const choicetype_t CHOICETYPE_POOL_FLAG         = 0x0200U;
static const choicetype_t CHOICETYPE_MELT_FLAG         = 0x0400U;
static const choicetype_t CHOICETYPE_ALL_FLAG          = 0x1000U;
static const choicetype_t CHOICETYPE_LAST_FLAG         = 0x2000U;
static const choicetype_t CHOICETYPE_VOID_FLAG         = 0x4000U;

static const choicetype_t CHOICETYPE_SELECT_FILTER     = 0x00FFU;
static const choicetype_t CHOICETYPE_OUTPUT_FILTER     = 0xFF00U;
static const choicetype_t CHOICETYPE_SPECOUT_FILTER    = 0xF000U;

static const choicetype_t CHOICETYPE_VOID              = CHOICETYPE_VOID_FLAG;                                  /* no output */
static const choicetype_t CHOICETYPE_ALL               = CHOICETYPE_ALL_FLAG;                                   /* Sum all outputs as strings */
static const choicetype_t CHOICETYPE_LAST              = CHOICETYPE_LAST_FLAG;                                  /* return last var only */
static const choicetype_t CHOICETYPE_RANDOM            = CHOICETYPE_PICKONE_FLAG | CHOICETYPE_RANDOM_FLAG;      /* random pick one */
static const choicetype_t CHOICETYPE_NONOVERLAP        = CHOICETYPE_PICKONE_FLAG | CHOICETYPE_NONOVERLAP_FLAG;  /* random but not overlapped until the cycle ends */
static const choicetype_t CHOICETYPE_SEQUENTIAL        = CHOICETYPE_PICKONE_FLAG | CHOICETYPE_SEQUENTIAL_FLAG;  /* pick sequential */
static const choicetype_t CHOICETYPE_ARRAY             = CHOICETYPE_PICKONE_FLAG | CHOICETYPE_ARRAY_FLAG;       /* extract as array */
static const choicetype_t CHOICETYPE_POOL              = CHOICETYPE_POOL_FLAG    | CHOICETYPE_RANDOM_FLAG;      /* random, ignoring scope */
static const choicetype_t CHOICETYPE_POOL_ARRAY        = CHOICETYPE_POOL_FLAG    | CHOICETYPE_ARRAY_FLAG;       /* array, ignoring scope : pick all candidates as array */
static const choicetype_t CHOICETYPE_NONOVERLAP_POOL   = CHOICETYPE_POOL_FLAG    | CHOICETYPE_NONOVERLAP_FLAG;  /* nonoverlap, ignoring scope */
static const choicetype_t CHOICETYPE_SEQUENTIAL_POOL   = CHOICETYPE_POOL_FLAG    | CHOICETYPE_SEQUENTIAL_FLAG;  /* sequential, ignoring scope */

class CAyaVM;

//----

class CVecValue
{
public:
	std::vector<CValue> array;
};

//----

class	CDuplEvInfo
{
protected:
	choicetype_t	type;			// �I�����

	std::vector<size_t>	num;			// --�ŋ�؂�ꂽ�̈斈�̌�␔
	std::vector<size_t>	roundorder;		// ���񏇏�

	ptrdiff_t	lastroundorder; // ���O�̏��񏇏��l
	size_t	total;			// �o�͌��l�̑���
	size_t	index;			// ���݂̏���ʒu

private:
	CDuplEvInfo(void);

public:
	CDuplEvInfo(choicetype_t tp)
	{
		type = tp;
		total = 0;
		index = 0;
		lastroundorder = -1;
	}

	choicetype_t	GetType(void) { return type; }

	CValue	Choice(CAyaVM &vm, size_t areanum, const std::vector<CVecValue> &values, int mode);
	size_t	GetNum(CAyaVM& vm, size_t areanum, const std::vector<CVecValue>& values, int mode);

protected:
	void	InitRoundOrder(CAyaVM &vm,int mode);
	bool	UpdateNums(size_t areanum, const std::vector<CVecValue> &values);
	bool	UpdateNums(const CValue& value);
	CValue	GetValue(CAyaVM &vm, size_t areanum, const std::vector<CVecValue> &values);
};

//----

class CSelecter
{
protected:
	CAyaVM *pvm;
	std::vector<CVecValue>	values;			// �o�͌��l
	size_t					areanum;		// �o�͌���~�ς���̈�̐�
	CDuplEvInfo				*duplctl;		// �Ή�����d��������ւ̃|�C���^
	ptrdiff_t				aindex;			// switch�\���Ŏg�p

	friend class CFunction;//for pool
public:

#if CPP_STD_VER < 2011
private:
	CSelecter() {
		aindex = areanum = 0;
		duplctl			 = nullptr;
		pvm				 = nullptr;
	}
public:
#else
	CSelecter()=delete;
#endif
	CSelecter(CAyaVM *pvmr, CDuplEvInfo* dc, ptrdiff_t aid);

	void	AddArea(void);
	void	Append(const CValue &value);
	CValue	Output(void);
	size_t	OutputNum();

	static choicetype_t			GetDefaultBlockChoicetype(choicetype_t nowtype);
	static choicetype_t			StringToChoiceType(const yaya::string_t& ctypestr, CAyaVM &vm, const yaya::string_t& dicfilename, size_t linecount);
	static yaya::string_t		ChoiceTypeToString(choicetype_t ctype);

	void clear() {
		areanum = 0;
		values.clear();
		values.emplace_back(CVecValue());
	}
protected:
	CValue	StructArray1(size_t index);
	CValue	StructArray(void);
	CValue	StructString1(size_t index);
	CValue	StructString(void);
	CValue	ChoiceRandom(void);
	size_t	ChoiceRandom_NumGet(void);
	CValue	ChoiceRandom1(size_t index);
	CValue	ChoiceByIndex(void);
	CValue	ChoiceByIndex1(size_t index);
};

//----

#endif
