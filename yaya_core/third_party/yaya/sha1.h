/*
 *  sha1.h
 */

#ifndef _SHA1_H_
#define _SHA1_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _SHA_enum_
#define _SHA_enum_
enum
{
    shaSuccess = 0,
    shaNull,            /* Null pointer parameter */
    shaInputTooLong,    /* input data too long */
    shaStateError       /* called Input after Result */
};
#endif
#define SHA1HashSize 20

typedef struct SHA1Context
{
    uint32_t Intermediate_Hash[SHA1HashSize/4];
    uint32_t Length_Low;
    uint32_t Length_High;
    int_least16_t Message_Block_Index;
    uint8_t Message_Block[64];
    int Computed;
    int Corrupted;
} SHA1Context;

int SHA1Reset(  SHA1Context *);
int SHA1Input(  SHA1Context *, const uint8_t *, unsigned int);
int SHA1Result( SHA1Context *, uint8_t Message_Digest[SHA1HashSize]);

#ifdef __cplusplus
}
#endif

#endif

