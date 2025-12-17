{
  inputs = {
    nixpkgs.url      = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url  = "github:numtide/flake-utils";
    nixgl.url        = "github:guibou/nixGL";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, nixgl, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ nixgl.overlay (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        local-rust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-analysis" ];
        };
        tree-sitter-odin = pkgs.stdenv.mkDerivation {
          pname = "tree-sitter-odin";
          version = "1.3.0";

          src = builtins.fetchGit {
            url = "https://github.com/tree-sitter-grammars/tree-sitter-odin.git";
            rev = "e8adc739b78409a99f8c31313f0bb54cc538cf73";
          };

          installPhase = ''
            mkdir -p $out/lib
            cp libtree-sitter-odin.a $out/lib
          '';
        };
        tree-sitter-json = pkgs.stdenv.mkDerivation {
          pname = "tree-sitter-json";
          version = "0.24.8";

          src = builtins.fetchGit {
            url = "https://github.com/tree-sitter/tree-sitter-json.git";
            rev = "ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24";
          };

          installPhase = ''
            mkdir -p $out/lib
            cp libtree-sitter-json.a $out/lib
          '';
        };
        tree-sitter-rust = pkgs.stdenv.mkDerivation {
          pname = "tree-sitter-rust";
          version = "0.24.0";

          src = builtins.fetchGit {
            url = "https://github.com/tree-sitter/tree-sitter-rust.git";
            rev = "18b0515fca567f5a10aee9978c6d2640e878671a";
          };

          installPhase = ''
            mkdir -p $out/lib
            cp libtree-sitter-rust.a $out/lib
          '';
        };
        grep-lib = pkgs.rustPlatform.buildRustPackage rec {
            name = "grep-lib";
            src = ./src/pkg/grep_lib;
            nativeBuildInputs = [ local-rust ];

            cargoLock = {
              lockFile = ./src/pkg/grep_lib/Cargo.lock;
            };

            # lol, why does `buildRustPackage` not work without this?
            # postPatch = ''
            #   ln -sf ${./src/pkg/grep_lib/Cargo.lock} Cargo.lock
            # '';
          };
        tree-sitter = pkgs.stdenv.mkDerivation {
            name = "tree-sitter";
            src = ./third_party/tree-sitter;
            nativeBuildInputs = [ pkgs.clang ];

            installPhase = ''
              mkdir -p $out/lib
              cp libtree-sitter.a $out/lib
            '';
          };
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; (if pkgs.system == "aarch64-darwin" || pkgs.system == "x86_64-darwin" then [
            git
            local-rust
            odin
            ols
            SDL2
            SDL2_ttf
            tree-sitter-odin
            tree-sitter-json
            tree-sitter-rust
            tree-sitter
            grep-lib
            binutils
            clang
          ] else if pkgs.system == "x86_64-linux" then [
            pkg-config
            binutils
            odin
            ols
            local-rust
            libGL
            xorg.libX11
            xorg.libXi
            xorg.xinput
            xorg.libXcursor
            xorg.libXrandr
            xorg.libXinerama
            pkgs.nixgl.nixGLIntel
          ] else throw "unsupported system" );
        };

        packages = {
          grep-lib = grep-lib;
          tree-sitter-json = tree-sitter-json;
          tree-sitter-rust = tree-sitter-rust;
          tree-sitter-odin = tree-sitter-odin;
          tree-sitter = tree-sitter;

          editor = pkgs.stdenv.mkDerivation rec {
            pname = "editor";
            version = "0.1";
            src = ./.;

            buildInputs = with pkgs; [
              tree-sitter-odin
              tree-sitter-json
              tree-sitter-rust
              tree-sitter
              grep-lib
              odin
              SDL2
              SDL2_ttf
            ];
            installPhase = ''
              mkdir -p $out/bin
              cp bin/editor $out/bin/editor
            '';
          };
        };
      }
    );
}
