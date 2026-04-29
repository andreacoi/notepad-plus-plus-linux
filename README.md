# Notepad++ Linux

A native Linux port of [Notepad++ for macOS](https://github.com/notepadplusplus/notepad-plus-plus-mac), built with C and GTK3.

## Why this is possible

The macOS port and this Linux port share a common foundation: both macOS and Linux are UNIX-based systems. This means the underlying OS primitives — file I/O, process model, character encoding, shared library loading — are compatible. The two vendored libraries at the heart of the editor, **Scintilla** (editing engine) and **Lexilla** (syntax highlighting), already ship GTK3 and platform-agnostic backends alongside their Cocoa ones. The Linux port replaces only the UI layer, swapping Cocoa/Objective-C++ for GTK3/C, while leaving the editor core untouched.

## Status

Early development. Phase 1 is working:

- Multi-tab editing
- File operations: New, Open, Save, Save As, Close
- Undo / Redo, Cut / Copy / Paste, Select All
- Go To Line
- Status bar (line/column, EOL mode, encoding)
- Modified-document tracking with ask-to-save on close/quit
- Command-line file arguments

## Build

Requires CMake 3.20+, GCC, and GTK3 development headers.

```sh
sudo apt-get install libgtk-3-dev
cmake -B linux/build -S linux
cmake --build linux/build -j$(nproc)
```

Output: `linux/build/notepad++`

## Run

```sh
./linux/build/notepad++
./linux/build/notepad++ file1.c file2.h
```

## Architecture

```
linux/src/main.c         — GtkApplication, window, menu bar, keyboard shortcuts
linux/src/editor.c/h    — tab/document management, file I/O, Scintilla wrappers
linux/src/statusbar.c/h — bottom status bar
linux/src/sci_c.h        — C-safe Scintilla interface (bypasses C++-only headers)

scintilla/               — vendored editing engine (GTK3 backend used as-is)
lexilla/                 — vendored syntax highlighting (~80 language lexers)
```

The application layer is pure C. Scintilla and Lexilla are compiled as C++ static libraries and accessed exclusively through their C message API (`scintilla_send_message`).

## Original projects

- [Notepad++ for macOS](https://github.com/notepadplusplus/notepad-plus-plus-mac)
- [Scintilla](https://www.scintilla.org)
- [Lexilla](https://www.scintilla.org/Lexilla.html)
- [Notepad++ (Windows)](https://notepad-plus-plus.org)
