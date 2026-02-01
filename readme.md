## What is this?
This is an in-development modal text editor inspired by vim but with an actual GUI interface instead of yet another terminal program nobody asked for.

![editor screenshot](https://blog-assets.spacegirl.nl/odin-editor/screenshot-2.png)

## How to build on *nix and macOS
* Install the [nix package manager](https://nixos.org/download/).
* Run `nix build .#editor` or `nix run .#editor`.

# How to build on Windows
1. Install the VS Build Tools from [here](https://visualstudio.microsoft.com/downloads/).
2. Install [rustup](https://rust-lang.org/tools/install/)
3. Download the 2025-01 version of the Odin compiler [here](https://github.com/odin-lang/Odin/releases/tag/dev-2025-01), and extract to a folder next to this one called `odin-2025-01`
4. Clone the [tree-sitter-odin](https://github.com/tree-sitter-grammars/tree-sitter-odin.git) and checkout commit `e8adc739b78409a99f8c31313f0bb54cc538cf73`, again next to this folder
5. Run the `x64 Native Tools Command Prompt for VS` shortcut.
6. Run `build`

This will create a `bin` directory with an `editor.exe`

## Is it currently usuable to edit files?
Yes. It's capabilities are slightly higher than that of the Windows Notepad. However, the *ergonomics* of using the editor aren't quite where I'd like them to be. It's at a point where I can bear using it to further improve it, but still wouldn't use it for real work.

## Planned stuff
See the [todo list](todo.md)
