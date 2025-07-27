
#include "ico_cur.h"
#include <string.h>
#include <stdlib.h>
#pragma pack(push,1)
typedef struct { uint16_t reserved, type, count; } ICONDIR;
typedef struct {
    uint8_t  width, height, colorCount, reserved;
    uint16_t planes_or_hotspotX, bpp_or_hotspotY;
    uint32_t bytesInRes, imageOffset;
} ICONDIRENTRY;
typedef struct {
    uint32_t biSize; int32_t biWidth, biHeight; uint16_t biPlanes, biBitCount;
    uint32_t biCompression, biSizeImage; int32_t biXPelsPerMeter, biYPelsPerMeter;
    uint32_t biClrUsed, biClrImportant;
} BITMAPINFOHEADER;
#pragma pack(pop)

static int has_png(const uint8_t* p, size_t n){
    static const unsigned char sig[8]={0x89,'P','N','G',0x0D,0x0A,0x1A,0x0A};
    return n>=8 && memcmp(p,sig,8)==0;
}
static bool decode32(const uint8_t* dib, size_t n, OurinIcoCurImage* out){
    if(n<40) return false;
    const BITMAPINFOHEADER* bih=(const BITMAPINFOHEADER*)dib;
    if(bih->biSize<40 || bih->biCompression!=0 || bih->biBitCount!=32) return false;
    int w=bih->biWidth, h=bih->biHeight/2; if(w<=0||h<=0) return false;
    size_t row=(size_t)w*4, xors=row*h;
    if(n < bih->biSize + xors) return false;
    const uint8_t* xorbase=dib+bih->biSize;
    size_t androw=((size_t)w+31)/32*4, andsize=androw*h;
    if(n < bih->biSize + xors + andsize) return false;
    const uint8_t* andbase=xorbase+xors;
    uint8_t* rgba=(uint8_t*)malloc(xors); if(!rgba) return false;
    int hasA=0;
    for(int y=0;y<h;y++){
        const uint8_t* s=xorbase+(h-1-y)*row; uint8_t* d=rgba+y*row;
        for(int x=0;x<w;x++){ uint8_t b=s[x*4+0],g=s[x*4+1],r=s[x*4+2],a=s[x*4+3];
            d[x*4+0]=r; d[x*4+1]=g; d[x*4+2]=b; d[x*4+3]=a; if(a) hasA=1; }
    }
    if(!hasA){
        for(int y=0;y<h;y++){
            const uint8_t* m=andbase+(h-1-y)*androw; uint8_t* d=rgba+y*row;
            for(int x=0;x<w;x++){ int bit=7-(x&7); if((m[x>>3]>>bit)&1) d[x*4+3]=0; }
        }
    }
    out->width=w; out->height=h; out->rgba=rgba; out->png_data=NULL; out->png_size=0; return true;
}
bool ourin_icocur_parse_best(const uint8_t* data, size_t size, OurinIcoCurImage* img){
    if(!data||!img||size<6) return false; memset(img,0,sizeof(*img));
    const ICONDIR* dir=(const ICONDIR*)data;
    if(dir->reserved!=0 || (dir->type!=1 && dir->type!=2) || dir->count==0) return false;
    img->is_cursor=(dir->type==2);
    size_t best=0; int bestScore=-1;
    for(uint16_t i=0;i<dir->count;i++){
        size_t off=6+(size_t)i*sizeof(ICONDIRENTRY); if(size<off+sizeof(ICONDIRENTRY)) return false;
        const ICONDIRENTRY* e=(const ICONDIRENTRY*)(data+off);
        if(e->imageOffset>size || e->bytesInRes>size-e->imageOffset) continue;
        int w=(e->width==0)?256:e->width, h=(e->height==0)?256:e->height;
        int bpp=img->is_cursor?32:e->bpp_or_hotspotY;
        int score=(has_png(data+e->imageOffset,e->bytesInRes)?1000000:0)+w*h*bpp;
        if(score>bestScore){bestScore=score; best=i;}
    }
    const ICONDIRENTRY* be=(const ICONDIRENTRY*)(data+6+best*sizeof(ICONDIRENTRY));
    if(img->is_cursor){ img->hotspot_x=be->planes_or_hotspotX; img->hotspot_y=be->bpp_or_hotspotY; }
    const uint8_t* payload=data+be->imageOffset; size_t plen=be->bytesInRes;
    if(has_png(payload,plen)){ img->png_data=payload; img->png_size=plen;
        img->width=(be->width==0)?256:be->width; img->height=(be->height==0)?256:be->height; return true; }
    return decode32(payload,plen,img);
}
