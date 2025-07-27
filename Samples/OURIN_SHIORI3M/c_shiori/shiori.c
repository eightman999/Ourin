#include "shiori.h"
#include <string.h>
#include <stdlib.h>

bool shiori_load(const char* dir_utf8){ (void)dir_utf8; return true; }
void shiori_unload(void){}

static unsigned char* duputf8(const char* s, size_t* out){
  size_t n=strlen(s);
  unsigned char* p=(unsigned char*)malloc(n);
  if(!p) return NULL;
  memcpy(p,s,n); *out=n; return p;
}

bool shiori_request(const unsigned char* req, size_t len,
                    unsigned char** res, size_t* res_len){
  (void)len; (void)req;
  const char* ok =
    "SHIORI/3.0 200 OK\r\n"
    "Charset: UTF-8\r\n"
    "Value: \\h\\s0Hello from 3.0M\r\n"
    "\r\n";
  *res = duputf8(ok, res_len);
  return *res != NULL;
}

void shiori_free(unsigned char* p){ free(p); }
