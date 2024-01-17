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

      mkLauncher = { writeScript, bash, nixGL, gossip }: writeScript "gossip-launcher" ''
        #!${bash}/bin/bash

        ${nixGL "gossip-nixgl" []}/bin/gossip-nixgl ${gossip}/bin/gossip
      '';

      mkDebugLauncher = { writeScript, bash, nixGL, gossip }: writeScript "gossip-debug-launcher" ''
        #!${bash}/bin/bash

        echo "Entering a busybox shell running within the AppImage chroot, for debugging."
        echo "To execute Gossip, run ${nixGL "gossip-nixgl" []}/bin/gossip-nixgl ${gossip}/bin/gossip"
        echo "Execute 'exit' to terminate the shell and the AppImage."

        export PATH="${pkgs.busybox}/bin:$PATH"
        ${pkgs.busybox}/bin/busybox ash
      '';
    in {
      gossip-nixgl = pkgs.callPackage ({
        stdenv
        , bash
        , writeScript
        , nixGL
        , gossip
        , mkLauncher
      }: let
        launcher = mkLauncher { inherit writeScript bash nixGL gossip; };
      in stdenv.mkDerivation {
        pname = "gossip-nixgl";
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
      }) { nixGL = nanoNixGL.nixGL; 
           gossip = erosanixPkgs.gossip; 
           inherit mkLauncher; 
         };

      gossip-appimage = nix-appimage.bundlers."${system}".default self.packages."${system}".gossip-nixgl;

      gossip-shell-appimage = nix-appimage.bundlers."${system}".default (self.packages."${system}".gossip-nixgl.override {
        mkLauncher = mkDebugLauncher;
      });
    };
  };
}
