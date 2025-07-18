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
        local-rust = (pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain).override {
          extensions = [ "rust-analysis" ];
        };
        local-nightly-rust = (pkgs.rust-bin.fromRustupToolchainFile ./plugins/grep/rust-toolchain.toml).override {
          extensions = [ "rust-analysis" ];
        };
        nightly-cargo = pkgs.writeShellScriptBin "nightly-cargo" ''
          export RUSTC="${local-nightly-rust}/bin/rustc";
          exec "${local-nightly-rust}/bin/cargo" "$@"
        '';
        fixed-odin = pkgs.odin.overrideAttrs (finalAttrs: prevAttr: rec {
          src = pkgs.fetchFromGitHub {
            owner = "pcleavelin";
            repo = "Odin";
            rev = "7b9ea9eca02bf5dd295439a46ed6103a0c4a44ff";
            hash = "sha256-pxvU5veB1NEYPfer5roiLp/od2Pv4l1jJah0OHwb5yo=";
          };
          LLVM_CONFIG = "${pkgs.llvmPackages_17.llvm.dev}/bin/llvm-config";
          nativeBuildInputs = with pkgs; prevAttr.nativeBuildInputs ++ [ libcxx libcxxabi ];
          postPatch = prevAttr.postPatch + ''
            sed -i build_odin.sh \
              -e 's|CXXFLAGS="$CXXFLAGS $($LLVM_CONFIG --cxxflags --ldflags)"|CXXFLAGS="$CXXFLAGS $($LLVM_CONFIG --cxxflags --ldflags) -I ${pkgs.libiconv.outPath}/include/"|' \
              -e 's|LDFLAGS="$LDFLAGS -pthread -lm -lstdc++"|LDFLAGS="$LDFLAGS -pthread -lm -lstdc++ -L ${pkgs.libiconv.outPath}/lib/ -L ${pkgs.llvmPackages_17.libcxxabi.outPath}/lib/"|'
          '';
          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp odin $out/bin/odin

            mkdir -p $out/share
            cp -r core $out/share/core
            cp -r vendor $out/share/vendor

            wrapProgram $out/bin/odin \
              --set PATH ${pkgs.lib.makeBinPath (with pkgs; [
                coreutils
                llvmPackages_17.bintools
                llvmPackages_17.lld
                llvmPackages_17.clang
              ])} \
              --set-default ODIN_ROOT $out/share

            runHook postInstall
          '';
        });
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; (if pkgs.system == "aarch64-darwin" || pkgs.system == "x86_64-darwin" then [
            # fixed-odin
            llvmPackages_17.bintools
            llvmPackages_17.lld
            llvmPackages_17.clang
            local-rust
            nightly-cargo
            rust-analyzer
            lua54Packages.stdlib
            SDL2
            SDL2_ttf
            darwin.apple_sdk.frameworks.System
            darwin.apple_sdk.frameworks.CoreData
            darwin.apple_sdk.frameworks.Kernel
            darwin.apple_sdk.frameworks.CoreVideo
            darwin.apple_sdk.frameworks.GLUT
            darwin.apple_sdk.frameworks.IOKit
            darwin.apple_sdk.frameworks.OpenGL
            darwin.apple_sdk.frameworks.Cocoa
          ] else if pkgs.system == "x86_64-linux" then [
            pkg-config
            binutils
            odin
            local-rust
            rust-analyzer
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
      }
    );
}
