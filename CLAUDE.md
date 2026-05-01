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
| `lexer.c/h` | Lexilla integration: extension→language→lexer maps, keyword lists, fold props |
| `lexilla_bridge.cpp` | Minimal C++ bridge: `lexilla_create_lexer()` wraps `CreateLexer()` for use from C |
| `i18n.c/h` | Locale detection, NPP XML parser, `T()`/`TM()` macros for translated strings |
| `stylestore.c/h` | Parses `stylers.model.xml` / user `~/.config/npp/stylers.xml`; applies Scintilla styles |
| `styleeditor.c/h` | Style Configurator dialog (theme picker, per-language style editing) |
| `sci_c.h` | C-safe Scintilla constants and `SCNotification` layout |

**User config location (Linux port):** `~/.config/npp/`
- `stylers.xml` — user style overrides (saved by Style Configurator)
- `themes/` — user theme XML files (scanned alongside bundled `resources/themes/`)

**Key design rules for the Linux port:**
- All UI code is C11; only `lexilla_bridge.cpp` and `LexUserStub.cxx` are C++
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

## Linux port — next steps (priority / effort order)

### Low effort

1. **Language selection menu** — top-level Language menu in `main.c`. Groups by category matching `kLangLexer` in `lexer.c`. Radio checkmarks; "Normal Text" at top. Callback: `lexer_apply(sci, lang)` + `statusbar_set_language(lang)`. Update checkmark on tab switch via `on_switch_page`.
2. **Overwrite (INS) mode** — `SCI_SETOVERTYPE` toggle; add OVR indicator to statusbar.
3. **EOL type selection** — menu items calling `SCI_SETEOLMODE`; update statusbar EOL cell.
4. **Show/hide symbols** — menu toggles for `SCI_SETVIEWWS`, `SCI_SETVIEWEOL`, `SCI_SETMARGINWIDTHN` (line numbers, fold, bookmarks).
5. **Edge column** — `SCI_SETEDGEMODE` / `SCI_SETEDGECOLUMN` wired to a preference value.
6. **Insert date/time** — `g_date_time_format()` → `SCI_REPLACESEL`.
7. **Duplicate / Delete / Move line** — `SCI_LINEDUPLICATE`, `SCI_LINEDELETE`, `SCI_MOVESELECTEDLINESUP/DOWN`.
8. **Join / Split lines** — iterate selection lines via `SCI_GETTEXTRANGE`, reassemble.
9. **Insert blank line above/below** — `SCI_HOME` + `SCI_NEWLINE` sequence.
10. **Trim whitespace** — regex replace or line-by-line strip via Scintilla API.
11. **Hash tools** — link `libssl` or use GLib's `g_checksum_new()`; operate on selection or whole doc.
12. **Base64 / Hex tools** — `g_base64_encode/decode()` and a nibble-loop for hex; replace selection.

### Medium effort

13. **Case conversion** — `SCI_UPPERCASE`/`SCI_LOWERCASE` for basic; custom loops for Proper/Sentence/Random.
14. **Comment / Uncomment** — per-language delimiter table (reuse `kLangLexer`); detect and toggle via `SCI_GETLINE`/`SCI_REPLACELINE`.
15. **Whitespace / EOL conversions** — `SCI_SETTARGETWHOLEDOCUMENT` + `SCI_REPLACETARGET` loops.
16. **Remove duplicate/blank lines** — collect lines into array, filter, replace whole doc.
17. **Sort lines** — same collect/sort/replace pattern; multiple comparators.
18. **Word wrap toggle** — `SCI_SETWRAPMODE(SC_WRAP_WORD/SC_WRAP_NONE)`; persist per-tab.
19. **Bookmarks** — `SCI_MARKERADD`/`SCI_MARKERNEXT`/`SCI_MARKERPREV` with marker number 1; menu items + margin click.
20. **Mark styles** — 5 indicator slots (`SCI_INDICSETSTYLE`, `SCI_INDICATORFILLRANGE`); menu to apply/clear/jump.
21. **Go to matching brace** — `SCI_BRACEMATCH`; move caret or flash highlight.
22. **Recent files list** — maintain a `GList` of last N paths in config; rebuild submenu on open/close.
23. **Encoding selection** — per-tab encoding stored in `NppDoc`; recode buffer on switch via `g_convert()`; update statusbar.
24. **Keyboard shortcut mapper** — dialog listing `GtkAccelGroup` entries; serialize to `shortcuts.xml`.
25. **Preferences dialog** — GtkDialog with sections (editor, appearance, file, …); persist to `~/.config/npp/config.xml`.
26. **Auto-indent** — `SCN_CHARADDED` handler: copy leading whitespace of previous line; advanced: detect `{` / `:`.
27. **Code folding controls** — menu items calling `SCI_FOLDALL`, `SCI_FOLDDISPLAYTEXT`, `SCI_SETFOLDLEVEL` per level.

### High effort

28. **Find in Files** — extra tab in the Find/Replace dialog; `GThreadPool` recursive file walk; results in a collapsible `GtkTreeView`.
29. **Column / block selection** — `SCI_SETSELECTIONMODE(SC_SEL_RECTANGLE)`; column editor dialog for insert/fill.
30. **Multi-select** — `SCI_ADDSELECTION`, `SCI_MULTIPLESELECTADDNEXT`, `SCI_MULTIPLESELECTADDEACH`.
31. **Auto-completion** — `SCI_AUTOCSHOW` from word list built per language; `SCI_CALLTIPSHOW` for param hints.
32. **User-defined languages (UDL)** — parse `~/.config/npp/userDefineLangs/*.xml`; build a runtime `ILexer5` equivalent or use Lexilla's `LexerModule` API.
33. **Change history / git gutter** — run `git diff` in background; parse unified diff; set `SCI_MARKERDEFINE` symbols in margin.
34. **Session save / restore** — serialize open file paths + scroll/caret positions to `~/.config/npp/session.xml`; restore on launch.
35. **Auto-backup** — `g_timeout_add_seconds()` writes current doc to `~/.config/npp/backup/<name>~`; clean on clean save.
36. **File change detection** — `GFileMonitor` on each open path; prompt reload on `G_FILE_MONITOR_EVENT_CHANGED`.
37. **Macro recording / playback** — hook `SCN_MACRORECORD`; store `(msg, wParam, lParam)` triples; replay with `SCI_SENDMESSAGE`.
38. **Document List panel** — dockable `GtkListBox` synced to notebook pages; click to switch tab.
39. **Folder as Workspace panel** — dockable `GtkTreeView` backed by `GFileEnumerator`; double-click opens file.
40. **Function List panel** — dockable `GtkTreeView`; parse current file with a per-language regex or ctags; update on `SCN_MODIFIED`.
41. **Document Map** — secondary `ScintillaWidget` in read-only mode tracking the main one; scale via `SCI_SETZOOM`.
42. **Search Results panel** — dockable `GtkTreeView` accumulating Find-in-Files hits; click to navigate.
43. **Spell checker** — integrate `enchant-2` library; walk words with `SCI_WORDSTARTPOSITION`/`SCI_WORDENDPOSITION`; mark with indicator.
44. **Plugin system** — `dlopen`/`dlsym` loader for `.so` plugins exporting the five NPP symbols; `NPPM_*` message routing; auto-generated plugin menu.
