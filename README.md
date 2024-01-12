# gossip-appimage

This Nix flake can be used to build an AppImage of the [Gossip](https://github.com/mikedilger/gossip) Nostr client. It is designed such that even if you've never used the [Nix](https://nixos.org/) package manager before, you should be able to easily build your own AppImage in a reproducable way.

## All you need is Nix

The only tool you need to install to build the Gossip AppImage is the Nix package manager. The Nix package manager can run on most Linux distributions. If you don't already have Nix installed, with Flakes enabled, I recommend the portable version of Nix by downloading [nix-portable](https://github.com/DavHau/nix-portable). 

nix-portable is a self-extracting version of Nix and it comes with Flakes enabled. In this document I describe how to complete the build using nix-portable.

## How to build the Gossip AppImage

1. First install the Nix package manager and enable Nix flakes. I'll asume you're unfamiliar with Nix, therefore, simply head to https://github.com/DavHau/nix-portable and download the latest release.
2. Make `nix-portable` executable: Ex. `chmod u+x ./nix-portable`
3. Run `./nix-portable nix-shell -p nix`
4. Now you're in a shell with Nix available in your $PATH. To build the AppImage, run `nix build github:emmanuelrosa/gossip-appimage#gossip-minimal-appimage`
5. The build process will create a symlink named `result` pointing to the AppImage in the Nix store. The Nix store won't be available once your exit `nix-portable`, therefore, you'll need to copy the AppImage out of the Nix store. Run `cp ./result ./Gossip-minimal.AppImage`
6. Now, exit `nix-portable` by executing `exit`
7. Finally, make the AppImage executable. Ex. `chmod u+x Gossip-minimal.AppImage`

Now you can execute the `Gossip-minimal.AppImage`!

## Supported Linux distributions

This Gossip AppImage has been spotted in the wild running on the following x64_64 Linux distros:

- Fedora 39 [^1]
- Manjaro
- Ubuntu 23.10

If you run the AppImage successfully on another Linux distro, let me know at npub18eynzyyrx0v46qjnvtj6mvekpxlfnkq06e3zfd6q9487vty0lfaszucvu7

[^1]: By default the Fedora installer uses BTRFS with asynchronous discards for the root filesystem. This is not ideal for Gossip because it uses a database which makes heavy use of random writes. BTRFS random write IO throughput is supar with asynchronous discards disabled. With asynchronous discards enabled, the performance is *TERRIBLE!* In short, it causes Gossip to hang while using the database. If the root filesystem is something else, such as ext4 or xfs, then Gossip works just fine on Fedora.

## How does it work?

The AppImage is generated by first taking the Gossip dep package and building a Nix package out of it. The package is located in my Nix flake https://github.com/emmanuelrosa/erosanix/tree/master/pkgs/gossip

Next, this Nix flake takes the aforementioned Gossip Nix package and wraps it in a script which sets LD_LIBRARY_PATH and other environment variables such that Gossip is able to find the included OpenGL drivers. The AppImage is designed to contain *all* of Gossip's dependencies; All the way down to glibc.

Finally, [nix-appimage](https://github.com/ralismark/nix-appimage) is used to build an AppImage using the wrapped Gossip Nix package.

When the AppImage is executed, after the usual AppImage bootstrap process the `AppRun` entry point bind-mounts the Nix store that's included in the AppImage squashfs filesystem, and then it runs a launcher script. The launcher script of the Gossip-minimal.AppImage sets the LD_LIBRARY_PATH such that the Linux linker `ld` (the program which basically runs Linux executables, resolves OpenGL libraries using the Mesa drivers included in the AppImage. Using such a *fat* AppImage should allow for good compatibility with many Linux distributions.

## Packages

This Nix flake includes the following packages:

- *gossip-minimal-nixgl*: This is a wrapper which launches Gossip using *nanoNixGL*, which is a tiny version of [nixGL](https://github.com/nix-community/nixGL). nixGL makes it so that Nix packages which depend on OpenGL can run on Linux distributions other than NixOS, as long as the Nix package manager is installed.
- *gossip-minimal-appimage*: This is an AppImage of *gossip-minimal-nixgl*. No Nix store is required on the host OS.
- *gossip-minimal-shell-appimage*: This is the same as *gossip-minimal-appimage* but instead of running Gossip it drops you into a busybox shell. This package is for troubleshooting the chroot environment under which Gossip runs.

