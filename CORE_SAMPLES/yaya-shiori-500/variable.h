// 
// AYA version 5
//
// �ϐ��������N���X�@CVariable/CLVSubStack/CLocalVariable/CGlobalVariable
// written by umeici. 2004
// 
// CVariable�N���X�͒l�̕ێ������s�Ȃ��܂���B
//
// CLVSubStack/CLocalVariable�̓��[�J���ϐ����Ǘ����܂��B
// �X�^�b�N�Ƃ͖��΂���Ŏ��ۂ̍\���͉ϒ��z��ł��i�����_���A�N�Z�X�����������̂Łj
//
// CLocalVariable�̃C���X�^���X�͊֐����s�J�n���ɍ쐬����A�֐�����Ԃ�ۂɔj������܂��B
// �\���Ƃ��Ă� vector<vector<CVariable>> �ŁA{}����q�̐[�����Ƀ��[�J���ϐ��̔z���
// �����Ă��邱�ƂɂȂ�܂��B{}����q�ɓ���ۂɔz�񂪒ǉ�����A�o��ۂɔj������܂��B
//
// CGlobalVariable�̓O���[�o���ϐ����Ǘ����܂��B
//

#ifndef	VARIABLEH
#define	VARIABLEH

//----

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <vector>
#include <map>
#include <memory>

#include "cell.h"
#include "globaldef.h"
#include "value.h"

class CAyaVM;
class CFunction;

class	CVariable
{
public:
	yaya::string_t	name;					// ���O
	yaya::string_t	delimiter;				// �f���~�^

	yaya::string_t setter;
	yaya::string_t watcher;
	yaya::string_t destorier;

protected:
	mutable std_shared_ptr<CValue> m_value;				// �l
	bool	erased;					// �������ꂽ���Ƃ������t���O�i�O���[�o���ϐ��Ŏg�p�j
									// 0/1=�L��/�������ꂽ

public:
	CVariable(const yaya::string_t &n)
	{
		name       = n;
		delimiter  = VAR_DELIMITER;

		erased     = 0;
	}

	CVariable(yaya::char_t *n)
	{
		name       = n;
		delimiter  = VAR_DELIMITER;

		erased     = 0;
	}

	CVariable(void)
	{
		name.erase();
		delimiter  = VAR_DELIMITER;

		erased     = 0;
	}

	~CVariable(void) {}

	void	Enable(void) { erased = 0; }
	void	Erase(void) {
		erased = 1;
		m_value.reset();
		setter.erase();
		watcher.erase();
		destorier.erase();
	}
	char	IsErased(void) { return erased; }

	//////////////////////////////////////
	std_shared_ptr<CValue> &value_shared(void) const {
		return m_value;
	}
	const CValue &value_const(void) const {
		if ( ! m_value.get() ) {
			return emptyvalue;
		}
		return *m_value;
	}
	inline const CValue &value(void) const {
		return value_const();
	}
	CValue &value(void) {
		if( ! m_value.get() ) {
			m_value=std_make_shared<CValue>();
		}
		return *m_value;
	}
	const CValue& call_watcher(CAyaVM& vm, CValue& save);
	void call_destorier(CAyaVM& vm);
	void call_setter(CAyaVM& vm, const CValue& var_before);
	void set_watcher(const yaya::string_t& _watcher){watcher=_watcher;}
	void set_destorier(const yaya::string_t& _destorier){ destorier = _destorier;}
	void set_setter(const yaya::string_t& _setter){ setter = _setter;}
};

//----

class	CLVSubStack
{
public:
	std::vector<CVariable> substack;
};

//----

class	CLocalVariable
{
protected:
	std::vector<CLVSubStack> stack;
	int	depth;
	CAyaVM* pvm;
public:
	CLocalVariable(CAyaVM&vm);
	~CLocalVariable(void);

	CVariable	*GetArgvPtr(void);

	void	AddDepth(void);
	void	DelDepth(void);

	int		GetDepth(void) { return depth; }

	int		GetNumber(int depth);
	CVariable	*GetPtr(size_t depth,size_t index);
	CVariable	*GetPtr(const yaya::char_t* name);
	CVariable	*GetPtr(const yaya::string_t& name);

public:
	void	GetIndex(const yaya::char_t *name, int &id, int &dp);
	void	GetIndex(const yaya::string_t &name, int &id, int &dp);

	void	Make(const yaya::char_t *name);
	void	Make(const yaya::string_t &name);
	void	Make(const yaya::char_t *name, const CValue &value);
	void	Make(const yaya::string_t &name, const CValue &value);
	void	Make(const yaya::string_t &name, const CValueSub &value);
	void	Make(const yaya::char_t *name, const yaya::string_t &delimiter);
	void	Make(const yaya::string_t &name, const yaya::string_t &delimiter);

	const CValue& GetValue(const yaya::char_t *name);
	const CValue& GetValue(const yaya::string_t &name);

	CValue*	GetValuePtr(const yaya::char_t *name);
	CValue*	GetValuePtr(const yaya::string_t &name);

	yaya::string_t	GetDelimiter(const yaya::char_t *name);
	yaya::string_t	GetDelimiter(const yaya::string_t &name);

	void	SetDelimiter(const yaya::char_t *name, const yaya::string_t &value);
	void	SetDelimiter(const yaya::string_t &name, const yaya::string_t &value);

	void	SetValue(const yaya::char_t *name, const CValue &value);
	void	SetValue(const yaya::string_t &name, const CValue &value);

	size_t	GetMacthedLongestNameLength(const yaya::string_t &name);

	void	Erase(const yaya::string_t &name);
};

//----

class	CGlobalVariable
{
protected:
	std::vector<CVariable> var;
	yaya::indexmap varmap;

private:
	CAyaVM &vm;

	CGlobalVariable(void);

public:
	CGlobalVariable(CAyaVM &vmr) : vm(vmr) {
	}
	void	CompleteSetting(void)
	{
	}

	int		Make(const yaya::string_t &name, char erased);

	size_t	GetMacthedLongestNameLength(const yaya::string_t &name);

	int		GetIndex(const yaya::string_t &name);

	yaya::string_t	GetName(size_t index) { return var[index].name; }
	size_t		GetNumber(void) { return var.size(); }
	CVariable	*GetPtr(size_t index) { return &(var[index]); }
	CVariable	*GetPtr(const yaya::string_t& name) {
		int index= GetIndex(name);
		if (index != -1)
			return GetPtr(index);
		else
			return NULL;
	}

	CValue			*GetValuePtr(size_t index) { return &(var[index].value()); }
	const CValue	*GetValuePtr(size_t index) const { return &(var[index].value_const()); }

	void	SetType(size_t index, int type) { var[index].value().SetType(type); }

	const CValue&	GetValue(size_t index) const { return var[index].value_const(); }

	yaya::string_t&	GetDelimiter(size_t index) { return var[index].delimiter; }

	void	SetValue(size_t index, const CValue &value) { var[index].Enable(); var[index].value() = value; }
	void	SetValue(size_t index, yaya::int_t value) { var[index].Enable(); var[index].value() = value; }
	void	SetValue(size_t index, double value) { var[index].Enable(); var[index].value() = value; }
	void	SetValue(size_t index, const yaya::string_t &value) { var[index].Enable(); var[index].value() = value; }
	void	SetValue(size_t index, const yaya::char_t *value) { var[index].Enable(); var[index].value() = value; }
	void	SetValue(size_t index, const CValueArray &value) { var[index].Enable(); var[index].value() = value; }
	void	SetValue(size_t index, const CValueSub &value) { var[index].Enable(); var[index].value() = value; }
	void	SetDelimiter(size_t index, const yaya::string_t value) { var[index].Enable(); var[index].delimiter = value; }

	void	EnableValue(size_t index) { var[index].Enable(); }

	void	Erase(const yaya::string_t &name)
	{
		int	index = GetIndex(name);
		if (index >= 0) {
			var[index].Erase();
		}
	}

};

//----

#endif
