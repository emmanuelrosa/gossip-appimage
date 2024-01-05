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

    packages.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" { inherit system; };
    in {
      gossip-patchelf = let
        gossip = erosanix.packages.x86_64-linux.gossip;
      in pkgs.stdenv.mkDerivation {
        pname = "gossip-patchelf";
        version = gossip.version;
        src = gossip;
        dontUnpack = true;
        meta = gossip.meta;
        dontPatchELF = true;
        nativeBuildInputs = [ pkgs.patchelf ];

        buildPhase = ''
            cp $src/bin/gossip ./
            chmod u+w gossip
            patchelf --add-rpath /usr/lib/${system}-gnu:/usr/lib:/lib64:/usr/lib64 ./gossip
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin

          cp ./gossip $out/bin/gossip

          # Symlink the share directory so that .desktop files and such continue to work.
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

      gossip-appimage = nix-appimage.bundlers.x86_64-linux.default self.packages.x86_64-linux.gossip-patchelf;
    };
  };
}
