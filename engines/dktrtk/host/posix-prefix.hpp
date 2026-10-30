#pragma once
#include <angelscript.h>
#include <string>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include "add_on/scriptstdstring/scriptstdstring.h"
#include "add_on/scriptarray/scriptarray.h"
#include "add_on/scriptany/scriptany.h"
#include "add_on/scripthandle/scripthandle.h"
#include "add_on/weakref/weakref.h"
#include "add_on/scriptdictionary/scriptdictionary.h"
#include "add_on/scriptfile/scriptfile.h"
#include "add_on/scriptfile/scriptfilesystem.h"
#include "add_on/scriptmath/scriptmath.h"
#include "add_on/scriptmath/scriptmathcomplex.h"
#include "add_on/scriptgrid/scriptgrid.h"
#include "add_on/scriptbuilder/scriptbuilder.h"
using namespace std;
using BOOL=bool;
using HGLOBAL=void*;
#define __cdecl
#define GMEM_FIXED 0
#define GlobalFree free
inline void* GlobalAlloc(int, size_t n) { return malloc(n); }
int CompileScript(asIScriptEngine*);
inline void Diagnostic(const asSMessageInfo *message, void*) { fprintf(stderr, "%s:%d:%d: %s\n", message->section, message->row, message->col, message->message); }
asIScriptEngine* engine=nullptr;
asIScriptContext* ctx=nullptr;
