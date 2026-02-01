@echo off

mkdir bin

cl.exe /c third_party\tree-sitter\lib\src\lib.c /Fobin\tree-sitter.obj /I third_party\tree-sitter\lib\include
lib.exe /OUT:bin\tree-sitter.lib bin\tree-sitter.obj

cl.exe /c ..\tree-sitter-odin\src\parser.c /Fo..\tree-sitter-odin\parser.obj /I ..\tree-sitter-odin\src\tree_sitter
cl.exe /c ..\tree-sitter-odin\src\scanner.c /Fo..\tree-sitter-odin\scanner.obj /I ..\tree-sitter-odin\src\tree_sitter
lib.exe /OUT:bin\tree-sitter-odin.lib ..\tree-sitter-odin\parser.obj ..\tree-sitter-odin\scanner.obj

cargo fmt --manifest-path "src/pkg/grep_lib/Cargo.toml"
cargo build --manifest-path "src/pkg/grep_lib/Cargo.toml"

copy ..\odin-2025-01\vendor\sdl2\SDL2.dll bin\SDL2.dll
copy ..\odin-2025-01\vendor\sdl2\ttf\SDL2_ttf.dll bin\SDL2_ttf.dll

..\odin-2025-01\odin.exe build src/ -out:bin/editor.exe -debug
