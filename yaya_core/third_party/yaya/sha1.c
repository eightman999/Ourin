/* Minimal SHA-1 implementation wrapper (original from yaya-shiori-500) */

#include "sha1.h"

#define SHA1CircularShift(bits,word) \
                (((word) << (bits)) | ((word) >> (32-(bits))))

static void SHA1PadMessage(struct SHA1Context *);
static void SHA1ProcessMessageBlock(struct SHA1Context *);

int SHA1Reset(struct SHA1Context *context)
{
    if (!context) return shaNull;
    context->Length_Low = 0;
    context->Length_High = 0;
    context->Message_Block_Index = 0;
    context->Intermediate_Hash[0] = 0x67452301;
    context->Intermediate_Hash[1] = 0xEFCDAB89;
    context->Intermediate_Hash[2] = 0x98BADCFE;
    context->Intermediate_Hash[3] = 0x10325476;
    context->Intermediate_Hash[4] = 0xC3D2E1F0;
    context->Computed = 0;
    context->Corrupted = 0;
    return shaSuccess;
}

int SHA1Result(struct SHA1Context *context, uint8_t Message_Digest[SHA1HashSize])
{
    int i;
    if (!context || !Message_Digest) return shaNull;
    if (context->Corrupted) return context->Corrupted;
    if (!context->Computed) {
        SHA1PadMessage(context);
        for (i=0; i<64; ++i) context->Message_Block[i] = 0;
        context->Length_Low = 0;
        context->Length_High = 0;
        context->Computed = 1;
    }
    for (i=0; i<SHA1HashSize; ++i) {
        Message_Digest[i] = (uint8_t)(context->Intermediate_Hash[i>>2] >> 8 * ( 3 - ( i & 0x03 ) ));
    }
    return shaSuccess;
}

int SHA1Input(struct SHA1Context *context, const uint8_t *message_array, unsigned length)
{
    if (!length) return shaSuccess;
    if (!context || !message_array) return shaNull;
    if (context->Computed) { context->Corrupted = shaStateError; return shaStateError; }
    if (context->Corrupted) return context->Corrupted;
    while (length-- && !context->Corrupted)
    {
        context->Message_Block[context->Message_Block_Index++] = (*message_array & 0xFF);
        context->Length_Low += 8;
        if (context->Length_Low == 0) {
            context->Length_High++;
            if (context->Length_High == 0) context->Corrupted = 1;
        }
        if (context->Message_Block_Index == 64) SHA1ProcessMessageBlock(context);
        message_array++;
    }
    return shaSuccess;
}

static void SHA1ProcessMessageBlock(struct SHA1Context *context)
{
    const uint32_t K[] = { 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xCA62C1D6 };
    int t;
    uint32_t temp;
    uint32_t W[80];
    uint32_t A, B, C, D, E;
    for (t=0; t<16; t++) {
        W[t] = context->Message_Block[t * 4] << 24;
        W[t] |= context->Message_Block[t * 4 + 1] << 16;
        W[t] |= context->Message_Block[t * 4 + 2] << 8;
        W[t] |= context->Message_Block[t * 4 + 3];
    }
    for (t=16; t<80; t++) W[t] = SHA1CircularShift(1,W[t-3] ^ W[t-8] ^ W[t-14] ^ W[t-16]);
    A = context->Intermediate_Hash[0];
    B = context->Intermediate_Hash[1];
    C = context->Intermediate_Hash[2];
    D = context->Intermediate_Hash[3];
    E = context->Intermediate_Hash[4];
    for (t=0; t<20; t++) {
        temp = SHA1CircularShift(5,A) + ((B & C) | ((~B) & D)) + E + W[t] + K[0];
        E = D; D = C; C = SHA1CircularShift(30,B); B = A; A = temp;
    }
    for (t=20; t<40; t++) {
        temp = SHA1CircularShift(5,A) + (B ^ C ^ D) + E + W[t] + K[1];
        E = D; D = C; C = SHA1CircularShift(30,B); B = A; A = temp;
    }
    for (t=40; t<60; t++) {
        temp = SHA1CircularShift(5,A) + ((B & C) | (B & D) | (C & D)) + E + W[t] + K[2];
        E = D; D = C; C = SHA1CircularShift(30,B); B = A; A = temp;
    }
    for (t=60; t<80; t++) {
        temp = SHA1CircularShift(5,A) + (B ^ C ^ D) + E + W[t] + K[3];
        E = D; D = C; C = SHA1CircularShift(30,B); B = A; A = temp;
    }
    context->Intermediate_Hash[0] += A;
    context->Intermediate_Hash[1] += B;
    context->Intermediate_Hash[2] += C;
    context->Intermediate_Hash[3] += D;
    context->Intermediate_Hash[4] += E;
    context->Message_Block_Index = 0;
}

static void SHA1PadMessage(struct SHA1Context *context)
{
    if (context->Message_Block_Index > 55) {
        context->Message_Block[context->Message_Block_Index++] = 0x80;
        while (context->Message_Block_Index < 64) context->Message_Block[context->Message_Block_Index++] = 0;
        SHA1ProcessMessageBlock(context);
        while (context->Message_Block_Index < 56) context->Message_Block[context->Message_Block_Index++] = 0;
    } else {
        context->Message_Block[context->Message_Block_Index++] = 0x80;
        while (context->Message_Block_Index < 56) context->Message_Block[context->Message_Block_Index++] = 0;
    }
    context->Message_Block[56] = (uint8_t)(context->Length_High >> 24);
    context->Message_Block[57] = (uint8_t)(context->Length_High >> 16);
    context->Message_Block[58] = (uint8_t)(context->Length_High >> 8);
    context->Message_Block[59] = (uint8_t)(context->Length_High);
    context->Message_Block[60] = (uint8_t)(context->Length_Low >> 24);
    context->Message_Block[61] = (uint8_t)(context->Length_Low >> 16);
    context->Message_Block[62] = (uint8_t)(context->Length_Low >> 8);
    context->Message_Block[63] = (uint8_t)(context->Length_Low);
    SHA1ProcessMessageBlock(context);
}

