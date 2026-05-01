# Notepad++ Linux

A native Linux port of [Notepad++ for macOS](https://github.com/notepadplusplus/notepad-plus-plus-mac), built with C and GTK3.

## Why this is possible

The macOS port and this Linux port share a common foundation: both macOS and Linux are UNIX-based systems. This means the underlying OS primitives — file I/O, process model, character encoding, shared library loading — are compatible. The two vendored libraries at the heart of the editor, **Scintilla** (editing engine) and **Lexilla** (syntax highlighting), already ship GTK3 and platform-agnostic backends alongside their Cocoa ones. The Linux port replaces only the UI layer, swapping Cocoa/Objective-C++ for GTK3/C, while leaving the editor core untouched.

## Features

### Editing
- Multi-tab editing with reorderable tabs and close buttons
- File operations: New, Open (multi-file), Save, Save As, Close
- Undo / Redo, Cut / Copy / Paste, Select All
- Go To Line dialog
- Modified-document tracking with ask-to-save on close/quit
- Command-line file arguments

### Syntax Highlighting
- Automatic language detection from file extension
- 70+ languages via Lexilla: C/C++, Python, JavaScript, TypeScript, PHP, HTML, CSS, JSON, XML, SQL, Bash, Ruby, Perl, Lua, Rust, Go, Java, Swift, Markdown, YAML, TOML, CMake, Makefile, Diff, and many more (Smalltalk, Forth, OScript, AVS, Hollywood, PureBasic, FreeBasic, BlitzBasic, KiX, VisualProlog, BaanC, NNCronTab, CSound, EScript, Spice, …)
- Keyword highlighting with per-language keyword sets
- Code folding with fold margin

### Themes & Style Configurator
- **Style Configurator** dialog (Settings → Style Configurator)
  - 20 bundled themes: Monokai, Bespin, Obsidian, Solarized, Twilight, DarkModeDefault, and more
  - User themes from `~/.config/npp/themes/` (place any Notepad++ XML theme file there)
  - Per-language, per-style editing: font family, font size, foreground/background color, bold, italic, underline
  - Live preview of each style
  - Save user overrides to `~/.config/npp/stylers.xml`
- System monospace font auto-detected on first run (via GSettings `org.gnome.desktop.interface`)

### Search
- Find / Replace dialog with forward/backward search, match-case, whole-word options
- Go To Line

### Interface
- GTK3 toolbar with Fluent icon set
- Status bar showing line/column, EOL mode (CRLF/CR/LF), encoding, and active language
- Keyboard shortcuts matching Notepad++ conventions (Ctrl+N/O/S/W/Z/Y/X/C/V/A/F/H/G)

## Build

Requires CMake 3.20+, GCC or Clang, and GTK3 development headers.

```sh
sudo apt-get install libgtk-3-dev cmake build-essential
cmake -B linux/build -S linux
cmake --build linux/build -j$(nproc)
```

Output: `linux/build/notepad++`

## Run

```sh
./linux/build/notepad++
./linux/build/notepad++ file1.c file2.h
```

## Upcoming features

- **Language menu** — top-level Language menu to manually override the detected language for the current tab, grouped by category with radio checkmarks
- **i18n / localisation** — system locale detection and translation loading from the 137 bundled Notepad++ XML language files (`resources/localization/`)

## User configuration

All user data lives in `~/.config/npp/`:

| Path | Purpose |
|------|---------|
| `~/.config/npp/stylers.xml` | Saved style/color overrides from the Style Configurator |
| `~/.config/npp/themes/` | User-supplied theme XML files (Notepad++ format) |

## Architecture

```
linux/src/main.c            — GtkApplication, window, menu bar, keyboard shortcuts
linux/src/editor.c/h       — tab/document management, file I/O, Scintilla wrappers
linux/src/statusbar.c/h    — bottom status bar
linux/src/toolbar.c/h      — GTK3 toolbar
linux/src/findreplace.c/h  — Find/Replace dialog
linux/src/lexer.c/h        — language detection, Lexilla integration, keyword tables
linux/src/lexilla_bridge.cpp — C++ bridge: exposes CreateLexer() to C code
linux/src/stylestore.c/h   — theme/style parser and Scintilla style applicator
linux/src/styleeditor.c/h  — Style Configurator dialog
linux/src/sci_c.h           — C-safe Scintilla interface

scintilla/                  — vendored editing engine (GTK3 backend used as-is)
lexilla/                    — vendored syntax highlighting (~80 language lexers)
resources/                  — shared with macOS port: themes, stylers.model.xml, langs.model.xml
```

The application layer is pure C (C11). Only `lexilla_bridge.cpp` uses C++ to call the Lexilla `CreateLexer()` API via a single `extern "C"` function. Scintilla and Lexilla are compiled as C++ static libraries and accessed exclusively through their C message API (`scintilla_send_message`).

## Original projects

- [Notepad++ for macOS](https://github.com/notepadplusplus/notepad-plus-plus-mac)
- [Scintilla](https://www.scintilla.org)
- [Lexilla](https://www.scintilla.org/Lexilla.html)
- [Notepad++ (Windows)](https://notepad-plus-plus.org)
