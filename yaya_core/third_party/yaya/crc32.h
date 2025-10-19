#ifndef CRC32_INCLUDED
#define CRC32_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif
unsigned long update_crc32(const unsigned char *buf,unsigned int len,unsigned long crc);
#ifdef __cplusplus
}
#endif

#endif //CRC32_INCLUDED

