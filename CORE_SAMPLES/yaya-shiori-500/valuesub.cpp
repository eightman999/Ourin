// 
// AYA version 5
//
// �z��ɐς܂�Ă���l�������N���X�@CValueSub
// written by umeici. 2004
// 

#if defined(WIN32) || defined(_WIN32_WCE)
# include "stdafx.h"
#endif

#include <math.h>

#include "globaldef.h"
#include "value.h"
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
 *  �֐���  �F  CValueSub::CValueSub
 *  �@�\�T�v�F  CValue����CValueSub���\�z���܂�
 * -----------------------------------------------------------------------
 */
CValueSub::CValueSub(const CValue &v)
{
	switch(v.type) {
	case F_TAG_INT:
		i_value = v.i_value;
		d_value = 0;
		s_value.erase();
		type = v.type;
		return;
	case F_TAG_DOUBLE:
		i_value = 0;
		d_value = v.d_value;
		s_value.erase();
		type = v.type;
		return;
	case F_TAG_STRING:
		i_value = 0;
		d_value = 0;
		s_value = v.s_value;
		type = v.type;
		return;
	default:
		i_value = 0;
		d_value = 0;
		s_value.erase();
		type = F_TAG_VOID;
		return;
	}
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CValueSub::GetValueInt
 *  �@�\�T�v�F  �l��int�Ŏ擾���܂�
 *
 *  �Ԓl�@�@�F  0/1/2=�G���[����/�擾�ł���/�擾�ł���(�^���ǂݑւ���ꂽ)
 * -----------------------------------------------------------------------
 */
yaya::int_t	CValueSub::GetValueInt(void) const
{
	switch(type) {
	case F_TAG_INT:
		return i_value;
	case F_TAG_DOUBLE:
		{
			if ( d_value > static_cast<double>(LLONG_MAX) ) {
				return LLONG_MAX;
			}
			else if ( d_value < static_cast<double>(LLONG_MIN) ) {
				return LLONG_MIN;
			}
			else {
				return (yaya::int_t)d_value;
			}
		}
	case F_TAG_STRING:
		return yaya::ws_atoll(s_value, 10);
	default:
		return 0;
	};
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CValueSub::GetValueDouble
 *  �@�\�T�v�F  �l��double�Ŏ擾���܂�
 *
 *  �Ԓl�@�@�F  0/1/2=�G���[����/�擾�ł���/�擾�ł���(�^���ǂݑւ���ꂽ)
 * -----------------------------------------------------------------------
 */
double	CValueSub::GetValueDouble(void) const
{
	switch(type) {
	case F_TAG_INT:
		return (double)i_value;
	case F_TAG_DOUBLE:
		return d_value;
	case F_TAG_STRING:
		return yaya::ws_atof(s_value);
	default:
		return 0.0;
	};
}

/* -----------------------------------------------------------------------
 *  �֐���  �F  CValueSub::GetValue
 *  �@�\�T�v�F  �l��yaya::string_t�ŕԂ��܂�
 * -----------------------------------------------------------------------
 */
yaya::string_t	CValueSub::GetValueString(void) const
{
	switch(type) {
	case F_TAG_INT: {
			return yaya::ws_lltoa(i_value);
		}
	case F_TAG_DOUBLE: {
			return yaya::ws_ftoa(d_value);
		}
	case F_TAG_STRING:
		return s_value;
	default:
		return yaya::string_t();
	};
}

/* -----------------------------------------------------------------------
 *  operator = (int)
 * -----------------------------------------------------------------------
 */
CValueSub &CValueSub::operator =(yaya::int_t value) LVALUE_MODIFIER
{
	type	= F_TAG_INT;
	i_value	= value;
	s_value.erase();

	return *this;
}

/* -----------------------------------------------------------------------
 *  operator = (double)
 * -----------------------------------------------------------------------
 */
CValueSub &CValueSub::operator =(double value) LVALUE_MODIFIER
{
	type	= F_TAG_DOUBLE;
	d_value	= value;
	s_value.erase();

	return *this;
}

/* -----------------------------------------------------------------------
 *  operator = (yaya::string_t)
 * -----------------------------------------------------------------------
 */
CValueSub &CValueSub::operator =(const yaya::string_t &value) LVALUE_MODIFIER
{
	type	= F_TAG_STRING;
	s_value = value;

	return *this;
}

#if CPP_STD_VER > 2011
CValueSub &CValueSub::operator =(yaya::string_t&& value) LVALUE_MODIFIER
{
	type	= F_TAG_STRING;
	std::swap(s_value,value);

	return *this;
}
#endif

/* -----------------------------------------------------------------------
 *  operator = (yaya::char_t*)
 * -----------------------------------------------------------------------
 */
CValueSub &CValueSub::operator =(const yaya::char_t *value) LVALUE_MODIFIER
{
	type	= F_TAG_STRING;
	s_value	= value;

	return *this;
}

/* -----------------------------------------------------------------------
 *  operator = (CValue)
 * -----------------------------------------------------------------------
 */
CValueSub &CValueSub::operator =(const CValue &v) LVALUE_MODIFIER
{
	switch(v.type) {
	case F_TAG_INT:
		i_value = v.i_value;
		s_value.erase();
		type = v.type;
		return *this;
	case F_TAG_DOUBLE:
		d_value = v.d_value;
		s_value.erase();
		type = v.type;
		return *this;
	case F_TAG_STRING:
		s_value = v.s_value;
		type = v.type;
		return *this;
	default:
		type = F_TAG_VOID;
		s_value.erase();
		return *this;
	}
}


/* -----------------------------------------------------------------------
 *  CalcEscalationTypeNum
 *
 *  �^�̏��i���[���������܂��i���l�D��j
 *  ��{�I��DOUBLE>INT�ł��B
 * -----------------------------------------------------------------------
 */
int CValueSub::CalcEscalationTypeNum(const int rhs) const
{
	int result = type > rhs ? type : rhs;
	if ( result != F_TAG_STRING ) { return result; }

	switch ( type <= rhs ? type : rhs ) {
	case F_TAG_VOID:
	case F_TAG_INT:
		return F_TAG_INT;
	case F_TAG_DOUBLE:
	case F_TAG_STRING:
		return F_TAG_DOUBLE;
	}
	return F_TAG_VOID;
}

/* -----------------------------------------------------------------------
 *  CalcEscalationTypeStr
 *
 *  �^�̏��i���[���������܂��i������D��j
 *  ��{�I��STRING>DOUBLE>INT�ł��B
 * -----------------------------------------------------------------------
 */
int CValueSub::CalcEscalationTypeStr(const int rhs) const
{
	return type > rhs ? type : rhs;
}

/* -----------------------------------------------------------------------
 *  operator + (CValueSub)
 * -----------------------------------------------------------------------
 */
CValueSub CValueSub::operator +(const CValueSub &value) const
{
	int t = CalcEscalationTypeStr(value.type);

	switch(t) {
	case F_TAG_INT:
		return CValueSub(GetValueInt()+value.GetValueInt());
	case F_TAG_DOUBLE:
		return CValueSub(GetValueDouble()+value.GetValueDouble());
	case F_TAG_STRING:
		return CValueSub(GetValueString()+value.GetValueString());
	}

	return CValueSub(value);
}

void CValueSub::operator +=(const CValueSub &value) LVALUE_MODIFIER
{
	int t = CalcEscalationTypeStr(value.type);
	if ( t != type ) {
		*this = operator+(value);
		return;
	}

	switch(t) {
	case F_TAG_INT:
		i_value += value.GetValueInt();
	case F_TAG_DOUBLE:
		d_value += value.GetValueDouble();
	case F_TAG_STRING:
		s_value += value.GetValueString();
	}
	SetType(t);
}

/* -----------------------------------------------------------------------
 *  operator - (CValueSub)
 * -----------------------------------------------------------------------
 */
CValueSub CValueSub::operator -(const CValueSub &value) const
{
	int t = CalcEscalationTypeNum(value.type);

	switch(t) {
	case F_TAG_INT:
		return CValueSub(GetValueInt()-value.GetValueInt());
	case F_TAG_DOUBLE:
		return CValueSub(GetValueDouble()-value.GetValueDouble());
	}

	return CValueSub(value);
}

void CValueSub::operator -=(const CValueSub &value) LVALUE_MODIFIER
{
	*this = operator-(value);
}

/* -----------------------------------------------------------------------
 *  operator * (CValueSub)
 * -----------------------------------------------------------------------
 */
CValueSub CValueSub::operator *(const CValueSub &value) const
{
	int t = CalcEscalationTypeNum(value.type);

	switch(t) {
	case F_TAG_INT:
		return CValueSub(GetValueInt()*value.GetValueInt());
	case F_TAG_DOUBLE:
		return CValueSub(GetValueDouble()*value.GetValueDouble());
	}

	return CValueSub(value);
}

void CValueSub::operator *=(const CValueSub &value) LVALUE_MODIFIER
{
	*this = operator*(value);
}

/* -----------------------------------------------------------------------
 *  operator / (CValueSub)
 * -----------------------------------------------------------------------
 */
CValueSub CValueSub::operator /(const CValueSub &value) const
{
	int t = CalcEscalationTypeNum(value.type);

	switch(t) {
	case F_TAG_INT:
		{
			yaya::int_t denom = value.GetValueInt();
			if ( denom ) {
				return CValueSub(GetValueInt() / denom);
			}
			else {
				return CValueSub(GetValueInt());
			}
		}
	case F_TAG_DOUBLE:
		{
			double denom = value.GetValueDouble();
			if ( denom ) {
				return CValueSub(GetValueDouble() / denom);
			}
			else {
				return CValueSub(GetValueDouble());
			}
		}
	}

	return CValueSub(value);
}

void CValueSub::operator /=(const CValueSub &value) LVALUE_MODIFIER
{
	*this = operator/(value);
}

/* -----------------------------------------------------------------------
 *  operator % (CValueSub)
 * -----------------------------------------------------------------------
 */
CValueSub CValueSub::operator %(const CValueSub &value) const
{
	int t = CalcEscalationTypeNum(value.type);

	switch(t) {
	case F_TAG_INT:
	case F_TAG_DOUBLE:
		{
			yaya::int_t denom = value.GetValueInt();
			if ( denom ) {
				return CValueSub(GetValueInt() % denom);
			}
			else {
				return CValueSub(GetValueInt());
			}
		}
	}

	return CValueSub(value);
}

void CValueSub::operator %=(const CValueSub &value) LVALUE_MODIFIER
{
	*this = operator%(value);
}

/* -----------------------------------------------------------------------
 *  Compare (CValueSub)
 *
 *  operator == �̎��̂ł��B
 *  int��double�̉��Z��double�����ł��Byaya::string_t�Ƃ̉��Z�͋󕶎����Ԃ��܂��B
 * -----------------------------------------------------------------------
 */
bool CValueSub::Compare(const CValueSub &value) const
{
	int t = CalcEscalationTypeStr(value.type);

	if (t == F_TAG_INT) {
		return GetValueInt() == value.GetValueInt();
	}
	else if (t == F_TAG_DOUBLE) {
		return GetValueDouble() == value.GetValueDouble();
	}
	else if (t == F_TAG_STRING) {
		return GetValueString() == value.GetValueString();
	}
	else {
		return 0;
	}
}

bool CValueSub::Less(const CValueSub &value) const
{
	int t = CalcEscalationTypeStr(value.type);

	if (t == F_TAG_INT) {
		return GetValueInt() < value.GetValueInt();
	}
	else if (t == F_TAG_DOUBLE) {
		return GetValueDouble() < value.GetValueDouble();
	}
	else if (t == F_TAG_STRING) {
		return GetValueString() < value.GetValueString();
	}
	return false;
}
