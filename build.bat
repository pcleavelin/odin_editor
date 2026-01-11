@echo off

cl.exe /c third_party\tree-sitter\lib\src\lib.c /Fobin\tree-sitter.obj /I third_party\tree-sitter\lib\include
lib.exe /OUT:bin\tree-sitter.lib bin\tree-sitter.obj

cargo fmt --manifest-path "src/pkg/grep_lib/Cargo.toml"
cargo build --manifest-path "src/pkg/grep_lib/Cargo.toml"

..\odin-2025-01\odin.exe build src/ -out:bin/editor.exe -debug
