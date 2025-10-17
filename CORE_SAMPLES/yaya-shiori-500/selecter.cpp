// 
// AYA version 5
//
// �o�͂̑I�����s�Ȃ��N���X�@CSelecter
// - �又����
// written by umeici. 2004
// 

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include "selecter.h"

#include "globaldef.h"
#include "sysfunc.h"
#include "ayavm.h"
#include "wsex.h"
#include "messages.h"

//////////DEBUG/////////////////////////
#ifdef _WINDOWS
#ifdef _DEBUG
#include <crtdbg.h>
#define new new( _NORMAL_BLOCK, __FILE__, __LINE__)
#endif
#endif
////////////////////////////////////////

/* -----------------------------------------------------------------------
 * CSelecter�R���X�g���N�^
 * -----------------------------------------------------------------------
 */
CSelecter::CSelecter(CAyaVM *pvmr, CDuplEvInfo *dc, ptrdiff_t aid) : pvm(pvmr), duplctl(dc), aindex(aid)
{
	areanum = 0;

	CVecValue	addvv;
	values.emplace_back(addvv);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::AddArea
 *  �@�\�T�v�F  �V�����o�͊i�[�p�̗̈��p�ӂ��܂�
 * -----------------------------------------------------------------------
 */
void	CSelecter::AddArea(void)
{
	// �ǉ��O�̗̈悪�󂾂����ꍇ�̓_�~�[�̋󕶎����ǉ�
	if (!values[areanum].array.size())
		Append(CValue());

	// �̈��ǉ�
	CVecValue	addvv;
	values.emplace_back(addvv);
	areanum++;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::Append
 *  �@�\�T�v�F  ���l��ǉ����܂�
 * -----------------------------------------------------------------------
 */
void	CSelecter::Append(const CValue &value)
{
	//�󕶎���͂���ς�ǉ����Ȃ��Ƃ܂���
	//if (value.GetType() == F_TAG_STRING && !value.s_value.size())
	//	return;
	if (value.GetType() == F_TAG_VOID)
		return;

	values[areanum].array.emplace_back(value);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::Output
 *  �@�\�T�v�F  �e�̈悩��l�𒊏o���ďo�͂��쐬���Ԃ��܂�
 *  �����@�@�F  duplctl �d��������ւ̃|�C���^
 *  �@�@�@�@�@          NULL�ɏꍇ�̓����_���I���œ��삵�܂�
 *
 *  �����_���I���͂��̃N���X�ŏ������܂��B
 *  nonoverlao/sequential�I����CDuplEvInfo�N���X�ɔC���܂��B
 * -----------------------------------------------------------------------
 */
CValue	CSelecter::Output()
{
	// switch�I��
	if (aindex >= BRACE_SWITCH_OUT_OF_RANGE) {
		pvm->sysfunction().SetLso(aindex);
		return ChoiceByIndex();
	}

	// �̈悪1�����Ȃ��A����₪���݂��Ȃ��ꍇ�͏o�͂Ȃ�
	if (!areanum && !values[0].array.size()) {
		pvm->sysfunction().SetLso(-1);
		return CValue(F_TAG_NOP, 0/*dmy*/);
	}

	// �Ō�̗̈悪�󂾂����ꍇ�̓_�~�[�̋󕶎����ǉ�
	if (!values[areanum].array.size())
		Append(CValue());

	// �����_���I��
	if (duplctl == NULL)
		return ChoiceRandom();

	// �d����𐧌�t���I��
	if (duplctl->GetType() & CHOICETYPE_SPECOUT_FILTER)
		switch(duplctl->GetType()){
		case CHOICETYPE_VOID:
			return CValue(F_TAG_NOP, 0/*dmy*/);
		case CHOICETYPE_ALL:
			return StructString();
		case CHOICETYPE_LAST:
			return *values.rbegin()->array.rbegin();
		}

	switch ( duplctl->GetType() & CHOICETYPE_SELECT_FILTER ) {
	case CHOICETYPE_NONOVERLAP_FLAG:
		return duplctl->Choice(*pvm, areanum, values, CHOICETYPE_NONOVERLAP_FLAG);
	case CHOICETYPE_SEQUENTIAL_FLAG:
		return duplctl->Choice(*pvm, areanum, values, CHOICETYPE_SEQUENTIAL_FLAG);
	case CHOICETYPE_ARRAY_FLAG:
		return StructArray();
	case CHOICETYPE_RANDOM_FLAG:
	default:
		return ChoiceRandom();
	};
}

size_t CSelecter::OutputNum()
{
	// switch�I��
	if (aindex >= BRACE_SWITCH_OUT_OF_RANGE) {
		pvm->sysfunction().SetLso(aindex);
		return 1;
	}

	// �̈悪1�����Ȃ��A����₪���݂��Ȃ��ꍇ�͏o�͂Ȃ�
	if (!areanum && !values[0].array.size()) {
		pvm->sysfunction().SetLso(-1);
		return 0;
	}

	// �Ō�̗̈悪�󂾂����ꍇ�̓_�~�[�̋󕶎����ǉ�
	if (!values[areanum].array.size())
		Append(CValue());

	// �����_���I��
	if (duplctl == NULL)
		return ChoiceRandom_NumGet();

	// �d����𐧌�t���I��
	if (duplctl->GetType() & CHOICETYPE_SPECOUT_FILTER)
		switch(duplctl->GetType()){
		case CHOICETYPE_VOID:
			return 0;
		case CHOICETYPE_ALL:
		case CHOICETYPE_LAST:
			return 1;
		}

	switch ( duplctl->GetType() & CHOICETYPE_SELECT_FILTER ) {
	case CHOICETYPE_NONOVERLAP_FLAG:
		return duplctl->GetNum(*pvm, areanum, values, CHOICETYPE_NONOVERLAP_FLAG);
	case CHOICETYPE_SEQUENTIAL_FLAG:
		return duplctl->GetNum(*pvm, areanum, values, CHOICETYPE_SEQUENTIAL_FLAG);
	case CHOICETYPE_ARRAY_FLAG:
		return 1;
	case CHOICETYPE_RANDOM_FLAG:
	default:
		return ChoiceRandom_NumGet();
	};
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::ChoiceRandom
 *  �@�\�T�v�F  �e�̈悩�烉���_���ɒl�𒊏o���ďo�͂��쐬���Ԃ��܂�
 *
 *  �i�[�̈悪������Ȃ��ꍇ�͂�������̂܂܏o���̂Œl�̌^���ی삳��܂��B
 *  �̈悪��������ꍇ�͂����͕�����Ƃ��Č�������܂��̂ŁA������^�ł̏o�͂ƂȂ�܂��B
 * -----------------------------------------------------------------------
 */
CValue	CSelecter::ChoiceRandom(void)
{
	if (areanum) {
		yaya::string_t	result;
		for(size_t i = 0; i <= areanum; i++)
			result += ChoiceRandom1(i).GetValueString();
		return CValue(result);
	}
	else
		return ChoiceRandom1(0);
}

size_t	CSelecter::ChoiceRandom_NumGet(void)
{
	if (areanum) {
		size_t aret=0;
		for (size_t i = 0; i <= areanum; i++)
			aret *= values[i].array.size();
		return aret;
	}
	else
		return values[0].array.size();
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::ChoiceRandom1
 *  �@�\�T�v�F  �w�肳�ꂽ�̈悩�烉���_���ɒl�𒊏o���܂�
 * -----------------------------------------------------------------------
 */
CValue	CSelecter::ChoiceRandom1(size_t index)
{
	if ( ! values[index].array.size() ) {
		return CValue();
	}

	size_t choice = pvm->genrand_uint(values[index].array.size());

    pvm->sysfunction().SetLso(choice);

    return values[index].array[choice];
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::ChoiceByIndex
 *  �@�\�T�v�F  �e�̈悩��w��ʒu�̒l�𒊏o���ďo�͂��쐬���Ԃ��܂�
 *
 *  �i�[�̈悪������Ȃ��ꍇ�͂�������̂܂܏o���̂Œl�̌^���ی삳��܂��B
 *  �̈悪��������ꍇ�͂����͕�����Ƃ��Č�������܂��̂ŁA������^�ł̏o�͂ƂȂ�܂��B
 *
 *  �w�����␔�����Ȃ��ꍇ�͋󕶎��񂪏o�͂���܂��B
 * -----------------------------------------------------------------------
 */
CValue	CSelecter::ChoiceByIndex()
{
	// �Ō�̗̈悪�󂾂����ꍇ�̓_�~�[�̋󕶎����ǉ�
	if (!values[areanum].array.size())
		Append(CValue());

	// �又��
	if (areanum) {
		yaya::string_t	result;
		for(size_t i = 0; i <= areanum; i++)
			result += ChoiceByIndex1(i).GetValueString();
		return CValue(result);
	}
	else
		return ChoiceByIndex1(0);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::ChoiceByIndex
 *  �@�\�T�v�F  �w�肳�ꂽ�̈悩��w��ʒu�̒l�𒊏o���܂�
 * -----------------------------------------------------------------------
 */
CValue	CSelecter::ChoiceByIndex1(size_t index)
{
	size_t	num = values[index].array.size();

	if (!num)
		return CValue();

	return (aindex >= 0 && (size_t)aindex < num) ? values[index].array[aindex] : CValue();
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::StructArray
 *  �@�\�T�v�F  �e�̈�̒l�����������ėp�z����쐬���Ԃ��܂�
 * -----------------------------------------------------------------------
 */
CValue CSelecter::StructArray()
{
	if (areanum) {
		CValue	result(F_TAG_ARRAY, 0/*dmy*/);
		for(size_t i = 0; i <= areanum; i++) {
			result = result + StructArray1(i);
//			result = result + StructArray1(i).GetValueString();
		}
		return result;
	}
	else {
		return StructArray1(0);
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::StructArray1
 *  �@�\�T�v�F  �w�肳�ꂽ�̈�̒l�����������ėp�z����쐬���܂�
 * -----------------------------------------------------------------------
 */
CValue CSelecter::StructArray1(size_t index)
{
	CValue	result(F_TAG_ARRAY, 0/*dmy*/);

    for(size_t i = 0; i < values[index].array.size(); ++i) {
		const CValue &target = values[index].array[i];
		int	valtype = target.GetType();
		
		if (valtype == F_TAG_ARRAY) {
			result.array().insert(result.array().end(), target.array().begin(), target.array().end());
		}
		else {
			result.array().emplace_back(CValueSub(target));
		}
	}

    return result;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::StructString
 *  �@�\�T�v�F  �e�̈�̒l������������������쐬���Ԃ��܂�
 * -----------------------------------------------------------------------
 */
CValue CSelecter::StructString()
{
	if (areanum) {
		CValue	result(F_TAG_STRING, 0/*dmy*/);
		for(size_t i = 0; i <= areanum; i++) {
			result.s_value += StructString1(i).s_value;
		}
		return result;
	}
	else {
		return StructString1(0);
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::StructString1
 *  �@�\�T�v�F  �w�肳�ꂽ�̈�̒l������������������쐬���܂�
 * -----------------------------------------------------------------------
 */
CValue CSelecter::StructString1(size_t index)
{
	CValue	result(F_TAG_STRING, 0/*dmy*/);

    for(size_t i = 0; i < values[index].array.size(); ++i) {
		const CValue &target = values[index].array[i];
		int	valtype = target.GetType();
		
		if (valtype == F_TAG_STRING) {
			result.s_value += target.s_value;
		}
		else {
			result.s_value += target.GetValueString();
		}
	}

    return result;
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::GetDefaultBlockChoicetype
 *  �@�\�T�v�F  { } �̏o�̓^�C�v���w��̎��̕W���^�C�v
 * -----------------------------------------------------------------------
 */
choicetype_t CSelecter::GetDefaultBlockChoicetype(choicetype_t nowtype)
{
	unsigned int choicetype = 0;

	if (nowtype & CHOICETYPE_SPECOUT_FILTER) {
		return nowtype;
	}
	else {
		if (nowtype & CHOICETYPE_ARRAY_FLAG) {
			choicetype = CHOICETYPE_ARRAY_FLAG;
		}
		else {
			choicetype = CHOICETYPE_RANDOM_FLAG;
		}
	}

	unsigned int outtype = CHOICETYPE_PICKONE_FLAG;
	if (nowtype & CHOICETYPE_POOL_FLAG) {
		outtype = CHOICETYPE_POOL_FLAG;
	}
	else if (nowtype & CHOICETYPE_PICKONE_FLAG) {
		outtype = CHOICETYPE_PICKONE_FLAG;
	}
	else if (nowtype & CHOICETYPE_MELT_FLAG) {
		outtype = CHOICETYPE_MELT_FLAG;
	}

	return static_cast<choicetype_t>(outtype | choicetype);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::StringToChoiceType
 *  �@�\�T�v�F  ������->choicetype_t
 * -----------------------------------------------------------------------
 */
choicetype_t CSelecter::StringToChoiceType(const yaya::string_t& ctypestr, CAyaVM &vm, const yaya::string_t& dicfilename, size_t linecount)
{
	unsigned int outtype = CHOICETYPE_PICKONE_FLAG;

	yaya::string_t checkstr = ctypestr;

	if ( checkstr.find(L"pool") != yaya::string_t::npos ) {
		outtype = CHOICETYPE_POOL_FLAG;
		yaya::ws_replace(checkstr,L"pool",L"");
	}
	else if ( checkstr.find(L"melt") != yaya::string_t::npos ) {
		outtype = CHOICETYPE_MELT_FLAG;
		yaya::ws_replace(checkstr,L"melt",L"");
	}
	else if ( checkstr.find(L"void") != yaya::string_t::npos ) {
		outtype = CHOICETYPE_VOID_FLAG;
		yaya::ws_replace(checkstr,L"void",L"");
	}
	else if ( checkstr.find(L"all") != yaya::string_t::npos ) {
		outtype = CHOICETYPE_ALL_FLAG;
		yaya::ws_replace(checkstr,L"all",L"");
	}
	else if ( checkstr.find(L"last") != yaya::string_t::npos ) {
		outtype = CHOICETYPE_LAST_FLAG;
		yaya::ws_replace(checkstr,L"last",L"");
	}

	unsigned int choicetype = 0;

	if (! (outtype & CHOICETYPE_SPECOUT_FILTER) ) {
		choicetype = CHOICETYPE_RANDOM_FLAG;

		if ( checkstr.find(L"sequential") != yaya::string_t::npos ) {
			choicetype = CHOICETYPE_SEQUENTIAL_FLAG;
			yaya::ws_replace(checkstr,L"sequential",L"");
		}
		else if ( checkstr.find(L"array") != yaya::string_t::npos ) {
			choicetype = CHOICETYPE_ARRAY_FLAG;
			yaya::ws_replace(checkstr,L"array",L"");
		}
		else if ( checkstr.find(L"nonoverlap") != yaya::string_t::npos ) {
			choicetype = CHOICETYPE_NONOVERLAP_FLAG;
			yaya::ws_replace(checkstr,L"nonoverlap",L"");
		}
		else {
			yaya::ws_replace(checkstr,L"random",L"");
		}
	}

	yaya::ws_replace(checkstr,L"_",L"");

	if ( checkstr.size() > 0 ) {
		//�Ȃɂ��]���Ȃ��̂���������
		vm.logger().Error(E_E, 30, ctypestr, dicfilename, linecount);
	}

	return static_cast<choicetype_t>(outtype | choicetype);
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CSelecter::ChoiceTypeToString
 *  �@�\�T�v�F  choicetype_t->������
 * -----------------------------------------------------------------------
 */
yaya::string_t CSelecter::ChoiceTypeToString(choicetype_t ctype)
{
	yaya::string_t aret;

	switch (ctype & CHOICETYPE_OUTPUT_FILTER)
	{
	case CHOICETYPE_POOL_FLAG:
		break;
	case CHOICETYPE_MELT_FLAG:
		aret += L"melt";
		break;
	case CHOICETYPE_VOID_FLAG:
		return L"void";
	case CHOICETYPE_ALL_FLAG:
		return L"all";
	case CHOICETYPE_LAST_FLAG:
		return L"last";
	case CHOICETYPE_PICKONE_FLAG:
		break;
	default:
		return L"unknown";
	}

	aret += L'_';

	switch (ctype & CHOICETYPE_SELECT_FILTER)
	{
	case CHOICETYPE_SEQUENTIAL_FLAG:
		aret += L"sequential";
		break;
	case CHOICETYPE_ARRAY_FLAG:
		aret += L"array";
		break;
	case CHOICETYPE_NONOVERLAP_FLAG:
		aret += L"nonoverlap";
		break;
	case CHOICETYPE_RANDOM_FLAG:
		aret += L"random";
		break;
	default:
		return L"unknown";
	}

	aret += L'_';

	switch (ctype & CHOICETYPE_OUTPUT_FILTER)
	{
	case CHOICETYPE_POOL_FLAG:
		aret += L"pool";
		break;
	}

	size_t beg = aret.find_first_not_of(L'_');
	size_t end = aret.find_last_not_of(L'_');
	size_t siz = end - beg + 1;
	aret = aret.substr(beg, siz);

	return aret;
}

