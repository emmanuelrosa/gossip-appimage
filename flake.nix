{
  description = "A Nix flake which builds an AppImage of the Gossip Nostr client.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    erosanix.url = "github:emmanuelrosa/erosanix";
    erosanix.inputs.nixpkgs.follows = "nixpkgs";
    nix-appimage.url = "github:ralismark/nix-appimage";
    nix-appimage.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, erosanix, nix-appimage }: {

    lib.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" { inherit system; };
      erosanixLib = erosanix.lib."${system}";
    in {
      commonLibraryPaths = 
        [ "/lib"
          "/lib64"
          "/usr/lib"
          "/usr/lib64"
          "/usr/lib64/llvm16/lib"
          "/usr/lib/${system}-gnu"
          "/usr/lib/${system}-gnu/dri"
          "/lib/${system}-gnu"
          "/lib/${system}-gnu/dri"
        ];

      getPackageReferences = erosanixLib.composeAndApply [
        pkgs.writeReferencesToFile
        builtins.readFile 
        (pkgs.lib.strings.splitString "\n")
        (builtins.map pkgs.lib.attrsets.getLib) 
      ];

      mkLibraryPath = pkg: (builtins.concatStringsSep ":" self.lib."${system}".commonLibraryPaths) + ":" + (pkgs.symlinkJoin { 
        name = "${pkg.name}-library-path";
        paths = self.lib."${system}".getPackageReferences pkg;
      }) + "/lib";
    };

    # A miniturized version of nixGL (https://github.com/nix-community/nixGL)
    # made specifically for Gossip.
    nanoNixGL.x86_64-linux = let 
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" { inherit system; };
      lib = pkgs.lib;
    in {
      writeExecutable = pkgs.callPackage ({ writeTextFile, shellcheck, pcre }: { name, text }:
        writeTextFile {
          inherit name text;

          executable = true;
          destination = "/bin/${name}";

          checkPhase = ''
            ${shellcheck}/bin/shellcheck "$out/bin/${name}"

            # Check that all the files listed in the output binary exists
            for i in $(${pcre}/bin/pcregrep  -o0 '/nix/store/.*?/[^ ":]+' $out/bin/${name})
            do
              ls $i > /dev/null || (echo "File $i, referenced in $out/bin/${name} does not exists."; exit -1)
            done
          '';
        }) { };

        nixGL = pkgs.callPackage ({ 
          lib
          , runCommand
          , runtimeShell
          , mesa
          , libglvnd
          , libvdpau-va-gl 
        }: name: vadrivers: self.nanoNixGL."${system}".writeExecutable {
          inherit name;
          text = let
            mesa-drivers = [ mesa.drivers ];
            libvdpau = [ libvdpau-va-gl ];
            glxindirect = runCommand "mesa_glxindirect" { } (''
              mkdir -p $out/lib
              ln -s ${mesa.drivers}/lib/libGLX_mesa.so.0 $out/lib/libGLX_indirect.so.0
            '');
          in ''
            #!${runtimeShell}
            export LIBGL_DRIVERS_PATH=${lib.makeSearchPathOutput "lib" "lib/dri" mesa-drivers}
            export LIBVA_DRIVERS_PATH=${lib.makeSearchPathOutput "out" "lib/dri" (mesa-drivers ++ vadrivers)}
            ${''export __EGL_VENDOR_LIBRARY_FILENAMES=${mesa.drivers}/share/glvnd/egl_vendor.d/50_mesa.json"''${__EGL_VENDOR_LIBRARY_FILENAMES:+:$__EGL_VENDOR_LIBRARY_FILENAMES}"''
            }
            export LD_LIBRARY_PATH=${lib.makeLibraryPath mesa-drivers}:${lib.makeSearchPathOutput "lib" "lib/vdpau" libvdpau}:${glxindirect}/lib:${lib.makeLibraryPath [libglvnd]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            exec "$@"
          '';
      }) { };
    };

    packages.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" { inherit system; };
      erosanixPkgs = erosanix.packages."${system}";
      erosanixLib = erosanix.lib."${system}";
      nanoNixGL = self.nanoNixGL."${system}";
    in {
      # This patchelf version is not working.
      gossip-patchelf = let
        gossip = erosanix.packages.x86_64-linux.gossip;
      in pkgs.stdenv.mkDerivation {
        pname = "gossip-patchelf";
        version = gossip.version;
        src = gossip;
        dontUnpack = true;
        meta = gossip.meta;
        dontPatchELF = true;
        nativeBuildInputs = [ pkgs.patchelf pkgs.gawk ];

        buildPhase = ''
            cp $src/bin/gossip ./
            chmod u+w gossip
            patchelf --set-rpath ${self.lib."${system}".mkLibraryPath gossip} ./gossip
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin

          cp ./gossip $out/bin/gossip

          if [[ -h $src/share ]]
          then
            ln -s $(readlink $src/share) $out/share
          elif [[ -d $src/share ]]
          then
            ln -s $src/share $out/share
          fi

          runHook postInstall
        '';
      };

      gossip-lite = let
        gossip = erosanix.packages."${system}".gossip;

        launcher = pkgs.writeScript "gossip-launcher" ''
          #!${pkgs.bash}/bin/bash

          LD_LIBRARY_PATH=${libraryPath} ${gossip}/bin/gossip
        '';

        libraryPath = self.lib."${system}".mkLibraryPath gossip;
      in pkgs.stdenv.mkDerivation {
        pname = "gossip-lite";
        version = gossip.version;
        src = gossip;
        dontUnpack = true;
        meta = gossip.meta;
        dontPatchELF = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin

          cp ${launcher} $out/bin/gossip

          if [[ -h $src/share ]]
          then
            ln -s $(readlink $src/share) $out/share
          elif [[ -d $src/share ]]
          then
            ln -s $src/share $out/share
          fi

          runHook postInstall
        '';
      };

      gossip-minimal-nixgl = pkgs.callPackage ({
        stdenv
        , writeScript
        , bash
        , nixGL
        , gossip
      }:let
        launcher = writeScript "gossip-launcher" ''
          #!${bash}/bin/bash

          ${nixGL "gossip-nixgl" []}/bin/gossip-nixgl ${gossip}/bin/gossip
        '';
      in stdenv.mkDerivation {
        pname = "gossip-minimal-nixgl";
        version = gossip.version;
        src = gossip;
        dontUnpack = true;
        meta = gossip.meta;
        dontPatchELF = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin

          cp ${launcher} $out/bin/gossip

          if [[ -h $src/share ]]
          then
            ln -s $(readlink $src/share) $out/share
          elif [[ -d $src/share ]]
          then
            ln -s $src/share $out/share
          fi

          runHook postInstall
        '';
      }) { nixGL = nanoNixGL.nixGL; gossip = erosanixPkgs.gossip; };

      # The gossip-appimage-lite AppImage includes all of Gossip's dependencies except
      # for OpenGL. When Gossip is executed it will attempt to load its dependencies
      # from the host Linux distribution, and fallback to using the dependencies in the
      # AppImage. 
      gossip-appimage-lite = nix-appimage.bundlers.x86_64-linux.default self.packages.x86_64-linux.gossip-lite;

      gossip-minimal-appimage = nix-appimage.bundlers.x86_64-linux.default self.packages.x86_64-linux.gossip-minimal-nixgl;
    };
  };
}
