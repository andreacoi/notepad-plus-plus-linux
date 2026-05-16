/* lexilla_bridge.cpp — minimal C++ bridge exposing CreateLexer() to C code. */
#include "ILexer.h"
#include "Lexilla.h"

extern "C" void *lexilla_create_lexer(const char *name)
{
    return (void *)CreateLexer(name);
}
