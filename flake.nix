{
  description = "A Nix flake which builds an AppImage of the Gossip Nostr client.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    erosanix.url = "github:emmanuelrosa/erosanix";
    erosanix.inputs.nixpkgs.follows = "nixpkgs";
    nix-appimage.url = "github:ralismark/nix-appimage";
    nix-appimage.inputs.nixpkgs.follows = "nixpkgs";
    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, erosanix, nix-appimage, nixgl}: {

    lib.x86_64-linux = let
      pkgs = import "${nixpkgs}" { system = "x86_64-linux"; };
      erosanixLib = erosanix.lib.x86_64-linux;
    in {
        mkNixGL = pkg: 
          let
            wrapper = pkgs.writeShellScript "nixgl-wrapper" ''
              ${nixgl.packages.x86_64-linux.nixGLDefault}/bin/nixGL "@EXECUTABLE@" "$@"
            '';
          in erosanixLib.genericBinWrapper pkg wrapper;
    };

    packages.x86_64-linux.gossip-nixgl = self.lib.x86_64-linux.mkNixGL erosanix.packages.x86_64-linux.gossip;
    packages.x86_64-linux.gossip-appimage = nix-appimage.bundlers.x86_64-linux.default self.packages.x86_64-linux.gossip-nixgl;
  };
}
