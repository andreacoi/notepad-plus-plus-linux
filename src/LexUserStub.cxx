// Stub for LexUser (User Defined Language) which requires windows.h.
// On macOS we provide a no-op placeholder so Lexilla.cxx links successfully.
// UDL support will be implemented natively in a later phase.
#include <cstdint>
#include "ILexer.h"
#include "LexerModule.h"
#include "DefaultLexer.h"

using namespace Lexilla;
using namespace Scintilla;

namespace {

class LexerNull final : public DefaultLexer {
public:
    explicit LexerNull() : DefaultLexer("user", 1) {}
    void SCI_METHOD Lex(Sci_PositionU, Sci_Position, int, IDocument *) override {}
    void SCI_METHOD Fold(Sci_PositionU, Sci_Position, int, IDocument *) override {}
    static ILexer5 *LexerFactory() { return new LexerNull(); }
};

} // namespace

LexerModule lmUserDefine(1, LexerNull::LexerFactory, "user", nullptr);
