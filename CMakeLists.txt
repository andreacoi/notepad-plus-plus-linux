cmake_minimum_required(VERSION 3.20)
project(NotepadPlusPlusMac OBJCXX CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")

# Paths to the original notepad-plus-plus repo (sibling directory)
set(NPP_ROOT "${CMAKE_SOURCE_DIR}/../notepad-plus-plus")
set(SCI_ROOT "${NPP_ROOT}/scintilla")
set(LEX_ROOT "${NPP_ROOT}/lexilla")

# -----------------------------------------------------------------------------
# Scintilla core (platform-agnostic)
# -----------------------------------------------------------------------------
file(GLOB SCI_CORE_SRCS "${SCI_ROOT}/src/*.cxx")

set(SCI_COCOA_SRCS
    "${SCI_ROOT}/cocoa/PlatCocoa.mm"
    "${SCI_ROOT}/cocoa/ScintillaCocoa.mm"
    "${SCI_ROOT}/cocoa/ScintillaView.mm"
    "${SCI_ROOT}/cocoa/InfoBar.mm"
)

add_library(scintilla STATIC ${SCI_CORE_SRCS} ${SCI_COCOA_SRCS})

target_include_directories(scintilla PUBLIC
    "${SCI_ROOT}/include"
    "${SCI_ROOT}/src"
    "${SCI_ROOT}/cocoa"
)

target_compile_definitions(scintilla PRIVATE
    SCI_NAMESPACE
    SCINTILLA_QT=0
)

set_source_files_properties(${SCI_COCOA_SRCS} PROPERTIES
    COMPILE_FLAGS "-fobjc-arc"
)

# -----------------------------------------------------------------------------
# Lexilla (syntax highlighting)
# -----------------------------------------------------------------------------
file(GLOB LEX_SRCS
    "${LEX_ROOT}/src/*.cxx"
    "${LEX_ROOT}/lexers/*.cxx"
    "${LEX_ROOT}/lexlib/*.cxx"
)
# LexUser.cxx requires windows.h — exclude and replace with a macOS stub
list(FILTER LEX_SRCS EXCLUDE REGEX "LexUser\\.cxx$")
list(APPEND LEX_SRCS "${CMAKE_SOURCE_DIR}/src/LexUserStub.cxx")

add_library(lexilla STATIC ${LEX_SRCS})

target_include_directories(lexilla PUBLIC
    "${LEX_ROOT}/include"
    "${LEX_ROOT}/src"
    "${LEX_ROOT}/lexlib"
    "${LEX_ROOT}/access"
    "${SCI_ROOT}/include"
    "${SCI_ROOT}/src"
    "${CMAKE_SOURCE_DIR}/src"
)

# -----------------------------------------------------------------------------
# Application
# -----------------------------------------------------------------------------
set(APP_SRCS
    src/main.mm
    src/AppDelegate.mm
    src/MainWindowController.mm
    src/EditorView.mm
    src/TabManager.mm
    src/NppTabBar.mm
    src/MenuBuilder.mm
    src/FindReplacePanel.mm
    src/ColumnEditorPanel.mm
    src/PreferencesWindowController.mm
    src/FindInFilesPanel.mm
    src/SidePanelHost.mm
    src/DocumentListPanel.mm
    src/ClipboardHistoryPanel.mm
    src/FunctionListPanel.mm
    src/DocumentMapPanel.mm
    src/ProjectPanel.mm
    src/StyleConfiguratorWindowController.mm
    src/IncrementalSearchBar.mm
    src/CommandPalettePanel.mm
    src/GitHelper.mm
    src/GitPanel.mm
    src/FolderTreePanel.mm
    src/CharacterPanel.mm
)

set(APP_HEADERS
    src/AppDelegate.h
    src/MainWindowController.h
    src/EditorView.h
    src/TabManager.h
    src/NppTabBar.h
    src/MenuBuilder.h
    src/FindReplacePanel.h
    src/ColumnEditorPanel.h
    src/PreferencesWindowController.h
    src/FindInFilesPanel.h
    src/SidePanelHost.h
    src/DocumentListPanel.h
    src/ClipboardHistoryPanel.h
    src/FunctionListPanel.h
    src/DocumentMapPanel.h
    src/ProjectPanel.h
    src/StyleConfiguratorWindowController.h
    src/IncrementalSearchBar.h
    src/CommandPalettePanel.h
    src/GitHelper.h
    src/GitPanel.h
    src/FolderTreePanel.h
    src/CharacterPanel.h
)

add_executable(NotepadPlusPlusMac MACOSX_BUNDLE ${APP_SRCS} ${APP_HEADERS})

# Copy icons at BUILD time so updated PNGs are picked up on every make, not just cmake re-run
add_custom_command(TARGET NotepadPlusPlusMac POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/resources/icons"
        "$<TARGET_BUNDLE_DIR:NotepadPlusPlusMac>/Contents/Resources/icons"
    COMMENT "Syncing icons into app bundle")

add_custom_command(TARGET NotepadPlusPlusMac POST_BUILD
    # Force-copy so an updated icns is always written (copy_if_different can miss timestamp ties)
    COMMAND ${CMAKE_COMMAND} -E copy
        "${CMAKE_SOURCE_DIR}/resources/npp.icns"
        "$<TARGET_BUNDLE_DIR:NotepadPlusPlusMac>/Contents/Resources/npp.icns"
    # Touch the bundle so macOS knows the icon changed, then re-register with LaunchServices
    COMMAND touch "$<TARGET_BUNDLE_DIR:NotepadPlusPlusMac>"
    COMMAND /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
            -f "$<TARGET_BUNDLE_DIR:NotepadPlusPlusMac>"
    COMMENT "Copying app icon and refreshing macOS icon cache")

add_custom_command(TARGET NotepadPlusPlusMac POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/resources/stylers.model.xml"
        "$<TARGET_BUNDLE_DIR:NotepadPlusPlusMac>/Contents/Resources/stylers.model.xml"
    COMMENT "Copying stylers.model.xml into bundle")

add_custom_command(TARGET NotepadPlusPlusMac POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/resources/themes"
        "$<TARGET_BUNDLE_DIR:NotepadPlusPlusMac>/Contents/Resources/themes"
    COMMENT "Copying theme XML files into bundle")

set_target_properties(NotepadPlusPlusMac PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/resources/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "Notepad++"
    MACOSX_BUNDLE_GUI_IDENTIFIER "org.notepadplusplus.mac"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
)

target_include_directories(NotepadPlusPlusMac PRIVATE
    src
    "${SCI_ROOT}/include"
    "${SCI_ROOT}/cocoa"
    "${LEX_ROOT}/include"
)

target_link_libraries(NotepadPlusPlusMac PRIVATE
    scintilla
    lexilla
    "-framework Cocoa"
    "-framework QuartzCore"
)

set_source_files_properties(${APP_SRCS} PROPERTIES
    COMPILE_FLAGS "-fobjc-arc"
)
