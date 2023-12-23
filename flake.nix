{
  inputs = {
    nixpkgs.url      = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url  = "github:numtide/flake-utils";
    nixgl.url        = "github:guibou/nixGL";
  };

  outputs = { self, nixpkgs, flake-utils, nixgl, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ nixgl.overlay ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        fixed-odin = pkgs.odin.overrideAttrs (finalAttrs: prevAttr: rec {
          src = /Users/temp/Documents/personal/Odin;
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
            fixed-odin
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
