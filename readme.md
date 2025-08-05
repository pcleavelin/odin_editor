## How to build
* Install the [nix package manager](https://nixos.org/download/).
* Download [JetBrains Mono](https://www.jetbrains.com/lp/mono/) and place it in a new `bin` directory in the root of the project.
* Run `nix build .#editor` or `nix run .#editor`.

## What is this?
This is an in-development modal text editor inspired by vim but with an actual GUI interface instead of yet another terminal program nobody asked for.

## Is it currently usuable to edit files?
Yes, in a technical sense. It can load files, allow you to make edits to said file, and save the file. However, the *ergonomics* of using the editor aren't quite where I'd like them to be. It's almost at a point where I could bear using it to further improve it, but still wouldn't use it for real work.
