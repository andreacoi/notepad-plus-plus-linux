# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A native macOS port of Notepad++ (the Windows text editor), built with C++17 and Objective-C++ (Cocoa). It wraps the vendored Scintilla editing engine and Lexilla syntax-highlighting library in a full Cocoa UI. Despite the repo name, this targets **macOS 11+** (Universal Binary: arm64 + x86_64), not Linux.

### Linux port (active development)

There is an **in-progress native GTK3 Linux port** living entirely in `linux/`. It is written in C11 with a thin C++ wrapper for Lexilla. It is a separate CMake project and does not share build infrastructure with the macOS app.

**Build the Linux port:**
```sh
cd linux
cmake -B build && cmake --build build
./build/notepad++
```

**Linux port source files (`linux/src/`):**

| File | Purpose |
|------|---------|
| `main.c` | GTK application entry point, menu bar, window setup |
| `editor.c/h` | Tab notebook, document open/save/close, `NppDoc` struct |
| `statusbar.c/h` | Bottom status bar (line, col, encoding, EOL, language) |
| `toolbar.c/h` | GTK3 toolbar with Fluent icon set |
| `findreplace.c/h` | Find/Replace dialog |
| `lexer.cpp/h` | Lexilla integration: extension→language→lexer maps, keyword lists, fold props |
| `stylestore.c/h` | Parses `stylers.model.xml` / user `~/.config/npp/stylers.xml`; applies Scintilla styles |
| `styleeditor.c/h` | Style Configurator dialog (theme picker, per-language style editing) |
| `sci_c.h` | C-safe Scintilla constants and `SCNotification` layout |

**User config location (Linux port):** `~/.config/npp/`
- `stylers.xml` — user style overrides (saved by Style Configurator)
- `themes/` — user theme XML files (scanned alongside bundled `resources/themes/`)

**Key design rules for the Linux port:**
- All UI code is C11; only `lexer.cpp` and `LexUserStub.cxx` are C++
- Scintilla color format is BGR: `r | (g<<8) | (b<<16)`
- Styling call order: `stylestore_apply_default()` → `SCI_STYLECLEARALL` → `stylestore_apply_global()` → install lexer → `stylestore_apply_lexer(sci, lang_name)` (pass `lang_name`, NOT the Lexilla lexer name)
- `stylestore_apply_lexer` must receive the XML `LexerType name` (e.g. `"php"`), not the Lexilla internal name (e.g. `"phpscript"`)
- System monospace font is auto-detected via GSettings on first run, replacing "Courier New"

## Build

Requires CMake 3.20+ and Xcode toolchain.

```sh
cmake -B build && cmake --build build
```

Output: `build/Notepad++.app` — a self-contained app bundle. Post-build steps copy XML resources, bundle localizations, and ad-hoc-sign the binary. No install step is needed; open the `.app` directly.

## Tests

No automated tests exist for the main application. Two test harnesses are available:

**Plugin load test** — verifies `.dylib` plugins export the required symbols:
```sh
cmake -S test_plugins -B test_plugins/build && cmake --build test_plugins/build
./test_plugins/build/test_plugins [optional_plugins_dir]
```

**Lexilla unit tests** (C++, makefile-based):
```sh
cd lexilla/test/unit && make
```

**Scintilla tests** (Python, in `scintilla/test/`):
```sh
cd scintilla/test && python3 simpleTests.py
```

## Architecture

### Layer overview

```
User code
  └── Scintilla (vendored, cocoa-specific branch in scintilla/cocoa/)
        └── Lexilla (vendored, ~80 language lexers in lexilla/lexers/)

macOS UI (src/*.mm / src/*.h)
  ├── AppDelegate            – app lifecycle, file open/reopen
  ├── main.mm                – CLI parsing (--help, -n<line>, -lLanguage, etc.)
  ├── MainWindowController   – central window, split view, session management (391 KB)
  ├── EditorView             – Scintilla wrapper + Notepad++ feature layer (264 KB)
  ├── TabManager / NppTabBar – tabbed editing, tab bar rendering
  ├── MenuBuilder            – dynamic menu generation from XML configs
  ├── FindWindow             – search / replace panel
  ├── NppPluginManager       – .dylib plugin loading via dlopen/dlsym
  └── ... (panels, dialogs, helpers — see src/)
```

### Key design points

- **ScintillaView** (from Cocoa Scintilla) is embedded inside **EditorView**, which adds Notepad++ semantics (language detection, fold margin, auto-complete, etc.).
- **MainWindowController** owns both editor panes for the split-view mode and coordinates everything else. It is the largest single file in the repo.
- All persistent user config lives in `~/.notepad++/` at runtime; the app bundle ships defaults under `resources/`.
- XML drives most customisation: `shortcuts.xml`, `contextMenu.xml`, `toolbarButtonsConf.xml`, `langs.model.xml`, `stylers.model.xml`, themes.
- Localisation uses the Windows Notepad++ XML format (137 languages in `resources/localization/`), loaded by **NppLocalizer**.

### Plugin system

Plugins are macOS `.dylib` files placed in `~/.notepad++/plugins/<Name>/<Name>.dylib`. They must export five C symbols: `getName`, `getFuncsArray`, `beNotified`, `messageProc`, and `isUnicode`. Communication happens through NPPM messages passed to Scintilla handles.

### Vendored dependencies

| Directory | Purpose |
|-----------|---------|
| `scintilla/` | Editing engine (do not modify public API surface) |
| `lexilla/` | Syntax lexers; add language support here |

Changes to vendored code should be minimal and clearly marked so they survive upstream merges.

---

## Linux port — next steps (priority order)

### 1. Convert `lexer.cpp` to C
`lexer.cpp` is the only application-level file written in C++ (needed solely for the `CreateLexer()` call from Lexilla's C++ API). Convert it to `lexer.c` by isolating the C++ call in a minimal one-function wrapper:

- Create `linux/src/lexer_create.cpp` (or keep a renamed `lexilla_bridge.cpp`) with a single `extern "C"` function:
  ```c
  /* lexilla_bridge.cpp */
  #include "ILexer.h"
  #include "Lexilla.h"
  extern "C" void *lexer_create(const char *name) {
      return (void *)CreateLexer(name);
  }
  ```
- Rename `lexer.cpp` → `lexer.c`, replace the `CreateLexer()` call with the bridge function, and cast the `void *` result to `sptr_t` for `SCI_SETILEXER`
- Update `CMakeLists.txt`: add `lexilla_bridge.cpp`, change `lexer.cpp` → `lexer.c`
- Remove the `set_source_files_properties` workaround for `lexer.cpp` (it was only needed because of C++ headers); `lexilla_bridge.cpp` still needs `-include cstdint`

### 2. Language selection menu
Add a **Language** top-level menu to `main.c` that lets the user manually override the detected language for the current tab. Each entry calls `lexer_apply(sci, lang_name)`.

- Group entries by category (C-family, Web, Scripting, …) matching the `kExtLang` / `kLangLexer` tables in `lexer.cpp`
- The active language should be checkmarked (radio-style); switching clears the old check
- "Normal Text" entry at the top sets language to NULL (plain text, no lexer)
- Callback: `lexer_apply(editor_current_doc()->sci, lang)` then `statusbar_set_language(lang)`

### 2. i18n / localisation
Port `NppLocalizer` from the macOS version. The `resources/localization/` directory already contains 137 XML files in the Windows Notepad++ format.

- Create `linux/src/i18n.c/h`
- `i18n_init(locale)` — detect system locale, load matching XML from `resources/localization/`, fall back to `english.xml`
- `i18n_str(key)` — look up a translation string by the `name` attribute of `<Item>` elements
- Wire into menu labels, dialog button text, statusbar, and dialog titles
- Locale detection: `g_get_language_names()` → try each prefix (e.g. `"it_IT"` → `"it"`) against filenames
- XML format: `<NotepadPlus><Native-Langue ...><Menu>...<Item menuId="..." name="..."/>` — parse with GMarkupParser (same approach as `stylestore.c`)
