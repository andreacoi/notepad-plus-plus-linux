# Notepad++ for Linux

**The first native port of Notepad++ to Linux.** A full port of the original [Notepad++](https://notepad-plus-plus.org) codebase — not a rewrite, not an alternative, not Wine.

<p align="center">
  <img src="https://notepad-plus-plus-mac.org/assets/images/icon-128x128.png" alt="Notepad++ for macOS app icon" width="128" height="128">
</p>

---

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
- Status bar showing line/column, EOL mode (CRLF/CR/LF), encoding, active language, and INS/OVR mode indicator
- Keyboard shortcuts matching Notepad++ conventions (Ctrl+N/O/S/W/Z/Y/X/C/V/A/F/H/G)
- **Language menu** — top-level Language menu to manually override the detected language, grouped into 9 categories (C/C++, Web, Scripting, Systems, Markup/Config, Database, Scientific, Hardware, Other) with radio checkmarks; "Normal Text" at top; checkmark syncs automatically on tab switch
- **EOL Conversion** — Edit → EOL Conversion submenu with radio items: Windows (CR+LF), Unix (LF), Old Mac (CR); converts all existing line endings when switched; status bar EOL cell syncs on tab switch

### Localisation
- Automatic system locale detection via GLib (`g_get_language_names()`)
- 137 bundled translations from the official Notepad++ XML localization files
- All menus, dialogs, and buttons translated; falls back to English when no match

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

Ordered by implementation effort (low → high).

### Low effort
- **Show/hide symbols** — toggle whitespace, EOL markers, line numbers, fold margin, bookmarks margin
- **Edge column** — configurable vertical guide line
- **Insert date/time** — short and long format insertion
- **Duplicate / Delete / Move line** — single-line operations under Edit menu
- **Join / Split lines** — line joining and splitting
- **Insert blank line above/below** — keyboard-accessible line insertion
- **Trim whitespace** — strip leading and trailing spaces on save or on demand
- **Hash tools** — MD5, SHA-1, SHA-256, SHA-512 generation from selection or file
- **Base64 encode/decode** — ASCII ↔ Base64 and ASCII ↔ Hex conversions

### Medium effort
- **Case conversion** — UPPER, lower, Proper, Sentence, Inverted, Random case
- **Comment / Uncomment** — single-line and block comment, language-aware delimiters
- **EOL and whitespace conversions** — EOL↔space, spaces↔tabs, tabs↔spaces
- **Remove duplicate / blank lines** — various line-cleanup operations
- **Sort lines** — lexicographic, case-insensitive, by length, numeric, random, reverse
- **Word wrap toggle** — per-tab word wrap
- **Bookmarks** — toggle, next/prev, clear all, cut/copy/remove bookmarked lines
- **Mark styles** — highlight text with 5 color styles, jump next/prev, clear
- **Go to matching brace** — brace/bracket/parenthesis matching navigation
- **Recent files list** — reopen recently closed files
- **Encoding selection** — manual per-tab encoding, reload with specified encoding
- **Keyboard shortcut mapper** — customise and save key bindings
- **Preferences dialog** — persistent settings (config.xml equivalent)
- **Auto-indent** — None / Basic / Advanced modes
- **Code folding controls** — fold/unfold all and by individual levels (1–8)

### High effort
- **Find in Files** — recursive directory search with collapsible results tree
- **Column / block selection** — Alt-drag rectangular selection and column editor
- **Multi-select** — select all occurrences, next occurrence, match-case/whole-word variants
- **Auto-completion** — word, function, and path completion with parameter hints
- **User-defined languages (UDL)** — custom syntax highlighting via XML definitions
- **Change history / git gutter** — diff markers in margin, next/prev change navigation
- **Session save / restore** — persist and reopen tab sets
- **Auto-backup** — timed backup copies to `~/.config/npp/backup/`
- **File change detection** — detect external modifications and prompt to reload
- **Macro recording / playback** — record and replay keystroke sequences
- **Document List panel** — dockable panel listing all open tabs
- **Folder as Workspace panel** — multi-root file tree browser
- **Function List panel** — tree view of functions/classes in the current file
- **Document Map** — minimap preview of the full document
- **Search Results panel** — accumulated find results with navigation
- **Spell checker** — inline spell checking with highlight and correction
- **Plugin system** — dlopen-based plugin loading, menu integration, NPPM message routing

## Release packaging

Once the project is feature-complete, pre-compiled packages will be produced for all major Linux distributions:

| Format | Target distros |
|--------|---------------|
| `.deb` | Debian, Ubuntu, Linux Mint, Pop!_OS |
| `.rpm` | Fedora, RHEL, CentOS Stream, openSUSE |
| `.pkg.tar.zst` | Arch Linux, Manjaro |
| `.apk` | Alpine Linux |

> **Note:** No AppImage, Flatpak, or Snap packages will ever be produced. These distribution formats are philosophically opposed to how native software should be shipped on Linux — they sidestep the distro package manager, bloat the install, and erode the integration that makes a native app feel native. Packages will be built for distro toolchains only.

## Extra features

Features beyond the original Notepad++ scope, specific to this Linux port. These will be tackled only after all upcoming features are complete.

- **Vim mode** — modal editing (Normal / Insert / Visual) with core Vim motions and commands, toggled via Settings → Vim Mode

## Bug fixes

| # | Component | Description | Resolution |
|---|-----------|-------------|------------|
| 1 | Style Configurator | Save and Close buttons had no effect on GTK3/Wayland | Replaced `gtk_dialog_run()` loop with `response` signal handler; dialog is now a persistent singleton closed via `gtk_widget_hide()` |
| 2 | Style Configurator | "Salva" and "Salva e chiudi" actions were swapped — Save closed the dialog, Save and Close kept it open | Corrected response-ID assignment to match translated button labels |
| 3 | Style store | `~/.config/npp/stylers.xml` triggered a parse warning for entries whose `name` attribute contains `&` (e.g. CaML `BUILTIN FUNC & TYPE`) | XML is pre-processed to escape bare `&` before passing to `GMarkupParser` |

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
